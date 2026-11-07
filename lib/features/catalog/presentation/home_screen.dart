import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../app_config/domain/app_config.dart';
import '../../app_config/domain/home_layout.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/presentation/cart_badge_button.dart';
import '../../dev_tools/dev_tools_screen.dart';
import '../../orders/presentation/orders_screen.dart';
import '../../search/search_screen.dart';
import '../data/catalog_repository.dart';
import '../domain/product.dart';
import 'catalog_controller.dart';
import 'category_screen.dart';
import 'widgets/paginated_catalog_view.dart';
import 'widgets/product_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeName = ref.watch(mockServerProvider).storeName;
    final config = ref.watch(appConfigControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(storeName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Text('Delivery in 10 minutes ⚡',
                style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Dev tools',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DevToolsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'My orders',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const OrdersScreen()),
            ),
          ),
          const CartBadgeButton(),
        ],
      ),
      body: _HomeContent(config: config),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayout.parse(config.homeSectionsJson);
    final sections =
        layout.map((section) => _homeSectionSliver(section, config)).toList();
    final allProductsIndex = layout.indexOf(HomeSection.allProducts);
    final search = _searchSliver(context);

    if (allProductsIndex < 0) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [search, ...sections],
      );
    }

    return PaginatedCatalogView(
      categoryId: kAllProductsCategory,
      headerSlivers: [
        search,
        ...sections.take(allProductsIndex + 1),
      ],
      footerSlivers: sections.skip(allProductsIndex + 1).toList(),
    );
  }
}

Widget _searchSliver(BuildContext context) {
  return SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
        ),
        child: InputDecorator(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search for products',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Search "milk", "chips"…',
              style: TextStyle(color: Colors.grey)),
        ),
      ),
    ),
  );
}

Widget _homeSectionSliver(HomeSection section, AppConfig config) {
  switch (section) {
    case HomeSection.banner:
      final banner = config.homeBanner;
      return SliverToBoxAdapter(
        key: const ValueKey('home-section-banner'),
        child: banner == null
            ? const SizedBox.shrink()
            : _BannerCard(banner: banner),
      );
    case HomeSection.categories:
      return const SliverToBoxAdapter(
        key: ValueKey('home-section-categories'),
        child: _SectionBlock(title: 'Categories', child: _CategoriesRow()),
      );
    case HomeSection.deals:
      return const SliverToBoxAdapter(
        key: ValueKey('home-section-deals'),
        child: _DealsSection(),
      );
    case HomeSection.allProducts:
      return const SliverToBoxAdapter(
        key: ValueKey('home-section-all-products'),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text('All products',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.banner});

  final HomeBanner banner;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _bannerColor(banner.colorHex),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              banner.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            if (banner.subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                banner.subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Color _bannerColor(String colorHex) {
  final hex = colorHex.startsWith('#') ? colorHex.substring(1) : colorHex;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return Colors.deepOrange;
  if (hex.length == 6) return Color(0xFF000000 | value);
  if (hex.length == 8) return Color(value);
  return Colors.deepOrange;
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

final _homeDealsProvider = FutureProvider<List<Product>>((ref) async {
  final page = await ref.watch(catalogRepositoryProvider).getDeals();
  return page.items;
});

class _DealsSection extends ConsumerWidget {
  const _DealsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deals = ref.watch(_homeDealsProvider);
    return _SectionBlock(
      title: 'Deals',
      child: deals.when(
        loading: () => const SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(_homeDealsProvider),
            child: const Text("Couldn't load deals. Retry"),
          ),
        ),
        data: (items) => items.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No deals right now'),
              )
            : SizedBox(
                height: 270,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) => SizedBox(
                    width: 168,
                    child: ProductCard(product: items[index]),
                  ),
                ),
              ),
      ),
    );
  }
}

class _CategoriesRow extends ConsumerWidget {
  const _CategoriesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return SizedBox(
      height: 104,
      child: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(categoriesProvider),
            child: const Text("Couldn't load categories. Retry"),
          ),
        ),
        data: (items) => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final c = items[index];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => CategoryScreen(category: c)),
              ),
              child: SizedBox(
                width: 76,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.green.shade50,
                      child:
                          Text(c.emoji, style: const TextStyle(fontSize: 24)),
                    ),
                    const SizedBox(height: 4),
                    Text(c.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
