import 'package:flutter/material.dart';

/// Entrada suave (fade + sobe uns pixels) pra um item de lista. [indice]
/// escalona a duração pros itens irem aparecendo em sequência. Só usar em
/// listas curtas (cards da Home) -- em lista longa, cada item que volta
/// pra tela na rolagem animaria de novo.
class Aparece extends StatelessWidget {
  final int indice;
  final Widget child;

  const Aparece({super.key, required this.child, this.indice = 0});

  @override
  Widget build(BuildContext context) {
    final atraso = (indice > 6 ? 6 : indice) * 70;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + atraso),
      curve: Curves.easeOutCubic,
      builder: (context, valor, filho) => Opacity(
        opacity: valor,
        child: Transform.translate(
          offset: Offset(0, (1 - valor) * 18),
          child: filho,
        ),
      ),
      child: child,
    );
  }
}
