import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/entities.dart';
import '../services/db_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'entity_detail_screen.dart';

/// Tela de detalhamento das produções de uma equipe em um período.
class ConsultaProducaoEquipeScreen extends StatelessWidget {
  final Map<String, dynamic> equipe;
  final DateTime dataInicio;
  final DateTime dataFim;
  final List<Map<String, dynamic>> producoesEquipe;
  final List<Map<String, dynamic>> producaoFuncionarios;

  const ConsultaProducaoEquipeScreen({
    super.key,
    required this.equipe,
    required this.dataInicio,
    required this.dataFim,
    required this.producoesEquipe,
    required this.producaoFuncionarios,
  });

  static final _dateFmt = DateFormat('dd/MM/yyyy');
  static final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  Widget build(BuildContext context) {
    double volume = 0;
    double arvores = 0;
    double valor = 0;
    for (final p in producoesEquipe) {
      volume += _d(p, 'volume_total');
      arvores += _d(p, 'total_arvores');
      final pfs = producaoFuncionarios.where(
          (pf) => '${pf['producao_id']}' == '${p['id']}');
      valor += pfs.fold<double>(0, (s, pf) => s + _d(pf, 'valor_total'));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_s(equipe, 'nome')),
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
                    ResponsiveStatGrid(
                      minItemWidth: 120,
                      children: [
                        _miniStat('Produções', '${producoesEquipe.length}'),
                        _miniStat(
                            'Volume', '${volume.toStringAsFixed(1)} m³'),
                        _miniStat('Árvores', '${arvores.toStringAsFixed(0)}'),
                        _miniStat('Total pago', _currency.format(valor),
                            highlight: true),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (producoesEquipe.isEmpty)
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
                  childCount: producoesEquipe.length,
                  (context, index) {
                      final p = producoesEquipe[index];
                      final data = _parseDate(p['data']);
                      final talhao = _ref(p, 'talhao', 'codigo');
                      final volumeP = _d(p, 'volume_total');
                      final arvoresP = _d(p, 'total_arvores');
                      final pfs = producaoFuncionarios.where(
                          (pf) => '${pf['producao_id']}' == '${p['id']}');
                      final valorP = pfs.fold<double>(
                          0, (s, pf) => s + _d(pf, 'valor_total'));
                      final participantes = pfs
                          .map((pf) {
                            final f = pf['funcionario'];
                            if (f is Map && f['nome'] != null) {
                              return f['nome'].toString();
                            }
                            return null;
                          })
                          .whereType<String>()
                          .toList();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _abrirDetalheProducao(context, p),
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
                                  Text(
                                    _currency.format(valorP),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: BrandColors.forest,
                                        fontSize: 16),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (talhao.isNotEmpty)
                                _linhaInfo(Icons.forest_outlined,
                                    'Talhão: $talhao'),
                              if (participantes.isNotEmpty)
                                _linhaInfo(Icons.groups_outlined,
                                    'Participantes: ${participantes.join(', ')}'),
                              _buildStatusParticipantes(pfs),
                              const Divider(height: 24),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Volume: ${volumeP.toStringAsFixed(1)} m³',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Text(
                                    'Árvores: ${arvoresP.toStringAsFixed(0)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
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
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusParticipantes(Iterable<Map<String, dynamic>> pfs) {
    final pagos = pfs.where((pf) => pf['pago'] == true).length;
    if (pagos == 0) return const SizedBox.shrink();
    if (pagos == pfs.length) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: const [
            Icon(Icons.check_circle, color: BrandColors.success, size: 16),
            SizedBox(width: 6),
            Text('Todos os participantes pagos',
                style: TextStyle(color: BrandColors.success, fontSize: 12)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: BrandColors.alert, size: 16),
          const SizedBox(width: 6),
          Text('$pagos de ${pfs.length} participante(s) pago(s)',
              style: const TextStyle(color: BrandColors.alert, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _abrirDetalheProducao(
      BuildContext context, Map<String, dynamic> producao) async {
    try {
      final id = '${producao['id']}';
      final def = kEntities['producao']!;
      final completo = await Db.instance.client
          .from(def.table)
          .select(def.selectQuery)
          .eq('id', id)
          .single();
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EntityDetailScreen(
              def: def,
              item: completo as Map<String, dynamic>,
              onEdit: () {},
              onDelete: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao abrir detalhe: $e')),
        );
      }
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
