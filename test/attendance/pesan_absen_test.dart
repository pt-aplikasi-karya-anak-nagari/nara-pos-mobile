import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/core/offline/tanda_tangan.dart';
import 'package:nara_pos_mobile/features/settings/data/app_settings.dart';

void main() {
  test('pesan absen sama persis dengan attendance.PesanAbsen di server', () {
    // Vektor yang sama dengan TestPesanAbsen di backend.
    expect(
      pesanAbsen(
        outletId: 'O1',
        userId: 'U1',
        jenis: 'masuk',
        waktu: '2026-10-30T07:00:00Z',
        deviceId: 'D1',
      ),
      'absen|v1|O1|U1|masuk|2026-10-30T07:00:00Z|D1',
    );
  });

  test('tanda tangan absen dibuat dari kunci perangkat', () async {
    final kunci = KunciTandaTangan(benih: List.filled(32, 7));
    final sig = await kunci.tandatanganiTeks('absen|v1|O1|U1|masuk|w|D1');
    expect(sig, isNotEmpty);
    expect(await kunci.tandatanganiTeks('absen|v1|O1|U1|masuk|w|D1'), sig,
        reason: 'Ed25519 deterministik');
  });

  test('aturan absensi dibaca dari pengaturan outlet', () {
    final st = OutletAppSettings.fromJson({
      'absen_radius_meter': 150,
      'absen_wajib_foto': true,
      'absen_perangkat_terdaftar': true,
    });
    expect(
      (st.absenRadiusMeter, st.absenWajibFoto, st.absenPerangkatTerdaftar),
      (150, true, true),
    );
    // Server lama tanpa field → semua aturan mati.
    final lama = OutletAppSettings.fromJson(const {});
    expect((lama.absenRadiusMeter, lama.absenWajibFoto), (0, false));
    // Round-trip cache.
    expect(OutletAppSettings.fromJson(st.toJson()).absenRadiusMeter, 150);
  });
}
