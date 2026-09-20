import 'package:flutter/material.dart';
import '../data/entities.dart';
import '../services/db_service.dart';
import '../services/cliente_preco_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'consulta_producao_screen.dart';

String _s(dynamic v) => v?.toString() ?? '';
double _d(Map m, String k) => double.tryParse('${m[k]}') ?? 0;
int _i(Map m, String k) => int.tryParse('${m[k]}'.split('.').first) ?? 0;
String _ref(Map m, String alias, String field) {
  final v = m[alias];
  if (v is Map && v[field] != null) return v[field].toString();
  return '';
}

/// Tela de detalhes de um registro. Para Funcionário, exibe produção,
/// equipes e equipamentos vinculados.
class EntityDetailScreen extends StatelessWidget {
  final EntityDef def;
  final Map<String, dynamic> item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool useAsSheet;

  const EntityDetailScreen({
    super.key,
    required this.def,
    required this.item,
    required this.onEdit,
    required this.onDelete,
    this.useAsSheet = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    if (useAsSheet) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          child: content,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(def.titleOf(item)),
        backgroundColor: BrandColors.forest,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: content,
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final custom = _buildCustomDetail();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                def.titleOf(item),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: BrandColors.forest,
                    ),
              ),
            ),
            if (def.table != 'producao_funcionarios') ...[
              IconButton(
                icon: const Icon(Icons.edit, color: BrandColors.forest),
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: BrandColors.alert),
                onPressed: onDelete,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (def.subtitleOf(item).isNotEmpty)
          Text(def.subtitleOf(item),
              style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        ..._buildDefaultFields(),
        if (custom != null) ...[
          const SizedBox(height: 24),
          if (def.table == 'producao') _buildProducaoStatusHeader(context, item),
          if (def.table == 'producao') const SizedBox(height: 12),
          custom,
        ],
      ],
    );
  }

  List<Widget> _buildDefaultFields() {
    return def.fields
        .map((f) {
          dynamic raw;
          if (f.refTable != null && f.refLabelOf != null) {
            raw = f.refLabelOf!(_mapRef(item, f.refTable!));
          } else {
            raw = item[f.key];
          }
          final label = f.label;
          final value = _formatValue(raw, f);
          return _DetailRow(label: label, value: value);
        })
        .cast<Widget>()
        .toList();
  }

  Map<String, dynamic> _mapRef(Map<String, dynamic> item, String alias) {
    final v = item[alias];
    if (v is Map) return v.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  String _formatValue(dynamic raw, FieldDef f) {
    if (raw == null) return '-';
    if (f.type == FieldType.date) {
      final dt = DateTime.tryParse(raw.toString());
      if (dt != null) return _s(dt.toLocal().toIso8601String().split('T').first);
      return raw.toString();
    }
    if (f.type == FieldType.decimal || f.type == FieldType.number) {
      return raw.toString();
    }
    return raw.toString();
  }

  Widget? _buildCustomDetail() {
    switch (def.table) {
      case 'funcionarios':
        return _FuncionarioDetails(funcionarioId: '${item['id']}');
      case 'equipes':
        return _EquipeDetails(equipeId: '${item['id']}');
      case 'producao':
        return _ProducaoDetails(item: item);
      case 'clientes':
        return _ClientePrecoHistorico(clienteId: '${item['id']}');
      default:
        return null;
    }
  }

  Widget _buildProducaoStatusHeader(BuildContext context, Map<String, dynamic> producao) {
    final pfs = producao['producao_funcionarios'];
    if (pfs is! List) return const SizedBox.shrink();
    final pagosList = pfs
        .where((pf) => pf is Map && pf['pago'] == true)
        .cast<Map<String, dynamic>>()
        .toList();
    final pagos = pagosList.length;
    if (pagos == 0) return const SizedBox.shrink();

    final todosPagos = pagos == pfs.length;
    final texto = todosPagos
        ? 'Pagamento fechado para todos os participantes'
        : 'Pagamento fechado para $pagos de ${pfs.length} participante(s)';

    final funcionarioIds = pagosList
        .map((pf) => pf['funcionario_id']?.toString())
        .whereType<String>()
        .toList();
    final primeiroPago = pagosList.first;
    final fechamentoId = primeiroPago['fechamento_id']?.toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BrandColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BrandColors.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock, color: BrandColors.success, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  texto,
                  style: const TextStyle(
                    color: BrandColors.success,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (fechamentoId != null && funcionarioIds.isNotEmpty)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: BrandColors.forestDark,
                    ),
                    onPressed: () => _abrirFechamentoNaConsulta(
                      context,
                      fechamentoId: fechamentoId,
                      funcionarioIds: funcionarioIds,
                    ),
                    child: const Text(
                      'Ver fechamento',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
          const StatusChip('Pago', BrandColors.success),
        ],
      ),
    );
  }

  Future<void> _abrirFechamentoNaConsulta(
    BuildContext context, {
    required String fechamentoId,
    required List<String> funcionarioIds,
  }) async {
    try {
      final res = await Db.instance.client
          .from('pagamento_fechamentos')
          .select()
          .eq('id', fechamentoId)
          .single();
      final inicio = _parseDate(res['periodo_inicio']);
      final fim = _parseDate(res['periodo_fim']);
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ConsultaProducaoScreen(
              dataInicio: inicio,
              dataFim: fim,
              funcionarioIds: funcionarioIds,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar fechamento: $e')),
        );
      }
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) {
      final local = value.toLocal();
      return DateTime(local.year, local.month, local.day);
    }
    try {
      final dt = DateTime.parse(value.toString());
      final local = dt.toLocal();
      return DateTime(local.year, local.month, local.day);
    } catch (_) {
      return null;
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: const TextStyle(
                    color: Colors.grey, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 3,
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _FuncionarioDetails extends StatelessWidget {
  final String funcionarioId;
  const _FuncionarioDetails({required this.funcionarioId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        Db.list('producao_funcionarios',
            select: '*, pago, data_pagamento, fechamento_id, producao:producao!producao_id(*, talhao:talhoes!talhao_id(codigo), equipe:equipes!equipe_id(nome))')
            .then((l) => l.where((m) => '${m['funcionario_id']}' == funcionarioId).toList()),
        Db.list('equipes',
            select: '*, lider:funcionarios!lider_id(nome), veiculo:veiculos!veiculo_id(nome), membros:equipe_membros(funcionario_id, funcionarios!funcionario_id(nome))')
            .then((l) => l.where((m) =>
                '${m['lider_id']}' == funcionarioId ||
                _membrosIds(m).contains(funcionarioId)).toList()),
        Db.list('equipamentos', select: '*, responsavel:funcionarios!responsavel_id(nome)')
            .then((l) => l.where((m) => '${m['responsavel_id']}' == funcionarioId).toList()),
      ]),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(),
          ));
        }
        final producao = ((snap.data?[0] as List?) ?? []).cast<Map<String, dynamic>>();
        final equipes = ((snap.data?[1] as List?) ?? []).cast<Map<String, dynamic>>();
        final equipamentos = ((snap.data?[2] as List?) ?? []).cast<Map<String, dynamic>>();

        final totalReceber = producao.fold<double>(0, (s, m) => s + _d(m, 'valor_total'));
        final totalPago = producao.where((m) => m['pago'] == true).fold<double>(
            0, (s, m) => s + _d(m, 'valor_total'));
        final totalPendente = totalReceber - totalPago;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DADOS DO FUNCIONÁRIO',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: BrandColors.forest)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Expanded(
                        child: _MiniStat('A receber',
                            'R\$ ${totalReceber.toStringAsFixed(2)}', Icons.payments, BrandColors.success)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _MiniStat('Pago',
                            'R\$ ${totalPago.toStringAsFixed(2)}', Icons.check_circle, BrandColors.success)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _MiniStat('Pendente',
                            'R\$ ${totalPendente.toStringAsFixed(2)}', Icons.pending, BrandColors.info)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (equipes.isNotEmpty) ...[
              Text('Equipes (${equipes.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...equipes.map((e) => _DetailRow(
                  label: _s(e['nome']),
                  value: [
                    if (_ref(e, 'lider', 'nome').isNotEmpty)
                      'Líder: ${_ref(e, 'lider', 'nome')}',
                    if (_ref(e, 'veiculo', 'nome').isNotEmpty)
                      _ref(e, 'veiculo', 'nome'),
                  ].join(' • '))),
              const SizedBox(height: 16),
            ],
            if (equipamentos.isNotEmpty) ...[
              Text('Equipamentos (${equipamentos.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...equipamentos.map((e) => _DetailRow(
                  label: _s(e['nome']),
                  value: '${_s(e['tipo'])} • ${_s(e['situacao'])}')),
              const SizedBox(height: 16),
            ],
            if (producao.isNotEmpty) ...[
              Text('Produção recente (${producao.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...producao.take(5).map((p) {
                final prod = p['producao'] as Map? ?? {};
                final pago = p['pago'] == true;
                return _DetailRow(
                  label: '${_ref(prod, 'talhao', 'codigo')}',
                  value: '${_s(prod['data'])} • ${_d(prod, 'volume_total').toStringAsFixed(1)} m³ • R\$ ${_d(p, 'valor_total').toStringAsFixed(2)}${pago ? ' • Pago' : ''}',
                );
              }),
            ],
          ],
        );
      },
    );
  }

  List<String> _membrosIds(Map m) {
    final v = m['membros'];
    if (v is List) {
      return v
          .map((e) => e is Map ? '${e['funcionario_id']}' : '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return [];
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniStat(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16)),
      ],
    );
  }
}

class _ProducaoDetails extends StatefulWidget {
  final Map<String, dynamic> item;
  const _ProducaoDetails({required this.item});

  @override
  State<_ProducaoDetails> createState() => _ProducaoDetailsState();
}

class _ProducaoDetailsState extends State<_ProducaoDetails> {
  List<Map<String, dynamic>> _integrantes = [];

  @override
  void initState() {
    super.initState();
    _carregarIntegrantes();
  }

  Future<void> _carregarIntegrantes() async {
    final id = widget.item['id']?.toString();
    if (id == null || id.isEmpty) return;
    try {
      final rows = await Db.list('producao_funcionarios',
          select: '*, pago, data_pagamento, fechamento_id, funcionario:funcionarios!funcionario_id(nome, forma_remuneracao, valor_diaria, valor_hora, valor_m3, valor_arvore, valor_producao_fixa)')
          .then((l) => l.where((m) => '${m['producao_id']}' == id).cast<Map<String, dynamic>>().toList());
      if (mounted) setState(() => _integrantes = rows);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final valor = _calcularValorProducao(item);
    final equipeNome = _ref(item, 'equipe', 'nome');
    final funcNome = _ref(item, 'funcionario', 'nome');
    final talhaoCod = _ref(item, 'talhao', 'codigo');
    final isEquipe = item['equipe_id'] != null;
    final volumeTotal = _d(item, 'volume_total');
    final arvoresTotal = _i(item, 'total_arvores');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RESUMO DA PRODUÇÃO',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: BrandColors.forest)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                    child: _MiniStat('Volume',
                        '${volumeTotal.toStringAsFixed(1)} m³', Icons.grass, BrandColors.forest)),
                const SizedBox(width: 12),
                Expanded(
                    child: _MiniStat('Árvores',
                        '$arvoresTotal', Icons.park, BrandColors.success)),
                const SizedBox(width: 12),
                Expanded(
                    child: _MiniStat('Valor total',
                        'R\$ ${valor.toStringAsFixed(2)}', Icons.payments, BrandColors.info)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (item['tipo_producao']?.toString() == 'Equipe' && equipeNome.isNotEmpty)
          _DetailRow(label: 'Equipe', value: equipeNome),
        if (item['tipo_producao']?.toString() == 'Individual' && funcNome.isNotEmpty)
          _DetailRow(label: 'Funcionário', value: funcNome),
        if (talhaoCod.isNotEmpty)
          _DetailRow(label: 'Talhão', value: talhaoCod),
        _DetailRow(label: 'Data', value: _s(item['data'])),
        _DetailRow(label: 'Tipo de produção', value: _s(item['tipo_producao'])),
        if (_s(item['observacoes']).isNotEmpty)
          _DetailRow(label: 'Observações', value: _s(item['observacoes'])),
        const SizedBox(height: 24),
        if (isEquipe) ...[
          Text('PARTICIPANTES E REMUNERAÇÃO',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: BrandColors.forest)),
          const SizedBox(height: 12),
          if (_integrantes.isEmpty)
            const Text('Nenhum participante registrado nesta produção.')
          else
            ..._integrantes.map((m) {
              final func = m['funcionario'] is Map
                  ? m['funcionario'] as Map
                  : const <String, dynamic>{};
              final nome = _s(func['nome']);
              final forma = _s(m['forma_remuneracao']);
              final valorInd = _d(m, 'valor_total');
              final qtd = _d(m, 'quantidade_calculo');
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nome,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('$forma • ${qtd.toStringAsFixed(0)} un',
                                style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('R\$ ${valorInd.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: BrandColors.forest)),
                          if (m['pago'] == true)
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Text('Pago',
                                  style: TextStyle(
                                      color: BrandColors.success,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ],
    );
  }
}

double _calcularValorProducao(Map<String, dynamic> p) {
  final pfs = p['producao_funcionarios'];
  if (pfs is List) {
    return pfs.fold<double>(0, (s, pf) => s + _d(pf as Map, 'valor_total'));
  }
  return 0;
}

class _EquipeDetails extends StatelessWidget {
  final String equipeId;
  const _EquipeDetails({required this.equipeId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        Db.list('producao',
            select:
                '*, funcionario:funcionarios!funcionario_id(nome), talhao:talhoes!talhao_id(codigo), producao_funcionarios(*)')
            .then((l) => l.where((m) => '${m['equipe_id']}' == equipeId).toList()),
      ]),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(),
          ));
        }
        final producao = ((snap.data?[0] as List?) ?? []).cast<Map<String, dynamic>>();
        final totalVolume = producao.fold<double>(0, (s, p) => s + _d(p, 'volume_total'));
        final totalArvores = producao.fold<int>(0, (s, p) => s + _i(p, 'total_arvores'));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PRODUÇÃO DA EQUIPE',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: BrandColors.forest)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Expanded(
                        child: _MiniStat('Volume',
                            '${totalVolume.toStringAsFixed(1)} m³', Icons.grass, BrandColors.forest)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _MiniStat('Árvores',
                            '$totalArvores', Icons.park, BrandColors.success)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _MiniStat('Registros',
                            '${producao.length}', Icons.list_alt, BrandColors.info)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (producao.isEmpty)
              const Text('Nenhuma produção registrada para esta equipe.')
            else
              ...producao.take(5).map((p) => _DetailRow(
                  label: _s(p['data']),
                  value: '${_d(p, 'volume_total').toStringAsFixed(1)} m³ • R\$ ${_calcularValorProducao(p).toStringAsFixed(2)}')),
          ],
        );
      },
    );
  }
}

class _ClientePrecoHistorico extends StatefulWidget {
  final String clienteId;
  const _ClientePrecoHistorico({required this.clienteId});

  @override
  State<_ClientePrecoHistorico> createState() => _ClientePrecoHistoricoState();
}

class _ClientePrecoHistoricoState extends State<_ClientePrecoHistorico> {
  List<Map<String, dynamic>> _historico = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final lista = await ClientePrecoService.listarHistorico(widget.clienteId);
      if (mounted) setState(() { _historico = lista; _carregando = false; });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: CircularProgressIndicator(),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('HISTÓRICO DE PREÇOS',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: BrandColors.forest)),
        const SizedBox(height: 12),
        if (_historico.isEmpty)
          const Text('Nenhum preço cadastrado para este cliente.')
        else
          ..._historico.map((p) {
            final vigenteDesde = p['vigente_desde']?.toString() ?? '';
            final vigenteAte = p['vigente_ate']?.toString();
            final atual = vigenteAte == null;
            final valor = _d(p, 'valor_m3');
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: atual ? BrandColors.forest.withValues(alpha: 0.08) : null,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('R\$ ${valor.toStringAsFixed(2)}/m³',
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(
                            'Vigente de: $vigenteDesde'
                            '${vigenteAte != null ? ' até: $vigenteAte' : ' (atualmente vigente)'}',
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (atual)
                      const Icon(Icons.check_circle, color: BrandColors.success, size: 20),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
