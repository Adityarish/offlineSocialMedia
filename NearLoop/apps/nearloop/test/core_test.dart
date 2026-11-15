import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';
import 'package:local_store/local_store.dart';
import 'package:transport/transport.dart';
import 'package:cryptography/cryptography.dart';
import '../lib/controller.dart';

void main() {
  late Directory temp;
  late LocalRepository repo;
  late DeviceIdentity owner,other;
  late String space;
  Json event(String op,String entity,Json payload,{int revision=0,String? actor})=>{'v':1,'id':randomId(),'space':space,'actor':actor??owner.id,'op':op,'entity':entity,'revision':revision,'payload':payload,'clientTime':0};
  setUp(() async {
    temp=await Directory.systemTemp.createTemp('nearloop-test-');repo=await LocalRepository.open('${temp.path}/test.sqlite');
    owner=await DeviceIdentity.create();other=await DeviceIdentity.create();space=randomId();
    await repo.addSpace(space,'Test',owner.id);
    for(final i in [owner,other]) {await repo.db.insert('memberships',{'space':space,'actor':i.id,'name':'Test','role':i==owner?'host':'member'});}
  });
  tearDown(() async {await repo.close();await temp.delete(recursive:true);});
  test('Identity seed roundtrip and request signature tamper rejection',() async {
    final restored=await DeviceIdentity.restore(await owner.exportSeed());expect(restored.id,owner.id);
    final h=await owner.headers('GET','/spaces/test',[]);
    final sig=Signature(base64Decode(h['x-signature']!),publicKey:SimplePublicKey(base64Decode(owner.publicKey),type:KeyPairType.ed25519));
    expect(await Ed25519().verify(signedBytes('GET','/spaces/test',digest([]),h['x-time']!,h['x-nonce']!),signature:sig),true);
    expect(await Ed25519().verify(signedBytes('GET','/spaces/other',digest([]),h['x-time']!,h['x-nonce']!),signature:sig),false);
  });
  test('Commit deduplication, conflicts, ownership and permanent tombstone',() async {
    final id=randomId(), create=event('post.create',randomId(),{'text':'Hello','media':[]});
    final a=await repo.commit(space,owner.id,create), b=await repo.commit(space,owner.id,create);expect(a['seq'],b['seq']);
    expect((await repo.feed(space)).length,1);
    await expectLater(repo.commit(space,other.id,event('post.edit',create['entity'],{'text':'Intruder'},revision:1,actor:other.id)),throwsA(isA<ProtocolError>()));
    await expectLater(repo.commit(space,owner.id,event('post.edit',create['entity'],{'text':'Stale'},revision:0)),throwsA(isA<ProtocolError>()));
    await repo.commit(space,owner.id,event('post.delete',create['entity'],{},revision:1));
    await expectLater(repo.commit(space,owner.id,event('post.create',create['entity'],{'text':id,'media':[]})),throwsA(isA<ProtocolError>()));
    expect(await repo.feed(space),isEmpty);
    expect((await repo.db.query('events')).length,2); // Rejected edits rolled back.
  });
  test('Space scoping, pagination, private bookmarks and blocking',() async {
    for(var i=0;i<35;i++) {await repo.commit(space,owner.id,event('post.create',randomId(),{'text':'Post $i','media':[]}));}
    final first=await repo.feed(space);expect(first.length,30);
    expect((await repo.feed(space,before:first.last['seq'])).length,5);
    expect(await repo.feed(randomId()),isEmpty);
    await repo.db.insert('bookmarks',{'space':space,'entity':first.first['id']});expect((await repo.feed(space,saved:true)).length,1);
    await repo.db.insert('blocks',{'space':space,'actor':owner.id});expect(await repo.feed(space),isEmpty);
  });
  test('Durable outbox and drafts survive reopening',() async {
    final e=event('post.create',randomId(),{'text':'Offline','media':[]});await repo.queue(space,e);
    await repo.db.insert('drafts',{'space':space,'body':'draft'});await repo.close();repo=await LocalRepository.open('${temp.path}/test.sqlite');
    expect((await repo.db.query('outbox')).single['id'],e['id']);expect((await repo.db.query('drafts')).single['body'],'draft');
  });
  test('Reaction state is unique per actor; removed member cannot replay',() async {
    final p=event('post.create',randomId(),{'text':'Post','media':[]});await repo.commit(space,owner.id,p);
    for(final liked in [true,true,false]) {await repo.commit(space,other.id,event('reaction.set','reaction:${other.id}:${p['entity']}',{'post':p['entity'],'liked':liked},actor:other.id));}
    final rows=await repo.db.query('entities',where:"kind='reaction'");expect(rows.length,1);expect(jsonDecode(rows.single['body'] as String)['liked'],false);
    await repo.db.update('memberships',{'removed':1},where:'space=? AND actor=?',whereArgs:[space,owner.id]);
    await expectLater(repo.commit(space,owner.id,p),throwsA(isA<ProtocolError>()));
  });
  test('Pinned HTTPS join, image integrity, authorization and duplicate commit',() async {
    final pem=await makeCertificate();
    final tls=SecurityContext()..useCertificateChainBytes(utf8.encode(pem['cert']!))..usePrivateKeyBytes(utf8.encode(pem['key']!));
    final host=LanHost(repo,Directory('${temp.path}/host-media'),space);
    final port=await host.start(InternetAddress.loopbackIPv4,tls);
    final secret=randomId();await repo.db.insert('invitations',{'hash':digest(utf8.encode(secret)),'space':space,'expires':now+60000});
    final pin=digest(base64Decode(pem['cert']!.replaceAll(RegExp(r'-----[^-]+-----|\s'),'')));
    final invite=Invitation(Uri(scheme:'https',host:'127.0.0.1',port:port),space,pin,secret);
    final guest=await DeviceIdentity.create(),client=LanClient(invite,await DeviceIdentity.create());
    final authorized=LanClient(invite,guest);
    try {
      await expectLater(client.request('GET','/spaces/$space/events?after=0'),throwsA(isA<ProtocolError>()));
      await authorized.request('POST','/spaces/$space/join',{'secret':secret,'name':'Guest'});
      final e=event('post.create',randomId(),{'text':'Across TLS','media':[]},actor:guest.id);
      final first=await authorized.request('POST','/spaces/$space/events',e);final again=await authorized.request('POST','/spaces/$space/events',e);expect(first['seq'],again['seq']);
      final png=base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg==');
      final original=File('${temp.path}/pixel.png');await original.writeAsBytes(png);
      final transfer=FileTransfers(authorized,Directory('${temp.path}/cache'));
      final hash=await transfer.upload(original.path);final downloaded=await transfer.download(hash);expect(digest(await File(downloaded).readAsBytes()),digest(png));
      await expectLater(client.raw('GET','/spaces/$space/media/$hash?offset=0'),throwsA(isA<ProtocolError>()));
      final bad=LanClient(Invitation(invite.endpoint,space,'0'*64,secret),guest);
      try {await expectLater(bad.request('GET','/spaces/$space/members'),throwsA(anything));} finally {bad.close();}
    } finally {client.close();authorized.close();await host.stop();}
  });
}
