import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/gps_screen.dart';
import '../screens/financeiro_screen.dart';
import '../screens/relatorios_screen.dart';
import '../screens/ia_screen.dart';
import '../screens/configuracoes_screen.dart';
import '../screens/entity_list_screen.dart';
import '../screens/consulta_producao_screen.dart';
import '../data/entities.dart';
import '../widgets/app_shell.dart';
import '../services/auth_service.dart';
import '../services/supabase_client_helper.dart';

/// Adapta o stream de auth do Supabase para um Listenable que o go_router
/// escuta para reavaliar as rotas quando o usuário entra ou sai.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    final client = SupabaseClientHelper.currentClient;
    if (client != null) {
      _sub = client.auth.onAuthStateChange.listen((_) {
        notifyListeners();
      });
    }
  }
  StreamSubscription<AuthState>? _sub;
  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

CustomTransitionPage _fade(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

final appRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: _AuthRefresh(),
  redirect: (context, state) {
    final loggedIn = AuthService.instance.isLoggedIn;
    final loc = state.uri.path;
    final onSplash = loc == '/';
    final onLogin = loc == '/login';
    // Deixa a splash decidir o primeiro destino.
    if (onSplash) return null;
    if (!loggedIn && !onLogin) return '/login';
    if (loggedIn && onLogin) return '/dashboard';
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    ShellRoute(
      builder: (context, state, child) =>
          AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(
            path: '/dashboard',
            pageBuilder: (c, s) => _fade(const DashboardScreen(), s)),
        GoRoute(
            path: '/producao',
            pageBuilder: (c, s) =>
                _fade(EntityListScreen(kEntities['producao']!), s)),
        GoRoute(
            path: '/consulta-producao',
            pageBuilder: (c, s) => _fade(const ConsultaProducaoScreen(), s)),
        GoRoute(
            path: '/funcionarios',
            pageBuilder: (c, s) =>
                _fade(EntityListScreen(kEntities['funcionarios']!), s)),
        GoRoute(
            path: '/equipes',
            pageBuilder: (c, s) =>
                _fade(EntityListScreen(kEntities['equipes']!), s)),
        GoRoute(
            path: '/fazendas',
            pageBuilder: (c, s) =>
                _fade(EntityListScreen(kEntities['fazendas']!), s)),
        GoRoute(
            path: '/talhoes',
            pageBuilder: (c, s) =>
                _fade(EntityListScreen(kEntities['talhoes']!), s)),
        GoRoute(
            path: '/veiculos',
            pageBuilder: (c, s) =>
                _fade(EntityListScreen(kEntities['veiculos']!), s)),
        GoRoute(
            path: '/transporte',
            pageBuilder: (c, s) =>
                _fade(EntityListScreen(kEntities['transporte']!), s)),
        GoRoute(
            path: '/clientes',
            pageBuilder: (c, s) =>
                _fade(EntityListScreen(kEntities['clientes']!), s)),
        GoRoute(
            path: '/equipamentos',
            pageBuilder: (c, s) =>
                _fade(EntityListScreen(kEntities['equipamentos']!), s)),
        GoRoute(
            path: '/estoque',
            pageBuilder: (c, s) =>
                _fade(EntityListScreen(kEntities['estoque']!), s)),
        GoRoute(
            path: '/financeiro',
            pageBuilder: (c, s) => _fade(const FinanceiroScreen(), s)),
        GoRoute(
            path: '/gps', pageBuilder: (c, s) => _fade(const GpsScreen(), s)),
        GoRoute(
            path: '/relatorios',
            pageBuilder: (c, s) => _fade(const RelatoriosScreen(), s)),
        GoRoute(
            path: '/ia', pageBuilder: (c, s) => _fade(const IaScreen(), s)),
        GoRoute(
            path: '/configuracoes',
            pageBuilder: (c, s) => _fade(const ConfiguracoesScreen(), s)),
      ],
    ),
  ],
);
