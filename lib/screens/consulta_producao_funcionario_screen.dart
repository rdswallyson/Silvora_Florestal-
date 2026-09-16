import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Tela de detalhamento das produções de um funcionário em um período.
class ConsultaProducaoFuncionarioScreen extends StatelessWidget {
  final Map<String, dynamic> funcionario;
  final DateTime dataInicio;
  final DateTime dataFim;
  final List<Map<String, dynamic>> producoesFuncionario;

  const ConsultaProducaoFuncionarioScreen({
    super.key,
    required this.funcionario,
    required this.dataInicio,
    required this.dataFim,
    required this.producoesFuncionario,
  });

  static final _dateFmt = DateFormat('dd/MM/yyyy');
  static final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  Widget build(BuildContext context) {
    final forma = _s(funcionario, 'forma_remuneracao');
    double volume = 0;
    double arvores = 0;
    double horas = 0;
    double valor = 0;
    for (final pf in producoesFuncionario) {
      final p = pf['producao'];
      if (p is Map) {
        volume += _d(p, 'volume_total');
        arvores += _d(p, 'total_arvores');
      }
      if (forma == 'Hora') {
        horas += _d(pf, 'quantidade_calculo');
      }
      valor += _d(pf, 'valor_total');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_s(funcionario, 'nome')),
        backgroundColor: BrandColors.forest,
        foregroundColor: Colors.white,
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RESUMO DO PERÍODO',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: BrandColors.forest),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_dateFmt.format(dataInicio)} a ${_dateFmt.format(dataFim)}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    _buildResumoStats(forma, volume, arvores, horas, valor),
                  ],
                ),
              ),
            ),
          ),
          if (producoesFuncionario.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                  child: Text('Nenhuma produção no período selecionado.')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  childCount: producoesFuncionario.length,
                  (context, index) {
                      final pf = producoesFuncionario[index];
                      final p = pf['producao'] is Map
                          ? pf['producao'] as Map
                          : const <String, dynamic>{};
                      final data = _parseDate(p['data']);
                      final talhao = _ref(p, 'talhao', 'codigo');
                      final equipe = _ref(p, 'equipe', 'nome');
                      final forma = _s(pf, 'forma_remuneracao');
                      final qtd = _d(pf, 'quantidade_calculo');
                      final valorPf = _d(pf, 'valor_total');
                      final volumeP = _d(p, 'volume_total');
                      final arvoresP = _d(p, 'total_arvores');

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      data == null
                                          ? 'Data não informada'
                                          : _dateFmt.format(data),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15),
                                    ),
                                  ),
                                  if (pf['pago'] == true)
                                    const StatusChip('Pago', BrandColors.success),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (talhao.isNotEmpty)
                                _linhaInfo(Icons.forest_outlined,
                                    'Talhão: $talhao'),
                              if (equipe.isNotEmpty)
                                _linhaInfo(Icons.groups_outlined,
                                    'Equipe: $equipe'),
                              _linhaInfo(Icons.paid_outlined,
                                  '$forma • ${qtd.toStringAsFixed(0)} un'),
                              if (pf['pago'] == true)
                                _linhaInfo(Icons.calendar_today_outlined,
                                    'Pago em: ${_fmtDataPagamento(pf['data_pagamento'])}'),
                              const Divider(height: 24),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Valor: ${_currency.format(valorPf)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: BrandColors.forest,
                                          fontSize: 15),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              _buildItemResumo(forma, volumeP, arvoresP, qtd),
                            ],
                          ),
                        ),
                      );
                    },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResumoStats(
      String forma, double volume, double arvores, double horas, double valor) {
    final stats = <Widget>[
      _miniStat('Produções', '${producoesFuncionario.length}'),
    ];

    switch (forma) {
      case 'Diária':
      case 'Produção fixa':
        break;
      case 'Hora':
        stats.add(_miniStat('Horas', '${horas.toStringAsFixed(1)} h'));
        break;
      case 'Árvore':
        stats.add(_miniStat('Árvores', '${arvores.toStringAsFixed(0)}'));
        break;
      case 'Metro cúbico':
      default:
        stats.add(_miniStat('Volume', '${volume.toStringAsFixed(1)} m³'));
        break;
    }

    stats.add(
        _miniStat('Total', _currency.format(valor), highlight: true));

    return ResponsiveStatGrid(minItemWidth: 120, children: stats);
  }

  Widget _buildItemResumo(
      String forma, double volume, double arvores, double qtd) {
    switch (forma) {
      case 'Diária':
      case 'Produção fixa':
        return const SizedBox.shrink();
      case 'Hora':
        return Row(
          children: [
            Expanded(
              child: Text(
                'Horas: ${qtd.toStringAsFixed(1)} h',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        );
      case 'Árvore':
        return Row(
          children: [
            Expanded(
              child: Text(
                'Árvores: ${arvores.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        );
      case 'Metro cúbico':
      default:
        return Row(
          children: [
            Expanded(
              child: Text(
                'Volume: ${volume.toStringAsFixed(1)} m³',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Text(
              'Árvores: ${arvores.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
    }
  }

  Widget _miniStat(String label, String value, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? BrandColors.forest.withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color:
                      highlight ? BrandColors.forest : BrandColors.forestDark),
              textAlign: TextAlign.center),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _linhaInfo(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  static String _fmtDataPagamento(dynamic value) {
    if (value == null) return '-';
    try {
      final dt = DateTime.parse(value.toString());
      return _dateFmt.format(dt);
    } catch (_) {
      return value.toString();
    }
  }

  static String _s(Map m, String k) => (m[k] ?? '').toString();
  static double _d(Map m, String k) =>
      double.tryParse('${m[k]}') ?? 0;

  static String _ref(Map m, String alias, String field) {
    final v = m[alias];
    if (v is Map && v[field] != null) return v[field].toString();
    return '';
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }
}
