import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/core/device_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ID perangkat menegakkan "satu staf = satu perangkat" di server. Kalau ID
// berganti di tablet yang sama, stafnya ditolak sebagai "perangkat lain".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('ID dibuat sekali lalu tetap sama di peluncuran berikutnya', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final pertama = await DeviceIdentity.load(prefs);
    final kedua = await DeviceIdentity.load(prefs);

    expect(pertama.id, hasLength(32));
    expect(kedua.id, pertama.id);
    expect(DeviceIdentity.current.id, pertama.id);
  });

  test('ID pulih dari keystore bila SharedPreferences terhapus', () async {
    FlutterSecureStorage.setMockInitialValues({'device.id': 'abc123'});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final id = await DeviceIdentity.load(prefs);

    expect(id.id, 'abc123');
    expect(prefs.getString('device.id'), 'abc123');
  });

  test('ID dari SharedPreferences dipakai walau keystore dikosongkan', () async {
    // AuthStorage mengosongkan keystore saat datanya korup.
    SharedPreferences.setMockInitialValues({'device.id': 'dari-prefs'});
    final prefs = await SharedPreferences.getInstance();

    final id = await DeviceIdentity.load(prefs);

    expect(id.id, 'dari-prefs');
  });
}
