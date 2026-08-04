import 'package:supabase_flutter/supabase_flutter.dart';

/// CRUD genérico sobre o Supabase. Cada tabela usa RLS por `owner_id`,
/// então o filtro por usuário é feito automaticamente pelo banco.
class Db {
  static final Db instance = Db._internal();
  Db._internal();

  static SupabaseClient get _c {
    final c = Supabase.instance.clientOrNull;
    if (c == null) {
      throw Exception('Cliente Supabase não inicializado.');
    }
    return c;
  }

  SupabaseClient get client => _c;

  /// Lista os registros de [table] do usuário logado (mais recentes primeiro).
  /// [select] permite trazer dados relacionados (embedding do PostgREST).
  static Future<List<Map<String, dynamic>>> list(
    String table, {
    String select = '*',
    String orderBy = 'created_at',
    bool ascending = false,
  }) async {
    final res = await _c
        .from(table)
        .select(select)
        .order(orderBy, ascending: ascending);
    return (res as List).cast<Map<String, dynamic>>();
  }

  /// Carrega opções (registros) de uma tabela para preencher seletores.
  static Future<List<Map<String, dynamic>>> options(String table) async {
    final res =
        await _c.from(table).select().order('created_at', ascending: false);
    return (res as List).cast<Map<String, dynamic>>();
  }

  /// Atualiza o registro [id]. Remove campos nulos para evitar erro de coluna inexistente.
  static Future<void> update(
      String table, String id, Map<String, dynamic> data) async {
    final clean = Map<String, dynamic>.from(data)
      ..removeWhere((k, v) => v == null);
    await _c.from(table).update(clean).eq('id', id);
  }

  /// Insere um novo registro. Remove campos nulos para evitar erro de coluna inexistente.
  static Future<Map<String, dynamic>> insert(String table, Map<String, dynamic> data) async {
    final clean = Map<String, dynamic>.from(data)
      ..removeWhere((k, v) => v == null);
    final res = await _c.from(table).insert(clean).select().single();
    return res as Map<String, dynamic>;
  }

  /// Insere e devolve o id do registro criado.
  static Future<String> insertReturningId(
      String table, Map<String, dynamic> data) async {
    final clean = Map<String, dynamic>.from(data)
      ..removeWhere((k, v) => v == null);
    final res = await _c.from(table).insert(clean).select('id').single();
    return '${res['id']}';
  }

  /// Insere vários registros de uma vez.
  static Future<void> insertMany(
      String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final cleaned = rows.map((r) {
      return Map<String, dynamic>.from(r)
        ..removeWhere((k, v) => v == null);
    }).toList();
    await _c.from(table).insert(cleaned);
  }

  /// Remove o registro [id].
  static Future<void> delete(String table, String id) async {
    await _c.from(table).delete().eq('id', id);
  }

  /// Sincroniza uma relação muitos-para-muitos numa tabela de ligação.
  /// Ex.: equipe_membros (equipe_id -> funcionario_id).
  static Future<void> setJoin({
    required String joinTable,
    required String parentKey,
    required String parentId,
    required String childKey,
    required List<String> childIds,
  }) async {
    await _c.from(joinTable).delete().eq(parentKey, parentId);
    if (childIds.isNotEmpty) {
      final rows =
          childIds.map((c) => {parentKey: parentId, childKey: c}).toList();
      await _c.from(joinTable).insert(rows);
    }
  }
}
