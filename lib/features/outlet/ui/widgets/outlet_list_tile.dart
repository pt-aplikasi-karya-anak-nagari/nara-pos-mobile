import 'package:flutter/material.dart';
import '../../domain/outlet.dart';
import '../../../../shared/widgets/app_list_tile.dart';
import '../../../../shared/widgets/tablet_components.dart';
import '../../../../app/theme.dart';
import '../../../../core/app_icons.dart';

class OutletListTile extends StatelessWidget {
  final Outlet outlet;
  final bool isSelected;
  final VoidCallback? onTap;

  const OutletListTile({
    super.key,
    required this.outlet,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      isSelected: isSelected,
      onTap: onTap,
      leading: TabletHeaderBadge(
        icon: AppIcons.storefront,
        color: isSelected ? kPrimary : kTextMid,
      ),
      title: Text(outlet.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (outlet.address.isNotEmpty)
            Text(outlet.address, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            '${outlet.staffMembers.length} Staff',
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}
