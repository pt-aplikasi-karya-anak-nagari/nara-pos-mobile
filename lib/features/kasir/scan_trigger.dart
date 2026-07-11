import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Provider sederhana untuk trigger scanner dari navbar.
/// Ketika navbar scan button ditekan, nilai di-increment.
/// KasirPage listen perubahan ini untuk membuka scanner.
class ScanTriggerNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void trigger() => state++;
}

final scanTriggerProvider =
    NotifierProvider<ScanTriggerNotifier, int>(ScanTriggerNotifier.new);
