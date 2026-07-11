import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../app/theme.dart';
import '../../../../core/app_icons.dart';
import '../../../../core/i18n.dart';

/// Scanner barcode yang di-embed langsung ke dalam layout (tanpa Scaffold),
/// dirancang untuk dipakai sebagai panel kiri di layout split pada tablet.
///
/// Berbeda dengan `BarcodeScannerPage` yang bersifat one-shot (pop value),
/// widget ini tetap aktif setelah detection dan memanggil [onDetected]
/// untuk setiap kode yang valid. Ada jeda (cooldown) ~1.2 detik agar satu
/// barcode tidak terdeteksi berulang kali, dan pengguna dapat melakukan
/// pemindaian berkelanjutan tanpa keluar dari halaman.
class InlineBarcodeScanner extends ConsumerStatefulWidget {
  final ValueChanged<String> onDetected;
  final VoidCallback? onClose;

  const InlineBarcodeScanner({
    super.key,
    required this.onDetected,
    this.onClose,
  });

  @override
  ConsumerState<InlineBarcodeScanner> createState() =>
      _InlineBarcodeScannerState();
}

class _InlineBarcodeScannerState extends ConsumerState<InlineBarcodeScanner> {
  late final MobileScannerController _controller;
  bool _cooldown = false;
  String? _lastCode;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_cooldown) return;
    for (final b in capture.barcodes) {
      final value = b.rawValue;
      if (value != null && value.isNotEmpty) {
        setState(() {
          _cooldown = true;
          _lastCode = value;
        });
        widget.onDetected(value);
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) setState(() => _cooldown = false);
        });
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (_, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '${ref.t('scanner.error')}\n${error.errorCode.name}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                const _ScannerOverlay(),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Center(child: _buildStatusChip()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        decoration: const BoxDecoration(color: Colors.black),
        child: Row(
          children: [
            if (widget.onClose != null)
              _CircleIconButton(
                icon: HugeIcons.strokeRoundedCancel01,
                tooltip: ref.t('scanner.close'),
                onPressed: widget.onClose!,
              ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ref.t('scanner.title'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const Gap(2),
                  Text(
                    ref.t('scanner.multi_hint'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip() {
    if (_cooldown && _lastCode != null) {
      final display = _lastCode!.length > 18
          ? '${_lastCode!.substring(0, 18)}…'
          : _lastCode!;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: kSuccess.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HugeIcon(
              icon: AppIcons.checkCircle,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              display,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HugeIcon(
                  icon: AppIcons.qrCode, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                ref.t('scanner.hint'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (_, state, _) {
                final on = state.torchState == TorchState.on;
                return _CircleIconButton(
                  materialIcon: on ? Icons.flash_on : Icons.flash_off,
                  iconColor: on ? Colors.amber : Colors.white,
                  tooltip: ref.t('scanner.torch'),
                  onPressed: _controller.toggleTorch,
                );
              },
            ),
            const Gap(12),
            _CircleIconButton(
              materialIcon: Icons.cameraswitch,
              tooltip: ref.t('scanner.flip'),
              onPressed: _controller.switchCamera,
            ),
          ],
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconAsset? icon;
  final IconData? materialIcon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color iconColor;
  const _CircleIconButton({
    this.icon,
    this.materialIcon,
    required this.tooltip,
    required this.onPressed,
    this.iconColor = Colors.white,
  }) : assert(icon != null || materialIcon != null);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: icon != null
                ? HugeIcon(icon: icon!, color: iconColor, size: 18)
                : Icon(materialIcon, color: iconColor, size: 20),
          ),
        ),
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (_, c) {
          // Skalakan frame terhadap sisi terpendek agar tetap enak dilihat
          // baik saat panel sempit (split view) maupun lebar.
          final shortest = c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;
          final size = shortest * 0.72;
          return Center(
            child: Container(
              width: size,
              height: size * 0.65,
              decoration: BoxDecoration(
                border: Border.all(color: kPrimary, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          );
        },
      ),
    );
  }
}
