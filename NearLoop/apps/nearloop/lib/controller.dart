import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'package:protocol/protocol.dart';
import 'package:local_store/local_store.dart';
import 'package:transport/transport.dart';

class SecureIdentityStore implements IdentityStore {
  final FlutterSecureStorage storage;
  SecureIdentityStore(this.storage);
  @override
  Future<DeviceIdentity> load() async {
    final seed = await storage.read(key: 'identity');
    if (seed != null) return DeviceIdentity.restore(seed);
    final identity = await DeviceIdentity.create();
    await storage.write(key: 'identity', value: await identity.exportSeed());
    return identity;
  }
}

Future<Map<String, String>> makeCertificate() => Isolate.run(() {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final private = pair.privateKey as RSAPrivateKey,
      public = pair.publicKey as RSAPublicKey;
  final csr = X509Utils.generateRsaCsrPem(
    {'CN': 'NearLoop local host'},
    private,
    public,
  );
  return {
    'key': CryptoUtils.encodeRSAPrivateKeyToPem(private),
    'cert': X509Utils.generateSelfSignedCertificate(private, csr, 365),
  };
});

class NativeDiscovery implements DiscoveryService {
  nsd.Discovery? discovery;
  final StreamController<Uri> _results = StreamController.broadcast();
  @override
  Stream<Uri> discover() {
    _start();
    return _results.stream;
  }

  Future<void> _start() async {
    try {
      discovery = await nsd.startDiscovery('_nearloop._tcp');
      discovery!.addListener(() {
        for (final s in discovery!.services) {
          if (s.host != null && s.port != null)
            _results.add(Uri(scheme: 'https', host: s.host!, port: s.port!));
        }
      });
    } catch (e) {
      _results.addError(e);
    }
  }

  @override
  Future<void> stop() async {
    if (discovery != null) await nsd.stopDiscovery(discovery!);
    discovery = null;
  }
}

class AppController extends ChangeNotifier
    implements SyncEngine, SpaceSession, MembershipService, CapabilityService {
  final secure = const FlutterSecureStorage();
  late LocalRepository repo;
  late DeviceIdentity identity;
  late Directory directory;
  String name = '', bio = '', status = 'Choose a nearby space', search = '';
  @override
  String? spaceId;
  @override
  bool online = false;
  bool busy = false, saved = false, _syncing = false;
  List<Json> posts = [], pending = [], members = [];
  List<Json> profilePosts = [], explorePosts = [], recentActivity = [];
  Map<String, Json> social = {}, profiles = {};
  String spaceTitle = 'Your nearby space';
  String? lastError;
  Set<String> blockedActors = {};
  List<Json> get visibleMembers =>
      members.where((m) => !blockedActors.contains(m['actor'])).toList();
  LanHost? host;
  LanClient? client;
  Invitation? invitation;
  nsd.Registration? registration;
  Timer? timer;
  int failures = 0;
  @override
  Map<String, CapabilityState> get capabilities => {
    'LAN': CapabilityState.unverified,
    'mDNS': CapabilityState.unverified,
    'Nearby Connections': CapabilityState.unverified,
    'Bluetooth-only': CapabilityState.unsupported,
  };
  Future<void> initialize() async {
    directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    repo = await LocalRepository.open('${directory.path}/nearloop.sqlite');
    identity = await SecureIdentityStore(secure).load();
    name = await repo.setting('name') ?? '';
    bio = await repo.setting('bio') ?? '';
    spaceId = await repo.setting('activeSpace');
    if (spaceId != null && spaceId!.isEmpty) spaceId = null;
    await refresh();
  }

  Future<void> profile(String value, String about) async {
    name = boundedText(value, 60);
    bio = boundedText(about, 300, empty: true);
    await repo.setSetting('name', name);
    await repo.setSetting('bio', bio);
    if (spaceId != null)
      await enqueue('profile.set', 'profile:${identity.id}', {
        'name': name,
        'bio': bio,
      });
    notifyListeners();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      lastError = describe(e);
      status = lastError!;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String describe(Object e) {
    if (e is SocketException || e is TimeoutException)
      return 'Space unreachable. Check host, interface, firewall, VPN and router client isolation. A manual endpoint only bypasses discovery.';
    if (e is HandshakeException)
      return 'Host identity could not be verified. Compare the certificate fingerprint with the host.';
    return e is ProtocolError
        ? e.message
        : 'Operation failed: ${e.runtimeType}. Your pending content is retained.';
  }

  Future<void> createSpace(String title, InternetAddress address) async {
    await disconnect();
    final previous = spaceId == null
        ? <Map<String, Object?>>[]
        : await repo.db.query(
            'spaces',
            where: 'id=? AND host=?',
            whereArgs: [spaceId, identity.id],
          );
    final id = previous.isEmpty ? randomId() : previous.first['id'] as String;
    await repo.addSpace(id, boundedText(title, 80), identity.id);
    await repo.db.rawInsert(
      'INSERT OR REPLACE INTO memberships(space,actor,name,role,seen) VALUES(?,?,?,?,?)',
      [id, identity.id, name, 'host', now],
    );
    var cert = await secure.read(key: 'tls-cert'),
        key = await secure.read(key: 'tls-key');
    if (cert == null || key == null) {
      final pair = await makeCertificate();
      cert = pair['cert']!;
      key = pair['key']!;
      await secure.write(key: 'tls-cert', value: cert);
      await secure.write(key: 'tls-key', value: key);
    }
    final tls = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(cert))
      ..usePrivateKeyBytes(utf8.encode(key));
    host = LanHost(repo, Directory('${directory.path}/media'), id);
    final port = await host!.start(address, tls);
    final der = base64Decode(
      cert.replaceAll(RegExp(r'-----[^-]+-----|\s'), ''),
    );
    final secret = randomId();
    await repo.db.insert('invitations', {
      'hash': digest(utf8.encode(secret)),
      'space': id,
      'expires': now + 3600000,
    });
    invitation = Invitation(
      Uri(scheme: 'https', host: address.address, port: port),
      id,
      digest(der),
      secret,
    );
    spaceId = id;
    client = LanClient(invitation!, identity);
    await repo.setSetting('activeSpace', id);
    try {
      registration = await nsd.register(
        nsd.Service(
          name: 'NearLoop-${randomId().substring(0, 8)}',
          type: '_nearloop._tcp',
          port: port,
        ),
      );
    } catch (_) {
      status = 'Hosting; discovery unavailable. Share the invitation manually.';
    }
    await synchronize();
  }

  @override
  Future<void> join(Invitation invite, String name) async {
    await disconnect();
    final candidate = LanClient(invite, identity);
    try {
      final info = await candidate.request(
        'POST',
        '/spaces/${invite.space}/join',
        {'secret': invite.secret, 'name': name},
      );
      await repo.addSpace(invite.space, info['name'], info['host']);
      invitation = invite;
      spaceId = invite.space;
      client = candidate;
      await repo.setSetting('activeSpace', spaceId!);
      await synchronize();
    } catch (_) {
      candidate.close();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    timer?.cancel();
    timer = null;
    // Avoid changing clients underneath an active sync.
    while (_syncing) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    client?.close();
    client = null;
    await host?.stop();
    host = null;
    if (registration != null) {
      try {
        await nsd.unregister(registration!);
      } catch (_) {}
      registration = null;
    }
    invitation = null;
    online = false;
    status = 'Saved/offline — reconnect with a new invitation';
    notifyListeners();
  }

  @override
  Future<void> leave() async {
    if (client != null && host == null)
      await client!.request('POST', '/spaces/$spaceId/leave', {});
    await disconnect();
    spaceId = null;
    await repo.setSetting('activeSpace', '');
    await refresh();
  }

  Future<void> enqueue(
    String op,
    String entity,
    Json payload, {
    int revision = 0,
  }) async {
    require(spaceId != null, 'Join or create a space first');
    await repo.queue(spaceId!, {
      'v': 1,
      'id': randomId(),
      'space': spaceId,
      'actor': identity.id,
      'op': op,
      'entity': entity,
      'revision': revision,
      'payload': payload,
      'clientTime': now,
    });
    await refresh();
    await synchronize();
  }

  Future<void> publish(String text, List<String> sources, String alt) async {
    require(spaceId != null, 'Join a space first');
    final media = <String>[];
    for (final source in sources) {
      // Keep originals private and immutable while offline; an outbox upload precedes publication.
      final f = File(source);
      require(await f.length() <= maxImageBytes, 'Image exceeds 20 MB');
      final dest = File('${directory.path}/draft-${randomId()}');
      await f.copy(dest.path);
      media.add(dest.path);
    }
    await enqueue('post.create', randomId(), {
      'text': text,
      'media': <String>[],
      'alt': alt,
      'localFiles': media,
    });
    await repo.db.delete('drafts', where: 'space=?', whereArgs: [spaceId]);
  }

  @override
  Future<void> synchronize() async {
    if (client == null || spaceId == null || _syncing) return;
    timer?.cancel();
    _syncing = true;
    try {
      final space = spaceId!;
      final items = await repo.db.query(
        'outbox',
        where: 'space=? AND error IS NULL',
        whereArgs: [space],
        orderBy: 'rowid',
        limit: 25,
      );
      for (final item in items) {
        var e = jsonDecode(item['body'] as String) as Json;
        try {
          final p = Map<String, dynamic>.from(e['payload']);
          if (p.containsKey('localFiles')) {
            final hashes = <String>[];
            for (final path in p['localFiles'] as List) {
              hashes.add(
                await FileTransfers(
                  client!,
                  Directory('${directory.path}/cache'),
                ).upload(path),
              );
            }
            p.remove('localFiles');
            p['media'] = hashes;
            e = {...e, 'payload': p};
            // Persist the exact wire envelope BEFORE sending: retries must be byte-equivalent.
            await repo.db.update(
              'outbox',
              {'body': jsonEncode(e)},
              where: 'space=? AND id=?',
              whereArgs: [space, item['id']],
            );
          }
          await client!.request('POST', '/spaces/$space/events', e);
          await repo.db.delete(
            'outbox',
            where: 'space=? AND id=?',
            whereArgs: [space, item['id']],
          );
        } on ProtocolError catch (err) {
          if (err.status == 429 || err.status >= 500) rethrow;
          await repo.db.update(
            'outbox',
            {'error': err.message},
            where: 'space=? AND id=?',
            whereArgs: [space, item['id']],
          );
        }
      }
      // Hosting already applies commits; only clients replay into their local materialization.
      if (host == null) {
        for (var batch = 0; batch < 20; batch++) {
          final c = (await repo.db.query(
            'cursors',
            where: 'space=?',
            whereArgs: [space],
          )).first['seq'];
          final result = await client!.request(
            'GET',
            '/spaces/$space/events?after=$c',
          );
          final events = result['events'] as List;
          await repo.receive(space, events);
          if (events.length < 10) break;
        }
      }
      final result = await client!.request('GET', '/spaces/$space/members');
      members = (result['members'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      online = true;
      failures = 0;
      status = host == null
          ? 'Connected · encrypted LAN'
          : 'Hosting · keep this app in the foreground';
    } catch (e) {
      online = false;
      failures++;
      status = describe(e);
    } finally {
      _syncing = false;
      await refresh();
      if (client != null)
        timer = Timer(
          Duration(
            milliseconds: online
                ? 2000
                : min(60000, 2000 * (1 << min(failures, 5))) +
                      Random().nextInt(1000),
          ),
          synchronize,
        );
    }
  }

  Future<void> refresh({bool more = false}) async {
    if (spaceId == null) {
      posts = [];
      pending = [];
      profilePosts = [];
      explorePosts = [];
      recentActivity = [];
      social = {};
      profiles = {};
      notifyListeners();
      return;
    }
    final page = await repo.feed(
      spaceId!,
      before: more && posts.isNotEmpty
          ? posts.last['seq'] as int
          : 9223372036854775807,
      search: search,
      saved: saved,
    );
    posts = more ? [...posts, ...page] : page;
    pending = (await repo.db.query(
      'outbox',
      where: 'space=?',
      whereArgs: [spaceId],
      orderBy: 'rowid',
    )).map((r) => Map<String, dynamic>.from(r)).toList();
    await refreshSocial();
    notifyListeners();
  }

  Future<void> refreshSocial() async {
    final space = spaceId;
    if (space == null) return;
    blockedActors = (await repo.db.query(
      'blocks',
      where: 'space=?',
      whereArgs: [space],
    )).map((r) => r['actor'] as String).toSet();
    final spaces = await repo.db.query(
      'spaces',
      where: 'id=?',
      whereArgs: [space],
    );
    spaceTitle = spaces.isEmpty
        ? 'Your nearby space'
        : spaces.first['name'] as String;
    final entities = await repo.db.rawQuery(
      "SELECT * FROM entities WHERE space=? AND deleted=0 AND actor NOT IN (SELECT actor FROM blocks WHERE space=?) ORDER BY seq DESC",
      [space, space],
    );
    social = {};
    profiles = {};
    profilePosts = [];
    explorePosts = [];
    Json stats(String id) => social.putIfAbsent(
      id,
      () => {'likes': 0, 'comments': 0, 'liked': false, 'saved': false},
    );
    for (final row in entities) {
      final data = jsonDecode(row['body'] as String) as Json;
      if (row['kind'] == 'post') {
        final post = <String, dynamic>{...row, 'data': data};
        if (row['actor'] == identity.id) profilePosts.add(post);
        explorePosts.add(post);
      }
      if (row['kind'] == 'profile') profiles[row['actor'] as String] = data;
      if (row['kind'] == 'comment') {
        final s = stats(data['post']);
        s['comments'] = (s['comments'] as int) + 1;
      }
      if (row['kind'] == 'reaction' && data['liked'] == true) {
        final s = stats(data['post']);
        s['likes'] = (s['likes'] as int) + 1;
        if (row['actor'] == identity.id) s['liked'] = true;
      }
    }
    for (final row in await repo.db.query(
      'bookmarks',
      where: 'space=?',
      whereArgs: [space],
    )) {
      stats(row['entity'] as String)['saved'] = true;
    }
    // Keep offline reactions visually consistent with the last queued intent.
    for (final row in pending) {
      if (row['error'] != null) continue;
      final e = jsonDecode(row['body'] as String) as Json;
      if (e['op'] == 'reaction.set') {
        final p = e['payload'] as Json, s = stats(p['post']);
        if (s['liked'] != p['liked'])
          s['likes'] = (s['likes'] as int) + (p['liked'] == true ? 1 : -1);
        s['liked'] = p['liked'];
        s['pending'] = true;
      }
    }
    final table = spaces.isNotEmpty && spaces.first['host'] == identity.id
        ? 'events'
        : 'activity';
    recentActivity = (await repo.db.rawQuery(
      'SELECT * FROM $table WHERE space=? AND actor NOT IN (SELECT actor FROM blocks WHERE space=?) ORDER BY seq DESC LIMIT 60',
      [space, space],
    )).map((row) => {...row, 'data': jsonDecode(row['body'] as String)}).toList();
  }

  String nameFor(String actor) {
    if (actor == identity.id) return name.isEmpty ? 'You' : name;
    return profiles[actor]?['name'] as String? ??
        members.where((m) => m['actor'] == actor).firstOrNull?['name']
            as String? ??
        'Neighbor';
  }

  Future<void> toggleLike(String post) async {
    await enqueue('reaction.set', 'reaction:${identity.id}:$post', {
      'post': post,
      'liked': social[post]?['liked'] != true,
    });
  }

  Future<List<Json>> commentsFor(String post) async {
    if (spaceId == null) return [];
    final rows = await repo.db.rawQuery(
      "SELECT * FROM entities WHERE space=? AND kind='comment' AND deleted=0 AND actor NOT IN (SELECT actor FROM blocks WHERE space=?) ORDER BY seq",
      [spaceId, spaceId],
    );
    return rows
        .map(
          (r) => <String, dynamic>{
            ...r,
            'data': jsonDecode(r['body'] as String),
          },
        )
        .where((r) => r['data']['post'] == post)
        .toList();
  }

  Future<void> bookmark(String id) async {
    final r = await repo.db.query(
      'bookmarks',
      where: 'space=? AND entity=?',
      whereArgs: [spaceId, id],
    );
    if (r.isEmpty) {
      await repo.db.insert('bookmarks', {'space': spaceId, 'entity': id});
    } else {
      await repo.db.delete(
        'bookmarks',
        where: 'space=? AND entity=?',
        whereArgs: [spaceId, id],
      );
    }
    await refresh();
  }

  Future<void> block(String actor) async {
    await repo.db.rawInsert(
      'INSERT OR IGNORE INTO blocks(space,actor) VALUES(?,?)',
      [spaceId, actor],
    );
    await refresh();
  }

  Future<void> retry(String id) async {
    await repo.db.update(
      'outbox',
      {'error': null},
      where: 'space=? AND id=?',
      whereArgs: [spaceId, id],
    );
    await synchronize();
  }

  Future<void> clearCache() async {
    require(!online, 'Disconnect before clearing downloaded originals');
    final cache = Directory('${directory.path}/cache');
    if (await cache.exists()) await cache.delete(recursive: true);
    status =
        'Downloaded originals cleared. Hosted originals, posts and drafts retained.';
    notifyListeners();
  }

  Future<String> exportData() async {
    final data = <String, dynamic>{
      'format': 'nearloop-local-export-v1',
      'device': identity.id,
      'name': name,
      'bio': bio,
    };
    for (final table in [
      'spaces',
      'entities',
      'bookmarks',
      'drafts',
      'outbox',
    ]) {
      data[table] = await repo.db.query(table);
    }
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<void> deleteLocalData() async {
    await disconnect();
    await repo.close();
    for (final key in ['identity', 'tls-cert', 'tls-key']) {
      await secure.delete(key: key);
    }
    for (final entity in directory.listSync()) {
      final file = entity.path.split(Platform.pathSeparator).last;
      if (file.startsWith('nearloop.sqlite') ||
          file.startsWith('draft-') ||
          file == 'cache' ||
          file == 'media')
        await entity.delete(recursive: true);
    }
    spaceId = null;
    posts = [];
    pending = [];
    members = [];
    name = '';
    bio = '';
    await initialize();
    status = 'Local data deleted. Copies on other devices remain.';
    notifyListeners();
  }
}
