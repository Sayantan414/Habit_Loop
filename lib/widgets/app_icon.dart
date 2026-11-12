import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/services/usage_service.dart';
import '../core/theme/app_theme.dart';

/// Another app's launcher icon, loaded once from Android and then cached for
/// the life of the process. Falls back to a neutral app glyph.
class AppIcon extends StatelessWidget {
  const AppIcon({super.key, required this.packageName, this.size = 36});

  final String packageName;
  final double size;

  static final _cache = <String, Future<Uint8List?>>{};

  @override
  Widget build(BuildContext context) {
    final future = _cache.putIfAbsent(
      packageName,
      () => UsageService.appIcon(packageName).catchError((Object _) => null),
    );
    return SizedBox.square(
      dimension: size,
      child: FutureBuilder<Uint8List?>(
        future: future,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null) {
            return Image.memory(bytes, gaplessPlayback: true);
          }
          return Icon(
            Icons.apps_rounded,
            size: size * 0.7,
            color: AppPalette.of(context).textTertiary,
          );
        },
      ),
    );
  }
}
