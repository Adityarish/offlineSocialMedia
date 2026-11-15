import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

const protocolVersion = 1;
const maxMetadata = 65536;
const chunkSize = 262144;
const maxImageBytes = 20 * 1024 * 1024;
const cacheQuota = 500 * 1024 * 1024;
typedef Json = Map<String, dynamic>;
String randomId() => base64UrlEncode(List.generate(32, (_) => Random.secure().nextInt(256))).replaceAll('=', '');
String digest(List<int> bytes) => sha256.convert(bytes).toString();
String deviceId(String publicKey) => digest(base64Decode(publicKey));
int get now => DateTime.now().millisecondsSinceEpoch;
class ProtocolError implements Exception {
  final int status;
  final String message;
  const ProtocolError(this.status, this.message);
  @override String toString() => message;
}
void require(bool condition, String message, [int status = 400]) {
  if (!condition) throw ProtocolError(status, message);
}
String boundedText(dynamic value, int max, {bool empty = false}) {
  require(value is String, 'Expected text');
  final s = (value as String).trim();
  require((empty || s.isNotEmpty) && s.length <= max, 'Text must be ${empty ? 0 : 1}–$max characters');
  return s;
}
List<int> signedBytes(String method, String path, String hash, String time, String nonce) =>
  utf8.encode('nearloop/1\n$method\n$path\n$hash\n$time\n$nonce');
class DeviceIdentity {
  final SimpleKeyPair keys;
  final String publicKey;
  DeviceIdentity(this.keys, this.publicKey);
  String get id => deviceId(publicKey);
  static Future<DeviceIdentity> create() async {
    final k = await Ed25519().newKeyPair();
    return DeviceIdentity(k, base64Encode((await k.extractPublicKey()).bytes));
  }
  static Future<DeviceIdentity> restore(String seed) async {
    final k = await Ed25519().newKeyPairFromSeed(base64Decode(seed));
    return DeviceIdentity(k, base64Encode((await k.extractPublicKey()).bytes));
  }
  Future<String> exportSeed() async => base64Encode((await keys.extract()).bytes);
  Future<Map<String,String>> headers(String method, String path, List<int> body) async {
    final time = '$now', nonce = randomId();
    final signature = await Ed25519().sign(signedBytes(method,path,digest(body),time,nonce),keyPair: keys);
    return {'x-nearloop-version':'1','x-key':publicKey,'x-time':time,'x-nonce':nonce,'x-signature':base64Encode(signature.bytes)};
  }
}
class Invitation {
  final Uri endpoint;
  final String space, pin, secret;
  Invitation(this.endpoint,this.space,this.pin,this.secret) {
    require(endpoint.scheme == 'https' && endpoint.host.isNotEmpty && endpoint.userInfo.isEmpty && endpoint.path.isEmpty && !endpoint.hasQuery && !endpoint.hasFragment, 'Use an HTTPS endpoint without a path');
    require(RegExp(r'^[a-f0-9]{64}$').hasMatch(pin), 'Expected SHA-256 certificate fingerprint');
    require(RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(space), 'Invalid space ID');
    require(RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(secret), 'Invalid invitation secret');
  }
  factory Invitation.parse(String value) {
    final j=jsonDecode(value) as Json;
    require(j['v']==protocolVersion,'Incompatible invitation version');
    return Invitation(Uri.parse(j['endpoint']),j['space'],j['pin'],j['secret']);
  }
  String encode()=>jsonEncode({'v':1,'endpoint':'$endpoint','space':space,'pin':pin,'secret':secret});
}
enum CapabilityState { supported, unsupported, permissionDenied, radioOff, hardwareUnavailable, serviceUnavailable, unverified }
abstract interface class CapabilityService { Map<String,CapabilityState> get capabilities; }
abstract interface class IdentityStore { Future<DeviceIdentity> load(); }
abstract interface class DiscoveryService { Stream<Uri> discover(); Future<void> stop(); }
abstract interface class MembershipService { Future<void> join(Invitation invite, String name); Future<void> leave(); }
abstract interface class SpaceSession { String? get spaceId; bool get online; }
abstract interface class TransportAdapter { Future<Json> request(String method,String path,[Json? data]); void close(); }
abstract interface class SyncEngine { Future<void> synchronize(); }
abstract interface class MediaTransferService { Future<String> upload(String path); Future<String> download(String hash); }
