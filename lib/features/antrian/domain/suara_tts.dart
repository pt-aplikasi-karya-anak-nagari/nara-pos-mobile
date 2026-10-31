/// Suara Text-to-Speech perangkat dan cara memilih yang paling alami.
///
/// # KENAPA
///
/// Browser (Chrome/Edge) otomatis memakai suara Google neural yang terdengar
/// alami. Aplikasi memakai suara BAWAAN mesin TTS perangkat — sering kali
/// suara lokal berkualitas rendah, atau mesin pabrikan tablet yang kaku.
/// Padahal hampir semua perangkat punya suara Indonesia yang jauh lebih baik:
/// Android memberi tahu kualitas tiap suara ("very high" … "very low") dan
/// apakah ia butuh internet (suara online = neural, paling alami); iOS
/// menandai suara "premium" / "enhanced".
library;

/// Satu suara TTS, dari `FlutterTts.getVoices`.
class SuaraTts {
  const SuaraTts({
    required this.nama,
    required this.lokal,
    this.kualitas = '',
    this.butuhInternet = false,
    this.identifier = '',
  });

  final String nama;

  /// Tag bahasa, mis. "id-ID".
  final String lokal;

  /// Android: "very high" | "high" | "normal" | "low" | "very low".
  /// iOS: "premium" | "enhanced" | "default".
  final String kualitas;
  final bool butuhInternet;

  /// iOS: identifier AVSpeechSynthesisVoice.
  final String identifier;

  factory SuaraTts.dariMap(Map<dynamic, dynamic> m) => SuaraTts(
    nama: m['name']?.toString() ?? '',
    lokal: m['locale']?.toString() ?? '',
    kualitas: (m['quality']?.toString() ?? '').toLowerCase(),
    butuhInternet: '${m['network_required'] ?? ''}' == '1',
    identifier: m['identifier']?.toString() ?? '',
  );

  /// Bentuk untuk `FlutterTts.setVoice`.
  Map<String, String> get kePlatform => {
    'name': nama,
    'locale': lokal,
    if (identifier.isNotEmpty) 'identifier': identifier,
  };

  /// Suara bahasa Indonesia? Android lama memakai kode "in" untuk Indonesia.
  bool get indonesia {
    final l = lokal.toLowerCase().replaceAll('_', '-');
    return l == 'id' || l.startsWith('id-') || l == 'in' || l.startsWith('in-');
  }

  /// Skor kealamian — makin tinggi makin alami. MURNI.
  int skor({required bool online}) {
    var s = switch (kualitas) {
      'premium' => 50,
      'very high' => 40,
      'enhanced' => 35,
      'high' => 30,
      'normal' || 'default' => 15,
      'low' => 5,
      _ => 10,
    };
    if (butuhInternet) {
      // Suara online (neural) paling alami — tapi tak bisa bicara tanpa
      // internet. Saat offline jangan dipilih.
      s = online ? s + 25 : -100;
    }
    final n = nama.toLowerCase();
    if (n.contains('network')) s += online ? 5 : -100;
    if (n.contains('neural') || n.contains('wavenet')) s += 10;
    return s;
  }

  /// Label ramah untuk pilihan di pengaturan.
  String label(int urutan) {
    final ciri = <String>[
      if (kualitas == 'premium' || kualitas == 'very high')
        'paling alami'
      else if (kualitas == 'enhanced' || kualitas == 'high')
        'alami'
      else
        'standar',
      if (butuhInternet || nama.toLowerCase().contains('network'))
        'butuh internet',
    ];
    return 'Suara $urutan (${ciri.join(', ')})';
  }
}

/// Suara Indonesia paling alami yang bisa dipakai saat ini. Null bila
/// perangkat tak punya suara Indonesia. MURNI.
SuaraTts? pilihSuaraTerbaik(Iterable<SuaraTts> semua, {required bool online}) {
  SuaraTts? terbaik;
  var skorTerbaik = -1 << 30;
  for (final s in semua) {
    if (!s.indonesia) continue;
    final k = s.skor(online: online);
    if (k > skorTerbaik) {
      skorTerbaik = k;
      terbaik = s;
    }
  }
  // Yang tersisa hanya suara online padahal sedang offline.
  if (terbaik != null && skorTerbaik < 0) return null;
  return terbaik;
}

/// Suara Indonesia, terbaik dulu — untuk daftar pilihan. MURNI.
List<SuaraTts> urutkanSuaraIndonesia(
  Iterable<SuaraTts> semua, {
  required bool online,
}) {
  final id = semua.where((s) => s.indonesia).toList();
  id.sort((a, b) => b.skor(online: true).compareTo(a.skor(online: true)));
  return id;
}

/// Mesin TTS Google di Android — suara Indonesianya paling lengkap & alami.
const mesinGoogle = 'com.google.android.tts';
