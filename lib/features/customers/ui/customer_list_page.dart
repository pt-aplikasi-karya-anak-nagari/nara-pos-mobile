import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../../app/app_routes.dart';
import 'package:gap/gap.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/responsive.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../data/customer_repository.dart';
import '../domain/customer.dart';
import 'customer_detail_page.dart';
import 'customer_form_page.dart';

class CustomerListPage extends HookConsumerWidget {
  const CustomerListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTablet = context.isTablet;
    final customersAsync = ref.watch(customersFutureProvider);

    final selectedId = useState<String?>(null);
    final isAdding = useState<bool>(false);
    final isEditing = useState<bool>(false);
    final formRevision = useState(0);
    final masterWidth = useState<double>(350.0);
    final query = useState('');
    final searchCtrl = useTextEditingController();

    return Scaffold(
      backgroundColor: kBg,
      appBar: isTablet
          ? null
          : AppBar(
              backgroundColor: kCard,
              elevation: 0,
              iconTheme: IconThemeData(color: kTextDark),
              title: Text(
                'Database Pelanggan',
                style: TextStyle(color: kTextDark, fontWeight: FontWeight.w700),
              ),
            ),
      floatingActionButton: isTablet
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(AppRoutes.customersNew),
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Tambah'),
            ),
      body: SafeArea(
        child: customersAsync.when(
          // Skeleton loader yang meniru struktur _CustomerTile supaya
          // perubahan dari loading → data terasa mulus (layout tidak
          // melompat) dan user langsung tahu bentuk konten yang akan tiba.
          loading: () => Skeletonizer(
            enabled: true,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: 6,
              separatorBuilder: (_, _) => const Gap(8),
              itemBuilder: (_, _) => _CustomerTile(
                customer: Customer(name: 'Nama Pelanggan', phone: '08123456789'),
              ),
            ),
          ),
          error: (e, _) => Center(child: Text('$e')),
          data: (list) {
            final filtered = list.where((c) {
              final q = query.value.toLowerCase().trim();
              return q.isEmpty ||
                  c.name.toLowerCase().contains(q) ||
                  c.phone.toLowerCase().contains(q);
            }).toList();

            if (!isTablet) {
              return _PhoneList(items: filtered);
            }

            return Row(
              children: [
                SizedBox(
                  width: masterWidth.value,
                  child: _TabletMasterPanel(
                    items: filtered,
                    selectedId: selectedId.value,
                    searchCtrl: searchCtrl,
                    onSearch: (v) => query.value = v,
                    onSelect: (id) {
                      if (selectedId.value == id) {
                        selectedId.value = null;
                      } else {
                        selectedId.value = id;
                      }
                      isAdding.value = false;
                      isEditing.value = false;
                      formRevision.value++;
                    },
                    onAddNew: () {
                      selectedId.value = null;
                      isAdding.value = true;
                      isEditing.value = false;
                      formRevision.value++;
                    },
                  ),
                ),
                TabletResizableDivider(
                  onResize: (delta) {
                    final newWidth = masterWidth.value + delta;
                    if (newWidth >= 280 && newWidth <= 500) {
                      masterWidth.value = newWidth;
                    }
                  },
                ),
                Expanded(
                  child: _TabletDetailPanel(
                    key: ValueKey(
                      'customer-detail-${selectedId.value}-${isAdding.value}-${isEditing.value}-${formRevision.value}',
                    ),
                    customerId: selectedId.value,
                    isAdding: isAdding.value,
                    isEditing: isEditing.value,
                    onEdit: () => isEditing.value = true,
                    onSaved: () {
                      isAdding.value = false;
                      isEditing.value = false;
                      formRevision.value++;
                    },
                    onDeleted: () {
                      selectedId.value = null;
                      isAdding.value = false;
                      isEditing.value = false;
                      formRevision.value++;
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PhoneList extends ConsumerWidget {
  final List<Customer> items;
  const _PhoneList({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 120),
        children: [
          Center(
            child: Text(
              'Belum ada pelanggan',
              style: TextStyle(color: kTextMid),
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      color: kPrimary,
      onRefresh: () async {
        ref.invalidate(customersFutureProvider);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Gap(8),
        itemBuilder: (_, i) => _CustomerTile(customer: items[i]),
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final Customer customer;
  const _CustomerTile({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push(
          AppRoutes.customersDetail.replaceAll(':id', customer.id.toString()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  customer.name.isEmpty ? '?' : customer.name[0].toUpperCase(),
                  style: const TextStyle(
                    color: kPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: kTextDark,
                      ),
                    ),
                    const Gap(2),
                    Text(
                      '${customer.phone} • Points: ${customer.points}',
                      style: TextStyle(fontSize: 12, color: kTextMid),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: kTextLight, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabletMasterPanel extends ConsumerWidget {
  final List<Customer> items;
  final String? selectedId;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onSelect;
  final VoidCallback onAddNew;

  const _TabletMasterPanel({
    required this.items,
    required this.selectedId,
    required this.searchCtrl,
    required this.onSearch,
    required this.onSelect,
    required this.onAddNew,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: kBg,
      child: Column(
        children: [
          TabletPanelHeader(
            title: 'Pelanggan',
            subtitle: items.isNotEmpty ? '${items.length} pelanggan' : null,
            trailing: TabletAddButton(label: 'Tambah', onTap: onAddNew),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kDivider),
              ),
              child: TextField(
                controller: searchCtrl,
                onChanged: onSearch,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Cari nama atau nomor HP...',
                  prefixIcon: Icon(Icons.search, color: kTextMid, size: 18),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(customersFutureProvider);
                await Future.delayed(const Duration(milliseconds: 500));
              },
              child: items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: const TabletMasterEmptyState(
                            icon: AppIcons.person,
                            message: 'Belum ada pelanggan',
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Gap(4),
                      itemBuilder: (_, i) {
                        final c = items[i];
                        final selected = c.id == selectedId;
                        return _MasterTile(
                          customer: c,
                          isSelected: selected,
                          onTap: () => onSelect(c.id),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MasterTile extends StatelessWidget {
  final Customer customer;
  final bool isSelected;
  final VoidCallback onTap;

  const _MasterTile({
    required this.customer,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? kPrimary.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? kPrimary.withValues(alpha: 0.3)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? kPrimary.withValues(alpha: 0.15)
                      : kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  customer.name.isEmpty ? '?' : customer.name[0].toUpperCase(),
                  style: const TextStyle(
                    color: kPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected ? kPrimary : kTextDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      customer.phone,
                      style: TextStyle(fontSize: 11, color: kTextMid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: kPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabletDetailPanel extends StatelessWidget {
  final String? customerId;
  final bool isAdding;
  final bool isEditing;
  final VoidCallback onEdit;
  final VoidCallback onSaved;
  final VoidCallback onDeleted;

  const _TabletDetailPanel({
    super.key,
    required this.customerId,
    required this.isAdding,
    required this.isEditing,
    required this.onEdit,
    required this.onSaved,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    if (customerId == null && !isAdding) {
      return const TabletDetailEmptyState(
        icon: AppIcons.person,
        title: 'Database Pelanggan',
        subtitle:
            'Pilih pelanggan dari daftar di sebelah kiri\natau tambahkan pelanggan baru.',
      );
    }

    if (isAdding || (customerId != null && isEditing)) {
      return Container(
        color: kBg,
        child: Column(
          children: [
            Expanded(
              child: CustomerFormView(
                customerId: customerId,
                isEmbedded: true,
                onSaveComplete: onSaved,
              ),
            ),
          ],
        ),
      );
    }

    if (customerId != null) {
      return Container(
        color: kBg,
        child: Column(
          children: [
            Expanded(
              child: CustomerDetailView(
                customerId: customerId!,
                isEmbedded: true,
                onEdit: onEdit,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
