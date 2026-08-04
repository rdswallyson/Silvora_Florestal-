import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Serviço de autenticação usando Supabase (email/senha).
class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  SupabaseClient get _client {
    final c = Supabase.instance.clientOrNull;
    if (c == null) {
      throw Exception('Cliente Supabase não inicializado.');
    }
    return c;
  }

  User? get currentUser => _client.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signUp(String email, String password,
      {String? nome}) async {
    await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: nome != null ? {'nome': nome} : null,
    );
  }

  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  String get userName {
    final u = currentUser;
    if (u == null) return 'Usuário';
    final nome = u.userMetadata?['nome'] as String?;
    if (nome != null && nome.isNotEmpty) return nome;
    return u.email ?? 'Usuário';
  }

  /// Traduz erros do Supabase para mensagens amigáveis em PT-BR.
  static String friendlyError(Object e) {
    if (e is AuthException) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid login')) {
        return 'E-mail ou senha incorretos.';
      }
      if (m.contains('email not confirmed')) {
        return 'Confirme seu e-mail antes de entrar.';
      }
      if (m.contains('already registered') ||
          m.contains('already been registered')) {
        return 'Este e-mail já está cadastrado.';
      }
      if (m.contains('password') && m.contains('6')) {
        return 'A senha deve ter pelo menos 6 caracteres.';
      }
      return e.message;
    }
    if (kDebugMode) {
      return 'Erro: $e';
    }
    return 'Não foi possível concluir. Tente novamente.';
  }
}
