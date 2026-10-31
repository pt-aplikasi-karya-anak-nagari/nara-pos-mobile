import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/antrian/domain/suara_tts.dart';

// Daftar suara seperti yang dikirim Google TTS di Android.
final _android = [
  for (final m in [
    {
      'name': 'en-us-x-sfg-local',
      'locale': 'en-US',
      'quality': 'very high',
      'network_required': '0',
    },
    {
      'name': 'id-id-x-dfz-local',
      'locale': 'id-ID',
      'quality': 'normal',
      'network_required': '0',
    },
    {
      'name': 'id-id-x-idc-local',
      'locale': 'id-ID',
      'quality': 'high',
      'network_required': '0',
    },
    {
      'name': 'id-id-x-idc-network',
      'locale': 'id-ID',
      'quality': 'very high',
      'network_required': '1',
    },
    {
      'name': 'id-id-language',
      'locale': 'id-ID',
      'quality': 'low',
      'network_required': '0',
    },
  ])
    SuaraTts.dariMap(m),
];

void main() {
  test('online: suara neural (online) Indonesia paling alami', () {
    expect(
      pilihSuaraTerbaik(_android, online: true)?.nama,
      'id-id-x-idc-network',
    );
  });

  test(
    'offline: suara lokal terbaik, tak pernah suara yang butuh internet',
    () {
      expect(
        pilihSuaraTerbaik(_android, online: false)?.nama,
        'id-id-x-idc-local',
      );
    },
  );

  test('hanya ada suara online & sedang offline → null (pakai bawaan)', () {
    final s = [
      SuaraTts.dariMap({
        'name': 'id-id-x-idc-network',
        'locale': 'id-ID',
        'quality': 'very high',
        'network_required': '1',
      }),
    ];
    expect(pilihSuaraTerbaik(s, online: false), isNull);
  });

  test('tak ada suara Indonesia → null', () {
    expect(pilihSuaraTerbaik([_android.first], online: true), isNull);
  });

  test('kode bahasa lama Android "in" tetap dikenali sebagai Indonesia', () {
    final s = SuaraTts.dariMap({'name': 'x', 'locale': 'in_ID'});
    expect(s.indonesia, isTrue);
    expect(
      SuaraTts.dariMap({'name': 'x', 'locale': 'en-IN'}).indonesia,
      isFalse,
    );
  });

  test('iOS: premium > enhanced > default', () {
    final ios = [
      for (final m in [
        {
          'name': 'Damayanti',
          'locale': 'id-ID',
          'quality': 'default',
          'identifier': 'a',
        },
        {
          'name': 'Damayanti (Enhanced)',
          'locale': 'id-ID',
          'quality': 'enhanced',
          'identifier': 'b',
        },
        {
          'name': 'Damayanti (Premium)',
          'locale': 'id-ID',
          'quality': 'premium',
          'identifier': 'c',
        },
      ])
        SuaraTts.dariMap(m),
    ];
    final p = pilihSuaraTerbaik(ios, online: false)!;
    expect(p.nama, 'Damayanti (Premium)');
    expect(p.kePlatform, {
      'name': 'Damayanti (Premium)',
      'locale': 'id-ID',
      'identifier': 'c',
    });
  });

  test('daftar pilihan: hanya Indonesia, terbaik dulu, berlabel ramah', () {
    final d = urutkanSuaraIndonesia(_android, online: true);
    expect(d.map((s) => s.nama), [
      'id-id-x-idc-network',
      'id-id-x-idc-local',
      'id-id-x-dfz-local',
      'id-id-language',
    ]);
    expect(d.first.label(1), 'Suara 1 (paling alami, butuh internet)');
    expect(d[1].label(2), 'Suara 2 (alami)');
  });
}
