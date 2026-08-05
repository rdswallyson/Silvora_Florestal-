import 'package:supabase_flutter/supabase_flutter.dart';

/// Helper seguro para acessar o cliente Supabase.
///
/// `Supabase.instance.client` lança `StateError` quando o cliente não foi
/// inicializado. Este helper captura a exceção e devolve `null`, permitindo
/// que as camadas superiores decidam como tratar a situação.
class SupabaseClientHelper {
  static SupabaseClient? get currentClient {
    try {
      return Supabase.instance.client;
    } on StateError catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }
}
