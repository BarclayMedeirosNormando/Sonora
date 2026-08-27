import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import '../services/api_service.dart';
import '../services/device_id_service.dart';
import 'main_screen.dart';

/// Primeira tela do app: gera/mostra o App_ID do dispositivo e verifica
/// se ele já foi liberado na planilha de controle de acesso.
///
/// Depois da primeira liberação bem-sucedida, guarda isso localmente pra
/// não precisar mostrar essa tela de novo toda vez que o app abrir — só
/// volta a pedir verificação manual se o acesso for revogado (percebido
/// numa revalidação silenciosa em segundo plano).
class ValidationScreen extends StatefulWidget {
  const ValidationScreen({super.key});

  @override
  State<ValidationScreen> createState() => _ValidationScreenState();
}

class _ValidationScreenState extends State<ValidationScreen> {
  static const _prefsKeyLiberado = 'sonora_liberado';

  String? _deviceId;
  bool _checking = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final id = await DeviceIdService.getOrCreateDeviceId();
    if (!mounted) return;
    setState(() => _deviceId = id);

    final prefs = await SharedPreferences.getInstance();
    final jaLiberado = prefs.getBool(_prefsKeyLiberado) ?? false;
    if (!jaLiberado) return;

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );

    // Revalida em segundo plano, sem travar quem já está usando o app — só
    // se o acesso tiver sido revogado na planilha é que a PRÓXIMA abertura
    // do app vai cair de novo na tela de verificação.
    _revalidarEmSegundoPlano(id, prefs);
  }

  Future<void> _revalidarEmSegundoPlano(String id, SharedPreferences prefs) async {
    try {
      final aindaLiberado = await ApiService.validarId(id);
      if (!aindaLiberado) {
        await prefs.setBool(_prefsKeyLiberado, false);
      }
    } catch (_) {
      // Sem internet ou backend fora do ar agora — mantém liberado
      // localmente, não faz sentido bloquear quem já tinha sido aprovado
      // só porque não deu pra confirmar de novo neste instante.
    }
  }

  Future<void> _verificarLiberacao() async {
    if (_deviceId == null) return;

    setState(() {
      _checking = true;
      _errorMessage = null;
    });

    try {
      final liberado = await ApiService.validarId(_deviceId!);
      if (!mounted) return;

      if (liberado) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_prefsKeyLiberado, true);
        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
        return;
      }

      setState(() {
        _checking = false;
        _errorMessage =
            'Ainda não liberado. Envie o ID acima para liberação manual.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _errorMessage = 'Erro ao verificar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Sonora',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Este é o identificador do seu aparelho. Envie-o para liberação de acesso.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  _deviceId ?? 'Gerando ID...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _checking ? null : _verificarLiberacao,
                child: _checking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Text('Verificar liberação'),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
