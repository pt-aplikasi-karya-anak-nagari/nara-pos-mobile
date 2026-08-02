import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';

import '../../../../app/theme.dart';
import '../../../../core/app_icons.dart';

class EmptyCart extends StatelessWidget {
  const EmptyCart({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: kBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Text('🛒', style: TextStyle(fontSize: 32)),
            ),
          ),
          const Gap(16),
          Text(
            'Keranjang kosong',
            style: TextStyle(fontWeight: FontWeight.w600, color: kTextDark),
          ),
          const Gap(4),
          Text(
            'Belum ada produk dipilih',
            style: TextStyle(fontSize: 12, color: kTextMid),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconAsset icon;
  final String title;
  final String subtitle;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: kBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: HugeIcon(icon: icon, size: 32, color: kTextMid),
          ),
          const Gap(16),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: kTextDark,
            ),
          ),
          const Gap(4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: kTextMid),
          ),
        ],
      ),
    );
  }
}
