import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/format.dart';
import '../../../core/outlet_scope.dart';
import '../../products/data/modifier_repository.dart';
import '../../products/domain/modifier_group.dart';

/// Halaman manajemen "Modifier & Add-on" — padanan /dashboard/modifiers di web.
/// Owner mengelola grup add-on (mis. "Topping", "Level Gula") beserta opsinya;
/// grup lalu di-attach ke produk (di form produk) dan muncul di kasir saat
/// menambah item.
class ModifierGroupsPage extends ConsumerWidget {
  const ModifierGroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outletId = ref.watch(activeOutletIdProvider);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kCard,
        elevation: 0,
        title: Text(
          'Modifier & Add-on',
          style: TextStyle(
            color: kTextDark,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        iconTheme: IconThemeData(color: kTextDark),
      ),
      floatingActionButton: outletId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(context, ref, outletId, null),
              backgroundColor: kPrimary,
              icon: const HugeIcon(icon: AppIcons.add, color: Colors.white),
              label: const Text(
                'Grup modifier',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
      body: outletId == null
          ? Center(
              child: Text(
                'Pilih outlet aktif dulu.',
                style: TextStyle(color: kTextMid),
              ),
            )
          : _GroupList(outletId: outletId),
    );
  }
}

class _GroupList extends ConsumerWidget {
  final String outletId;
  const _GroupList({required this.outletId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(modifierGroupsProvider(outletId));

    return RefreshIndicator(
      color: kPrimary,
      onRefresh: () async {
        ref.invalidate(modifierGroupsProvider(outletId));
        await Future.delayed(const Duration(milliseconds: 400));
      },
      child: async.when(
        loading: () => Skeletonizer(
          enabled: true,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: 4,
            separatorBuilder: (_, _) => const Gap(12),
            itemBuilder: (_, _) => const _GroupCard(
              group: ModifierGroup(
                id: 'x',
                name: 'Contoh grup',
                minSelect: 1,
                maxSelect: 1,
                options: [ModifierOption(id: 'o', name: 'Opsi')],
              ),
              onTap: null,
              onDelete: null,
            ),
          ),
        ),
        error: (e, _) => ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Gagal memuat: $e',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kTextMid),
                ),
              ),
            ),
          ],
        ),
        data: (groups) {
          if (groups.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        HugeIcon(
                          icon: AppIcons.discount,
                          color: kTextLight,
                          size: 48,
                        ),
                        const Gap(14),
                        Text(
                          'Belum ada grup modifier',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: kTextDark,
                            fontSize: 15,
                          ),
                        ),
                        const Gap(6),
                        Text(
                          'Buat grup add-on (mis. Topping, Level Gula), lalu '
                          'lekatkan ke produk lewat form produk. Add-on akan '
                          'muncul di kasir saat item ditambahkan.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: kTextMid, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const Gap(12),
            itemBuilder: (_, i) {
              final g = groups[i];
              return _GroupCard(
                group: g,
                onTap: () => _openEditor(context, ref, outletId, g),
                onDelete: () => _confirmDelete(context, ref, outletId, g),
              );
            },
          );
        },
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final ModifierGroup group;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  const _GroupCard({required this.group, this.onTap, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: kTextDark,
                      ),
                    ),
                  ),
                  if (onDelete != null)
                    InkWell(
                      onTap: onDelete,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: HugeIcon(
                          icon: AppIcons.delete,
                          color: kDanger,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
              const Gap(4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: group.required
                      ? kDanger.withValues(alpha: 0.1)
                      : kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  modifierRuleLabel(group),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: group.required ? kDanger : kPrimary,
                  ),
                ),
              ),
              const Gap(10),
              if (group.options.isEmpty)
                Text(
                  'belum ada opsi',
                  style: TextStyle(
                    fontSize: 12,
                    color: kTextMid,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: group.options.map((o) {
                    final muted = !o.isActive;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: kBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: kDivider),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: o.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: muted ? kTextLight : kTextDark,
                                decoration: muted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            if (o.price > 0)
                              TextSpan(
                                text: '  +${formatRupiah(o.price)}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: kPrimary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Navigasi editor + delete ─────────────────────────────────────────

Future<void> _openEditor(
  BuildContext context,
  WidgetRef ref,
  String outletId,
  ModifierGroup? group,
) async {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ModifierGroupEditPage(outletId: outletId, group: group),
    ),
  );
  if (saved == true) {
    ref.invalidate(modifierGroupsProvider(outletId));
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  String outletId,
  ModifierGroup group,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Hapus grup?'),
      content: Text(
        '"${group.name}" akan dihapus. Produk yang memakainya akan lepas.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: kDanger),
          child: const Text('Hapus'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ref
        .read(modifierRepositoryProvider)
        .deleteGroup(outletId, group.id);
    ref.invalidate(modifierGroupsProvider(outletId));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${group.name}" dihapus')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal hapus: $e'), backgroundColor: kDanger),
      );
    }
  }
}

// ── Editor (create / edit) ───────────────────────────────────────────

class _OptDraft {
  final String id; // kosong = opsi baru
  final TextEditingController name;
  final TextEditingController price;
  bool active;
  _OptDraft({
    this.id = '',
    required this.name,
    required this.price,
    this.active = true,
  });

  factory _OptDraft.from(ModifierOption o) => _OptDraft(
        id: o.id,
        name: TextEditingController(text: o.name),
        price: TextEditingController(
          text: o.price > 0 ? 'Rp ${formatThousand(o.price.toInt())}' : '',
        ),
        active: o.isActive,
      );

  factory _OptDraft.empty() => _OptDraft(
        name: TextEditingController(),
        price: TextEditingController(),
      );

  void dispose() {
    name.dispose();
    price.dispose();
  }
}

class _ModifierGroupEditPage extends ConsumerStatefulWidget {
  final String outletId;
  final ModifierGroup? group;
  const _ModifierGroupEditPage({required this.outletId, this.group});

  @override
  ConsumerState<_ModifierGroupEditPage> createState() =>
      _ModifierGroupEditPageState();
}

class _ModifierGroupEditPageState
    extends ConsumerState<_ModifierGroupEditPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _maxCtrl;
  late bool _required;
  late bool _multiple;
  late List<_OptDraft> _opts;
  bool _saving = false;

  bool get _isEdit => widget.group != null;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    _nameCtrl = TextEditingController(text: g?.name ?? '');
    _required = (g?.minSelect ?? 0) > 0;
    _multiple = (g?.maxSelect ?? 1) != 1;
    _maxCtrl = TextEditingController(text: (g?.maxSelect ?? 1).toString());
    _opts = (g?.options.isNotEmpty ?? false)
        ? g!.options.map(_OptDraft.from).toList()
        : [_OptDraft.empty()];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _maxCtrl.dispose();
    for (final o in _opts) {
      o.dispose();
    }
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? kDanger : null,
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Nama grup wajib diisi.', error: true);
      return;
    }

    // Susun opsi — skip baris tanpa nama; harga wajib >= 0.
    final options = <ModifierOption>[];
    for (final d in _opts) {
      final n = d.name.text.trim();
      if (n.isEmpty) continue;
      final price = parseRupiahInput(d.price.text).toDouble();
      if (price < 0) {
        _snack('Harga opsi "$n" tidak boleh negatif.', error: true);
        return;
      }
      options.add(ModifierOption(
        id: d.id,
        name: n,
        price: price,
        sortOrder: options.length,
        isActive: d.active,
      ));
    }
    if (options.isEmpty) {
      _snack('Minimal satu opsi.', error: true);
      return;
    }

    // Encode aturan pilih (sama seperti web):
    //   min = wajib ? 1 : 0
    //   max = multi ? (n>0 ? n : 0) : 1
    final min = _required ? 1 : 0;
    int max;
    if (_multiple) {
      final n = int.tryParse(_maxCtrl.text.trim()) ?? 0;
      max = n > 0 ? n : 0;
    } else {
      max = 1;
    }

    final group = ModifierGroup(
      id: widget.group?.id ?? '',
      name: name,
      minSelect: min,
      maxSelect: max,
      sortOrder: widget.group?.sortOrder ?? 0,
      options: options,
    );

    setState(() => _saving = true);
    try {
      final repo = ref.read(modifierRepositoryProvider);
      if (_isEdit) {
        await repo.updateGroup(widget.outletId, widget.group!.id, group);
      } else {
        await repo.createGroup(widget.outletId, group);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      _snack('Gagal menyimpan: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kCard,
        elevation: 0,
        title: Text(
          _isEdit ? 'Edit grup modifier' : 'Grup modifier baru',
          style: TextStyle(
            color: kTextDark,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        iconTheme: IconThemeData(color: kTextDark),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          const _Label('Nama grup'),
          _Wrap(
            child: TextField(
              controller: _nameCtrl,
              maxLength: 120,
              decoration: _dec('Topping / Level Gula / Ukuran Es')
                  .copyWith(counterText: ''),
            ),
          ),
          const Gap(14),

          // Aturan pilih
          _Wrap(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: kPrimary,
                  title: Text(
                    'Wajib dipilih',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: kTextDark,
                    ),
                  ),
                  subtitle: Text(
                    'Pelanggan harus memilih minimal satu opsi.',
                    style: TextStyle(fontSize: 11, color: kTextMid),
                  ),
                  value: _required,
                  onChanged: (v) => setState(() => _required = v),
                ),
                Divider(height: 1, color: kDivider),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: kPrimary,
                  title: Text(
                    'Boleh pilih lebih dari satu',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: kTextDark,
                    ),
                  ),
                  subtitle: Text(
                    _multiple
                        ? 'Multi-pilih. Atur batas maksimal di bawah.'
                        : 'Pilih satu opsi saja (single-choice).',
                    style: TextStyle(fontSize: 11, color: kTextMid),
                  ),
                  value: _multiple,
                  onChanged: (v) => setState(() => _multiple = v),
                ),
                if (_multiple) ...[
                  Divider(height: 1, color: kDivider),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Maksimal pilihan',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: kTextDark,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: _maxCtrl,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: _dec('0 = bebas'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Gap(18),

          // Opsi
          Row(
            children: [
              Expanded(
                child: Text(
                  'Opsi',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kTextDark,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _opts = [..._opts, _OptDraft.empty()]),
                icon: const HugeIcon(
                  icon: AppIcons.add,
                  color: kPrimary,
                  size: 18,
                ),
                label: const Text('Tambah opsi'),
                style: TextButton.styleFrom(foregroundColor: kPrimary),
              ),
            ],
          ),
          const Gap(6),
          for (int i = 0; i < _opts.length; i++) ...[
            _OptRow(
              draft: _opts[i],
              onToggleActive: () =>
                  setState(() => _opts[i].active = !_opts[i].active),
              onRemove: _opts.length <= 1
                  ? null
                  : () => setState(() {
                        _opts.removeAt(i).dispose();
                      }),
            ),
            const Gap(8),
          ],

          const Gap(16),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      _isEdit ? 'Simpan perubahan' : 'Buat grup',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptRow extends StatelessWidget {
  final _OptDraft draft;
  final VoidCallback onToggleActive;
  final VoidCallback? onRemove;
  const _OptRow({
    required this.draft,
    required this.onToggleActive,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return _Wrap(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: TextField(
                controller: draft.name,
                decoration: _dec('Nama opsi (mis. Boba)'),
              ),
            ),
            const Gap(8),
            Expanded(
              flex: 4,
              child: TextField(
                controller: draft.price,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: _dec('+ Rp 0'),
              ),
            ),
            const Gap(4),
            // Toggle aktif/nonaktif.
            InkWell(
              onTap: onToggleActive,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  draft.active
                      ? Icons.check_circle
                      : Icons.remove_circle_outline,
                  color: draft.active ? kSuccess : kTextLight,
                  size: 22,
                ),
              ),
            ),
            if (onRemove != null)
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: HugeIcon(
                    icon: AppIcons.delete,
                    color: kDanger,
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Shared little widgets ────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: kTextDark,
          ),
        ),
      );
}

class _Wrap extends StatelessWidget {
  final Widget child;
  const _Wrap({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: child,
      );
}

InputDecoration _dec(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: kTextMid, fontSize: 13),
      border: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
    );
