import 'package:flutter/material.dart';

/// Abonelik kategorileri: ad, simge ve renk.
/// Kategori anahtarları veritabanında saklanır; bu katalog görselleştirme için
/// kullanılır. Yeni kategori eklemek için bu listeye bir öğe eklemek yeterli.
class CategoryCatalog {
  static const List<CategoryInfo> all = [
    CategoryInfo('music', 'Müzik', Icons.music_note, Color(0xFF5C6BC0)),
    CategoryInfo('video', 'Video / Streaming', Icons.movie_outlined,
        Color(0xFFEC407A)),
    CategoryInfo('cloud', 'Bulut Depolama', Icons.cloud_outlined,
        Color(0xFF29B6F6)),
    CategoryInfo('games', 'Oyun', Icons.sports_esports_outlined,
        Color(0xFF66BB6A)),
    CategoryInfo('fitness', 'Fitness', Icons.fitness_center_outlined,
        Color(0xFFFFA726)),
    CategoryInfo('software', 'SaaS / Uygulama', Icons.apps_outlined,
        Color(0xFFAB47BC)),
    CategoryInfo('other', 'Diğer', Icons.category_outlined, Color(0xFF90A4AE)),
  ];

  static const CategoryInfo defaultCategory = CategoryInfo(
    'other',
    'Diğer',
    Icons.category_outlined,
    Color(0xFF90A4AE),
  );

  static CategoryInfo byKey(String key) {
    for (final c in all) {
      if (c.key == key) return c;
    }
    return defaultCategory;
  }
}

/// Kategorinin görsel tanımı.
class CategoryInfo {
  final String key;
  final String label;
  final IconData icon;
  final Color color;

  const CategoryInfo(this.key, this.label, this.icon, this.color);
}
