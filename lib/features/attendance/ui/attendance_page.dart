import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme.dart';
import '../../../core/image_crop.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/outlet_scope.dart';
import '../../../core/responsive.dart';
import '../data/attendance_repository.dart';
import '../domain/attendance.dart';

/// Halaman utama absensi.
///
/// **Phone**: layout vertikal — card sesi/check-in di atas, riwayat di
/// bawahnya, semuanya satu kolom yang bisa di-scroll.
///
/// **Tablet**: layout master-detail — card sesi/check-in di kiri
/// (sticky, tidak ikut scroll), riwayat di kanan dengan list yang
/// lebih luas. Pas untuk tablet horizontal supaya tidak ada whitespace
/// besar yang sia-sia.
class AttendancePage extends HookConsumerWidget {
  const AttendancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTablet = context.isTablet;

    final body = RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(activeAttendanceProvider);
        ref.invalidate(myAttendanceHistoryProvider);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      },
      child: isTablet ? const _TabletLayout() : const _PhoneLayout(),
    );

    // Saat dipanggil sebagai detail panel di tablet master-detail Profil,
    // parent sudah punya Scaffold + AppBar. Kita skip Scaffold sendiri
    // untuk hindari double app bar & background. Phone always wraps.
    if (isTablet) {
      return Container(color: kBg, child: body);
    }
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text(
          'Absensi',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        elevation: 0,
      ),
      body: body,
    );
  }
}

/// Phone layout — single column scrollable.
class _PhoneLayout extends ConsumerWidget {
  const _PhoneLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(activeAttendanceProvider);
    final historyAsync = ref.watch(myAttendanceHistoryProvider);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        activeAsync.when(
          loading: () => const _SkeletonCard(),
          error: (e, _) => _ErrorCard(message: 'Gagal memuat: $e'),
          data: (active) => active != null
              ? _ActiveSessionCard(attendance: active)
              : const _CheckInCard(),
        ),
        const Gap(24),
        Text(
          'Riwayat Absensi',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: kTextDark,
          ),
        ),
        const Gap(8),
        historyAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _ErrorCard(message: 'Gagal memuat riwayat: $e'),
          data: (items) => items.isEmpty
              ? _EmptyHistory()
              : Column(
                  children:
                      items.map((a) => _HistoryTile(attendance: a)).toList(),
                ),
        ),
      ],
    );
  }
}

/// Tablet layout — kiri: action card (sticky), kanan: riwayat list.
class _TabletLayout extends ConsumerWidget {
  const _TabletLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(activeAttendanceProvider);
    final historyAsync = ref.watch(myAttendanceHistoryProvider);

    // Lebar kolom kiri responsive — semakin lebar layar, semakin lebar
    // panel action (max 480 supaya tidak terlalu lebar di iPad besar).
    final leftWidth = context.responsive<double>(
      compact: 320,
      medium: 380,
      expanded: 420,
      large: 480,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Kolom kiri: action card (sticky di tablet)
          SizedBox(
            width: leftWidth,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _PageHeader(),
                  const Gap(16),
                  activeAsync.when(
                    loading: () => const _SkeletonCard(),
                    error: (e, _) => _ErrorCard(message: 'Gagal memuat: $e'),
                    data: (active) => active != null
                        ? _ActiveSessionCard(attendance: active)
                        : const _CheckInCard(),
                  ),
                ],
              ),
            ),
          ),
          const Gap(24),
          // ── Kolom kanan: riwayat
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'Riwayat Absensi',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: kTextDark,
                      ),
                    ),
                    const Spacer(),
                    historyAsync.maybeWhen(
                      data: (items) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${items.length} sesi',
                          style: const TextStyle(
                            color: kPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      orElse: () => const SizedBox.shrink(),
                    ),
                  ],
                ),
                const Gap(12),
                Expanded(
                  child: historyAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) =>
                        _ErrorCard(message: 'Gagal memuat riwayat: $e'),
                    data: (items) => items.isEmpty
                        ? _EmptyHistory()
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: items.length,
                            itemBuilder: (_, i) =>
                                _HistoryTile(attendance: items[i]),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.access_time, color: kPrimary, size: 22),
        ),
        const Gap(12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Absensi',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: kTextDark,
              ),
            ),
            const Gap(2),
            Text(
              'Catat jam kerja & lihat riwayat',
              style: TextStyle(color: kTextMid, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Active session ─────────────────────────────────────────────────────

class _ActiveSessionCard extends HookConsumerWidget {
  final Attendance attendance;
  const _ActiveSessionCard({required this.attendance});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live duration: rebuild teks tiap menit. Tidak perlu detik-an —
    // absensi durasinya jam-an, jadi update tiap menit cukup hemat.
    final now = useState(DateTime.now());
    useEffect(() {
      final t = Timer.periodic(
        const Duration(seconds: 30),
        (_) => now.value = DateTime.now(),
      );
      return t.cancel;
    }, const []);

    final duration = attendance.durationUntil(now.value);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kSuccess.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: kSuccess.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: kSuccess,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const Gap(6),
                    const Text(
                      'SEDANG BEKERJA',
                      style: TextStyle(
                        color: kSuccess,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Gap(12),
          Text(
            '${hours}j ${minutes}m',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: kTextDark,
              height: 1.1,
            ),
          ),
          const Gap(4),
          Text(
            'Mulai pada ${_formatDateTime(attendance.checkInAt)}',
            style: TextStyle(color: kTextMid, fontSize: 12),
          ),
          if (attendance.checkInPhotoUrl != null &&
              attendance.checkInPhotoUrl!.isNotEmpty) ...[
            const Gap(12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                resolveAssetUrl(attendance.checkInPhotoUrl),
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
          const Gap(16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _checkOut(context, ref),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text(
                'Absen Pulang',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kDanger,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkOut(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<_AbsenSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AbsenSheet(
        title: 'Absen Pulang',
        subtitle: 'Foto opsional — bisa skip kalau tidak diperlukan.',
        confirmLabel: 'Konfirmasi Pulang',
        confirmColor: kDanger,
      ),
    );
    if (result == null) return;
    try {
      await ref.read(attendanceRepositoryProvider).checkOut(
            attendance.id,
            photoUrl: result.photoUrl,
            notes: result.notes,
          );
      ref.invalidate(activeAttendanceProvider);
      ref.invalidate(myAttendanceHistoryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Berhasil absen pulang'),
            backgroundColor: kSuccess,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal absen pulang: $e'),
            backgroundColor: kDanger,
          ),
        );
      }
    }
  }
}

// ─── Check-in card (saat tidak ada sesi aktif) ──────────────────────────

class _CheckInCard extends ConsumerWidget {
  const _CheckInCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kDivider),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.access_time_filled,
              color: kPrimary,
              size: 32,
            ),
          ),
          const Gap(12),
          Text(
            'Belum absen hari ini',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: kTextDark,
            ),
          ),
          const Gap(4),
          Text(
            'Tap tombol di bawah untuk mulai sesi kerja.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kTextMid, fontSize: 12),
          ),
          const Gap(20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _checkIn(context, ref),
              icon: const Icon(Icons.login, size: 18),
              label: const Text(
                'Absen Masuk',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkIn(BuildContext context, WidgetRef ref) async {
    final outletId = ref.read(activeOutletIdProvider);
    if (outletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Outlet aktif tidak ditemukan')),
      );
      return;
    }
    final result = await showModalBottomSheet<_AbsenSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AbsenSheet(
        title: 'Absen Masuk',
        subtitle: 'Foto opsional — bisa skip kalau tidak diperlukan.',
        confirmLabel: 'Konfirmasi Masuk',
        confirmColor: kPrimary,
      ),
    );
    if (result == null) return;
    try {
      await ref.read(attendanceRepositoryProvider).checkIn(
            outletId: outletId,
            photoUrl: result.photoUrl,
            notes: result.notes,
          );
      ref.invalidate(activeAttendanceProvider);
      ref.invalidate(myAttendanceHistoryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Berhasil absen masuk'),
            backgroundColor: kSuccess,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal absen masuk: $e'),
            backgroundColor: kDanger,
          ),
        );
      }
    }
  }
}

// ─── Bottom sheet untuk check-in / check-out ────────────────────────────

class _AbsenSheetResult {
  final String? photoUrl;
  final String? notes;
  const _AbsenSheetResult({this.photoUrl, this.notes});
}

class _AbsenSheet extends HookConsumerWidget {
  final String title;
  final String subtitle;
  final String confirmLabel;
  final Color confirmColor;
  const _AbsenSheet({
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoPath = useState<String?>(null);
    final photoUrl = useState<String?>(null);
    final uploading = useState(false);
    final notesCtrl = useTextEditingController();

    Future<void> capture() async {
      try {
        final picker = ImagePicker();
        // Source: CAMERA langsung, bukan gallery. Sesuai requirement —
        // foto absensi harus dari kamera supaya tidak bisa dipalsukan
        // dengan upload foto lama.
        final picked = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1280,
          maxHeight: 1280,
          imageQuality: 80,
          preferredCameraDevice: CameraDevice.front,
        );
        if (picked == null) return;
        // Crop ke 1:1 sebelum upload — foto absensi standar kotak.
        // User batal (return null) → tidak lanjut upload.
        final croppedPath = await ImageCrop.square(
          picked.path,
          title: 'Sesuaikan foto absensi',
        );
        if (croppedPath == null) return;
        photoPath.value = croppedPath;
        uploading.value = true;
        try {
          final url = await ref
              .read(attendanceRepositoryProvider)
              .uploadPhoto(croppedPath);
          photoUrl.value = url;
        } finally {
          uploading.value = false;
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal ambil foto: $e')),
          );
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: kDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kTextDark,
            ),
          ),
          const Gap(2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: kTextMid),
          ),
          const Gap(16),
          // Camera capture area
          if (photoPath.value == null)
            OutlinedButton.icon(
              onPressed: capture,
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Ambil Foto (Opsional)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kPrimary,
                side: const BorderSide(color: kPrimary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size.fromHeight(48),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kDivider),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Image.file(
                    File(photoPath.value!),
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                  if (uploading.value)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.4),
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: kDanger,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: uploading.value
                            ? null
                            : () {
                                photoPath.value = null;
                                photoUrl.value = null;
                              },
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Gap(12),
          TextField(
            controller: notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Catatan (opsional)',
              hintText: 'Mis. Terlambat karena macet',
            ),
          ),
          const Gap(20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: uploading.value
                  ? null
                  : () => Navigator.pop(
                        context,
                        _AbsenSheetResult(
                          photoUrl: photoUrl.value,
                          notes: notesCtrl.text.trim(),
                        ),
                      ),
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                confirmLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── History list ───────────────────────────────────────────────────────

class _HistoryTile extends StatelessWidget {
  final Attendance attendance;
  const _HistoryTile({required this.attendance});

  @override
  Widget build(BuildContext context) {
    final isActive = attendance.isActive;
    final duration = attendance.durationUntil(DateTime.now());
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showDialog(
            context: context,
            builder: (_) => _AttendanceDetailDialog(attendance: attendance),
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kDivider),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color:
                        (isActive ? kSuccess : kPrimary).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isActive ? Icons.work_outline : Icons.check_circle_outline,
                    color: isActive ? kSuccess : kPrimary,
                    size: 20,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDateOnly(attendance.checkInAt),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: kTextDark,
                          fontSize: 13,
                        ),
                      ),
                      const Gap(2),
                      Text(
                        isActive
                            ? 'Masuk ${_formatTimeOnly(attendance.checkInAt)} · Sedang bekerja'
                            : 'Masuk ${_formatTimeOnly(attendance.checkInAt)} → Pulang ${_formatTimeOnly(attendance.checkOutAt!)}',
                        style: TextStyle(color: kTextMid, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${hours}j ${minutes}m',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: isActive ? kSuccess : kTextDark,
                        fontSize: 12,
                      ),
                    ),
                    const Gap(2),
                    Icon(
                      Icons.chevron_right,
                      color: kTextMid,
                      size: 16,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog yang menampilkan detail satu sesi absensi:
///   - Status badge (sedang bekerja / selesai)
///   - Jam masuk & jam pulang side-by-side, plus durasi total
///   - Foto check-in & check-out (kalau ada) — bisa di-tap untuk
///     full-screen viewer
///   - Catatan
///   - Outlet ID & ID sesi (untuk audit trace)
class _AttendanceDetailDialog extends StatelessWidget {
  final Attendance attendance;
  const _AttendanceDetailDialog({required this.attendance});

  @override
  Widget build(BuildContext context) {
    final isActive = attendance.isActive;
    final duration = attendance.durationUntil(DateTime.now());
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: kCard,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (isActive ? kSuccess : kPrimary)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isActive ? Icons.work : Icons.check_circle,
                        color: isActive ? kSuccess : kPrimary,
                        size: 24,
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDateOnly(attendance.checkInAt),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: kTextDark,
                            ),
                          ),
                          const Gap(2),
                          _StatusBadge(isActive: isActive),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      color: kTextMid,
                    ),
                  ],
                ),
                const Gap(20),
                // Durasi besar
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: (isActive ? kSuccess : kPrimary)
                        .withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: (isActive ? kSuccess : kPrimary)
                          .withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        isActive ? 'Sudah berjalan' : 'Durasi kerja',
                        style: TextStyle(
                          color: kTextMid,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Gap(4),
                      Text(
                        '${hours}j ${minutes}m',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: isActive ? kSuccess : kTextDark,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(16),
                // Check-in & Check-out timeline
                _TimelineRow(
                  icon: Icons.login,
                  iconColor: kPrimary,
                  label: 'Absen Masuk',
                  time: _formatDateTime(attendance.checkInAt),
                  photoUrl: attendance.checkInPhotoUrl,
                ),
                const Gap(12),
                _TimelineRow(
                  icon: Icons.logout,
                  iconColor: isActive ? kTextMid : kDanger,
                  label: 'Absen Pulang',
                  time: attendance.checkOutAt != null
                      ? _formatDateTime(attendance.checkOutAt!)
                      : 'Belum dilakukan',
                  photoUrl: attendance.checkOutPhotoUrl,
                  muted: isActive,
                ),
                // Catatan (kalau ada)
                if (attendance.notes != null &&
                    attendance.notes!.isNotEmpty) ...[
                  const Gap(16),
                  _SectionLabel(label: 'Catatan'),
                  const Gap(6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kDivider),
                    ),
                    child: Text(
                      attendance.notes!,
                      style: TextStyle(color: kTextDark, fontSize: 13),
                    ),
                  ),
                ],
                const Gap(16),
                // Footer: ID sesi (audit trace)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: kBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tag, size: 12, color: kTextMid),
                      const SizedBox(width: 4),
                      Text(
                        attendance.id,
                        style: TextStyle(
                          fontSize: 10,
                          color: kTextMid,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
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

class _StatusBadge extends StatelessWidget {
  final bool isActive;
  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? kSuccess : kPrimary;
    final label = isActive ? 'SEDANG BEKERJA' : 'SELESAI';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String time;
  final String? photoUrl;
  final bool muted;
  const _TimelineRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.time,
    this.photoUrl,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: muted ? 0.05 : 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: kTextMid,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Gap(2),
              Text(
                time,
                style: TextStyle(
                  color: muted ? kTextMid : kTextDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontStyle: muted ? FontStyle.italic : FontStyle.normal,
                ),
              ),
              if (photoUrl != null && photoUrl!.isNotEmpty) ...[
                const Gap(8),
                _PhotoThumb(url: resolveAssetUrl(photoUrl)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Thumbnail foto — tap untuk lihat full-screen dengan InteractiveViewer
/// (pinch to zoom). Berguna untuk verifikasi visual oleh atasan.
class _PhotoThumb extends StatelessWidget {
  final String url;
  const _PhotoThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => _PhotoViewer(url: url),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          width: 100,
          height: 100,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: 100,
            height: 100,
            color: kBg,
            alignment: Alignment.center,
            child: Icon(Icons.broken_image_outlined, color: kTextMid),
          ),
        ),
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  final String url;
  const _PhotoViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // Foto dengan pinch-to-zoom.
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 16,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: kTextMid,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kDivider),
      ),
      child: Text(
        'Belum ada riwayat absensi.',
        style: TextStyle(color: kTextMid, fontSize: 12),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kDivider),
      ),
      alignment: Alignment.center,
      child: const CircularProgressIndicator(),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kDanger.withValues(alpha: 0.4)),
      ),
      child: Text(message, style: const TextStyle(color: kDanger)),
    );
  }
}

// ─── Format helpers ─────────────────────────────────────────────────────

String _formatDateTime(DateTime dt) {
  final d = '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  return '$d ${_formatTimeOnly(dt)}';
}

String _formatDateOnly(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}

String _formatTimeOnly(DateTime dt) {
  return '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}
