import 'package:flutter/material.dart';
import 'db_service.dart';

/// Tipos de remuneração suportados.
enum FormaRemuneracao {
  diaria,
  metroCubico,
  arvore,
  hora,
  producaoFixa,
}

extension FormaRemuneracaoExt on FormaRemuneracao {
  String get label {
    switch (this) {
      case FormaRemuneracao.diaria:
        return 'Diária';
      case FormaRemuneracao.metroCubico:
        return 'Metro cúbico';
      case FormaRemuneracao.arvore:
        return 'Árvore';
      case FormaRemuneracao.hora:
        return 'Hora';
      case FormaRemuneracao.producaoFixa:
        return 'Produção fixa';
    }
  }

  static FormaRemuneracao fromString(String? value) {
    switch (value) {
      case 'Diária':
        return FormaRemuneracao.diaria;
      case 'Árvore':
        return FormaRemuneracao.arvore;
      case 'Hora':
        return FormaRemuneracao.hora;
      case 'Produção fixa':
        return FormaRemuneracao.producaoFixa;
      case 'Metro cúbico':
      default:
        return FormaRemuneracao.metroCubico;
    }
  }
}

/// Resultado de um cálculo individual de remuneração.
class CalculoRemuneracao {
  final FormaRemuneracao forma;
  final double valorUnitario;
  final double quantidadeCalculo;
  final double valorTotal;

  const CalculoRemuneracao({
    required this.forma,
    required this.valorUnitario,
    required this.quantidadeCalculo,
    required this.valorTotal,
  });

  Map<String, dynamic> toJson() => {
        'forma_remuneracao': forma.label,
        'valor_unitario': valorUnitario,
        'quantidade_calculo': quantidadeCalculo,
        'valor_total': valorTotal,
      };
}

class ProducaoCalculoService {
  /// Calcula a remuneração de um funcionário com base na produção informada.
  /// Nunca divide valores entre participantes.
  static CalculoRemuneracao calcular({
    required Map<String, dynamic> funcionario,
    double volume = 0,
    int arvores = 0,
    double horas = 1,
  }) {
    final forma = FormaRemuneracaoExt.fromString(funcionario['forma_remuneracao']?.toString());

    switch (forma) {
      case FormaRemuneracao.diaria:
        final unitario = _parseDouble(funcionario['valor_diaria']);
        return CalculoRemuneracao(
          forma: forma,
          valorUnitario: unitario,
          quantidadeCalculo: 1,
          valorTotal: unitario,
        );
      case FormaRemuneracao.hora:
        final unitario = _parseDouble(funcionario['valor_hora']);
        final qtd = (horas > 0 ? horas : 1).toDouble();
        return CalculoRemuneracao(
          forma: forma,
          valorUnitario: unitario,
          quantidadeCalculo: qtd,
          valorTotal: (unitario * qtd).toDouble(),
        );
      case FormaRemuneracao.metroCubico:
        final unitario = _parseDouble(funcionario['valor_m3']);
        final qtd = volume.toDouble();
        return CalculoRemuneracao(
          forma: forma,
          valorUnitario: unitario,
          quantidadeCalculo: qtd,
          valorTotal: (unitario * qtd).toDouble(),
        );
      case FormaRemuneracao.arvore:
        final unitario = _parseDouble(funcionario['valor_arvore']);
        final qtd = arvores.toDouble();
        return CalculoRemuneracao(
          forma: forma,
          valorUnitario: unitario,
          quantidadeCalculo: qtd,
          valorTotal: (unitario * qtd).toDouble(),
        );
      case FormaRemuneracao.producaoFixa:
        final unitario = _parseDouble(funcionario['valor_producao_fixa']);
        return CalculoRemuneracao(
          forma: forma,
          valorUnitario: unitario,
          quantidadeCalculo: 1,
          valorTotal: unitario,
        );
    }
  }

  /// Cria o registro de produção e os participantes calculados.
  /// Retorna o ID da produção criada.
  static Future<String> salvarProducao({
    required String tipoProducao,
    required String? funcionarioId,
    required String? equipeId,
    required String? talhaoId,
    required DateTime? data,
    required double volume,
    required int arvores,
    required String observacoes,
    required List<Map<String, dynamic>> participantes,
  }) async {
    // 1. Cria produção principal
    final producao = await Db.insert('producao', {
      'tipo_producao': tipoProducao,
      'funcionario_id': funcionarioId,
      'equipe_id': equipeId,
      'talhao_id': talhaoId,
      'data': data?.toIso8601String().split('T').first,
      'volume_total': volume,
      'total_arvores': arvores,
      'observacoes': observacoes,
    });

    final producaoId = producao['id']?.toString();
    if (producaoId == null) throw Exception('Falha ao criar produção');

    // 2. Cria participantes calculados
    for (final p in participantes) {
      final funcionario = p['funcionario'] as Map<String, dynamic>;
      final selecionado = p['selecionado'] as bool;

      if (!selecionado) continue;

      final calculo = calcular(
        funcionario: funcionario,
        volume: volume,
        arvores: arvores,
        horas: _parseDouble(p['horas'] ?? 1),
      );

      await Db.insert('producao_funcionarios', {
        'producao_id': producaoId,
        'funcionario_id': funcionario['id'].toString(),
        'participou': true,
        ...calculo.toJson(),
      });
    }

    return producaoId;
  }

  /// Atualiza o registro de produção e sincroniza participantes calculados,
  /// preservando registros já pagos.
  static Future<String> atualizarProducao({
    required String producaoId,
    required String tipoProducao,
    required String? funcionarioId,
    required String? equipeId,
    required String? talhaoId,
    required DateTime? data,
    required double volume,
    required int arvores,
    required String observacoes,
    required List<Map<String, dynamic>> participantes,
  }) async {
    // 1. Carrega participantes atuais para preservar os pagos.
    final existentesRes = await Db.instance.client
        .from('producao_funcionarios')
        .select('id, funcionario_id, pago, fechamento_id')
        .eq('producao_id', producaoId);
    final existentes = (existentesRes as List).cast<Map<String, dynamic>>();

    final pagos = existentes.where((e) => e['pago'] == true).toList();
    if (pagos.isNotEmpty) {
      // Só permite alterar observações quando existe participante pago.
      await Db.update('producao', producaoId, {
        'observacoes': observacoes,
      });
      return producaoId;
    }

    // 2. Atualiza produção principal.
    await Db.update('producao', producaoId, {
      'tipo_producao': tipoProducao,
      'funcionario_id': funcionarioId,
      'equipe_id': equipeId,
      'talhao_id': talhaoId,
      'data': data?.toIso8601String().split('T').first,
      'volume_total': volume,
      'total_arvores': arvores,
      'observacoes': observacoes,
    });

    // 3. Mapa dos novos participantes selecionados.
    final selecionados = <String, Map<String, dynamic>>{};
    for (final p in participantes) {
      final selecionado = p['selecionado'] as bool;
      if (!selecionado) continue;
      final funcionario = p['funcionario'] as Map<String, dynamic>;
      final fid = funcionario['id'].toString();
      selecionados[fid] = p;
    }

    // 4. Atualiza os existentes não pagos que continuam selecionados.
    for (final ex in existentes.where((e) => e['pago'] != true)) {
      final fid = ex['funcionario_id'].toString();
      if (selecionados.containsKey(fid)) {
        final p = selecionados[fid]!;
        final funcionario = p['funcionario'] as Map<String, dynamic>;
        final calculo = calcular(
          funcionario: funcionario,
          volume: volume,
          arvores: arvores,
          horas: _parseDouble(p['horas'] ?? 1),
        );
        await Db.instance.client
            .from('producao_funcionarios')
            .update(calculo.toJson())
            .eq('id', ex['id']);
        selecionados.remove(fid);
      } else {
        await Db.instance.client
            .from('producao_funcionarios')
            .delete()
            .eq('id', ex['id']);
      }
    }

    // 5. Insere os novos participantes.
    for (final p in selecionados.values) {
      final funcionario = p['funcionario'] as Map<String, dynamic>;
      final calculo = calcular(
        funcionario: funcionario,
        volume: volume,
        arvores: arvores,
        horas: _parseDouble(p['horas'] ?? 1),
      );
      await Db.insert('producao_funcionarios', {
        'producao_id': producaoId,
        'funcionario_id': funcionario['id'].toString(),
        'participou': true,
        ...calculo.toJson(),
      });
    }

    return producaoId;
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}
