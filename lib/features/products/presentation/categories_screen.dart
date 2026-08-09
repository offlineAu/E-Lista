import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/category.dart';
import '../../../routing/app_routes.dart';
import '../../../widgets/state_views.dart';
import '../application/catalog_controller.dart';

/// Browsing by shelf, for shoppers who would rather look than type.
///
/// Selecting a category sets the catalog filter and returns to the shop, rather than
/// opening a second product list — one grid, one place to scroll, one page cursor.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final selected = ref.watch(selectedCategoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.home),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
      ),
      body: AsyncView<List<ProductCategory>>(
        value: categories,
        onRetry: () => ref.invalidate(categoriesProvider),
        builder: (context, list) {
          if (list.isEmpty) {
            return const EmptyView(
              icon: Icons.category_outlined,
              title: 'No categories yet',
              message:
                  'The store has not set up its shelves. '
                  'You can still search for what you need.',
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.sizeOf(context).width < 600 ? 2 : 4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.25,
            ),
            itemCount: list.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _CategoryTile(
                  label: 'Everything',
                  icon: Icons.storefront,
                  isSelected: selected == null,
                  onTap: () {
                    ref.read(selectedCategoryProvider.notifier).state = null;
                    context.go(AppRoutes.home);
                  },
                );
              }

              final category = list[index - 1];
              return _CategoryTile(
                label: category.name,
                icon: iconForCategory(category.iconName),
                count: category.productCount,
                isSelected: selected == category.id,
                onTap: () {
                  ref.read(selectedCategoryProvider.notifier).state =
                      category.id;
                  context.go(AppRoutes.home);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.count,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: isSelected ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 30,
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: isSelected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurface,
                ),
              ),
              if (count != null) ...[
                const SizedBox(height: 2),
                Text(
                  '$count ${count == 1 ? 'product' : 'products'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Maps the icon name stored in Firestore to a Material icon.
///
/// Firestore holds a stable string rather than an icon code point, so the data does not
/// depend on a Flutter version. An unknown name falls back to a generic shelf icon instead
/// of an empty square.
IconData iconForCategory(String? iconName) => switch (iconName) {
  'cookie' => Icons.cookie_outlined,
  'local_drink' => Icons.local_drink_outlined,
  'ramen_dining' => Icons.ramen_dining_outlined,
  'inventory_2' => Icons.inventory_2_outlined,
  'rice_bowl' => Icons.rice_bowl_outlined,
  'soup_kitchen' => Icons.soup_kitchen_outlined,
  'cleaning_services' => Icons.cleaning_services_outlined,
  'soap' => Icons.soap_outlined,
  'edit' => Icons.edit_outlined,
  'category' => Icons.category_outlined,
  _ => Icons.shelves,
};
