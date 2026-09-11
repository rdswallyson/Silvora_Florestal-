import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../services/db_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<DashboardData> _future;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // Atualiza os dados a cada 30 segundos para ficar "em tempo real"
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _future = _load());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<DashboardData> _load() async {
    if (!AuthService.instance.isLoggedIn) {
      return DashboardData.fallback();
    }
    try {
      final results = await Future.wait([
        Db.list('producao',
            select:
                '*, funcionario:funcionarios!funcionario_id(nome), equipe:equipes!equipe_id(nome), talhao:talhoes!talhao_id(codigo), producao_funcionarios(*)'),
        Db.list('equipes', select: '*'),
        Db.list('veiculos', select: '*'),
        Db.list('equipamentos', select: '*'),
        Db.list('lancamentos', select: '*'),
        Db.list('estoque', select: '*'),
        Db.list('transporte', select: '*'),
        Db.list('funcionarios', select: '*'),
      ]);
      return DashboardData(
        producoes: results[0],
        equipes: results[1],
        veiculos: results[2],
        equipamentos: results[3],
        lancamentos: results[4],
        estoque: results[5],
        transporte: results[6],
        funcionarios: results[7],
      );
    } catch (_) {
      return DashboardData.fallback();
    }
  }

  double _sum(List<Map> list, String key) => list.fold<double>(
      0, (s, m) => s + (double.tryParse('${m[key]}') ?? 0));

  double _sumInt(List<Map> list, String key) => list.fold<double>(
      0, (s, m) => s + (int.tryParse('${m[key]}') ?? 0));

  String _todayStr() => DateTime.now().toIso8601String().split('T').first;

  String _fmt(double v) {
    if (v == v.toInt()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  Map<String, double> _producaoPorDia(List<Map> list) {
    final map = <String, double>{};
    for (final m in list) {
      var d = '${m['data']}'.trim();
      if (d.isEmpty || d == 'null') continue;
      // A coluna é `date`, mas se algum registro vier como timestamp
      // ("2026-08-14T00:00:00") a chave precisa ficar só com a parte da data.
      if (d.length > 10) d = d.substring(0, 10);
      map[d] = (map[d] ?? 0) + (double.tryParse('${m['volume_total']}') ?? 0);
    }
    return map;
  }

  List<FlSpot> _buildSpots(Map<String, double> porDia, DateTime fim) {
    return List.generate(7, (i) {
      final d = fim.subtract(Duration(days: 6 - i));
      return FlSpot(i.toDouble(), porDia[_dateStr(d)] ?? 0);
    });
  }

  /// Soma o volume de uma janela de dias contada a partir de [fim], de
  /// `deInicio` dias atrás até `deFim` dias atrás (exclusivo).
  double _volumeJanela(
      Map<String, double> porDia, DateTime fim, int deInicio, int deFim) {
    var total = 0.0;
    for (var i = deInicio; i > deFim; i--) {
      total += porDia[_dateStr(fim.subtract(Duration(days: i)))] ?? 0;
    }
    return total;
  }

  /// Data final da janela do gráfico: normalmente hoje, mas se não houve
  /// produção nos últimos 7 dias cai para o dia da última produção, para o
  /// gráfico não ficar permanentemente vazio.
  DateTime _fimJanelaGrafico(Map<String, double> porDia) {
    final hoje = DateTime.now();
    final hojeSemHora = DateTime(hoje.year, hoje.month, hoje.day);
    var temNaSemana = false;
    for (var i = 0; i < 7; i++) {
      if ((porDia[_dateStr(hojeSemHora.subtract(Duration(days: i)))] ?? 0) > 0) {
        temNaSemana = true;
        break;
      }
    }
    if (temNaSemana || porDia.isEmpty) return hojeSemHora;

    DateTime? ultima;
    for (final e in porDia.entries) {
      if (e.value <= 0) continue;
      final d = DateTime.tryParse(e.key);
      if (d == null) continue;
      if (ultima == null || d.isAfter(ultima)) ultima = d;
    }
    return ultima ?? hojeSemHora;
  }

  String _dateStr(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  String _two(int n) => n.toString().padLeft(2, '0');
  final _diasSemana = ['DOM', 'SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SAB'];

  String _hojeExtenso() {
    final d = DateTime.now();
    final semana = [
      'Domingo',
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado'
    ];
    final meses = [
      'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
      'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
    ];
    return '${semana[d.weekday % 7]}, ${d.day} de ${meses[d.month - 1]} de ${d.year}';
  }

  String _saudacao() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bom dia';
    if (h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  String _monthStart() {
    final d = DateTime.now();
    return '${d.year}-${_two(d.month)}-01';
  }

  String _monthEnd() {
    final d = DateTime.now();
    final last = DateTime(d.year, d.month + 1, 0);
    return '${last.year}-${_two(last.month)}-${_two(last.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final email = AuthService.instance.currentUser?.email ?? '';
    final nome = email.split('@').first;

    return FutureBuilder<DashboardData>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data ?? DashboardData.fallback();

        final volumeTotal = _sum(data.producoes, 'volume_total');
        final volumeHoje = _sum(
          data.producoes
              .where((m) => '${m['data']}'.startsWith(_todayStr()))
              .toList(),
          'volume_total',
        );
        final producoesMes = data.producoes.where((m) {
          final d = '${m['data']}';
          return d.compareTo(_monthStart()) >= 0 &&
              d.compareTo(_monthEnd()) <= 0;
        }).toList();
        final volumeMes = _sum(producoesMes, 'volume_total');
        final arvoresMes = _sumInt(producoesMes, 'total_arvores');

        final receitas = data.lancamentos
            .where((m) => '${m['tipo']}' == 'Receita')
            .fold<double>(0, (s, m) => s + (double.tryParse('${m['valor']}') ?? 0));
        final despesas = data.lancamentos
            .where((m) => '${m['tipo']}' == 'Despesa')
            .fold<double>(0, (s, m) => s + (double.tryParse('${m['valor']}') ?? 0));
        final lucro = receitas - despesas;

        final porDia = _producaoPorDia(data.producoes);
        final fimJanela = _fimJanelaGrafico(porDia);
        final spots = _buildSpots(porDia, fimJanela);
        final maxY = spots.fold<double>(0, (a, s) => a > s.y ? a : s.y);
        // Total/média precisam refletir a mesma janela do gráfico (7 dias),
        // senão o cabeçalho mostra um total que não existe na curva.
        final volume7 = spots.fold<double>(0, (a, s) => a + s.y);
        final volume7Anterior = _volumeJanela(porDia, fimJanela, 13, 6);
        final variacao7 = volume7Anterior > 0
            ? ((volume7 - volume7Anterior) / volume7Anterior) * 100
            : null;

        final freteReceitas = data.transporte.fold<double>(
            0, (s, m) => s + (double.tryParse('${m['frete']}') ?? 0));

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${_saudacao()}, ${nome.isNotEmpty ? nome : 'usuário'}! 👋',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(_hojeExtenso(),
                          style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.55),
                              fontSize: 12)),
                    ],
                  ),
                ),
                if (snap.connectionState != ConnectionState.done)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 18),

            // KPIs
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 1100
                  ? 4
                  : c.maxWidth > 700
                      ? 2
                      : 2;
              // Em telas estreitas o card precisa ficar mais alto para caber
              // ícone + valor + rótulo sem estourar.
              final ratio = cols == 4
                  ? 1.95
                  : c.maxWidth > 700
                      ? 1.85
                      : 1.4;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: ratio,
                children: [
                  _KpiCard(
                    label: 'Produção hoje',
                    value: '${_fmt(volumeHoje)} m³',
                    icon: Icons.grass_outlined,
                    gradient: const [BrandColors.forest, BrandColors.forestDark],
                    onTap: () => context.go('/producao'),
                  ),
                  _KpiCard(
                    label: 'Produção no mês',
                    value: '${_fmt(volumeMes)} m³',
                    icon: Icons.forest_outlined,
                    gradient: const [BrandColors.success, BrandColors.forest],
                    onTap: () => context.go('/producao'),
                  ),
                  _KpiCard(
                    label: 'Receitas',
                    value: 'R\$ ${_fmt(receitas)}',
                    icon: Icons.attach_money,
                    gradient: const [BrandColors.alert, Color(0xFFF57C00)],
                    onTap: () => context.go('/financeiro'),
                  ),
                  _KpiCard(
                    label: 'Saldo líquido',
                    value: 'R\$ ${_fmt(lucro)}',
                    icon: Icons.account_balance_wallet_outlined,
                    gradient: lucro >= 0
                        ? const [BrandColors.success, Color(0xFF2E7D32)]
                        : const [BrandColors.danger, Color(0xFFB71C1C)],
                    onTap: () => context.go('/financeiro'),
                  ),
                ],
              );
            }),

            const SizedBox(height: 18),

            // Gráfico
            _ChartCard(
              spots: spots,
              maxY: maxY,
              dias: _diasSemana,
              fim: fimJanela,
              volumeSemana: volume7,
              variacao: variacao7,
            ),

            const SizedBox(height: 18),

            // Resumo operacional
            _OperacionalCard(
              funcionarios: data.funcionarios.length,
              equipes: data.equipes.length,
              veiculos: data.veiculos.length,
              equipManutencao: data.equipamentos
                  .where((m) => '${m['situacao']}' == 'Manutenção')
                  .length,
              onVerDetalhes: () => context.go('/funcionarios'),
            ),

            const SizedBox(height: 22),

            // Layout de duas colunas: alertas + produção recente
            LayoutBuilder(builder: (context, c) {
              final alertas = _buildAlerts(data);
              final wide = c.maxWidth > 1000;
              final cardAlertas = _AlertsCard(
                alertas: alertas,
                onVerTodos: () => context.go('/relatorios'),
              );
              final cardProducao = _RecentProduction(
                producoes: data.producoes,
                onVerTudo: () => context.go('/producao'),
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: cardAlertas),
                    const SizedBox(width: 16),
                    Expanded(flex: 7, child: cardProducao),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  cardAlertas,
                  const SizedBox(height: 16),
                  cardProducao,
                ],
              );
            }),

            const SizedBox(height: 22),

            // Mapa
            _MapCard(
              equipes: data.equipes.length,
              veiculos: data.veiculos.length,
            ),

            const SizedBox(height: 22),

            // Card produtividade
            _ProductivityCard(),
          ],
        );
      },
    );
  }

  List<AlertItem> _buildAlerts(DashboardData data) {
    final list = <AlertItem>[];
    for (final m in data.estoque) {
      final q = int.tryParse('${m['quantidade']}') ?? 0;
      final min = int.tryParse('${m['minimo']}') ?? 0;
      if (q <= min && min > 0) {
        list.add(AlertItem(
          icon: Icons.inventory_2_outlined,
          titulo: 'Estoque baixo: ${m['nome']}',
          descricao: 'Restam apenas $q unidades.',
          cor: BrandColors.danger,
          acao: 'Comprar agora',
        ));
      }
    }
    for (final m in data.equipamentos) {
      if ('${m['situacao']}' == 'Manutenção') {
        list.add(AlertItem(
          icon: Icons.build_circle_outlined,
          titulo: 'Manutenção pendente',
          descricao: '${m['nome']} precisa de revisão',
          cor: BrandColors.alert,
        ));
      }
    }
    for (final m in data.veiculos) {
      if ('${m['situacao']}' == 'Manutenção') {
        list.add(AlertItem(
          icon: Icons.local_shipping_outlined,
          titulo: 'Veículo parado',
          descricao: '${m['nome']} em manutenção',
          cor: BrandColors.alert,
        ));
      }
    }
    if (list.isEmpty) {
      list.add(AlertItem(
        icon: Icons.check_circle_outline,
        titulo: 'Tudo sob controle!',
        descricao: 'Não há outras pendências no momento.',
        cor: BrandColors.success,
      ));
    }
    return list;
  }
}

class DashboardData {
  final List<Map<String, dynamic>> producoes;
  final List<Map<String, dynamic>> equipes;
  final List<Map<String, dynamic>> veiculos;
  final List<Map<String, dynamic>> equipamentos;
  final List<Map<String, dynamic>> lancamentos;
  final List<Map<String, dynamic>> estoque;
  final List<Map<String, dynamic>> transporte;
  final List<Map<String, dynamic>> funcionarios;

  DashboardData({
    required this.producoes,
    required this.equipes,
    required this.veiculos,
    required this.equipamentos,
    required this.lancamentos,
    required this.estoque,
    required this.transporte,
    required this.funcionarios,
  });

  factory DashboardData.fallback() => DashboardData(
        producoes: const [],
        equipes: const [],
        veiculos: const [],
        equipamentos: const [],
        lancamentos: const [],
        estoque: const [],
        transporte: const [],
        funcionarios: const [],
      );
}

class AlertItem {
  final IconData icon;
  final String titulo;
  final String descricao;
  final Color cor;
  final String? acao;
  AlertItem({
    required this.icon,
    required this.titulo,
    required this.descricao,
    required this.cor,
    this.acao,
  });
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    final y = size.height;
    path.moveTo(0, y * 0.7);
    path.quadraticBezierTo(size.width * 0.25, y * 0.9, size.width * 0.5, y * 0.5);
    path.quadraticBezierTo(size.width * 0.75, y * 0.2, size.width, y * 0.4);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ChartCard extends StatelessWidget {
  final List<FlSpot> spots;
  final double maxY;
  final List<String> dias;
  final DateTime fim;
  final double volumeSemana;
  final double? variacao;
  const _ChartCard({
    required this.spots,
    required this.maxY,
    required this.dias,
    required this.fim,
    required this.volumeSemana,
    required this.variacao,
  });

  @override
  Widget build(BuildContext context) {
    final media = volumeSemana / 7;
    final semProducao = maxY <= 0;
    final v = variacao;
    final hoje = DateTime.now();
    final atual = fim.year == hoje.year &&
        fim.month == hoje.month &&
        fim.day == hoje.day;
    final inicio = fim.subtract(const Duration(days: 6));
    final titulo = atual
        ? 'Produção dos últimos 7 dias'
        : 'Produção de ${_d(inicio)} a ${_d(fim)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 17)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: BrandColors.forest.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('m³/dia',
                      style: TextStyle(
                          color: BrandColors.forest,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Wrap em vez de Row: em telas estreitas o badge de variação passa
            // para a linha de baixo em vez de ser cortado na borda do card.
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Total: ${volumeSemana.toStringAsFixed(1)} m³',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                Text('Média diária: ${media.toStringAsFixed(1)} m³',
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.55),
                        fontSize: 13)),
                if (v != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: v >= 0
                          ? BrandColors.successSoft
                          : BrandColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                        '${v >= 0 ? '↗' : '↘'} ${v.abs().toStringAsFixed(1)}% vs semana anterior',
                        style: TextStyle(
                            color: v >= 0
                                ? BrandColors.success
                                : BrandColors.danger,
                            fontWeight: FontWeight.w700,
                            fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: semProducao
                  ? const Center(
                      child: Text('Sem produção registrada ainda',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey)))
                  : LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: maxY * 1.2,
                        // Sem o clip desligado, a parte da linha que encosta na
                        // borda do gráfico (valor 0) é cortada e desaparece.
                        clipData: const FlClipData.none(),
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            tooltipRoundedRadius: 12,
                            getTooltipColor: (_) => BrandColors.forest,
                            getTooltipItems: (touched) => touched
                                .map((e) => LineTooltipItem(
                                      '${e.y.toStringAsFixed(1)} m³',
                                      const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700),
                                    ))
                                .toList(),
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 1,
                              reservedSize: 44,
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx < 0 || idx > 6) {
                                  return const SizedBox.shrink();
                                }
                                final d = fim.subtract(Duration(days: 6 - idx));
                                final valor =
                                    idx < spots.length ? spots[idx].y : 0.0;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        dias[d.weekday % 7],
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey),
                                      ),
                                      Text(
                                        valor == 0
                                            ? '-'
                                            : valor.toStringAsFixed(
                                                valor == valor.roundToDouble()
                                                    ? 0
                                                    : 1),
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: valor == 0
                                                ? Colors.grey
                                                : BrandColors.forest),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            preventCurveOverShooting: true,
                            color: BrandColors.forest,
                            barWidth: 3,
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  BrandColors.forest.withValues(alpha: 0.3),
                                  BrandColors.forest.withValues(alpha: 0.0),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, pct, bar, idx) {
                                return FlDotCirclePainter(
                                  radius: 5,
                                  color: BrandColors.forest,
                                  strokeWidth: 2,
                                  strokeColor: Colors.white,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

class _OperacionalCard extends StatelessWidget {
  final int funcionarios;
  final int equipes;
  final int veiculos;
  final int equipManutencao;
  final VoidCallback onVerDetalhes;
  const _OperacionalCard({
    required this.funcionarios,
    required this.equipes,
    required this.veiculos,
    required this.equipManutencao,
    required this.onVerDetalhes,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader('Resumo operacional',
                action: 'Ver detalhes', onAction: onVerDetalhes),
            const SizedBox(height: 4),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 700 ? 4 : 2;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: cols == 4
                    ? 2.6
                    : c.maxWidth > 420
                        ? 2.2
                        : 1.9,
                children: [
                  _OpItem(Icons.badge_outlined, 'Funcionários', '$funcionarios',
                      BrandColors.info),
                  _OpItem(Icons.groups_outlined, 'Equipes', '$equipes',
                      BrandColors.forest),
                  _OpItem(Icons.local_shipping_outlined, 'Veículos',
                      '$veiculos', BrandColors.success),
                  _OpItem(Icons.build_circle_outlined, 'Manutenção',
                      '$equipManutencao', BrandColors.alert),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _OpItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _OpItem(this.icon, this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
                Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertsCard extends StatelessWidget {
  final List<AlertItem> alertas;
  final VoidCallback? onVerTodos;
  const _AlertsCard({required this.alertas, this.onVerTodos});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader('Alertas importantes',
                action: 'Ver todos', onAction: onVerTodos),
            const SizedBox(height: 4),
            ...alertas.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: a.cor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: a.cor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(a.icon, color: a.cor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.titulo,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(a.descricao,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6))),
                              if (a.acao != null) ...[
                                const SizedBox(height: 8),
                                FilledButton(
                                  onPressed: () {},
                                  style: FilledButton.styleFrom(
                                    backgroundColor: a.cor,
                                    minimumSize: const Size(0, 32),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8)),
                                  ),
                                  child: Text(a.acao!,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _RecentProduction extends StatelessWidget {
  final List<Map<String, dynamic>> producoes;
  final VoidCallback? onVerTudo;
  const _RecentProduction({required this.producoes, this.onVerTudo});

  @override
  Widget build(BuildContext context) {
    final recent = producoes.take(5).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader('Produção recente',
                action: 'Ver tudo', onAction: onVerTudo),
            const SizedBox(height: 4),
            if (recent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('Nenhuma produção registrada ainda',
                      style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              ...recent.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ModernListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: BrandColors.forest.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.grass_outlined,
                            color: BrandColors.forest, size: 18),
                      ),
                      title:
                          '${_ref(p, 'equipe', 'nome')} • ${_ref(p, 'talhao', 'codigo')}',
                      subtitle: '${p['data'] ?? ''}',
                      trailing:
                          '${(double.tryParse('${p['volume_total']}') ?? 0).toStringAsFixed(1)} m³',
                      onTap: () => context.go('/producao'),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _MapCard extends StatelessWidget {
  final int equipes;
  final int veiculos;
  const _MapCard({required this.equipes, required this.veiculos});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => context.go('/gps'),
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFE8F5E9),
                BrandColors.forestLight.withValues(alpha: 0.2),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 20,
                top: 20,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.map_outlined,
                          size: 16, color: BrandColors.forest),
                      SizedBox(width: 6),
                      Text('Mapa das equipes',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                bottom: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$equipes equipes • $veiculos veículos em campo',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: () => context.go('/gps'),
                      icon: const Icon(Icons.map, size: 18),
                      label: const Text('Abrir mapa'),
                      style: FilledButton.styleFrom(
                        backgroundColor: BrandColors.forest,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                  right: 20,
                  top: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.open_in_full,
                          size: 18, color: BrandColors.forest),
                      onPressed: () => context.go('/gps'),
                    ),
                  )),
              const Positioned(
                left: 120,
                top: 60,
                child: Icon(Icons.local_shipping,
                    color: BrandColors.forest, size: 36),
              ),
              const Positioned(
                right: 100,
                bottom: 80,
                child: Icon(Icons.local_shipping,
                    color: BrandColors.alert, size: 36),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductivityCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: BrandColors.forest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Produtividade\nem crescimento! 🌱',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          height: 1.2)),
                  const SizedBox(height: 8),
                  Text('Você está fazendo um ótimo trabalho.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 13)),
                ],
              ),
            ),
            Container(
              width: 80,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: CustomPaint(
                painter: _SparklinePainter(),
                size: const Size(80, 60),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _ref(Map m, String alias, String field) {
  final v = m[alias];
  if (v is Map && v[field] != null) return v[field].toString();
  return m[field] ?? '';
}
