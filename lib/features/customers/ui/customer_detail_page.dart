import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/format.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../../transactions/data/transaction_repository.dart';
import '../data/customer_repository.dart';
import '../domain/customer.dart';

class CustomerDetailPage extends ConsumerWidget {
  final String customerId;
  const CustomerDetailPage({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Detail Pelanggan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => context.push('/profil/customers/edit/$customerId'),
          ),
        ],
      ),
      body: CustomerDetailView(customerId: customerId),
    );
  }
}

class CustomerDetailView extends ConsumerWidget {
  final String customerId;
  final bool isEmbedded;
  final VoidCallback? onEdit;
  const CustomerDetailView({
    super.key,
    required this.customerId,
    this.isEmbedded = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerDetailProvider(customerId));

    return customerAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Gagal memuat: $e')),
      data: (customer) => _buildContent(context, ref, customer),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, Customer customer) {
    // Riwayat transaksi pelanggan dari backend (langsung filter via API).
    final salesAsync = ref.watch(customerSalesProvider(customerId));
    final sales = salesAsync.value ?? const [];

    // Statistik nilai pelanggan TIDAK menghitung transaksi yang di-refund
    // (uang dikembalikan) — kalau ikut, lifetime spend, jumlah transaksi, &
    // rata-rata menggelembung salah. Daftar transaksi di bawah tetap semua.
    final paidSales = sales.where((s) => !s.isRefunded).toList();
    final totalSpent = paidSales.fold(0.0, (sum, s) => sum + s.total);
    final avgSpent = paidSales.isEmpty ? 0.0 : totalSpent / paidSales.length;

    return Builder(
      builder: (context) {
        return Column(
          children: [
            if (isEmbedded)
              TabletPanelHeader(
                leading: const TabletHeaderBadge(
                  icon: AppIcons.person,
                  color: kPrimary,
                ),
                title: 'Detail Pelanggan',
                trailing: TabletAddButton(
                  label: 'Edit',
                  onTap:
                      onEdit ??
                      () => context.push('/profil/customers/edit/$customerId'),
                ),
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(16),
                children: [
                  // Profil Info
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: kCard,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: kPrimary.withValues(alpha: 0.1),
                          child: Text(
                            customer.name[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: kPrimary,
                            ),
                          ),
                        ),
                        const Gap(16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customer.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Gap(4),
                              Text(
                                '${customer.phone} • ${customer.email}',
                                style: TextStyle(color: kTextMid, fontSize: 12),
                              ),
                              const Gap(4),
                              Text(
                                customer.address,
                                style: TextStyle(color: kTextMid, fontSize: 12),
                              ),
                              if (customer.createdBy.isNotEmpty) ...[
                                const Gap(8),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.person_outline,
                                      size: 14,
                                      color: kTextMid,
                                    ),
                                    const Gap(4),
                                    Text(
                                      'Ditambahkan oleh: ${customer.createdBy}',
                                      style: TextStyle(
                                        color: kTextMid,
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(16),

                  // Kartu Member Section
                  _MembershipCard(customer: customer),

                  const Gap(24),
                  // Analisa Perilaku
                  const Text(
                    'Analisa Perilaku',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Gap(8),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Total Transaksi',
                          value: '${paidSales.length}',
                          icon: AppIcons.receiptLong,
                          color: kPrimary,
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: _StatCard(
                          title: 'Total Belanja',
                          value: formatRupiah(totalSpent),
                          icon: AppIcons.money,
                          color: kSuccess,
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Rata-rata Belanja',
                          value: formatRupiah(avgSpent),
                          icon: AppIcons.barChart,
                          color: kAccent,
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: _StatCard(
                          title: 'Loyalty Points',
                          value:
                              '${customer.points} (${customer.membershipLevel})',
                          icon: AppIcons.favorite,
                          color: kWarning,
                        ),
                      ),
                    ],
                  ),

                  const Gap(24),
                  const Text(
                    'Riwayat Pembelian',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Gap(8),
                  if (sales.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'Belum ada riwayat pembelian',
                        style: TextStyle(color: kTextMid),
                      ),
                    )
                  else
                    ...sales.map(
                      (sale) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: kCard,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: const HugeIcon(
                            icon: AppIcons.receiptLong,
                            color: kPrimary,
                            size: 24,
                          ),
                          title: Text(
                            '#${sale.invoiceId}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(formatDate(sale.createdAt)),
                          trailing: Text(
                            formatRupiah(sale.total),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: kPrimary,
                            ),
                          ),
                          onTap: () => context.push('/riwayat/${sale.id}'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MembershipCard extends StatelessWidget {
  final dynamic customer;
  const _MembershipCard({required this.customer});

  Future<void> _printCard() async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Text(
                'MEMBERSHIP CARD',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text('NARA POS SYSTEM'),
              pw.SizedBox(height: 10),
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: customer.phone,
                width: 100,
                height: 100,
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                customer.name,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(customer.phone),
              pw.Text('Level: ${customer.membershipLevel}'),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (format) => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimary, kPrimary.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'MEMBER CARD',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              HugeIcon(
                icon: AppIcons.storefront,
                color: Colors.white.withValues(alpha: 0.5),
                size: 24,
              ),
            ],
          ),
          const Gap(20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: customer.phone,
                  width: 80,
                  height: 80,
                ),
              ),
              const Gap(20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      customer.phone,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                    const Gap(8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        customer.membershipLevel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Gap(20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _printCard,
                  icon: const Icon(Icons.print, size: 16),
                  label: const Text('Cetak Kartu'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: kPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const Gap(10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Quick share logic could go here
                    // ignore: deprecated_member_use
                    Share.share(
                      'Kartu Member ${customer.name}\nPhone: ${customer.phone}',
                    );
                  },
                  icon: const Icon(Icons.share, size: 16),
                  label: const Text('Bagikan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconAsset icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: HugeIcon(icon: icon, color: color, size: 20),
          ),
          const Gap(12),
          Text(title, style: TextStyle(color: kTextMid, fontSize: 12)),
          const Gap(4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
