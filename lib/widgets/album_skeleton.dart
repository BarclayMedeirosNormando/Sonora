import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../core/theme.dart';

/// Placeholder "pulsante" no formato de um card de álbum (capa quadrada +
/// duas linhas de texto) — usado dentro de [AlbumGridSkeleton]/
/// [AlbumRowSkeleton] enquanto o conteúdo real ainda não carregou, em vez
/// do CircularProgressIndicator genérico de antes.
class AlbumSkeletonCard extends StatelessWidget {
  const AlbumSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(height: 10, color: Colors.white),
        const SizedBox(height: 4),
        Container(height: 10, width: 60, color: Colors.white),
      ],
    );
  }
}

/// Grade de skeletons imitando o grid de pastas do FolderScreen, com o
/// efeito de brilho passando por cima (Shimmer.fromColors).
class AlbumGridSkeleton extends StatelessWidget {
  final int quantidade;

  const AlbumGridSkeleton({super.key, this.quantidade = 8});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.surfaceHigh,
      highlightColor: AppTheme.surface,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.62,
        ),
        itemCount: quantidade,
        itemBuilder: (context, index) => const AlbumSkeletonCard(),
      ),
    );
  }
}

/// Fileira horizontal de skeletons imitando os carrosséis de álbum da Home.
class AlbumRowSkeleton extends StatelessWidget {
  final int quantidade;

  const AlbumRowSkeleton({super.key, this.quantidade = 5});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.surfaceHigh,
      highlightColor: AppTheme.surface,
      child: SizedBox(
        height: 168,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: quantidade,
          itemBuilder: (context, index) => const Padding(
            padding: EdgeInsets.only(right: 12),
            child: SizedBox(width: 110, child: AlbumSkeletonCard()),
          ),
        ),
      ),
    );
  }
}
