import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class FinanceiroScreen extends StatefulWidget {
  const FinanceiroScreen({super.key});

  @override
  State<FinanceiroScreen> createState() => _FinanceiroScreenState();
}

class _FinanceiroScreenState extends State<FinanceiroScreen> {
  late Future<FinData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<FinData> _load() async {
    try {
      final results = await Future.wait([
        Db.list('lancamentos', select: '*'),
        Db.list('producao', select: '*'),
        Db.list('transporte', select: '*'),
        Db.list('equipes', select: '*'),
      ]);
      return FinData(
        lancamentos: results[0],
        producoes: results[1],
        transporte: results[2],
        equipes: results[3],
      );
    } catch (_) {
      return FinData.fallback();
    }
  }

  void _reload() => setState(() => _future = _load());

  List<double> _monthly(List<Map<String, dynamic>> list, String tipo) {
    final now = DateTime.now();
    final values = List.filled(6, 0.0);
    for (final m in list) {
      if ('${m['tipo']}' != tipo) continue;
      final d = '${m['data']}';
      if (d.isEmpty || d == 'null') continue;
      final parts = d.split('-');
      if (parts.length < 2) continue;
      final year = int.tryParse(parts[0]) ?? 0;
      final month = int.tryParse(parts[1]) ?? 0;
      if (year != now.year) continue;
      final idx = month - (now.month - 5);
      if (idx >= 0 && idx < 6) {
        values[idx] += double.tryParse('${m['valor']}') ?? 0;
      }
    }
    return values;
  }

  List<String> _monthLabels() {
    final now = DateTime.now();
    final meses = [
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez'
    ];
    return List.generate(6, (i) {
      final idx = (now.month - 6 + i) % 12;
      return meses[idx];
    });
  }

  double _calcValor(Map<String, dynamic> m) {
    final tipo = '${m['tipo_pagamento']}';
    final unitario = double.tryParse('${m['valor_unitario']}') ?? 0;
    final volume = double.tryParse('${m['volume_m3']}') ?? 0;
    final arvores = int.tryParse('${m['arvores']}') ?? 0;
    if (tipo == 'Diária' || tipo == 'Tarefa') return unitario;
    if (tipo == 'Árvore') return arvores * unitario;
    return volume * unitario;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FinData>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data ?? FinData.fallback();
        final receitas = data.lancamentos
            .where((m) => '${m['tipo']}' == 'Receita')
            .fold<double>(0, (s, m) => s + (double.tryParse('${m['valor']}') ?? 0));
        final despesas = data.lancamentos
            .where((m) => '${m['tipo']}' == 'Despesa')
            .fold<double>(0, (s, m) => s + (double.tryParse('${m['valor']}') ?? 0));
        final lucro = receitas - despesas;
        final frete = data.transporte.fold<double>(
            0, (s, m) => s + (double.tryParse('${m['frete']}') ?? 0));

        final receitasMes = _monthly(data.lancamentos, 'Receita');
        final despesasMes = _monthly(data.lancamentos, 'Despesa');
        final maxY = [...receitasMes, ...despesasMes]
                .fold<double>(0, (a, b) => a > b ? a : b) *
            1.2;

        // custo por m³ por equipe
        final custoEquipes = <String, double>{};
        final volumeEquipes = <String, double>{};
        for (final p in data.producoes) {
          final eId = '${p['equipe_id']}';
          if (eId.isEmpty || eId == 'null') continue;
          custoEquipes[eId] = (custoEquipes[eId] ?? 0) + _calcValor(p);
          volumeEquipes[eId] = (volumeEquipes[eId] ?? 0) +
              (double.tryParse('${p['volume_m3']}') ?? 0);
        }
        final custoRows = custoEquipes.entries.map((e) {
          final equipe = data.equipes.firstWhere(
            (m) => '${m['id']}' == e.key,
            orElse: () => <String, dynamic>{'nome': 'Equipe ${e.key}'},
          );
          final vol = volumeEquipes[e.key] ?? 0;
          final custo = vol > 0 ? e.value / vol : 0;
          return _CustoRow(
              nome: '${equipe['nome']}',
              custo: custo,
              volume: vol);
        }).toList()
          ..sort((a, b) => b.custo.compareTo(a.custo));

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth > 800 ? 4 : 2;
                return GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: cols == 4 ? 1.8 : 1.6,
                  children: [
                    _kpi('Receitas', 'R\$ ${_fmt(receitas)}',
                        BrandColors.success, Icons.arrow_upward),
                    _kpi('Despesas', 'R\$ ${_fmt(despesas)}',
                        BrandColors.danger, Icons.arrow_downward),
                    _kpi('Lucro', 'R\$ ${_fmt(lucro)}', BrandColors.forest,
                        Icons.trending_up),
                    _kpi('Fretes', 'R\$ ${_fmt(frete)}', BrandColors.alert,
                        Icons.local_shipping),
                  ],
                );
              }),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader('Fluxo de caixa (6 meses)'),
                      SizedBox(
                          height: 220,
                          child: _BarChart(
                            receitas: receitasMes,
                            despesas: despesasMes,
                            labels: _monthLabels(),
                            maxY: maxY < 100 ? 100 : maxY,
                          )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(builder: (context, c) {
                final wide = c.maxWidth > 800;
                final pie = Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader('Custos por categoria'),
                        SizedBox(
                            height: 180,
                            child: _PieChart(lancamentos: data.lancamentos)),
                        const SizedBox(height: 12),
                        ..._categorias(data.lancamentos).map(
                            (c) => _legend(c.nome, c.cor, c.pct)),
                      ],
                    ),
                  ),
                );
                final custos = Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader('Custo por m³'),
                        if (custoRows.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                                child: Text('Sem dados de produção',
                                    style: TextStyle(color: Colors.grey))),
                          )
                        else
                          ...custoRows.map((r) => _costRow(
                              r.nome,
                              'R\$ ${r.custo.toStringAsFixed(2)}',
                              r.volume > 0 ? r.custo / 100 : 0)),
                        const SizedBox(height: 8),
                        _costRow(
                            'Frete médio',
                            'R\$ ${data.transporte.isNotEmpty ? (frete / data.transporte.length).toStringAsFixed(2) : '0,00'}',
                            0.4),
                      ],
                    ),
                  ),
                );
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: pie),
                      const SizedBox(width: 16),
                      Expanded(child: custos),
                    ],
                  );
                }
                return Column(
                    children: [pie, const SizedBox(height: 16), custos]);
              }),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader('Últimos lançamentos'),
                      if (data.lancamentos.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                              child: Text('Nenhum lançamento',
                                  style: TextStyle(color: Colors.grey))),
                        )
                      else
                        ...data.lancamentos.take(5).map((m) => ListTile(
                              leading: Icon(
                                '${m['tipo']}' == 'Receita'
                                    ? Icons.trending_up
                                    : Icons.trending_down,
                                color: '${m['tipo']}' == 'Receita'
                                    ? BrandColors.success
                                    : BrandColors.danger,
                              ),
                              title: Text('${m['descricao']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  '${m['categoria']} • ${m['data']}'),
                              trailing: Text(
                                  'R\$ ${(double.tryParse('${m['valor']}') ?? 0).toStringAsFixed(2)}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: '${m['tipo']}' == 'Receita'
                                          ? BrandColors.success
                                          : BrandColors.danger)),
                            )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmt(double v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(1)}k';
    }
    return v.toStringAsFixed(0);
  }

  List<_Cat> _categorias(List<Map<String, dynamic>> lancamentos) {
    final despesas = lancamentos.where((m) => '${m['tipo']}' == 'Despesa');
    final map = <String, double>{};
    for (final m in despesas) {
      final cat = '${m['categoria']}';
      if (cat.isEmpty || cat == 'null') continue;
      map[cat] = (map[cat] ?? 0) + (double.tryParse('${m['valor']}') ?? 0);
    }
    if (map.isEmpty) {
      return [
        _Cat('Mão de obra', BrandColors.forest, 42),
        _Cat('Combustível', BrandColors.alert, 26),
        _Cat('Manutenção', BrandColors.info, 18),
        _Cat('Outros', Colors.grey, 14),
      ];
    }
    final total = map.values.fold<double>(0, (a, b) => a + b);
    final cores = [
      BrandColors.forest,
      BrandColors.alert,
      BrandColors.info,
      Colors.grey,
      BrandColors.danger,
      BrandColors.success,
    ];
    return map.entries.toList().asMap().entries.map((e) {
      final pct = total > 0 ? (e.value.value / total) * 100 : 0;
      return _Cat(e.value.key, cores[e.key % cores.length], pct);
    }).toList();
  }

  Widget _kpi(String label, String value, Color color, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 18),
            ]),
            const SizedBox(height: 8),
            Text(value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16)),
            Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _legend(String label, Color color, double pct) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13))),
        Text('${pct.toStringAsFixed(0)}%',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _costRow(String label, String value, double frac) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13))),
            const SizedBox(width: 8),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: frac > 1 ? 1 : frac,
              minHeight: 8,
              backgroundColor: Colors.grey.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation(BrandColors.forest),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<double> receitas;
  final List<double> despesas;
  final List<String> labels;
  final double maxY;
  const _BarChart({
    required this.receitas,
    required this.despesas,
    required this.labels,
    required this.maxY,
  });

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(labels[v.toInt()],
                    style: const TextStyle(fontSize: 11)),
              ),
            ),
          ),
        ),
        barGroups: List.generate(6, (i) {
          return BarChartGroupData(x: i, barRods: [
            BarChartRodData(
                toY: receitas[i],
                color: BrandColors.forest,
                width: 9,
                borderRadius: BorderRadius.circular(4)),
            BarChartRodData(
                toY: despesas[i],
                color: BrandColors.alert,
                width: 9,
                borderRadius: BorderRadius.circular(4)),
          ]);
        }),
      ),
    );
  }
}

class _PieChart extends StatelessWidget {
  final List<Map<String, dynamic>> lancamentos;
  const _PieChart({required this.lancamentos});

  @override
  Widget build(BuildContext context) {
    final cats = _categorias(lancamentos);
    return PieChart(
      PieChartData(
        centerSpaceRadius: 40,
        sectionsSpace: 2,
        sections: cats.map((c) {
          return PieChartSectionData(
            value: c.pct <= 0 ? 1 : c.pct,
            color: c.cor,
            title: '${c.pct.toStringAsFixed(0)}%',
            radius: 50,
            titleStyle: _t,
          );
        }).toList(),
      ),
    );
  }

  static List<_Cat> _categorias(List<Map<String, dynamic>> lancamentos) {
    final despesas = lancamentos.where((m) => '${m['tipo']}' == 'Despesa');
    final map = <String, double>{};
    for (final m in despesas) {
      final cat = '${m['categoria']}';
      if (cat.isEmpty || cat == 'null') continue;
      map[cat] = (map[cat] ?? 0) + (double.tryParse('${m['valor']}') ?? 0);
    }
    if (map.isEmpty) {
      return [
        _Cat('Mão de obra', BrandColors.forest, 42),
        _Cat('Combustível', BrandColors.alert, 26),
        _Cat('Manutenção', BrandColors.info, 18),
        _Cat('Outros', Colors.grey, 14),
      ];
    }
    final total = map.values.fold<double>(0, (a, b) => a + b);
    final cores = [
      BrandColors.forest,
      BrandColors.alert,
      BrandColors.info,
      Colors.grey,
      BrandColors.danger,
      BrandColors.success,
    ];
    return map.entries.toList().asMap().entries.map((e) {
      final pct = total > 0 ? (e.value.value / total) * 100 : 0;
      return _Cat(e.value.key, cores[e.key % cores.length], pct);
    }).toList();
  }

  static const _t = TextStyle(
      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11);
}

class FinData {
  final List<Map<String, dynamic>> lancamentos;
  final List<Map<String, dynamic>> producoes;
  final List<Map<String, dynamic>> transporte;
  final List<Map<String, dynamic>> equipes;

  FinData({
    required this.lancamentos,
    required this.producoes,
    required this.transporte,
    required this.equipes,
  });

  factory FinData.fallback() => FinData(
        lancamentos: const [],
        producoes: const [],
        transporte: const [],
        equipes: const [],
      );
}

class _Cat {
  final String nome;
  final Color cor;
  final double pct;
  _Cat(this.nome, this.cor, this.pct);
}

class _CustoRow {
  final String nome;
  final double custo;
  final double volume;
  _CustoRow({required this.nome, required this.custo, required this.volume});
}
