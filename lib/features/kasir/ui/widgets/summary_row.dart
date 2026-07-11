import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

class SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;
  const SummaryRow(this.label, this.value, {super.key, this.bold = false, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: bold ? 14 : 13,
            color: bold ? kTextDark : kTextMid,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 17 : 13,
            color: valueColor ?? (bold ? kPrimary : kTextDark),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
