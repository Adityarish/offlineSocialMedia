import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:protocol/protocol.dart';
import 'package:local_store/local_store.dart';

Future<List<int>> boundedBody(Stream<List<int>> stream,int limit) async {
  final bytes=<int>[];
  await for(final chunk in stream.timeout(const Duration(seconds:20))) {
    require(bytes.length+chunk.length<=limit,'Request too large',413); bytes.addAll(chunk);
  }
  return bytes;
}
class LanClient implements TransportAdapter {
  final Invitation invite;
  final DeviceIdentity identity;
  late final HttpClient http;
  LanClient(this.invite,this.identity) {
    // Empty trust store ensures even a publicly trusted substitute must match the pin.
    http=HttpClient(context:SecurityContext(withTrustedRoots:false))
      ..connectionTimeout=const Duration(seconds:8)
      ..idleTimeout=const Duration(seconds:15)
      ..badCertificateCallback=(cert,host,port)=>host==invite.endpoint.host && port==invite.endpoint.port && digest(cert.der)==invite.pin;
  }
  Future<List<int>> raw(String method,String path,[List<int> body=const []]) async {
    final request=await http.openUrl(method,invite.endpoint.resolve(path)).timeout(const Duration(seconds:10));
    request.followRedirects=false;
    (await identity.headers(method,path,body)).forEach(request.headers.set);
    request.headers.contentType=ContentType.binary;
    request.contentLength=body.length; request.add(body);
    final response=await request.close().timeout(const Duration(seconds:25));
    require(response.certificate!=null && digest(response.certificate!.der)==invite.pin,'Host certificate changed; verify a new invitation',401);
    final result=await boundedBody(response,path.contains('/events?')?1024*1024:chunkSize+maxMetadata);
    if(response.statusCode!=200) {
      String message='Host returned ${response.statusCode}';
      try { message=(jsonDecode(utf8.decode(result)) as Json)['error']??message; } catch(_) {}
      throw ProtocolError(response.statusCode,message);
    }
    return result;
  }
  @override Future<Json> request(String method,String path,[Json? data]) async => jsonDecode(utf8.decode(await raw(method,path,data==null?[]:utf8.encode(jsonEncode(data))))) as Json;
  @override void close()=>http.close(force:true);
}
class LanHost {
  final LocalRepository repository;
  final Directory mediaDir;
  final String space;
  HttpServer? server;
  int _active=0;
  final Set<String> _writing={};
  final Map<String,List<int>> _rates={};
  LanHost(this.repository,this.mediaDir,this.space);
  Future<int> start(InternetAddress address,SecurityContext tls,{int port=0}) async {
    final raw=address.rawAddress;
    final private=address.isLoopback || address.isLinkLocal || (raw.length==4 && (raw[0]==10 || (raw[0]==172 && raw[1]>=16 && raw[1]<=31) || (raw[0]==192 && raw[1]==168))) || (raw.length==16 && (raw[0]&0xfe)==0xfc);
    require(private,'Choose a private LAN or loopback address; public-interface hosting is disabled');
    require(!address.isMulticast && address!=InternetAddress.anyIPv4 && address!=InternetAddress.anyIPv6,'Choose a specific local interface');
    await mediaDir.create(recursive:true);
    server=await HttpServer.bindSecure(address,port,tls,shared:false);
    server!.idleTimeout=const Duration(seconds:20);
    server!.listen((req) async {
      if(_active>=16) { req.response.statusCode=429; await req.response.close(); return; }
      _active++;
      try { await _handle(req); }
      on ProtocolError catch(e) { req.response.statusCode=e.status; req.response.write(jsonEncode({'error':e.message})); }
      catch(_) { req.response.statusCode=400; req.response.write(jsonEncode({'error':'Invalid request or storage unavailable'})); }
      finally { _active--; await req.response.close(); }
    });
    return server!.port;
  }
  Future<void> stop() async { await server?.close(force:true); server=null; }
  Future<String> _authenticate(HttpRequest req,List<int> body) async {
    String header(String n)=>req.headers.value(n)??'';
    require(header('x-nearloop-version')=='1','Incompatible protocol; NearLoop v1 required',426);
    final key=header('x-key'), nonce=header('x-nonce'), time=header('x-time');
    require(key.length<=64 && nonce.length==43,'Invalid credentials',401);
    final stamp=int.tryParse(time);
    require(stamp!=null && (now-stamp).abs()<300000,'Device clock differs by over five minutes',401);
    final pub=base64Decode(key); require(pub.length==32,'Invalid public key',401);
    final valid=await Ed25519().verify(signedBytes(req.method,req.uri.toString(),digest(body),time,nonce),signature:Signature(base64Decode(header('x-signature')),publicKey:SimplePublicKey(pub,type:KeyPairType.ed25519)));
    require(valid,'Invalid signature',401);
    final actor=deviceId(key);
    await repository.db.delete('nonces',where:'expires<?',whereArgs:[now]);
    final exists=await repository.db.query('nonces',where:'actor=? AND nonce=?',whereArgs:[actor,nonce]);
    require(exists.isEmpty,'Replayed request',409);
    await repository.db.insert('nonces',{'actor':actor,'nonce':nonce,'expires':now+600000});
    return actor;
  }
  Future<void> _handle(HttpRequest req) async {
    final peer=req.connectionInfo?.remoteAddress.address??'unknown';
    _rates.removeWhere((_,v)=>now-v[0]>60000);
    require(_rates.length<1024 || _rates.containsKey(peer),'Server busy',429);
    final rate=_rates.putIfAbsent(peer,()=>[now,0]);
    require(++rate[1]<=600,'Too many requests; retry in a minute',429);
    final bytes=await boundedBody(req,req.uri.path.contains('/media/')?chunkSize:maxMetadata);
    final actor=await _authenticate(req,bytes);
    final parts=req.uri.pathSegments;
    require(parts.length>=2 && parts[0]=='spaces' && parts[1]==space,'Unknown space',404);
    final route=parts.skip(2).join('/');
    Json data()=>jsonDecode(utf8.decode(bytes)) as Json;
    void reply(Object value) { req.response.headers.contentType=ContentType.json; req.response.write(jsonEncode(value)); }
    if(route=='join' && req.method=='POST') {
      final j=data(), secret=boundedText(data()['secret'],100);
      final name=boundedText(j['name'],60);
      await repository.db.transaction((tx) async {
        final invites=await tx.query('invitations',where:'hash=? AND space=? AND revoked=0 AND expires>? AND uses<10',whereArgs:[digest(utf8.encode(secret)),space,now]);
        require(invites.isNotEmpty,'Invitation expired, revoked or exhausted',403);
        final existing=await tx.query('memberships',where:'space=? AND actor=?',whereArgs:[space,actor]);
        require(existing.isEmpty || existing.first['removed']==0,'This device was removed',403);
        if(existing.isEmpty) {
          await tx.insert('memberships',{'space':space,'actor':actor,'name':name,'role':'member','seen':now});
          await tx.rawUpdate('UPDATE invitations SET uses=uses+1 WHERE hash=?',[digest(utf8.encode(secret))]);
        }
      });
      final info=(await repository.db.query('spaces',where:'id=?',whereArgs:[space])).first;
      reply({...info,'v':1}); return;
    }
    final members=await repository.db.query('memberships',where:'space=? AND actor=? AND removed=0',whereArgs:[space,actor]);
    require(members.isNotEmpty,'Join this space with a valid invitation',403);
    await repository.db.update('memberships',{'seen':now},where:'space=? AND actor=?',whereArgs:[space,actor]);
    if(route=='events' && req.method=='GET') {
      final cursor=int.tryParse(req.uri.queryParameters['after']??'0'); require(cursor!=null && cursor>=0,'Invalid cursor');
      final events=await repository.db.query('events',where:'space=? AND seq>?',whereArgs:[space,cursor],orderBy:'seq',limit:10);
      reply({'events':events.map((e)=>{...jsonDecode(e['body'] as String) as Json,'seq':e['seq'],'committed':e['committed']}).toList()});
    } else if(route=='events' && req.method=='POST') {
      reply(await repository.commit(space,actor,data()));
    } else if(route=='members' && req.method=='GET') {
      reply({'members':await repository.db.query('memberships',where:'space=? AND removed=0',whereArgs:[space],limit:200)});
    } else if(route=='leave' && req.method=='POST') {
      require(members.first['role']!='host','Stop hosting to disconnect the host');
      await repository.db.delete('memberships',where:'space=? AND actor=?',whereArgs:[space,actor]); reply({'left':true});
    } else if(route=='invite/revoke' && req.method=='POST') {
      require(members.first['role']=='host','Host role required',403);
      await repository.db.update('invitations',{'revoked':1},where:'space=?',whereArgs:[space]); reply({'revoked':true});
    } else if(route.startsWith('media/')) {
      await _media(req,actor,parts.last,bytes,reply);
    } else { throw const ProtocolError(404,'Unknown operation'); }
  }
  File file(String hash,{bool partial=false})=>File('${mediaDir.path}/$space-$hash${partial?'.partial':''}');
  Future<void> _media(HttpRequest req,String actor,String hash,List<int> bytes,void Function(Object) reply) async {
    require(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash),'Invalid media hash');
    final db=repository.db;
    final records=await db.query('media',where:'space=? AND hash=?',whereArgs:[space,hash]);
    if(req.method=='GET') {
      require(records.isNotEmpty && records.first['complete']==1,'Media unavailable',404);
      final posts=await db.query('entities',columns:['body'],where:"space=? AND kind='post' AND deleted=0",whereArgs:[space]);
      require(records.first['owner']==actor || posts.any((p)=>(jsonDecode(p['body'] as String)['media'] as List? ?? []).contains(hash)),'No accessible post references this media',403);
      final f=file(hash); require(await f.exists(),'Original unavailable',404);
      final size=await f.length(); final offset=int.tryParse(req.uri.queryParameters['offset']??'0');
      require(offset!=null && offset>=0 && offset<=size,'Invalid resume offset',416);
      req.response.headers.set('x-media-size','$size');
      await req.response.addStream(f.openRead(offset,min(size,offset!+chunkSize))); return;
    }
    require(req.method=='PUT','Unsupported media method',405);
    require(_writing.add(hash),'Transfer already active; retry',429);
    try {
      final size=int.tryParse(req.uri.queryParameters['size']??'');
      final offset=int.tryParse(req.uri.queryParameters['offset']??'');
      require(size!=null && size>0 && size<=maxImageBytes,'Images must be at most 20 MB',413);
      require(offset!=null && offset>=0 && offset+bytes.length<=size!,'Invalid chunk offset');
      if(records.isNotEmpty) {
        require(records.first['owner']==actor && records.first['size']==size,'Media belongs to another upload',403);
        if(records.first['complete']==1) { reply({'offset':size,'complete':true}); return; }
      } else {
        final total=(await db.rawQuery('SELECT COALESCE(SUM(size),0) AS total FROM media')).first['total'] as int;
        require(total+size!<=cacheQuota,'Host media quota reached',507);
        await db.insert('media',{'space':space,'hash':hash,'owner':actor,'size':size,'mime':'image/unknown'});
      }
      final partial=file(hash,partial:true);
      final current=await partial.exists()?await partial.length():0;
      if(current!=offset) { reply({'offset':current,'complete':false}); return; }
      final sink=partial.openWrite(mode:FileMode.append); sink.add(bytes); await sink.flush(); await sink.close();
      final received=await partial.length();
      if(received==size) {
        if((await sha256.bind(partial.openRead()).first).toString()!=hash) { await partial.delete(); throw const ProtocolError(422,'Corrupt media: hash mismatch'); }
        final handle=await partial.open(); final head=await handle.read(1024*1024); await handle.close();
        final png=head.length>=8 && head.take(8).join(',')=='137,80,78,71,13,10,26,10';
        final jpeg=head.length>=3 && head[0]==255 && head[1]==216 && head[2]==255;
        if(!png && !jpeg) { await partial.delete(); await db.delete('media',where:'space=? AND hash=?',whereArgs:[space,hash]); throw const ProtocolError(415,'Only PNG/JPEG originals are currently supported'); }
        try { validateImageDimensions(head,png); } catch(_) {await partial.delete(); await db.delete('media',where:'space=? AND hash=?',whereArgs:[space,hash]); rethrow;}
        await partial.rename(file(hash).path);
        await db.update('media',{'complete':1,'mime':png?'image/png':'image/jpeg'},where:'space=? AND hash=?',whereArgs:[space,hash]);
      }
      reply({'offset':received,'complete':received==size});
    } finally { _writing.remove(hash); }
  }
}
class FileTransfers implements MediaTransferService {
  final LanClient client;
  final Directory directory;
  FileTransfers(this.client,this.directory);
  String path(String hash)=>'${directory.path}/${client.invite.space}-$hash';
  @override Future<String> upload(String source) async {
    final f=File(source), size=await File(source).length();
    require(size>0 && size<=maxImageBytes,'Image exceeds 20 MB');
    final hash=(await sha256.bind(f.openRead()).first).toString();
    var offset=0;
    final input=await f.open();
    try {
      while(offset<size) {
        await input.setPosition(offset); final bytes=await input.read(min(chunkSize,size-offset));
        final response=jsonDecode(utf8.decode(await client.raw('PUT','/spaces/${client.invite.space}/media/$hash?offset=$offset&size=$size',bytes))) as Json;
        final next=response['offset'] as int;
        require(next>=0 && next<=size && next!=offset,'Transfer made no progress'); offset=next;
      }
    } finally { await input.close(); }
    return hash;
  }
  @override Future<String> download(String hash) async {
    require(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash),'Invalid media hash');
    final dest=File(path(hash));
    if(await dest.exists()) return dest.path;
    await directory.create(recursive:true);
    final partial=File('${dest.path}.partial');
    var offset=await partial.exists()?await partial.length():0;
    while(true) {
      final bytes=await client.raw('GET','/spaces/${client.invite.space}/media/$hash?offset=$offset');
      require(offset+bytes.length<=maxImageBytes,'Downloaded image exceeds limit',413);
      final sink=partial.openWrite(mode:FileMode.append); sink.add(bytes); await sink.flush(); await sink.close(); offset+=bytes.length;
      if(bytes.length<chunkSize) break;
    }
    if((await sha256.bind(partial.openRead()).first).toString()!=hash) {
      await partial.delete(); throw const ProtocolError(422,'Downloaded original failed integrity check; retry');
    }
    await partial.rename(dest.path); return dest.path;
  }
}

void validateImageDimensions(List<int> bytes,bool png) {
  int width=0,height=0;
  if(png && bytes.length>=24) {
    int u32(int n)=>(bytes[n]<<24)|(bytes[n+1]<<16)|(bytes[n+2]<<8)|bytes[n+3];
    width=u32(16);height=u32(20);
  } else if(!png) {
    var pos=2;
    while(pos+8<bytes.length) {
      if(bytes[pos++]!=255) break;
      while(pos<bytes.length && bytes[pos]==255) {pos++;}
      if(pos>=bytes.length)break;
      final marker=bytes[pos++];
      if(marker==0xd9 || marker==0xda)break;
      if(pos+2>bytes.length)break;
      final length=(bytes[pos]<<8)|bytes[pos+1];
      if(length<2 || pos+length>bytes.length)break;
      if([0xc0,0xc1,0xc2].contains(marker)) {height=(bytes[pos+3]<<8)|bytes[pos+4];width=(bytes[pos+5]<<8)|bytes[pos+6];break;}
      pos+=length;
    }
  }
  require(width>0 && height>0 && width<=12000 && height<=12000 && width*height<=40000000,'Unsupported image or image dimensions exceed 40 megapixels',415);
}
