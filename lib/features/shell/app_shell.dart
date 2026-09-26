import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/app_background.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/pressable.dart';
import '../add_habit/add_habit_screen.dart';
import '../notes/note_editor_screen.dart';
import '../notes/notes_tab.dart';
import '../settings/settings_screen.dart';
import '../today/today_screen.dart';
import '../todo/todo_tab.dart';

/// Root scaffold: four tabs kept alive in an [IndexedStack], an ergonomic
/// floating navigation bar pinned within thumb reach, and a contextual FAB
/// that changes its action with the tab.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  static const _destinations = <_NavDestination>[
    _NavDestination('Today', Icons.today_rounded, Icons.today_outlined),
    _NavDestination('To-Do', Icons.check_circle_rounded,
        Icons.check_circle_outline_rounded),
    _NavDestination(
        'Notes', Icons.sticky_note_2_rounded, Icons.sticky_note_2_outlined),
    _NavDestination('Settings', Icons.settings_rounded, Icons.settings_outlined),
  ];

  void _onFabPressed() {
    switch (_index) {
      case 0:
        AddHabitSheet.show(context);
      case 2:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NoteEditorScreen()),
        );
    }
  }

  void _onNavSelected(int i) {
    if (_index == i) return;
    setState(() => _index = i);
    _pageController.animateToPage(
      i,
      duration: AppTokens.base,
      curve: AppTokens.emphasized,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ShellTabRequest?>(shellTabRequestProvider, (_, request) {
      if (request != null) _onNavSelected(request.index);
    });

    final p = AppPalette.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final isKeyboardOpen = keyboardInset > 0;
    final showFab = (_index == 0 || _index == 2) && !isKeyboardOpen;

    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: AppBackground(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                behavior: HitTestBehavior.translucent,
                child: PageView(
                  controller: _pageController,
                  physics: const FirmPageScrollPhysics(),
                  onPageChanged: (i) {
                    if (_index != i) {
                      setState(() => _index = i);
                    }
                  },
                  children: const [
                    _KeepAlivePage(child: TodayScreen()),
                    _KeepAlivePage(child: TodoTab()),
                    _KeepAlivePage(child: NotesTab()),
                    _KeepAlivePage(child: SettingsScreen()),
                  ],
                ),
              ),
            ),
            AnimatedPositioned(
              duration: AppTokens.fast,
              curve: AppTokens.emphasized,
              left: 0,
              right: 0,
              bottom: isKeyboardOpen ? -100 : (bottomInset + 14),
              child: Center(
                child: _FloatingNavBar(
                  index: _index,
                  destinations: _destinations,
                  onSelected: _onNavSelected,
                ),
              ),
            ),
            Positioned(
              right: AppTokens.gutter,
              bottom: bottomInset + 14 + 68 + AppTokens.space4,
              child: AnimatedScale(
                scale: showFab ? 1 : 0,
                duration: AppTokens.base,
                curve: AppTokens.springy,
                child: AnimatedOpacity(
                  opacity: showFab ? 1 : 0,
                  duration: AppTokens.fast,
                  child: _ContextualFab(
                    icon: _index == 2
                        ? Icons.edit_note_rounded
                        : Icons.add_rounded,
                    label: _index == 2 ? 'New note' : 'New habit',
                    color: p.accent,
                    onPressed: showFab ? _onFabPressed : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});
  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _NavDestination {
  const _NavDestination(this.label, this.activeIcon, this.icon);

  final String label;
  final IconData activeIcon;
  final IconData icon;
}

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.index,
    required this.destinations,
    required this.onSelected,
  });

  final int index;
  final List<_NavDestination> destinations;
  final ValueChanged<int> onSelected;

  static const _height = 68.0;
  static const _maxItemWidth = 84.0;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);

    // Sized to content on wide screens, and shrunk to fit on narrow phones so
    // the bar never overflows its 16pt side margins.
    final available = MediaQuery.sizeOf(context).width - AppTokens.space8;
    final width = math.min(available, _maxItemWidth * destinations.length);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTokens.space4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        boxShadow: [
          BoxShadow(
            color: p.isDark
                ? Colors.black.withValues(alpha: 0.5)
                : const Color(0x1A0F172A),
            blurRadius: 30,
            offset: const Offset(0, 12),
            spreadRadius: -6,
          ),
        ],
      ),
      child: GlassBlur(
        radius: AppTokens.radiusXl,
        child: Container(
          width: width,
          height: _height,
          decoration: BoxDecoration(
            color: p.navGlass,
            borderRadius: BorderRadius.circular(AppTokens.radiusXl),
            border: Border.all(
              color: p.isDark ? p.strokeStrong : p.stroke,
            ),
          ),
          // The 1px border shrinks the inner box, so item widths are measured
          // from the real constraints rather than the outer width.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / destinations.length;
              return Stack(
                children: [
                  // Sliding accent pill behind the active destination.
                  AnimatedPositioned(
                    duration: AppTokens.base,
                    curve: AppTokens.emphasized,
                    left: index * slot + 5.0,
                    top: 6,
                    bottom: 6,
                    width: math.max(0.0, slot - 10.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            p.accent.withValues(alpha: p.isDark ? 0.16 : 0.10),
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                        border: Border.all(
                          color: p.accent
                              .withValues(alpha: p.isDark ? 0.28 : 0.16),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Row(
                      children: [
                        for (var i = 0; i < destinations.length; i++)
                          Expanded(
                            child: _NavItem(
                              destination: destinations[i],
                              selected: i == index,
                              onTap: () => onSelected(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final color = selected ? p.accent : p.textTertiary;

    return Pressable(
      onTap: onTap,
      scale: 0.9,
      child: Semantics(
        selected: selected,
        button: true,
        label: destination.label,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSlide(
              offset: selected ? const Offset(0, -0.06) : Offset.zero,
              duration: AppTokens.base,
              curve: AppTokens.emphasized,
              child: Icon(
                selected ? destination.activeIcon : destination.icon,
                size: 23,
                color: color,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: AppTokens.base,
              style: theme.textTheme.labelMedium!.copyWith(
                fontSize: 10,
                letterSpacing: 0,
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(
                destination.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextualFab extends StatelessWidget {
  const _ContextualFab({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Pressable(
      onTap: onPressed,
      scale: 0.93,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          color: color,
          boxShadow: [
            BoxShadow(
              color: p.isDark
                  ? Colors.black.withValues(alpha: 0.45)
                  : const Color(0x1F0F172A),
              blurRadius: 18,
              offset: const Offset(0, 8),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: Colors.white),
            const SizedBox(width: 7),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom page scroll physics that requires a deliberate, firm swipe gesture
/// (higher velocity or dragging at least 50% across the screen) to switch tabs.
/// Light drags or accidental edge back swipes snap back safely without changing tabs.
class FirmPageScrollPhysics extends PageScrollPhysics {
  const FirmPageScrollPhysics({
    super.parent,
    this.velocityThreshold = 750.0,
    this.distanceThreshold = 0.50,
  });

  final double velocityThreshold;
  final double distanceThreshold;

  @override
  FirmPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return FirmPageScrollPhysics(
      parent: buildParent(ancestor),
      velocityThreshold: velocityThreshold,
      distanceThreshold: distanceThreshold,
    );
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    final double viewport = position.viewportDimension;
    if (viewport <= 0) {
      return super.createBallisticSimulation(position, velocity);
    }

    final double currentPage = position.pixels / viewport;
    final int basePage = currentPage.floor();
    final double pageOffset = currentPage - basePage;

    int targetPage;
    if (velocity.abs() >= velocityThreshold) {
      targetPage = velocity > 0 ? basePage + 1 : basePage;
    } else {
      if (pageOffset >= distanceThreshold) {
        targetPage = basePage + 1;
      } else {
        targetPage = basePage;
      }
    }

    final int maxPage = (position.maxScrollExtent / viewport).round();
    targetPage = targetPage.clamp(0, maxPage);

    final double targetPixels = targetPage * viewport;
    if (targetPixels != position.pixels) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        targetPixels,
        velocity,
        tolerance: toleranceFor(position),
      );
    }
    return null;
  }
}
