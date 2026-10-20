/// Uygulamanın veri tipleri. Her fazda yenileri eklenecek.
library;

/// Bas-konuş tuşunun durumu.
enum PttDurumu {
  /// Tuş boşta, basılmayı bekliyor.
  bos,

  /// Tuşa basılı tutuluyor, ses alınıyor.
  dinliyor,

  /// Tuş bırakıldı, komut işleniyor.
  isleniyor,
}

/// Yer istasyonu bağlantısının durumu.
enum BaglantiDurumu { kopuk, baglaniyor, bagli, hata }
