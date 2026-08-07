import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'db_service.dart';

/// Gerencia o histórico de preços por m³ dos clientes.
///
/// Cada cliente pode ter vários preços ao longo do tempo, com vigência
/// definida por [vigente_desde] e [vigente_ate]. O preço vigente para uma
/// data específica é o último registro onde a data está dentro da vigência.
class ClientePrecoService {
  static final _client = Supabase.instance.client;

  /// Retorna o preço vigente para um cliente em uma data específica.
  /// Retorna `null` se não houver preço cadastrado para aquela data.
  static Future<double?> buscarPrecoVigente(
    String clienteId,
    DateTime data,
  ) async {
    try {
      final res = await _client
          .from('cliente_precos')
          .select('valor_m3')
          .eq('cliente_id', clienteId)
          .lte('vigente_desde', data.toIso8601String().split('T').first)
          .or('vigente_ate.is.null,vigente_ate.gte.${data.toIso8601String().split('T').first}')
          .order('vigente_desde', ascending: false)
          .limit(1);

      final lista = res as List<dynamic>?;
      if (lista == null || lista.isEmpty) return null;

      final valor = lista.first['valor_m3'];
      if (valor == null) return null;
      return (valor is num) ? valor.toDouble() : double.tryParse(valor.toString());
    } catch (e) {
      debugPrint('Erro ao buscar preço vigente: $e');
      return null;
    }
  }

  /// Salva um novo preço para o cliente, fechando a vigência anterior.
  static Future<void> salvarPreco(String clienteId, double valorM3) async {
    await Db.insert('cliente_precos', {
      'cliente_id': clienteId,
      'valor_m3': valorM3,
      'vigente_desde': DateTime.now().toIso8601String().split('T').first,
    });
  }

  /// Lista todo o histórico de preços de um cliente, do mais recente ao mais antigo.
  static Future<List<Map<String, dynamic>>> listarHistorico(
    String clienteId,
  ) async {
    try {
      final res = await _client
          .from('cliente_precos')
          .select('valor_m3, vigente_desde, vigente_ate, created_at')
          .eq('cliente_id', clienteId)
          .order('vigente_desde', ascending: false);

      return (res as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Erro ao listar histórico de preços: $e');
      return [];
    }
  }
}
