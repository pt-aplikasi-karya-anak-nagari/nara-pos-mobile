import 'package:audioplayers/audioplayers.dart';

/// Service singleton untuk memutar sound effect beep saat scan berhasil.
class BeepService {
  BeepService._();
  static final instance = BeepService._();

  final _player = AudioPlayer();

  /// Mainkan beep pendek (150ms, 1kHz).
  Future<void> beep() async {
    await _player.stop();
    await _player.play(AssetSource('sounds/beep.wav'));
  }
}
