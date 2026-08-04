import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'routing/app_router.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final canInitialize = SupabaseConfig.isConfigured;
  final isMock = SupabaseConfig.isMockMode;

  if (canInitialize) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.supabaseUrl,
        publishableKey: SupabaseConfig.supabasePublishableKey,
      );
    } catch (e) {
      // Em produção, impede o app de continuar sem autenticação.
      // Em modo mock de desenvolvimento, permite continuar com dados locais.
      if (!isMock) {
        runApp(const _ErrorApp(message: 'Não foi possível conectar ao servidor.'));
        return;
      }
    }
  } else if (!isMock) {
    // Produção sem configuração: bloqueia o acesso.
    runApp(const _ErrorApp(message: 'Configuração incompleta.'));
    return;
  }

  runApp(const RdsPhorestalApp());
}

class RdsPhorestalApp extends StatelessWidget {
  const RdsPhorestalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'SILVORA',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: AppState.instance.themeMode,
          routerConfig: appRouter,
        );
      },
    );
  }
}

/// Tela de erro exibida quando o app não pode inicializar o Supabase
/// em ambiente de produção.
class _ErrorApp extends StatelessWidget {
  final String message;
  const _ErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                const SizedBox(height: 24),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Verifique sua conexão e tente novamente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
