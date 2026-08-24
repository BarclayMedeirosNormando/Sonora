import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../core/theme.dart';

/// Tela pra pedir uma música, álbum ou artista que ainda não está na
/// biblioteca. Não passa por nenhum backend — só monta a mensagem e abre o
/// WhatsApp (app ou web) já com o texto pronto no número do Barclay,
/// pra quem pediu só conferir e apertar enviar.
class PedidoScreen extends StatefulWidget {
  const PedidoScreen({super.key});

  @override
  State<PedidoScreen> createState() => _PedidoScreenState();
}

class _PedidoScreenState extends State<PedidoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _obsController = TextEditingController();
  String _tipo = _tipos.first;

  static const _tipos = ['Música', 'Álbum', 'Artista'];

  String get _rotuloNome {
    switch (_tipo) {
      case 'Álbum':
        return 'Nome do álbum';
      case 'Artista':
        return 'Nome do artista';
      default:
        return 'Nome da música';
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _obsController.dispose();
    super.dispose();
  }

  InputDecoration _decoracao(String rotulo, {String? dica}) {
    return InputDecoration(
      labelText: rotulo,
      hintText: dica,
      labelStyle: const TextStyle(color: AppTheme.textSecondary),
      hintStyle: const TextStyle(color: AppTheme.textSecondary),
      filled: true,
      fillColor: AppTheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;

    final nome = _nomeController.text.trim();
    final obs = _obsController.text.trim();

    final mensagem = StringBuffer()
      ..writeln('Pedido de música - Sonora')
      ..writeln('Tipo: $_tipo')
      ..writeln('Pedido: $nome');
    if (obs.isNotEmpty) {
      mensagem.write('Observação: $obs');
    }

    final url = Uri.parse(
      'https://wa.me/${AppConstants.whatsappPedidosNumero}'
      '?text=${Uri.encodeComponent(mensagem.toString().trim())}',
    );

    var abriu = false;
    try {
      abriu = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      abriu = false;
    }

    if (!mounted) return;

    if (!abriu) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não deu pra abrir o WhatsApp. Ele está instalado?'),
        ),
      );
      return;
    }

    _nomeController.clear();
    _obsController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pedido pronto no WhatsApp — é só enviar.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pedir música')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Não achou o que queria na biblioteca? Manda o pedido — a '
                'gente recebe direto pelo WhatsApp.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                value: _tipo,
                decoration: _decoracao('Tipo de pedido'),
                dropdownColor: AppTheme.surfaceHigh,
                style: const TextStyle(color: AppTheme.textPrimary),
                items: _tipos
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (valor) => setState(() => _tipo = valor ?? _tipo),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nomeController,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: _decoracao(_rotuloNome),
                textCapitalization: TextCapitalization.sentences,
                validator: (valor) => (valor == null || valor.trim().isEmpty)
                    ? 'Digite um nome'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _obsController,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: _decoracao(
                  'Observação (opcional)',
                  dica: 'Ex: do álbum X, versão ao vivo, etc.',
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _enviar,
                  icon: const Icon(Icons.send),
                  label: const Text('Enviar pedido pelo WhatsApp'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
