import 'package:flutter/material.dart';

/// Chave global do ScaffoldMessenger, usada pra mostrar SnackBars a partir
/// de lugares sem BuildContext (ex: PlayerService avisando que a música
/// não conseguiu carregar/tocar, geralmente por bloqueio de rede).
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
