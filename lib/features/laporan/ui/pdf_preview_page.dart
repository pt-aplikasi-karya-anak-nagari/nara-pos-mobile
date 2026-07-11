import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../app/theme.dart';
import '../../../core/i18n.dart';
import '../data/export_service.dart';

/// Halaman preview PDF laporan.
/// Menampilkan rendering nyata dari dokumen PDF sebelum dibagikan.
/// Tombol bagikan (share) tersedia di toolbar bawaan [PdfPreview].
class PdfPreviewPage extends ConsumerWidget {
  final ReportSummary summary;
  const PdfPreviewPage({super.key, required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ExportService();
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Light blue-grey background
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: kTextDark,
        elevation: 0,
        centerTitle: false,
        leadingWidth: 56,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Preview ${ref.t('report.export_pdf')}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kTextDark,
              ),
            ),
            Text(
              summary.periodLabel,
              style: TextStyle(
                fontSize: 11,
                color: kTextMid,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          // We can add a custom share button here if needed, 
          // but PdfPreview has its own in the toolbar.
          const SizedBox(width: 16),
        ],
      ),
      body: Container(
        margin: isTablet 
            ? const EdgeInsets.symmetric(horizontal: 40, vertical: 20)
            : EdgeInsets.zero,
        decoration: isTablet ? BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ) : null,
        clipBehavior: Clip.antiAlias,
        child: PdfPreview(
          build: (format) async {
            final doc = await service.buildPdfDocument(summary);
            return doc.save();
          },
          pdfFileName: service.buildFileName(summary.periodLabel, 'pdf'),
          allowPrinting: true,
          allowSharing: true,
          canDebug: false,
          canChangeOrientation: false,
          canChangePageFormat: false,
          // Premium styling for the preview
          maxPageWidth: isTablet ? 700 : null,
          padding: const EdgeInsets.all(16),
          previewPageMargin: const EdgeInsets.only(bottom: 16),
          loadingWidget: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: kPrimary,
                  strokeWidth: 3,
                ),
                SizedBox(height: 16),
                Text(
                  'Menyiapkan Dokumen…',
                  style: TextStyle(
                    fontSize: 14,
                    color: kTextMid,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          onError: (_, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, color: kDanger, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Gagal membuat PDF:\n$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: kDanger,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
