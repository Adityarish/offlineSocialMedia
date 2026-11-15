import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:protocol/protocol.dart';

const schema = r"""CREATE TABLE spaces(id TEXT PRIMARY KEY, name TEXT NOT NULL, host TEXT NOT NULL);
CREATE TABLE memberships(space TEXT NOT NULL REFERENCES spaces(id), actor TEXT NOT NULL, name TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('host','member')), removed INTEGER NOT NULL DEFAULT 0, seen INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(space,actor));
CREATE TABLE invitations(hash TEXT PRIMARY KEY, space TEXT NOT NULL REFERENCES spaces(id), expires INTEGER NOT NULL, revoked INTEGER NOT NULL DEFAULT 0, uses INTEGER NOT NULL DEFAULT 0);
CREATE TABLE entities(space TEXT NOT NULL REFERENCES spaces(id), id TEXT NOT NULL, kind TEXT NOT NULL, actor TEXT NOT NULL, revision INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, seq INTEGER NOT NULL, body TEXT NOT NULL, PRIMARY KEY(space,id));
CREATE INDEX feed_order ON entities(space,kind,seq DESC);
CREATE TABLE events(seq INTEGER PRIMARY KEY AUTOINCREMENT, space TEXT NOT NULL REFERENCES spaces(id), id TEXT NOT NULL, actor TEXT NOT NULL, body TEXT NOT NULL, committed INTEGER NOT NULL, UNIQUE(space,id));
CREATE INDEX event_cursor ON events(space,seq);
CREATE TABLE outbox(space TEXT NOT NULL REFERENCES spaces(id), id TEXT NOT NULL, body TEXT NOT NULL, error TEXT, PRIMARY KEY(space,id));
CREATE TABLE cursors(space TEXT PRIMARY KEY REFERENCES spaces(id), seq INTEGER NOT NULL DEFAULT 0);
CREATE TABLE media(space TEXT NOT NULL REFERENCES spaces(id), hash TEXT NOT NULL, owner TEXT NOT NULL, size INTEGER NOT NULL, mime TEXT NOT NULL, complete INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(space,hash));
CREATE TABLE nonces(actor TEXT NOT NULL, nonce TEXT NOT NULL, expires INTEGER NOT NULL, PRIMARY KEY(actor,nonce));
CREATE TABLE bookmarks(space TEXT NOT NULL REFERENCES spaces(id), entity TEXT NOT NULL, PRIMARY KEY(space,entity));
CREATE TABLE blocks(space TEXT NOT NULL REFERENCES spaces(id), actor TEXT NOT NULL, PRIMARY KEY(space,actor));
CREATE TABLE drafts(space TEXT PRIMARY KEY REFERENCES spaces(id), body TEXT NOT NULL);
CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE activity(space TEXT NOT NULL REFERENCES spaces(id), seq INTEGER NOT NULL, actor TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY(space,seq));
""";
class LocalRepository {
  final Database db;
  LocalRepository(this.db);
  static Future<LocalRepository> open(String path) async {
    sqfliteFfiInit();
    final db=await databaseFactoryFfi.openDatabase(path,options:OpenDatabaseOptions(
      version:1, onConfigure:(db) async { await db.execute('PRAGMA foreign_keys=ON'); await db.rawQuery('PRAGMA journal_mode=WAL'); },
      onCreate:(db,_) async { for(final sql in schema.split(';')) { if(sql.trim().isNotEmpty) await db.execute(sql); } },
      onUpgrade:(_,oldVersion,newVersion) async => throw StateError('Unsupported database upgrade $oldVersion → $newVersion'),
    ));
    return LocalRepository(db);
  }
  Future<void> addSpace(String id,String name,String host) async {
    await db.insert('spaces',{'id':id,'name':name,'host':host}, conflictAlgorithm:ConflictAlgorithm.ignore);
    await db.insert('cursors',{'space':id,'seq':0},conflictAlgorithm:ConflictAlgorithm.ignore);
  }
  Future<String?> setting(String key) async {
    final r=await db.query('settings',where:'key=?',whereArgs:[key]); return r.isEmpty?null:r.first['value'] as String;
  }
  Future<void> setSetting(String key,String value) async => db.insert('settings',{'key':key,'value':value},conflictAlgorithm:ConflictAlgorithm.replace).then((_){});
  Future<void> queue(String space,Json event) async { await db.insert('outbox',{'space':space,'id':event['id'],'body':jsonEncode(event)}); }
  Future<List<Json>> feed(String space,{int before=9223372036854775807,String search='',bool saved=false}) async {
    final rows=await db.rawQuery("""SELECT e.* FROM entities e WHERE e.space=? AND e.kind='post' AND e.deleted=0 AND e.seq<?
    AND e.actor NOT IN (SELECT actor FROM blocks WHERE space=?)
    AND (?='' OR e.body LIKE ? ESCAPE '\\')
    AND (?=0 OR EXISTS(SELECT 1 FROM bookmarks b WHERE b.space=e.space AND b.entity=e.id))
    ORDER BY e.seq DESC,e.id LIMIT 30""",[space,before,space,search,'%${search.replaceAll('\\','\\\\').replaceAll('%','\\%').replaceAll('_','\\_')}%',saved?1:0]);
    return rows.map((e)=>{...e,'data':jsonDecode(e['body'] as String)}).toList();
  }
  Future<Json> commit(String space,String actor,Json event) => db.transaction((tx) async {
    require(event['v']==1 && event['space']==space && event['actor']==actor,'Invalid envelope');
    final id=boundedText(event['id'],100);
    final authorized=await tx.query('memberships',where:'space=? AND actor=? AND removed=0',whereArgs:[space,actor]);
    require(authorized.isNotEmpty,'Membership revoked',403);
    final previous=await tx.query('events',where:'space=? AND id=?',whereArgs:[space,id]);
    if(previous.isNotEmpty) {
      require(previous.first['actor']==actor && previous.first['body']==jsonEncode(event),'Idempotency key reused with different content',409);
      return {...event,'seq':previous.first['seq'],'committed':previous.first['committed']};
    }
    final m=await tx.query('memberships',where:'space=? AND actor=? AND removed=0',whereArgs:[space,actor]);
    require(m.isNotEmpty,'Membership revoked',403);
    final stamp=now;
    final seq=await tx.insert('events',{'space':space,'id':id,'actor':actor,'body':jsonEncode(event),'committed':stamp});
    await _reduce(tx,space,actor,event,seq,moderator:m.first['role']=='host');
    return {...event,'seq':seq,'committed':stamp};
  });
  Future<void> receive(String space,List<dynamic> events) => db.transaction((tx) async {
    final c=await tx.query('cursors',where:'space=?',whereArgs:[space]);
    var cursor=c.first['seq'] as int;
    for(final raw in events) {
      final e=Map<String,dynamic>.from(raw); require(e['space']==space,'Cross-space event rejected');
      final seq=e['seq'] as int; if(seq<=cursor) continue;
      await _reduce(tx,space,e['actor'],e,seq,trusted:true);
      await tx.insert('activity',{'space':space,'seq':seq,'actor':e['actor'],'body':jsonEncode(e)},conflictAlgorithm:ConflictAlgorithm.ignore);
      cursor=seq;
    }
    await tx.update('cursors',{'seq':cursor},where:'space=?',whereArgs:[space]);
  });
  static Future<void> _reduce(DatabaseExecutor tx,String space,String actor,Json e,int seq,{bool moderator=false,bool trusted=false}) async {
    final op=e['op'], entity=boundedText(e['entity'],150);
    final data=Map<String,dynamic>.from(e['payload'] as Map);
    final rows=await tx.query('entities',where:'space=? AND id=?',whereArgs:[space,entity]);
    final old=rows.isEmpty?null:rows.first;
    if(op=='member.remove') {
      require(trusted || moderator,'Host role required',403);
      final host=await tx.query('spaces',where:'id=?',whereArgs:[space]);
      require(entity!=host.first['host'],'The host cannot be removed');
      await tx.update('memberships',{'removed':1},where:'space=? AND actor=?',whereArgs:[space,entity]); return;
    }
    if(op=='reaction.set') {
      require(entity=='reaction:$actor:${data['post']}', 'Invalid reaction identity');
      final p=await tx.query('entities',where:"space=? AND id=? AND kind='post' AND deleted=0",whereArgs:[space,data['post']]);
      require(p.isNotEmpty,'Post is deleted or unavailable',409);
      require(data['liked'] is bool,'Invalid reaction');
    } else if(op=='profile.set') {
      require(entity=='profile:$actor','Profile belongs to another device',403);
      data['name']=boundedText(data['name'],60); data['bio']=boundedText(data['bio']??'',300,empty:true);
    } else if(op=='post.create' || op=='comment.create') {
      require(RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(entity),'Invalid entity ID');
      require(old==null,'Entity already exists or was deleted',409);
      data['text']=boundedText(data['text']??'',4000,empty:op=='post.create');
      if(op=='post.create') {
        final media=(data['media']??[]) as List;
        require(media.length<=10 && ((data['text'] as String).isNotEmpty || media.isNotEmpty),'Add text or up to 10 images');
        for(final hash in media) {
          final files=await tx.query('media',where:'space=? AND hash=? AND complete=1',whereArgs:[space,hash]);
          require(trusted || (files.isNotEmpty && files.first['owner']==actor),'Media unavailable or belongs to another member');
        }
        data['alt']=boundedText(data['alt']??'',1000,empty:true);
      } else {
        final p=await tx.query('entities',where:"space=? AND id=? AND kind='post' AND deleted=0",whereArgs:[space,data['post']]);
        require(p.isNotEmpty,'Post is deleted or unavailable',409);
      }
    } else if(['post.edit','post.delete','comment.delete','post.moderate'].contains(op)) {
      require(old!=null && old['deleted']==0,'Content has been deleted or is unavailable',409);
      require(old!['kind']==(op=='comment.delete'?'comment':'post'),'Wrong entity type');
      require(trusted || (op=='post.moderate'?moderator:old!['actor']==actor),'Only the author can modify this content',403);
      require(trusted || e['revision']==old!['revision'],'Revision conflict; review the latest version',409);
      if(op=='post.edit') { final b=jsonDecode(old!['body'] as String) as Json; b['text']=boundedText(data['text'],4000); data..clear()..addAll(b); }
    } else { throw const ProtocolError(400,'Unsupported operation'); }
    final kind=op.startsWith('post.')?'post':op.startsWith('comment.')?'comment':op.startsWith('profile.')?'profile':'reaction';
    final deleted=op.endsWith('.delete') || op=='post.moderate';
    await tx.insert('entities',{'space':space,'id':entity,'kind':kind,'actor':old?['actor']??actor,'revision':(old?['revision'] as int? ?? 0)+1,'deleted':deleted?1:0,'seq':old?['seq']??seq,'body':deleted?'{}':jsonEncode(data)},conflictAlgorithm:ConflictAlgorithm.replace);
  }
  Future<void> close()=>db.close();
}
