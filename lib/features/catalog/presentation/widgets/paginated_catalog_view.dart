import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog_controller.dart';
import 'product_card.dart';

/// Infinite-scrolling product grid with pull-to-refresh.
///
/// [headerSlivers] are rendered above the grid inside the same scroll view.
class PaginatedCatalogView extends ConsumerStatefulWidget {
  const PaginatedCatalogView({
    super.key,
    required this.categoryId,
    this.headerSlivers = const [],
    this.footerSlivers = const [],
  });

  final String categoryId;
  final List<Widget> headerSlivers;
  final List<Widget> footerSlivers;

  @override
  ConsumerState<PaginatedCatalogView> createState() =>
      _PaginatedCatalogViewState();
}

class _PaginatedCatalogViewState extends ConsumerState<PaginatedCatalogView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref
          .read(catalogControllerProvider(widget.categoryId).notifier)
          .loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = catalogControllerProvider(widget.categoryId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          ...widget.headerSlivers,
          if (state.fromCache)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.cloud_off, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('You are offline. Showing saved products.'),
                    ),
                  ],
                ),
              ),
            ),
          if (state.isLoadingFirstPage)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.items.isEmpty && state.errorMessage != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('😕', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 8),
                    Text(state.errorMessage!),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: controller.retry,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (state.items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('No products here yet')),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.62,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => ProductCard(product: state.items[index]),
                  childCount: state.items.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Center(
                  child: state.isLoadingMore
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(),
                        )
                      : state.errorMessage != null
                          ? TextButton(
                              onPressed: controller.loadMore,
                              child: const Text(
                                  "Couldn't load more. Tap to retry"),
                            )
                          : !state.hasMore
                              ? const Text("You've seen it all 🎉")
                              : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
          ...widget.footerSlivers,
        ],
      ),
    );
  }
}
