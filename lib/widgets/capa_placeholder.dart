import 'package:flutter/material.dart';

/// Capa "gerada" pra playlist que ainda não tem imagem: degradê numa cor
/// derivada do nome (a mesma playlist sempre tem a mesma cor) com um
/// ícone de fila de música por cima -- mais bonito que um quadrado cinza.
class CapaPlaceholder extends StatelessWidget {
  final String semente;
  final double tamanhoIcone;

  const CapaPlaceholder({super.key, required this.semente, this.tamanhoIcone = 28});

  @override
  Widget build(BuildContext context) {
    // Hash próprio (String.hashCode não tem garantia de valor estável).
    final hash = semente.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7fffffff);
    final matiz = (hash % 360).toDouble();
    final cor1 = HSLColor.fromAHSL(1, matiz, 0.45, 0.38).toColor();
    final cor2 = HSLColor.fromAHSL(1, (matiz + 40) % 360, 0.5, 0.2).toColor();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cor1, cor2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.queue_music,
          color: Colors.white.withValues(alpha: 0.85),
          size: tamanhoIcone,
        ),
      ),
    );
  }
}
