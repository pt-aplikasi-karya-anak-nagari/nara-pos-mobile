import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:gap/gap.dart';
import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/responsive.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../data/printer_service.dart';
import '../data/printer_settings.dart';
import '../../../core/permission_service.dart';

// ─── Page ─────────────────────────────────────────────────────────────────────

class PrinterSettingsPage extends HookConsumerWidget {
  const PrinterSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(printerSettingsProvider);
    final service = ref.read(printerServiceProvider);
    final isTablet = context.isTablet;

    final devices = useState<List<BluetoothInfo>>(const []);
    final scanning = useState(false);
    final connecting = useState(false);
    final connected = useState(false);
    final btEnabled = useState(true);
    final permissionOk = useState(true);

    Future<void> refreshStatus() async {
      connected.value = await service.isConnected;
      btEnabled.value = await service.isBluetoothEnabled;
      permissionOk.value = await service.isPermissionGranted;
    }

    Future<void> loadPaired() async {
      scanning.value = true;
      try {
        await refreshStatus();
        if (!permissionOk.value) {
          scanning.value = false;
          return;
        }
        devices.value = await service.pairedDevices();
      } finally {
        scanning.value = false;
      }
    }

    Future<void> requestPermissionFlow() async {
      await ref.read(systemPermissionServiceProvider).requestNearbyDevices();
      await refreshStatus();
      if (permissionOk.value) {
        devices.value = await service.pairedDevices();
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Izin ditolak. Aktifkan lewat Pengaturan > Aplikasi > nara > Izin.',
            ),
            backgroundColor: kDanger,
          ),
        );
      }
    }

    Future<void> showPermissionSheet() async {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) => _PermissionSheet(
          onAllow: () async {
            Navigator.pop(sheetCtx);
            await requestPermissionFlow();
          },
          onLater: () => Navigator.pop(sheetCtx),
        ),
      );
    }

    useEffect(() {
      Future<void> bootstrap() async {
        await loadPaired();
        if (!permissionOk.value && context.mounted) {
          await showPermissionSheet();
        }
      }

      bootstrap();
      return null;
    }, const []);

    Future<void> connect(BluetoothInfo d) async {
      connecting.value = true;
      try {
        final ok = await service.connect(d.macAdress);
        if (ok) {
          await ref
              .read(printerSettingsProvider.notifier)
              .setDevice(mac: d.macAdress, name: d.name);
        }
        connected.value = ok;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ok ? 'Terhubung ke ${d.name}' : 'Gagal terhubung ke ${d.name}',
              ),
              backgroundColor: ok ? kSuccess : kDanger,
            ),
          );
        }
      } finally {
        connecting.value = false;
      }
    }

    Future<void> disconnect() async {
      await service.disconnect();
      connected.value = false;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Printer terputus'),
            backgroundColor: kTextMid,
          ),
        );
      }
    }

    Future<void> testPrint() async {
      final ok = await service.testPrint();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Test print berhasil dikirim ✓' : 'Gagal test print',
          ),
          backgroundColor: ok ? kSuccess : kDanger,
        ),
      );
    }

    // ── Shared state bundle ──────────────────────────────────────────────────
    final connState = _ConnState(
      connected: connected.value,
      btEnabled: btEnabled.value,
      permissionOk: permissionOk.value,
      deviceName: settings.deviceName,
    );

    final devicePanel = _DevicePanel(
      connState: connState,
      devices: devices.value,
      scanning: scanning.value,
      connecting: connecting.value,
      settings: settings,
      onScan: loadPaired,
      onConnect: connect,
      onDisconnect: disconnect,
      onTestPrint: testPrint,
      onRequestPermission: showPermissionSheet,
    );

    final settingsPanel = _SettingsPanel(
      settings: settings,
      onPaperSize: (v) =>
          ref.read(printerSettingsProvider.notifier).setPaperSize(v),
      onAutoPrint: (v) =>
          ref.read(printerSettingsProvider.notifier).setAutoPrint(v),
      onCopies: (v) => ref.read(printerSettingsProvider.notifier).setCopies(v),
    );

    // ── Layout ───────────────────────────────────────────────────────────────
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSplit = constraints.maxWidth > 800;

        if (useSplit) {
          return Scaffold(
            backgroundColor: kBg,
            body: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left panel — connection + devices
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TabletPanelHeader(
                          leading: const TabletHeaderBadge(
                            icon: AppIcons.printer,
                            color: kPrimary,
                          ),
                          title: 'Printer Thermal',
                          subtitle: 'Kelola koneksi & perangkat',
                        ),
                        Expanded(
                          child: RefreshIndicator(
                            color: kPrimary,
                            onRefresh: loadPaired,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                24,
                              ),
                              children: [devicePanel],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Divider
                  VerticalDivider(width: 1, color: kDivider),
                  // Right panel — settings + receipt header
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                            children: [
                              settingsPanel,
                              const Gap(24),
                              _HeaderEditorCard(settings: settings),
                            ],
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

        // Single-column layout
        return Scaffold(
          backgroundColor: kBg,
          appBar: isTablet
              ? null
              : AppBar(
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.white,
                  elevation: 0,
                  title: Text(
                    'Printer Thermal',
                    style: TextStyle(
                      color: kTextDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  iconTheme: IconThemeData(color: kTextDark),
                ),
          body: Column(
            children: [
              if (isTablet)
                const TabletPanelHeader(
                  leading: TabletHeaderBadge(
                    icon: AppIcons.printer,
                    color: kPrimary,
                  ),
                  title: 'Printer Thermal',
                ),
              Expanded(
                child: RefreshIndicator(
                  color: kPrimary,
                  onRefresh: loadPaired,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      devicePanel,
                      const Gap(24),
                      settingsPanel,
                      const Gap(24),
                      _HeaderEditorCard(settings: settings),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── _PanelHeader removed — now using shared TabletPanelHeader ────────────────

// ─── Connection state value-object ────────────────────────────────────────────

class _ConnState {
  final bool connected;
  final bool btEnabled;
  final bool permissionOk;
  final String deviceName;
  const _ConnState({
    required this.connected,
    required this.btEnabled,
    required this.permissionOk,
    required this.deviceName,
  });
}

// ─── Device panel (left on tablet, middle on mobile) ─────────────────────────

class _DevicePanel extends StatelessWidget {
  final _ConnState connState;
  final List<BluetoothInfo> devices;
  final bool scanning;
  final bool connecting;
  final PrinterSettings settings;
  final VoidCallback onScan;
  final Future<void> Function(BluetoothInfo) onConnect;
  final Future<void> Function() onDisconnect;
  final Future<void> Function() onTestPrint;
  final VoidCallback onRequestPermission;

  const _DevicePanel({
    required this.connState,
    required this.devices,
    required this.scanning,
    required this.connecting,
    required this.settings,
    required this.onScan,
    required this.onConnect,
    required this.onDisconnect,
    required this.onTestPrint,
    required this.onRequestPermission,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Hero status card
        _StatusHeroCard(connState: connState),
        const Gap(20),

        // ── Device list section
        _SectionLabel(
          title: 'Perangkat Paired',
          trailing: _ScanButton(scanning: scanning, onScan: onScan),
        ),
        const Gap(10),
        if (devices.isEmpty && !scanning)
          _EmptyDevicesCard(
            needPermission: !connState.permissionOk,
            btEnabled: connState.btEnabled,
            onRequestPermission: onRequestPermission,
          )
        else if (scanning)
          const _ScanningPlaceholder()
        else
          for (final d in devices)
            _DeviceTile(
              name: d.name,
              mac: d.macAdress,
              active: d.macAdress == settings.deviceMac,
              connecting: connecting && d.macAdress == settings.deviceMac,
              onTap: () => onConnect(d),
            ),

        // ── Action buttons (only when a device is saved)
        if (settings.hasDevice) ...[
          const Gap(20),
          _SectionLabel(title: 'Tindakan'),
          const Gap(10),
          _ActionButtons(
            connected: connState.connected,
            onDisconnect: onDisconnect,
            onTestPrint: onTestPrint,
          ),
        ],
      ],
    );
  }
}

// ─── Settings panel (right on tablet, below devices on mobile) ───────────────

class _SettingsPanel extends StatelessWidget {
  final PrinterSettings settings;
  final ValueChanged<PaperSize> onPaperSize;
  final ValueChanged<bool> onAutoPrint;
  final ValueChanged<int> onCopies;

  const _SettingsPanel({
    required this.settings,
    required this.onPaperSize,
    required this.onAutoPrint,
    required this.onCopies,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(title: 'Ukuran Kertas'),
        const Gap(10),
        _PaperSizeSelector(current: settings.paperSize, onChanged: onPaperSize),
        const Gap(20),
        _SectionLabel(title: 'Pengaturan Cetak'),
        const Gap(10),
        _PrintSettingsCard(
          autoPrint: settings.autoPrint,
          copies: settings.copies,
          onAutoPrint: onAutoPrint,
          onCopies: onCopies,
        ),
      ],
    );
  }
}

// ─── Hero status card ─────────────────────────────────────────────────────────

class _StatusHeroCard extends StatelessWidget {
  final _ConnState connState;
  const _StatusHeroCard({required this.connState});

  @override
  Widget build(BuildContext context) {
    final s = connState;
    final color = s.connected
        ? kSuccess
        : (!s.permissionOk || !s.btEnabled)
        ? kDanger
        : kTextMid;

    final label = !s.permissionOk
        ? 'Izin belum diberikan'
        : !s.btEnabled
        ? 'Bluetooth dimatikan'
        : s.connected
        ? 'Terhubung'
        : 'Tidak terhubung';

    final sublabel = !s.permissionOk
        ? 'Berikan izin Bluetooth untuk melanjutkan'
        : !s.btEnabled
        ? 'Aktifkan Bluetooth di pengaturan perangkat'
        : s.connected
        ? s.deviceName
        : s.deviceName.isEmpty
        ? 'Belum ada printer tersimpan'
        : '${s.deviceName} · tidak terhubung';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: s.connected ? 0.08 : 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
      ),
      child: Row(
        children: [
          // Icon with ring
          Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
              ),
              HugeIcon(
                icon: s.connected
                    ? AppIcons.printer
                    : s.permissionOk && s.btEnabled
                    ? AppIcons.bluetoothOff
                    : AppIcons.bluetooth,
                color: color,
                size: 26,
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const Gap(3),
                Text(
                  sublabel,
                  style: TextStyle(fontSize: 12, color: kTextMid),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionLabel({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: kTextMid,
            letterSpacing: 0.7,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

// ─── Scan button ──────────────────────────────────────────────────────────────

class _ScanButton extends StatelessWidget {
  final bool scanning;
  final VoidCallback onScan;
  const _ScanButton({required this.scanning, required this.onScan});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: scanning ? null : onScan,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: kPrimary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            scanning
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kPrimary,
                    ),
                  )
                : const HugeIcon(
                    icon: AppIcons.refresh,
                    color: kPrimary,
                    size: 14,
                  ),
            const SizedBox(width: 6),
            Text(
              scanning ? 'Memindai…' : 'Pindai',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty devices card ───────────────────────────────────────────────────────

class _EmptyDevicesCard extends StatelessWidget {
  final bool needPermission;
  final bool btEnabled;
  final VoidCallback? onRequestPermission;
  const _EmptyDevicesCard({
    required this.needPermission,
    required this.btEnabled,
    this.onRequestPermission,
  });

  @override
  Widget build(BuildContext context) {
    final msg = needPermission
        ? 'Izin Bluetooth belum diberikan.\nIzinkan agar nara bisa menemukan printer.'
        : !btEnabled
        ? 'Bluetooth belum aktif.\nAktifkan terlebih dahulu di pengaturan perangkat.'
        : 'Tidak ada perangkat yang sudah dipairing.\nPairing printer di pengaturan Bluetooth sistem.';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDivider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: kBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: HugeIcon(
                icon: AppIcons.bluetoothSearch,
                color: kTextLight,
                size: 30,
              ),
            ),
          ),
          const Gap(12),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: TextStyle(color: kTextMid, fontSize: 12, height: 1.5),
          ),
          if (needPermission && onRequestPermission != null) ...[
            const Gap(16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRequestPermission,
                icon: const HugeIcon(
                  icon: AppIcons.bluetooth,
                  color: Colors.white,
                  size: 16,
                ),
                label: const Text('Izinkan Bluetooth'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Scanning placeholder ─────────────────────────────────────────────────────

class _ScanningPlaceholder extends StatelessWidget {
  const _ScanningPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDivider),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary),
          ),
          SizedBox(width: 12),
          Text(
            'Mencari perangkat Bluetooth…',
            style: TextStyle(color: kTextMid, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─── Device tile ─────────────────────────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  final String name;
  final String mac;
  final bool active;
  final bool connecting;
  final VoidCallback onTap;
  const _DeviceTile({
    required this.name,
    required this.mac,
    required this.active,
    required this.connecting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: connecting ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: active ? kPrimary.withValues(alpha: 0.06) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active ? kPrimary : kDivider,
                width: active ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: active ? kPrimary.withValues(alpha: 0.1) : kBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: AppIcons.bluetooth,
                      color: active ? kPrimary : kTextMid,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: active ? kPrimary : kTextDark,
                          fontSize: 13,
                        ),
                      ),
                      const Gap(2),
                      Text(
                        mac,
                        style: TextStyle(
                          fontSize: 11,
                          color: kTextMid,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (connecting)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kPrimary,
                    ),
                  )
                else if (active)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Tersimpan',
                      style: TextStyle(
                        fontSize: 11,
                        color: kPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: kBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kDivider),
                    ),
                    child: Text(
                      'Hubungkan',
                      style: TextStyle(
                        fontSize: 11,
                        color: kTextMid,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Action buttons ───────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  final bool connected;
  final Future<void> Function() onDisconnect;
  final Future<void> Function() onTestPrint;
  const _ActionButtons({
    required this.connected,
    required this.onDisconnect,
    required this.onTestPrint,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: AppIcons.bluetoothOff,
            label: 'Putuskan',
            color: kDanger,
            enabled: connected,
            onTap: onDisconnect,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: AppIcons.printer,
            label: 'Test Print',
            color: kPrimary,
            enabled: true,
            onTap: onTestPrint,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconAsset icon;
  final String label;
  final Color color;
  final bool enabled;
  final Future<void> Function() onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? color : kTextLight;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: enabled ? 0.08 : 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: effectiveColor.withValues(alpha: enabled ? 0.3 : 0.15),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(icon: icon, color: effectiveColor, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: effectiveColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Paper size selector ──────────────────────────────────────────────────────

class _PaperSizeSelector extends StatelessWidget {
  final PaperSize current;
  final ValueChanged<PaperSize> onChanged;
  const _PaperSizeSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const sizes = [PaperSize.mm58, PaperSize.mm72, PaperSize.mm80];
    // Visual widths (proportional representation)
    const widthRatios = {
      PaperSize.mm58: 0.58,
      PaperSize.mm72: 0.72,
      PaperSize.mm80: 0.80,
    };

    return Row(
      children: sizes.map((s) {
        final active = s == current;
        final isLast = s == PaperSize.mm80;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 10),
            child: GestureDetector(
              onTap: () => onChanged(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                decoration: BoxDecoration(
                  color: active
                      ? kPrimary.withValues(alpha: 0.08)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: active ? kPrimary : kDivider,
                    width: active ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Receipt width visual
                    Container(
                      height: 48,
                      alignment: Alignment.center,
                      child: FractionallySizedBox(
                        widthFactor: widthRatios[s]!,
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: active
                                ? kPrimary.withValues(alpha: 0.12)
                                : kBg,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: active
                                  ? kPrimary.withValues(alpha: 0.4)
                                  : kDivider,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                height: 3,
                                width: double.infinity,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: active
                                      ? kPrimary.withValues(alpha: 0.5)
                                      : kDivider,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const Gap(4),
                              Container(
                                height: 2,
                                width: double.infinity,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: active
                                      ? kPrimary.withValues(alpha: 0.3)
                                      : kDivider,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const Gap(3),
                              Container(
                                height: 2,
                                width: double.infinity,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: active
                                      ? kPrimary.withValues(alpha: 0.3)
                                      : kDivider,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Gap(10),
                    Text(
                      paperSizeLabel(s),
                      style: TextStyle(
                        color: active ? kPrimary : kTextMid,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    const Gap(2),
                    Text(
                      _sizeDesc(s),
                      style: TextStyle(fontSize: 10, color: kTextMid),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _sizeDesc(PaperSize s) {
    switch (s) {
      case PaperSize.mm58:
        return 'Paling umum';
      case PaperSize.mm72:
        return 'Menengah';
      case PaperSize.mm80:
        return 'Lebih lebar';
      default:
        return '';
    }
  }
}

// ─── Print settings card ──────────────────────────────────────────────────────

class _PrintSettingsCard extends StatelessWidget {
  final bool autoPrint;
  final int copies;
  final ValueChanged<bool> onAutoPrint;
  final ValueChanged<int> onCopies;
  const _PrintSettingsCard({
    required this.autoPrint,
    required this.copies,
    required this.onAutoPrint,
    required this.onCopies,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDivider),
      ),
      child: Column(
        children: [
          // Auto-print row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: kSuccess.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: HugeIcon(
                      icon: AppIcons.checkCircle,
                      color: kSuccess,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cetak otomatis',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: kTextDark,
                          fontSize: 13,
                        ),
                      ),
                      Gap(2),
                      Text(
                        'Cetak struk saat pembayaran sukses',
                        style: TextStyle(fontSize: 11, color: kTextMid),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: autoPrint,
                  onChanged: onAutoPrint,
                  activeThumbColor: kPrimary,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: kDivider, indent: 16, endIndent: 16),
          // Copies row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: kAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: HugeIcon(
                      icon: AppIcons.receipt,
                      color: kAccent,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Jumlah salinan',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: kTextDark,
                          fontSize: 13,
                        ),
                      ),
                      Gap(2),
                      Text(
                        'Cetak beberapa rangkap sekaligus',
                        style: TextStyle(fontSize: 11, color: kTextMid),
                      ),
                    ],
                  ),
                ),
                // Stepper
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StepButton(
                      icon: AppIcons.remove,
                      color: kDanger,
                      enabled: copies > 1,
                      onTap: () => onCopies(copies - 1),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '$copies',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: kTextDark,
                        ),
                      ),
                    ),
                    _StepButton(
                      icon: AppIcons.add,
                      color: kPrimary,
                      enabled: copies < 5,
                      onTap: () => onCopies(copies + 1),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconAsset icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  const _StepButton({
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: enabled ? color.withValues(alpha: 0.1) : kBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: HugeIcon(
            icon: icon,
            color: enabled ? color : kTextLight,
            size: 16,
          ),
        ),
      ),
    );
  }
}

// ─── Header editor card (with live receipt preview) ───────────────────────────

class _HeaderEditorCard extends HookConsumerWidget {
  final PrinterSettings settings;
  const _HeaderEditorCard({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final footerCtrl = useTextEditingController(text: settings.storeFooter);
    final defaults = ref.watch(receiptHeaderDefaultsProvider);
    final footerText = useState(settings.storeFooter);
    final isTablet = context.isTablet;

    Future<void> save() async {
      await ref
          .read(printerSettingsProvider.notifier)
          .setHeader(
            name: settings.storeName,
            address: settings.storeAddress,
            footer: footerCtrl.text.trim(),
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                HugeIcon(
                  icon: AppIcons.checkCircle,
                  color: Colors.white,
                  size: 16,
                ),
                SizedBox(width: 8),
                Text('Header struk disimpan'),
              ],
            ),
            backgroundColor: kSuccess,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: kPrimary, size: 15),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nama & alamat diambil otomatis dari outlet yang login.',
                  style: TextStyle(fontSize: 11, color: kPrimary),
                ),
              ),
            ],
          ),
        ),
        const Gap(14),
        // Nama toko (read-only)
        _ReadOnlyField(
          label: 'Nama Toko',
          value: defaults.name.isEmpty ? '-' : defaults.name,
        ),
        const Gap(10),
        // Alamat (read-only)
        _ReadOnlyField(
          label: 'Alamat / Kontak',
          value: defaults.address.isEmpty ? '-' : defaults.address,
          maxLines: 2,
        ),
        if (defaults.phone.isNotEmpty) ...[
          const Gap(10),
          _ReadOnlyField(label: 'Telepon', value: defaults.phone),
        ],
        const Gap(14),
        // Footer (editable)
        Text(
          'Footer Struk',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: kTextMid,
          ),
        ),
        const Gap(6),
        TextField(
          controller: footerCtrl,
          maxLines: 2,
          style: TextStyle(fontSize: 13, color: kTextDark),
          onChanged: (v) => footerText.value = v,
          decoration: InputDecoration(
            hintText: 'Misal: Terima kasih atas kunjungan Anda 😊',
            hintStyle: TextStyle(fontSize: 12, color: kTextLight),
            filled: true,
            fillColor: kBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kPrimary, width: 1.5),
            ),
          ),
        ),
        const Gap(14),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: save,
            icon: const HugeIcon(
              icon: AppIcons.checkCircle,
              color: Colors.white,
              size: 18,
            ),
            label: const Text(
              'Simpan Header',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );

    final preview = _ReceiptPreview(
      storeName: defaults.name.isEmpty ? 'Nama Toko' : defaults.name,
      storeAddress: defaults.address.isEmpty ? 'Alamat toko' : defaults.address,
      storePhone: defaults.phone,
      footer: footerText.value,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(title: 'Header Struk'),
        const Gap(10),
        // On tablet: side-by-side form + preview
        if (isTablet)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kDivider),
                  ),
                  child: form,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pratinjau Struk',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kTextMid,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Gap(10),
                    preview,
                  ],
                ),
              ),
            ],
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kDivider),
            ),
            child: form,
          ),
          const Gap(16),
          Text(
            'PRATINJAU STRUK',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: kTextMid,
              letterSpacing: 0.7,
            ),
          ),
          const Gap(10),
          preview,
        ],
      ],
    );
  }
}

// ─── Read-only field ──────────────────────────────────────────────────────────

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final int maxLines;
  const _ReadOnlyField({
    required this.label,
    required this.value,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: kTextMid,
          ),
        ),
        const Gap(6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: kBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: kTextMid),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: kTextLight,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Receipt preview widget ───────────────────────────────────────────────────

class _ReceiptPreview extends StatelessWidget {
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final String footer;
  const _ReceiptPreview({
    required this.storeName,
    required this.storeAddress,
    required this.storePhone,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8D5B0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Receipt "paper"
          Container(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Logo placeholder
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Text(
                      'M',
                      style: TextStyle(
                        color: kPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const Gap(6),
                Text(
                  storeName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: kTextDark,
                    letterSpacing: 0.3,
                  ),
                ),
                if (storeAddress.isNotEmpty) ...[
                  const Gap(2),
                  Text(
                    storeAddress,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      color: kTextMid,
                      height: 1.4,
                    ),
                  ),
                ],
                if (storePhone.isNotEmpty) ...[
                  const Gap(1),
                  Text(
                    storePhone,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9, color: kTextMid),
                  ),
                ],
                const Gap(10),
                _Dotted(),
                const Gap(8),
                // Sample items
                _PreviewRow(label: 'Kopi Susu x1', value: 'Rp 25.000'),
                const Gap(3),
                _PreviewRow(label: 'Roti Bakar x2', value: 'Rp 30.000'),
                const Gap(8),
                _Dotted(),
                const Gap(6),
                _PreviewRow(label: 'Total', value: 'Rp 55.000', bold: true),
                const Gap(10),
                _Dotted(),
                const Gap(8),
                if (footer.isNotEmpty)
                  Text(
                    footer,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      color: kTextMid,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
          const Gap(10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.visibility_outlined, size: 12, color: kTextMid),
              const SizedBox(width: 4),
              Text(
                'Pratinjau — bukan ukuran sebenarnya',
                style: TextStyle(fontSize: 10, color: kTextMid),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dotted extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        24,
        (_) => Expanded(
          child: Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            color: kDivider,
          ),
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _PreviewRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 9,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: bold ? kTextDark : kTextMid,
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }
}

// ─── Permission sheet ─────────────────────────────────────────────────────────

class _PermissionSheet extends StatelessWidget {
  final Future<void> Function() onAllow;
  final VoidCallback onLater;
  const _PermissionSheet({required this.onAllow, required this.onLater});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: kDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: HugeIcon(
                    icon: AppIcons.bluetoothSearch,
                    color: kPrimary,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Izin Perangkat Sekitar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kTextDark,
                      ),
                    ),
                    Gap(2),
                    Text(
                      'Diperlukan untuk menemukan printer',
                      style: TextStyle(fontSize: 12, color: kTextMid),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Gap(18),
          Text(
            'nara memerlukan izin untuk menemukan dan terhubung ke printer Bluetooth di sekitar Anda.',
            style: TextStyle(color: kTextMid, fontSize: 13, height: 1.5),
          ),
          const Gap(14),
          _PermissionBullet(
            icon: AppIcons.bluetoothSearch,
            text: 'Memindai printer thermal yang sudah dipairing.',
          ),
          _PermissionBullet(
            icon: AppIcons.bluetooth,
            text: 'Terhubung ke printer untuk mencetak struk.',
          ),
          _PermissionBullet(
            icon: AppIcons.checkCircle,
            text: 'nara tidak mengumpulkan lokasi atau data pribadi Anda.',
          ),
          const Gap(24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onLater,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kTextMid,
                    side: BorderSide(color: kDivider),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Nanti Saja'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onAllow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Izinkan',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PermissionBullet extends StatelessWidget {
  final IconAsset icon;
  final String text;
  const _PermissionBullet({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: HugeIcon(icon: icon, color: kPrimary, size: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                text,
                style: TextStyle(
                  color: kTextDark,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
