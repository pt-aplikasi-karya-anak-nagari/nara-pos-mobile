import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../../app/theme.dart';
import '../../../../core/format.dart';
import '../../../products/domain/product.dart';

class SizePickerSheet extends StatelessWidget {
  final Product product;
  const SizePickerSheet({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    // Opsi "Regular" sebagai entri pertama: ProductVariant sintetis dengan
    // remoteId=null & price=product.price. Saat dipilih, CartItem.from akan
    // menghasilkan variantId=null sehingga harga & diskon mengikuti produk
    // utama (lihat CartItem.effectivePrice & basePrice), tapi tetap berlabel
    // "Regular" di cart untuk membedakan dari pilihan varian eksplisit.
    //
    // Diskon "Regular" diambil dari product (discount_type/value/name); tiap
    // varian punya diskon-nya sendiri di field-field yang sama.
    final regularOption = ProductVariant(
      remoteId: null,
      productId: product.remoteId ?? '',
      name: 'Regular',
      price: product.price,
      discountType: product.discountType,
      discountValue: product.discountValue,
      discountName: product.discountName,
    );
    final options = [regularOption, ...product.variants];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: kDivider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: kTextDark,
                        ),
                      ),
                      const Gap(2),
                      Text(
                        'Pilih ukuran / varian',
                        style: TextStyle(fontSize: 12, color: kTextMid),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Gap(8),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: options.length,
            separatorBuilder: (_, _) => const Gap(8),
            itemBuilder: (_, i) {
              final v = options[i];
              final isRegular = v.remoteId == null;
              // Untuk varian eksplisit, selisih dari harga base ditampilkan
              // sebagai hint "+ Rp X" supaya kasir tahu tambahan-nya tanpa
              // kehilangan info total yang akan ditagih.
              final delta = v.price - product.price;
              final showDelta = !isRegular && delta > 0;
              final hasDiscount = v.hasDiscount;

              return Material(
                color: Colors.transparent,
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  tileColor: kBg,
                  dense: true,
                  onTap: () => Navigator.of(context).pop(v),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          v.name,
                          style: TextStyle(color: kTextDark),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasDiscount) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: kAccent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            v.discountType == 'percent'
                                ? '${v.discountValue.toInt()}% OFF'
                                : 'DISKON',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: showDelta
                      ? Text(
                          '+ ${formatRupiah(delta)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: kTextMid,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      : null,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (hasDiscount)
                        Text(
                          formatRupiah(v.price),
                          style: TextStyle(
                            fontSize: 11,
                            color: kTextMid,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      Text(
                        formatRupiah(v.discountedPrice),
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          fontWeight: FontWeight.w700,
                          color: kPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
