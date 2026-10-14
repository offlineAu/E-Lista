import 'package:flutter/material.dart';

import 'glass_card.dart';

/// One destination in a [FloatingNavBar].
class FloatingNavItem {
  const FloatingNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Shown as a small count badge on the icon, e.g. items in the cart. Zero hides it.
  final int badgeCount;
}

/// A rounded, frosted bottom navigation bar that floats above the content rather than
/// docking edge-to-edge — the pill-shaped nav from the redesign concept, replacing the
/// stock Material [NavigationBar]. Only the active destination shows its label, matching
/// the concept's denser phone layout.
///
/// Used as a plain `bottomNavigationBar` (no `extendBody`) — every screen's own pinned
/// bottom content (e.g. a checkout "Complete sale" button) must stay reserved space above
/// it, not sit underneath it.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final List<FloatingNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GlassCard(
          borderRadius: BorderRadius.circular(22),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var index = 0; index < items.length; index++)
                _FloatingNavButton(
                  item: items[index],
                  selected: index == selectedIndex,
                  onTap: () => onDestinationSelected(index),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingNavButton extends StatelessWidget {
  const _FloatingNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final FloatingNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    Widget icon = Icon(
      selected ? item.selectedIcon : item.icon,
      size: 20,
      color: color,
    );
    if (item.badgeCount > 0) {
      icon = Badge.count(count: item.badgeCount, child: icon);
    }

    return Semantics(
      button: true,
      selected: selected,
      label: item.badgeCount > 0
          ? '${item.label}, ${item.badgeCount} items'
          : item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              if (selected) ...[
                const SizedBox(height: 3),
                Text(
                  item.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
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
