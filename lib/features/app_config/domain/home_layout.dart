import 'dart:convert';

/// Sections the home screen knows how to render.
enum HomeSection { banner, categories, deals, allProducts }

/// Server-driven home screen layout.
///
/// Contract (see ASSIGNMENT.md, Part C: Feature 2):
/// * Input is the raw `home_sections` remote config value: a JSON array of
///   strings. Known ids: `banner`, `categories`, `deals`, `all_products`.
/// * Output keeps the order given by the config.
/// * Unknown ids are ignored (older app versions must not break when the
///   backend adds a new section type).
/// * Duplicates are ignored (first occurrence wins).
/// * null, malformed JSON, a non-array value, or a result with zero known
///   sections -> [HomeLayout.defaultSections].
class HomeLayout {
  const HomeLayout._();

  static const List<HomeSection> defaultSections = [
    HomeSection.categories,
    HomeSection.allProducts,
  ];

  static List<HomeSection> parse(String? rawJson) {
    if (rawJson == null) return defaultSections;

    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException {
      return defaultSections;
    }
    if (decoded is! List) return defaultSections;

    const sectionsById = {
      'banner': HomeSection.banner,
      'categories': HomeSection.categories,
      'deals': HomeSection.deals,
      'all_products': HomeSection.allProducts,
    };
    final seen = <HomeSection>{};
    final sections = <HomeSection>[];
    for (final sectionId in decoded) {
      if (sectionId is! String) continue;
      final section = sectionsById[sectionId];
      if (section != null && seen.add(section)) sections.add(section);
    }
    return sections.isEmpty ? defaultSections : sections;
  }
}
