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

  const ConsultaProducaoEquipeScreen({
    super.key,
    required this.equipe,
    required this.dataInicio,
    required this.dataFim,
    required this.producoesEquipe,
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
      final pfs = p['producao_funcionarios'];
      if (pfs is List) {
        for (final pf in pfs) {
          if (pf is Map) {
            valor += _d(pf, 'valor_total');
          }
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_s(equipe, 'nome')),
        backgroundColor: BrandColors.forest,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: producoesEquipe.isEmpty
            ? 2
            : producoesEquipe.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Card(
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
                        _miniStat('Volume', '${volume.toStringAsFixed(1)} m³'),
                        _miniStat('Árvores', '${arvores.toStringAsFixed(0)}'),
                        _miniStat('Total pago', _currency.format(valor),
                            highlight: true),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }

          if (producoesEquipe.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Nenhuma produção no período selecionado.'),
              ),
            );
          }

          final p = producoesEquipe[index - 1];
          final data = _parseDate(p['data']);
          final talhao = _ref(p, 'talhao', 'codigo');
          final volumeP = _d(p, 'volume_total');
          final arvoresP = _d(p, 'total_arvores');
          final pfs = p['producao_funcionarios'];
          final participantes = pfs is List
              ? pfs.where((pf) => pf is Map).cast<Map<String, dynamic>>().toList()
              : <Map<String, dynamic>>[];
          final valorP = participantes
              .fold<double>(0, (sum, pf) => sum + _d(pf, 'valor_total'));
          final pagos = participantes.where((pf) => pf['pago'] == true).length;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  final producaoId = p['id']?.toString();
                  if (producaoId == null ||
                      producaoId.isEmpty ||
                      producaoId == 'null') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('ID da produção não encontrado.')),
                    );
                    return;
                  }
                  _abrirDetalheProducao(context, producaoId);
                },
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
                                  fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                          ),
                          _buildStatusParticipantes(participantes),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (talhao.isNotEmpty)
                        _linhaInfo(Icons.forest_outlined, 'Talhão: $talhao'),
                      _linhaInfo(Icons.groups_outlined,
                          '${participantes.length} participante(s)'),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Valor total: ${_currency.format(valorP)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: BrandColors.forest,
                                  fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
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
                      if (pagos > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '$pagos de ${participantes.length} pago(s)',
                            style: const TextStyle(
                                fontSize: 12, color: BrandColors.success),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusParticipantes(Iterable<Map<String, dynamic>> pfs) {
    final pagos = pfs.where((pf) => pf['pago'] == true).length;
    if (pagos == 0) return const SizedBox.shrink();
    if (pagos == pfs.length) {
      return const StatusChip('Pago', BrandColors.success);
    }
    return const StatusChip('Parcial', BrandColors.alert);
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

  Future<void> _abrirDetalheProducao(
      BuildContext context, String producaoId) async {
    try {
      final def = kEntities['producao']!;
      final completo = await Db.instance.client
          .from(def.table)
          .select(def.selectQuery)
          .eq('id', producaoId)
          .single();
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EntityDetailScreen(
              def: def,
              item: completo as Map<String, dynamic>,
              useAsSheet: false,
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
