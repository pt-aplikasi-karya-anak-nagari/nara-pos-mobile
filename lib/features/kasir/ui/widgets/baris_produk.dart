import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../products/domain/product.dart';
import 'product_card.dart';

/// Satu baris kartu produk yang tingginya seragam — setinggi kartu TERTINGGI
/// di baris itu, bukan setinggi kartu tertinggi di seluruh daftar.
///
/// # KENAPA BEGINI, BUKAN GRID BIASA DAN BUKAN MASONRY
///
/// Ada tiga cara menata kartu produk, dan dua di antaranya sudah dicoba:
///
///   childAspectRatio   Semua petak setinggi SAMA di seluruh daftar. Nama
///                      panjang terpangkas jadi satu baris + elipsis, dan
///                      kartu bernama pendek menyisakan lubang kosong sebesar
///                      selisihnya terhadap kartu terpanjang di seluruh menu.
///
///   masonry            Tiap kartu setinggi isinya sendiri. Tak ada yang
///                      terpangkas, tapi penempatannya mengejar kolom
///                      TERPENDEK — jadi urutan bacanya melompat-lompat, kartu
///                      tetangganya tak sejajar, dan di ujung daftar muncul
///                      petak menganggur.
///
///   baris intrinsik    Yang dipakai di sini. Tinggi ditentukan per BARIS, dari
///                      kartu tertinggi di baris itu saja. Urutannya tetap
///                      kiri-ke-kanan, tepinya sejajar, tak ada petak
///                      menganggur, dan nama panjang tetap utuh.
///
/// Sisa ruang pada kartu yang lebih pendek dari tetangganya tidak dibiarkan
/// menganggur: Column di dalam ProductCard memakai Spacer, jadi tombol "+"
/// terdorong ke dasar kartu. Hasilnya deretan tombol yang sejajar rapi
/// antarkartu — sisa ruangnya justru jadi bagian dari tata letaknya.
class BarisProduk extends StatelessWidget {
  final List<Product> produk;
  final int kolom;
  final double spasi;

  const BarisProduk({
    super.key,
    required this.produk,
    required this.kolom,
    this.spasi = 8,
  });

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder di SINI, di atas IntrinsicHeight — bukan di dalam kartu.
    //
    // IntrinsicHeight tak bisa mengukur menembus LayoutBuilder ("does not
    // support returning intrinsic dimensions"), jadi selama tiap kartu
    // mengukur lebarnya sendiri, tinggi baris tak akan pernah bisa dihitung.
    // Lebar barisnya sudah diketahui di sini; dibagi sekali lalu dioper ke tiap
    // kartu.
    return LayoutBuilder(
      builder: (context, box) {
        final lebarKartu =
            (box.maxWidth - spasi * (kolom - 1)) / (kolom == 0 ? 1 : kolom);

        final anak = <Widget>[];
        for (var i = 0; i < kolom; i++) {
          if (i > 0) anak.add(SizedBox(width: spasi));
          anak.add(
            Expanded(
              // Petak kosong di baris terakhir diisi SizedBox, bukan dibiarkan
              // kosong: tanpa ini, kartu terakhir akan melar memenuhi seluruh
              // lebar dan tampil lebih besar daripada kartu di baris atasnya.
              child: i < produk.length
                  ? ProductCard(product: produk[i], lebarKartu: lebarKartu)
                  : const SizedBox.shrink(),
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.only(bottom: spasi),
          child: IntrinsicHeight(
            // stretch: kartu yang lebih pendek DITARIK setinggi baris, jadi
            // latar dan tepinya sejajar. Tanpa ini, kartu pendek berhenti di
            // tinggi isinya dan barisnya kembali terlihat bergerigi.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: anak,
            ),
          ),
        );
      },
    );
  }
}

/// Memotong daftar produk jadi baris-baris berisi [kolom] kartu.
///
/// Dipisah dari widget-nya supaya bisa diuji tanpa merender apa pun — dan
/// karena di sinilah letak kesalahan yang paling mudah terjadi: baris terakhir
/// yang tak genap, dan daftar kosong.
List<List<Product>> potongJadiBaris(List<Product> semua, int kolom) {
  if (kolom <= 0) return const [];
  final baris = <List<Product>>[];
  for (var i = 0; i < semua.length; i += kolom) {
    final akhir = i + kolom;
    baris.add(semua.sublist(i, akhir > semua.length ? semua.length : akhir));
  }
  return baris;
}

/// Mengubah keadaan pagination per-PRODUK jadi keadaan pagination per-BARIS.
///
/// # KENAPA DIRATAKAN DULU
///
/// Kalau tiap halaman dipotong sendiri-sendiri, baris terakhir setiap halaman
/// bisa tak genap — dan muncul baris pendek di TENGAH daftar tiap kali batas
/// halaman terlewati. Meratakan seluruh produk yang sudah termuat lebih dulu
/// membuat satu-satunya baris tak genap ada di ujung, tempat ia memang wajar.
///
/// hasNextPage & isLoading diteruskan apa adanya supaya indikator "memuat
/// halaman berikutnya" dan pemicu fetch tetap bekerja seperti semula.
PagingState<int, List<Product>> barisState(
  PagingState<int, Product> asal,
  int kolom,
) {
  final semua = asal.pages?.expand((p) => p).toList() ?? const <Product>[];
  final baris = potongJadiBaris(semua, kolom);
  return PagingState<int, List<Product>>(
    pages: asal.pages == null ? null : [baris],
    keys: asal.keys == null || asal.keys!.isEmpty
        ? asal.keys
        : [asal.keys!.first],
    error: asal.error,
    hasNextPage: asal.hasNextPage,
    isLoading: asal.isLoading,
  );
}
