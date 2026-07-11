import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';

import '../../../../app/theme.dart';
import '../../../../core/app_icons.dart';
import '../../../customers/data/customer_repository.dart';
import '../../providers.dart';

class CustomerSelector extends ConsumerWidget {
  const CustomerSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCustomer = ref.watch(activeCustomerProvider);

    return InkWell(
      onTap: () => _showCustomerPicker(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: activeCustomer != null ? kPrimary.withValues(alpha: 0.1) : kBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: activeCustomer != null
                ? kPrimary.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            HugeIcon(
              icon: AppIcons.person,
              color: activeCustomer != null ? kPrimary : kTextMid,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activeCustomer?.name ?? 'Pilih Pelanggan',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: activeCustomer != null ? kPrimary : kTextDark,
                    ),
                  ),
                  if (activeCustomer != null)
                    Text(
                      '${activeCustomer.phone} • Poin: ${activeCustomer.points} (${activeCustomer.membershipLevel})',
                      style: TextStyle(fontSize: 11, color: kTextMid),
                    ),
                ],
              ),
            ),
            if (activeCustomer != null)
              GestureDetector(
                onTap: () =>
                    ref.read(activeCustomerProvider.notifier).set(null),
                child: Icon(Icons.close, size: 18, color: kTextMid),
              )
            else
              HugeIcon(
                icon: AppIcons.chevronRight,
                size: 18,
                color: kTextMid,
              ),
          ],
        ),
      ),
    );
  }

  void _showCustomerPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CustomerPickerContent(ref: ref),
    );
  }
}

class _CustomerPickerContent extends HookConsumerWidget {
  final WidgetRef ref;
  const _CustomerPickerContent({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useState('');
    final customers = ref.watch(customersFutureProvider).value ?? [];

    final filtered = customers.where((c) {
      final q = query.value.toLowerCase().trim();
      return q.isEmpty ||
          c.name.toLowerCase().contains(q) ||
          c.phone.toLowerCase().contains(q);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: kDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Gap(16),
          Text(
            'Pilih Pelanggan',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: kTextDark,
            ),
          ),
          const Gap(16),
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: kBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              onChanged: (v) => query.value = v,
              decoration: InputDecoration(
                hintText: 'Cari nama atau nomor HP...',
                hintStyle: TextStyle(fontSize: 14, color: kTextMid),
                prefixIcon: Padding(
                  padding: EdgeInsets.all(10),
                  child: HugeIcon(
                    icon: AppIcons.search,
                    color: kTextMid,
                    size: 18,
                  ),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const Gap(16),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'Tidak ada pelanggan ditemukan',
                      style: TextStyle(color: kTextMid),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Gap(8),
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      return ListTile(
                        tileColor: kBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: CircleAvatar(
                          backgroundColor: kPrimary.withValues(alpha: 0.1),
                          child: Text(
                            c.name[0].toUpperCase(),
                            style: const TextStyle(
                              color: kPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          c.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${c.phone}${c.email.isNotEmpty ? " • ${c.email}" : ""}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            const Gap(2),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kPrimary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    c.membershipLevel,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: kPrimary,
                                    ),
                                  ),
                                ),
                                const Gap(8),
                                Text(
                                  'Poin: ${c.points}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: kTextMid,
                                  ),
                                ),
                              ],
                            ),
                            if (c.address.isNotEmpty) ...[
                              const Gap(4),
                              Text(
                                c.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: kTextMid,
                                ),
                              ),
                            ],
                          ],
                        ),
                        isThreeLine: true,
                        onTap: () {
                          ref.read(activeCustomerProvider.notifier).set(c);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
