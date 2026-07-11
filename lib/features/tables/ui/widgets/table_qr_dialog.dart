import 'dart:convert';
import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme.dart';
import '../../../../core/app_icons.dart';
import '../../../../core/config/app_config.dart';
import '../../domain/pos_table.dart';

/// Dialog tampil & ekspor QR code menu untuk satu meja. QR-nya dibaca via
/// `<base>/?data=<token>` — outlet & table di-encode jadi satu token opaque
/// (URL disingkat/disamarkan). Customer scan dari meja → langsung ke menu.
class TableQrDialog extends StatelessWidget {
  final PosTable table;
  final String outletName;

  const TableQrDialog({super.key, required this.table, this.outletName = ''});

  static const _qrSizePx = 280.0;

  /// Encode (outlet + table) → token base64url tanpa padding. Format `id~id`.
  /// HARUS sama dengan sisi web (lib/menu-link.ts) agar QR bisa dibuka di
  /// halaman /menu.
  String _encodeData(String outletId, String tableId) {
    final bytes = utf8.encode('$outletId~$tableId');
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Bangun URL final yang di-embed ke QR — bentuk singkat `?data=<token>`.
  /// Outlet ID diambil dari `table.outletRemoteId` (aman untuk multi-outlet).
  String _buildUrl() {
    final base = AppConfig.makoScanQrBaseUrl.trim();
    final outletId = table.outletRemoteId ?? '';
    return '$base/?data=${_encodeData(outletId, table.id)}';
  }

  bool _isConfigured() => AppConfig.makoScanQrBaseUrl.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final url = _buildUrl();
    final outletId = table.outletRemoteId ?? '';
    final canExport = _isConfigured() && outletId.isNotEmpty;
    final repaintKey = GlobalKey();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  HugeIcon(icon: AppIcons.qrCode, color: kPrimary, size: 22),
                  const Gap(8),
                  const Expanded(
                    child: Text(
                      'QR Menu Meja',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Tutup',
                  ),
                ],
              ),
              const Gap(8),
              Text(
                'Tempel QR ini di meja "${table.name}". Customer scan → buka halaman menu otomatis.',
                style: TextStyle(fontSize: 12, color: kTextMid),
                textAlign: TextAlign.center,
              ),
              const Gap(16),

              if (!canExport)
                _UnconfiguredBanner(missingOutlet: outletId.isEmpty)
              else ...[
                // RepaintBoundary supaya kita bisa capture ke PNG saat share.
                RepaintBoundary(
                  key: repaintKey,
                  child: _QrCard(
                    table: table,
                    outletName: outletName,
                    url: url,
                  ),
                ),
                const Gap(12),
                _UrlPreview(url: url),
                const Gap(16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _ActionButton(
                      icon: Icons.copy,
                      label: 'Salin Link',
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: url));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Link disalin ke clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    _ActionButton(
                      icon: Icons.share,
                      label: 'Bagikan PNG',
                      onTap: () async {
                        final bytes = await _capturePng(repaintKey);
                        if (bytes == null) return;
                        await SharePlus.instance.share(
                          ShareParams(
                            files: [
                              XFile.fromData(
                                bytes,
                                name: '${_safeFileName(table.name)}.png',
                                mimeType: 'image/png',
                              ),
                            ],
                            text: 'QR Menu Meja ${table.name}',
                          ),
                        );
                      },
                    ),
                    _ActionButton(
                      icon: Icons.print,
                      label: 'Cetak / PDF',
                      onTap: () =>
                          _printSingle(context, table, outletName, url),
                      filled: true,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Capture widget ber-RepaintBoundary jadi PNG bytes (3x pixel ratio supaya
  /// hasil cukup tajam saat dishare/dicetak dari HP).
  static Future<Uint8List?> _capturePng(GlobalKey key) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  static String _safeFileName(String name) {
    return 'qr-menu-${name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')}';
  }

  /// Kirim 1 halaman PDF berisi QR + nama meja ke print preview / file save.
  /// Pakai package `printing` yang sudah ada untuk konsistensi dengan struk.
  Future<void> _printSingle(
    BuildContext context,
    PosTable table,
    String outletName,
    String url,
  ) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        build: (ctx) =>
            pw.Center(child: _buildPdfQrCard(table, outletName, url)),
      ),
    );
    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'QR-Menu-${table.name}',
    );
  }
}

/// Helper publik: cetak semua QR meja outlet dalam satu PDF (grid 2 kolom).
/// Dipanggil dari header group "Cetak QR semua meja".
Future<void> printOutletQrSheet({
  required List<PosTable> tables,
  required String outletName,
}) async {
  final pdf = pw.Document();
  // 4 QR per halaman A4 (grid 2x2) — ukurannya pas untuk dipotong dan
  // dilaminating jadi standing card di meja.
  const perPage = 4;
  for (var i = 0; i < tables.length; i += perPage) {
    final chunk = tables.skip(i).take(perPage).toList();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.GridView(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          children: chunk.map((t) {
            final outletId = t.outletRemoteId ?? '';
            final base = AppConfig.makoScanQrBaseUrl.trim();
            final url = '$base/?outlet=$outletId&table=${t.id}';
            return pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: _buildPdfQrCard(t, outletName, url),
            );
          }).toList(),
        ),
      ),
    );
  }
  await Printing.layoutPdf(
    onLayout: (format) async => pdf.save(),
    name: 'QR-Menu-${outletName.isEmpty ? 'Outlet' : outletName}',
  );
}

/// QR card untuk PDF (memakai widget `pdf` package, bukan Flutter widget).
pw.Widget _buildPdfQrCard(PosTable table, String outletName, String url) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(width: 1),
      borderRadius: pw.BorderRadius.circular(12),
    ),
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Text(
          'Scan untuk Pesan',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        if (outletName.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(outletName, style: const pw.TextStyle(fontSize: 10)),
        ],
        pw.SizedBox(height: 12),
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: url,
          width: 160,
          height: 160,
          color: PdfColors.black,
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey300,
            borderRadius: pw.BorderRadius.circular(16),
          ),
          child: pw.Text(
            'Meja ${table.name}',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}

/// Kartu QR yang dirender di dialog. Selain dilihat customer, ini juga
/// jadi sumber image saat tombol "Bagikan PNG" ditekan (via RepaintBoundary).
class _QrCard extends StatelessWidget {
  final PosTable table;
  final String outletName;
  final String url;

  const _QrCard({
    required this.table,
    required this.outletName,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: kDivider),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            'Scan untuk Pesan',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          if (outletName.isNotEmpty) ...[
            const Gap(2),
            Text(
              outletName,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
          const Gap(10),
          BarcodeWidget(
            barcode: Barcode.qrCode(),
            data: url,
            width: TableQrDialog._qrSizePx,
            height: TableQrDialog._qrSizePx,
            backgroundColor: Colors.white,
            color: Colors.black,
            padding: const EdgeInsets.all(8),
          ),
          const Gap(10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Meja ${table.name}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: kPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UrlPreview extends StatelessWidget {
  final String url;
  const _UrlPreview({required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kBg,
        border: Border.all(color: kDivider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        url,
        style: TextStyle(
          fontSize: 11,
          color: kTextMid,
          fontFamily: 'monospace',
        ),
        maxLines: 2,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return filled
        ? ElevatedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 16),
            label: Text(label),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          )
        : OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 16, color: kPrimary),
            label: Text(label, style: const TextStyle(color: kPrimary)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: kPrimary.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          );
  }
}

class _UnconfiguredBanner extends StatelessWidget {
  /// true → outletRemoteId kosong (data meja); false → AppConfig URL kosong.
  final bool missingOutlet;
  const _UnconfiguredBanner({required this.missingOutlet});

  @override
  Widget build(BuildContext context) {
    final msg = missingOutlet
        ? 'Meja ini tidak terhubung ke outlet manapun. Sunting meja & '
              'pastikan area-nya sudah dipasangkan ke outlet sebelum '
              'generate QR.'
        : 'URL NARA Scan QR belum diset. Tambahkan field '
              'NARA_SCAN_QR_BASE_URL di env/*.json (mis. '
              'http://localhost:3000), lalu rebuild aplikasi.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_outlined, color: Colors.orange),
          const Gap(8),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
