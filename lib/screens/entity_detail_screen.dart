import 'package:flutter/material.dart';
import '../data/entities.dart';
import '../services/db_service.dart';
import '../theme/app_theme.dart';

/// Tela de detalhes de um registro. Para Funcionário, exibe produção,
/// equipes e equipamentos vinculados.
class EntityDetailScreen extends StatelessWidget {
  final EntityDef def;
  final Map<String, dynamic> item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const EntityDetailScreen({
    super.key,
    required this.def,
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final leading = def.leadingOf?.call(item) ??
        CircleAvatar(
          radius: 32,
          backgroundColor: BrandColors.forest.withValues(alpha: 0.15),
          child: Icon(def.icon, color: BrandColors.forest, size: 32),
        );
    final trailing = def.trailingOf?.call(item);

    return Scaffold(
      appBar: AppBar(
        title: Text(def.noun.toUpperCase()),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar',
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Excluir',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Excluir registro'),
                  content: Text('Deseja excluir "${def.titleOf(item)}"?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: BrandColors.danger),
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Excluir'),
                    ),
                  ],
                ),
              );
              if (ok == true) onDelete();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    leading,
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(def.titleOf(item),
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(def.subtitleOf(item),
                              style: TextStyle(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.7))),
                        ],
                      ),
                    ),
                    if (trailing != null) trailing,
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('INFORMAÇÕES',
                style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: BrandColors.forest)),
            const SizedBox(height: 12),
            ...def.fields.where((f) {
              if (def.table != 'producao') return true;
              final tipo = item['tipo_producao']?.toString();
              if (f.key == 'funcionario_id') return tipo == 'Individual';
              if (f.key == 'equipe_id') return tipo == 'Equipe';
              return true;
            }).map((f) {
              final value = _fieldValue(f);
              return _DetailRow(label: f.label, value: value);
            }),
            const SizedBox(height: 24),
            if (def.table == 'funcionarios')
              _FuncionarioDetails(funcionarioId: '${item['id']}'),
            if (def.table == 'producao')
              _ProducaoDetails(item: item),
            if (def.table == 'equipes')
              _EquipeDetails(equipeId: '${item['id']}'),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onEdit,
        icon: const Icon(Icons.edit),
        label: const Text('Editar'),
      ),
    );
  }

  String _fieldValue(FieldDef f) {
    if (f.type == FieldType.reference) {
      final alias = f.key.endsWith('_id') ? f.key.substring(0, f.key.length - 3) : f.key;
      final map = item[alias];
      if (map is Map) return f.refLabelOf?.call(map.cast<String, dynamic>()) ?? _s(map['nome']);
      return '-';
    }
    if (f.type == FieldType.multiReference) {
      final alias = f.joinAlias ?? f.key;
      final list = item[alias];
      if (list is List && list.isNotEmpty) {
        return list
            .map((e) => (e is Map && e[f.joinChildKey ?? 'id'] != null)
                ? (e['funcionarios']?['nome'] ?? e['nome'] ?? '').toString()
                : '')
            .where((e) => e.isNotEmpty)
            .join(', ');
      }
      return '-';
    }
    final v = item[f.key];
    if (v == null) return '-';
    if (f.suffix != null) return '$v ${f.suffix}';
    return v.toString();
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6))),
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
            select: '*, producao:producao!producao_id(*, talhao:talhoes!talhao_id(codigo), equipe:equipes!equipe_id(nome))')
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
                        child: _MiniStat('Registros',
                            '${producao.length}', Icons.list_alt, BrandColors.info)),
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
                return _DetailRow(
                  label: '${_ref(prod, 'talhao', 'codigo')}',
                  value: '${_s(prod['data'])} • ${_d(prod, 'volume_total').toStringAsFixed(1)} m³ • R\$ ${_d(p, 'valor_total').toStringAsFixed(2)}',
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
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

double _calcularValorProducao(Map<String, dynamic> p) {
  // Usa o valor já calculado em producao_funcionarios quando disponível
  final pfs = p['producao_funcionarios'];
  if (pfs is List) {
    return pfs.fold<double>(
        0, (s, m) => s + (double.tryParse('${m['valor_total']}') ?? 0));
  }
  return 0;
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
          select: '*, funcionario:funcionarios!funcionario_id(nome, forma_remuneracao, valor_diaria, valor_hora, valor_m3, valor_arvore, valor_producao_fixa)')
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
                      Text('R\$ ${valorInd.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: BrandColors.forest)),
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
        final volumeTotal = producao.fold<double>(0, (s, m) => s + _d(m, 'volume_total'));
        final valorTotal = producao.fold<double>(0, (s, m) => s + _calcularValorProducao(m));

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
                        child: _MiniStat('Registros',
                            '${producao.length}', Icons.list_alt, BrandColors.info)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _MiniStat('Volume',
                            '${volumeTotal.toStringAsFixed(1)} m³', Icons.grass, BrandColors.forest)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _MiniStat('Valor total',
                            'R\$ ${valorTotal.toStringAsFixed(2)}', Icons.payments, BrandColors.success)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (producao.isNotEmpty) ...[
              Text('Produções recentes (${producao.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...producao.take(5).map((p) => _DetailRow(
                  label: '${_ref(p, 'funcionario', 'nome')}',
                  value: '${_s(p['data'])} • ${_d(p, 'volume_total').toStringAsFixed(1)} m³ • R\$ ${_calcularValorProducao(p).toStringAsFixed(2)}')),
            ],
          ],
        );
      },
    );
  }
}

String _s(dynamic v) => v?.toString() ?? '';
double _d(Map m, String k) => double.tryParse('${m[k]}') ?? 0;
int _i(Map m, String k) => int.tryParse('${m[k]}'.split('.').first) ?? 0;
String _ref(Map m, String alias, String field) {
  final v = m[alias];
  if (v is Map && v[field] != null) return v[field].toString();
  return '';
}
