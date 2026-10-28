import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/printer/domain/receipt_settings.dart';

// Akun sosmed & WiFi tamu di struk cetak — diatur Owner di dashboard web,
// dicetak kasir. Baris harus sama persis dengan pratinjau web.

void main() {
  test('baris sosmed memakai label pendek & membuang akun kosong', () {
    final rs = OutletReceiptSettings.fromJson({
      'outlet_id': 'O1',
      'social_accounts': [
        {'platform': 'instagram', 'handle': ' @kopinara '},
        {'platform': 'tiktok', 'handle': ''},
        {'platform': 'website', 'handle': 'kopinara.id'},
      ],
      'show_social_accounts': true,
    });
    expect(rs.barisSosmed, ['IG @kopinara', 'Web kopinara.id']);
  });

  test('sosmed dimatikan → tak dicetak', () {
    final rs = OutletReceiptSettings.fromJson({
      'outlet_id': 'O1',
      'social_accounts': [
        {'platform': 'instagram', 'handle': '@kopinara'},
      ],
      'show_social_accounts': false,
    });
    expect(rs.barisSosmed, isEmpty);
  });

  test('WiFi: nama + sandi apa adanya; tanpa nama atau dimatikan → kosong', () {
    Map<String, dynamic> j(bool tampil, String ssid, String sandi) => {
          'outlet_id': 'O1',
          'show_wifi': tampil,
          'wifi_ssid': ssid,
          'wifi_password': sandi,
        };
    expect(
      OutletReceiptSettings.fromJson(j(true, 'Nara-Tamu', ' ab c ')).barisWifi,
      ['WiFi: Nara-Tamu', 'Sandi:  ab c '],
    );
    expect(
      OutletReceiptSettings.fromJson(j(true, 'Terbuka', '')).barisWifi,
      ['WiFi: Terbuka'],
    );
    expect(OutletReceiptSettings.fromJson(j(true, ' ', 'x')).barisWifi, isEmpty);
    expect(
      OutletReceiptSettings.fromJson(j(false, 'Nara', 'x')).barisWifi,
      isEmpty,
    );
  });

  test('server lama tanpa kolom baru → bawaan aman (tak ada baris)', () {
    final rs = OutletReceiptSettings.fromJson({'outlet_id': 'O1'});
    expect(rs.barisSosmed, isEmpty);
    expect(rs.barisWifi, isEmpty);
    expect(rs.showSocialAccounts, isTrue);
    expect(rs.showWifi, isFalse);
  });

  test('toJson membawa field baru', () {
    const rs = OutletReceiptSettings(
      outletId: 'O1',
      socialAccounts: [AkunSosmed(platform: 'x', handle: '@nara')],
      wifiSsid: 'A',
      wifiPassword: 'b',
      showWifi: true,
    );
    final j = rs.toJson();
    expect(j['social_accounts'], [
      {'platform': 'x', 'handle': '@nara'},
    ]);
    expect(j['wifi_ssid'], 'A');
    expect(j['show_wifi'], isTrue);
  });
}
