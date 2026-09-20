import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Tela de "nada aqui" / "deu erro": ícone num círculo, título, mensagem e
/// (opcional) um botão de ação -- em vez de só uma linha de texto solta.
/// Pensado pra ficar dentro de um ListView (o pull-to-refresh continua
/// funcionando por cima).
class EstadoVazio extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String? mensagem;
  final String? rotuloAcao;
  final VoidCallback? aoAcionar;

  const EstadoVazio({
    super.key,
    required this.icone,
    required this.titulo,
    this.mensagem,
    this.rotuloAcao,
    this.aoAcionar,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 56, 32, 0),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(icone, size: 40, color: AppTheme.accent),
          ),
          const SizedBox(height: 20),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (mensagem != null) ...[
            const SizedBox(height: 8),
            Text(
              mensagem!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ],
          if (rotuloAcao != null && aoAcionar != null) ...[
            const SizedBox(height: 24),
            ElevatedButton(onPressed: aoAcionar, child: Text(rotuloAcao!)),
          ],
        ],
      ),
    );
  }
}
