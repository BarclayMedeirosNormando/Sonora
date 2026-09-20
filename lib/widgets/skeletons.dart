import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../core/theme.dart';

/// Cards de playlist "pulsantes" enquanto a Home carrega.
class SkeletonPlaylists extends StatelessWidget {
  final int quantidade;

  const SkeletonPlaylists({super.key, this.quantidade = 3});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.surfaceHigh,
      highlightColor: AppTheme.surface,
      child: Column(
        children: List.generate(
          quantidade,
          (_) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Linhas de faixa "pulsantes" enquanto a playlist carrega.
class SkeletonFaixas extends StatelessWidget {
  final int quantidade;

  const SkeletonFaixas({super.key, this.quantidade = 8});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.surfaceHigh,
      highlightColor: AppTheme.surface,
      child: Column(
        children: List.generate(
          quantidade,
          (_) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 12, width: 170, color: Colors.white),
                    const SizedBox(height: 8),
                    Container(height: 10, width: 100, color: Colors.white),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
