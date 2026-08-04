/// Credenciais do projeto Supabase.
///
/// Em produção, defina SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY como
/// variáveis de ambiente e passe-as para o build via --dart-define.
///
/// Em desenvolvimento, use:
///   flutter run --dart-define=FLUTTER_ENV=dev
/// para ativar o modo mock (dados locais, sem autenticação real).
///
/// A chave "publishable" pode ficar no app cliente (é pública por design).
/// NUNCA coloque aqui a chave "secret" (sb_secret_...).
class SupabaseConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  static const String flutterEnv = String.fromEnvironment('FLUTTER_ENV');

  static bool get isDev => flutterEnv == 'dev';

  static bool get isConfigured =>
      supabaseUrl.startsWith('http') &&
      supabaseUrl.length > 10 &&
      supabasePublishableKey.startsWith('sb_publishable_') &&
      supabasePublishableKey.length > 30;

  /// Modo mock: apenas em desenvolvimento explicitamente ativado
  /// e quando o Supabase não estiver configurado.
  static bool get isMockMode => isDev && !isConfigured;
}
