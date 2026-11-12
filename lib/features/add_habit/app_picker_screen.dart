import 'package:flutter/material.dart';

import '../../core/services/usage_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/app_background.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/pressable.dart';

/// Picks the apps whose screen time a habit limits. Pops with the chosen
/// apps (sorted by name), or null when backed out of.
class AppPickerScreen extends StatefulWidget {
  const AppPickerScreen({super.key, required this.selected});

  /// Package names already chosen.
  final Set<String> selected;

  static Future<List<InstalledApp>?> push(
    BuildContext context, {
    required Set<String> selected,
  }) {
    return Navigator.of(context).push<List<InstalledApp>>(
      MaterialPageRoute(builder: (_) => AppPickerScreen(selected: selected)),
    );
  }

  @override
  State<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends State<AppPickerScreen> {
  late final Future<List<InstalledApp>> _apps = UsageService.installedApps();
  late final Set<String> _selected = {...widget.selected};
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String packageName) {
    setState(() {
      if (!_selected.remove(packageName)) _selected.add(packageName);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: SafeArea(
          child: FutureBuilder<List<InstalledApp>>(
            future: _apps,
            builder: (context, snapshot) {
              final apps = snapshot.data ?? const <InstalledApp>[];
              final query = _search.text.trim().toLowerCase();
              final shown = query.isEmpty
                  ? apps
                  : apps
                        .where((a) => a.label.toLowerCase().contains(query))
                        .toList();

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.gutter,
                      vertical: AppTokens.space2,
                    ),
                    child: Row(
                      children: [
                        Pressable(
                          onTap: () => Navigator.of(context).pop(),
                          scale: 0.9,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: p.isDark ? p.surfaceHigh : p.surface,
                              border: Border.all(color: p.stroke),
                            ),
                            child: Icon(
                              Icons.arrow_back_rounded,
                              size: 20,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Choose apps',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        FilledButton(
                          onPressed: _selected.isEmpty
                              ? null
                              : () => Navigator.of(context).pop(
                                  apps
                                      .where(
                                        (a) => _selected.contains(a.packageName),
                                      )
                                      .toList(),
                                ),
                          child: Text(
                            _selected.isEmpty
                                ? 'Done'
                                : 'Done (${_selected.length})',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTokens.gutter,
                      AppTokens.space2,
                      AppTokens.gutter,
                      AppTokens.space3,
                    ),
                    child: TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: InputDecoration(
                        hintText: 'Search apps',
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 19,
                          color: p.textTertiary,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: switch (snapshot.connectionState) {
                      ConnectionState.done when snapshot.hasError => Center(
                        child: Text(
                          "Couldn't load your apps.",
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      ),
                      ConnectionState.done => shown.isEmpty
                          ? Center(
                              child: Text(
                                'No apps match "${_search.text.trim()}".',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: p.textSecondary,
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(
                                bottom: AppTokens.space6,
                              ),
                              itemCount: shown.length,
                              itemBuilder: (context, i) {
                                final app = shown[i];
                                final on = _selected.contains(app.packageName);
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppTokens.gutter,
                                  ),
                                  leading: AppIcon(
                                    packageName: app.packageName,
                                  ),
                                  title: Text(
                                    app.label,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  trailing: Checkbox(
                                    value: on,
                                    onChanged: (_) => _toggle(app.packageName),
                                  ),
                                  onTap: () => _toggle(app.packageName),
                                );
                              },
                            ),
                      _ => const Center(child: CircularProgressIndicator()),
                    },
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
