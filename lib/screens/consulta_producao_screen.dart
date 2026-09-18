import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/db_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'consulta_producao_equipe_screen.dart';
import 'consulta_producao_funcionario_screen.dart';

/// Tela de consulta de produção por funcionário/equipe em um período.
class ConsultaProducaoScreen extends StatefulWidget {
  final DateTime? dataInicio;
  final DateTime? dataFim;
  final String? funcionarioId;
  final List<String>? funcionarioIds;
  final int initialTabIndex;

  const ConsultaProducaoScreen({
    super.key,
    this.dataInicio,
    this.dataFim,
    this.funcionarioId,
    this.funcionarioIds,
    this.initialTabIndex = 0,
  });

  @override
  State<ConsultaProducaoScreen> createState() => _ConsultaProducaoScreenState();
}

class _ConsultaProducaoScreenState extends State<ConsultaProducaoScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime? _dataInicio;
  DateTime? _dataFim;
  bool _incluirInativos = false;
  bool _carregando = false;

  List<Map<String, dynamic>> _funcionarios = [];
  List<Map<String, dynamic>> _equipes = [];
  List<Map<String, dynamic>> _producoes = [];
  List<Map<String, dynamic>> _producaoFuncionarios = [];

  final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    final hasFiltroFuncionario =
        widget.funcionarioId != null ||
        (widget.funcionarioIds != null && widget.funcionarioIds!.isNotEmpty);
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: hasFiltroFuncionario ? 0 : widget.initialTabIndex,
    );
    if (widget.dataInicio != null && widget.dataFim != null) {
      _dataInicio = widget.dataInicio;
      _dataFim = widget.dataFim;
    } else {
      final hoje = DateTime.now();
      _dataInicio = DateTime(hoje.year, hoje.month, 1);
      _dataFim = DateTime(hoje.year, hoje.month, hoje.day);
    }
    _carregar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (_dataInicio == null || _dataFim == null) return;
    setState(() => _carregando = true);
    try {
      final inicio = DateFormat('yyyy-MM-dd').format(_dataInicio!);
      final fim = DateFormat('yyyy-MM-dd').format(_dataFim!);

      final funcionariosFuture = Db.list('funcionarios', orderBy: 'nome', ascending: true);
      final equipesFuture = Db.list('equipes', orderBy: 'nome', ascending: true);

      final c = Db.instance.client;
      final producoesRes = await c
          .from('producao')
          .select(
              'id, data, talhao_id, equipe_id, funcionario_id, volume_total, total_arvores, equipe:equipes!equipe_id(nome), talhao:talhoes!talhao_id(codigo), funcionario:funcionarios!funcionario_id(nome)')
          .gte('data', inicio)
          .lte('data', fim)
          .order('data', ascending: false);

      final producoesNoPeriodo = (producoesRes as List).cast<Map<String, dynamic>>();
      final producaoIds = producoesNoPeriodo.map((p) => '${p['id']}').toList();

      List<Map<String, dynamic>> pfNoPeriodo = [];
      if (producaoIds.isNotEmpty) {
        final pfRes = await c
            .from('producao_funcionarios')
            .select(
                '*, pago, data_pagamento, fechamento_id, funcionario:funcionarios!funcionario_id(nome, forma_remuneracao, situacao), producao:producao!producao_id(data, volume_total, total_arvores, talhao:talhao_id(codigo), equipe:equipe_id(nome))')
            .inFilter('producao_id', producaoIds)
            .order('created_at', ascending: false);
        pfNoPeriodo = (pfRes as List).cast<Map<String, dynamic>>();
      }

      final results = await Future.wait([
        funcionariosFuture,
        equipesFuture,
      ]);

      if (mounted) {
        setState(() {
          _funcionarios = (results[0] as List).cast<Map<String, dynamic>>();
          _equipes = (results[1] as List).cast<Map<String, dynamic>>();
          _producoes = producoesNoPeriodo;
          _producaoFuncionarios = pfNoPeriodo;
          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _carregando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar dados: $e')),
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

  Future<void> _selecionarDataInicio() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dataInicio ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _dataInicio = picked);
    }
  }

  Future<void> _selecionarDataFim() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dataFim ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _dataFim = picked);
    }
  }

  List<Map<String, dynamic>> get _funcionariosVisiveis {
    var list = _funcionarios;
    if (! _incluirInativos) {
      list = list.where((f) => _s(f, 'situacao') != 'Inativo').toList();
    }
    final ids = _filtroFuncionarioIds;
    if (ids != null && ids.isNotEmpty) {
      list = list.where((f) => ids.contains('${f['id']}')).toList();
    }
    return list;
  }

  List<String>? get _filtroFuncionarioIds {
    if (widget.funcionarioId != null) return [widget.funcionarioId!];
    if (widget.funcionarioIds != null && widget.funcionarioIds!.isNotEmpty) {
      return widget.funcionarioIds;
    }
    return null;
  }

  List<Map<String, dynamic>> _producoesDoFuncionario(String funcionarioId) {
    return _producaoFuncionarios
        .where((pf) => '${pf['funcionario_id']}' == funcionarioId)
        .toList();
  }

  Map<String, dynamic> _totaisFuncionario(Map<String, dynamic> funcionario) {
    final id = '${funcionario['id']}';
    final forma = _s(funcionario, 'forma_remuneracao');
    final pfs = _producoesDoFuncionario(id);
    double volume = 0;
    double arvores = 0;
    double horas = 0;
    double valor = 0;

    for (final pf in pfs) {
      final producao = pf['producao'];
      if (producao is Map) {
        volume += _d(producao, 'volume_total');
        arvores += _d(producao, 'total_arvores');
      }
      if (forma == 'Hora') {
        horas += _d(pf, 'quantidade_calculo');
      }
      valor += _d(pf, 'valor_total');
    }

    final pagos = pfs.where((pf) => pf['pago'] == true).length;
    final status = pagos == 0
        ? 'Pendente'
        : pagos == pfs.length
            ? 'Pago'
            : 'Parcial';

    return {
      'quantidade': pfs.length,
      'volume': volume,
      'arvores': arvores,
      'horas': horas,
      'valor': valor,
      'forma': forma,
      'pagos': pagos,
      'status': status,
      'fechamentoId': _fechamentoIdDoFuncionario(id),
    };
  }

  String? _fechamentoIdDoFuncionario(String funcionarioId) {
    final pfs = _producoesDoFuncionario(funcionarioId).where((pf) => pf['pago'] == true);
    if (pfs.isEmpty) return null;
    return pfs.first['fechamento_id']?.toString();
  }

  Future<void> _fecharPagamento(Map<String, dynamic> funcionario) async {
    if (_dataInicio == null || _dataFim == null) return;
    final id = '${funcionario['id']}';
    final totais = _totaisFuncionario(funcionario);
    if (totais['status'] == 'Pago') return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Marcar como pago'),
        content: Text(
          'Fechamento para ${_s(funcionario, 'nome')} no período '
          '${DateFormat('dd/MM/yyyy').format(_dataInicio!)} a ${DateFormat('dd/MM/yyyy').format(_dataFim!)}.\n\n'
          'Registros: ${totais['quantidade']}\n'
          'Valor total: ${_currency.format(totais['valor'])}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirmar pagamento'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _carregando = true);
    try {
      await Db.rpc<dynamic>(
        'fechar_pagamento_funcionario',
        {
          'p_funcionario_id': id,
          'p_inicio': DateFormat('yyyy-MM-dd').format(_dataInicio!),
          'p_fim': DateFormat('yyyy-MM-dd').format(_dataFim!),
        },
      );
      await _carregar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fechamento realizado com sucesso.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _carregando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao fechar pagamento: $e')),
        );
      }
    }
  }

  Future<void> _reabrirFechamento(String? fechamentoId) async {
    if (fechamentoId == null || fechamentoId.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reabrir fechamento'),
        content: const Text(
          'Isso desfaz o fechamento do período e libera edição dos registros. Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Reabrir'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _carregando = true);
    try {
      await Db.rpc<dynamic>(
        'reabrir_pagamento_funcionario',
        {'p_fechamento_id': fechamentoId},
      );
      await _carregar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fechamento reaberto com sucesso.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _carregando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao reabrir fechamento: $e')),
        );
      }
    }
  }

  Map<String, dynamic> _totaisEquipe(String equipeId) {
    final producoes = _producoes.where((p) {
      return _matchEquipeId(p, equipeId);
    }).toList();
    double volume = 0;
    double arvores = 0;
    double valor = 0;
    for (final p in producoes) {
      volume += _d(p, 'volume_total');
      arvores += _d(p, 'total_arvores');
      final pfs = _producaoFuncionarios
          .where((pf) => '${pf['producao_id']}' == '${p['id']}');
      valor += pfs.fold<double>(0, (s, pf) => s + _d(pf, 'valor_total'));
    }
    return {
      'quantidade': producoes.length,
      'volume': volume,
      'arvores': arvores,
      'valor': valor,
    };
  }

  List<Map<String, dynamic>> _producoesDaEquipe(String equipeId) {
    return _producoes.where((p) => _matchEquipeId(p, equipeId)).toList();
  }

  bool _matchEquipeId(Map<String, dynamic> producao, String equipeId) {
    final rawId = producao['equipe_id'];
    if (rawId != null && '${rawId}' == equipeId) return true;
    final nested = producao['equipe'];
    if (nested is Map && nested['id'] != null && '${nested['id']}' == equipeId) {
      return true;
    }
    return false;
  }

  String _nomeFuncionario(String id) {
    final f = _funcionarios.firstWhere(
      (f) => '${f['id']}' == id,
      orElse: () => {'nome': 'Funcionário'},
    );
    return _s(f, 'nome');
  }

  String _nomeEquipe(String id) {
    final e = _equipes.firstWhere(
      (e) => '${e['id']}' == id,
      orElse: () => {'nome': 'Equipe'},
    );
    return _s(e, 'nome');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(child: _buildFiltros()),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarHeaderDelegate(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              child: TabBar(
                controller: _tabController,
                labelColor: BrandColors.forest,
                unselectedLabelColor: Colors.grey,
                indicatorColor: BrandColors.forest,
                tabs: const [
                  Tab(icon: Icon(Icons.person_outline), text: 'Por funcionário'),
                  Tab(icon: Icon(Icons.groups_outlined), text: 'Por equipe'),
                ],
              ),
            ),
          ),
        ],
        body: _carregando
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildPorFuncionario(),
                  _buildPorEquipe(),
                ],
              ),
      ),
    );
  }

  Widget _buildFiltros() {
    final fmt = DateFormat('dd/MM/yyyy');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final botaoBuscar = SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: _carregar,
        style: FilledButton.styleFrom(
          backgroundColor: BrandColors.forest,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.search, size: 20),
        label: const Text('Buscar'),
      ),
    );

    return Card(
      color: isDark ? BrandColors.graySurface : Colors.white,
      elevation: 2,
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Período',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: BrandColors.forestDark)),
            const SizedBox(height: 12),
            ResponsiveRow(
              breakpoint: 520,
              children: [
                _buildDateButton(
                  label: _dataInicio == null
                      ? 'Data inicial'
                      : fmt.format(_dataInicio!),
                  icon: Icons.calendar_today,
                  onTap: _selecionarDataInicio,
                ),
                _buildDateButton(
                  label:
                      _dataFim == null ? 'Data final' : fmt.format(_dataFim!),
                  icon: Icons.calendar_today,
                  onTap: _selecionarDataFim,
                ),
                botaoBuscar,
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _incluirInativos,
                  onChanged: (v) =>
                      setState(() => _incluirInativos = v ?? false),
                  activeColor: BrandColors.forest,
                ),
                const Flexible(
                  child: Text('Incluir inativos',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: BrandColors.forestDark)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: BrandColors.forest.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: BrandColors.forest),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: BrandColors.forestDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPorFuncionario() {
    if (_funcionariosVisiveis.isEmpty) {
      return const Center(child: Text('Nenhum funcionário encontrado.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: _funcionariosVisiveis.length,
      itemBuilder: (context, index) {
        final f = _funcionariosVisiveis[index];
        final id = '${f['id']}';
        final totais = _totaisFuncionario(f);
        final forma = _s(totais, 'forma');
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ConsultaProducaoFuncionarioScreen(
                  funcionario: f,
                  dataInicio: _dataInicio!,
                  dataFim: _dataFim!,
                  producoesFuncionario: _producoesDoFuncionario(id),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor:
                            BrandColors.forest.withValues(alpha: 0.15),
                        child: Text(_iniciais(_s(f, 'nome')),
                            style: const TextStyle(
                                color: BrandColors.forest,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_s(f, 'nome'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15)),
                            Text(
                              '${totais['quantidade']} produção(ões)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildStatsRow(totais, forma),
                  const SizedBox(height: 12),
                  _buildAcaoFechamento(f, totais),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPorEquipe() {
    if (_equipes.isEmpty) {
      return const Center(child: Text('Nenhuma equipe encontrada.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: _equipes.length,
      itemBuilder: (context, index) {
        final e = _equipes[index];
        final id = '${e['id']}';
        final totais = _totaisEquipe(id);
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ConsultaProducaoEquipeScreen(
                  equipe: e,
                  dataInicio: _dataInicio!,
                  dataFim: _dataFim!,
                  producoesEquipe: _producoesDaEquipe(id),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor:
                            BrandColors.forest.withValues(alpha: 0.15),
                        child: const Icon(Icons.groups,
                            color: BrandColors.forest),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_s(e, 'nome'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15)),
                            Text(
                              '${totais['quantidade']} produção(ões)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _miniStat('Volume',
                            '${(totais['volume'] as double).toStringAsFixed(1)} m³'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _miniStat('Árvores',
                            '${(totais['arvores'] as double).toStringAsFixed(0)}'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _miniStat('Total pago',
                            _currency.format(totais['valor']),
                            highlight: true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsRow(Map<String, dynamic> totais, String forma) {
    final receber = Expanded(
      child: _miniStat('A receber', _currency.format(totais['valor']),
          highlight: true),
    );
    switch (forma) {
      case 'Diária':
      case 'Produção fixa':
        return Row(
          children: [
            Expanded(
              child: _miniStat('Dias/participações',
                  '${totais['quantidade']}'),
            ),
            const SizedBox(width: 8),
            receber,
          ],
        );
      case 'Hora':
        return Row(
          children: [
            Expanded(
              child: _miniStat(
                  'Horas', '${(totais['horas'] as double).toStringAsFixed(1)} h'),
            ),
            const SizedBox(width: 8),
            receber,
          ],
        );
      case 'Árvore':
        return Row(
          children: [
            Expanded(
              child: _miniStat('Árvores',
                  '${(totais['arvores'] as double).toStringAsFixed(0)}'),
            ),
            const SizedBox(width: 8),
            receber,
          ],
        );
      case 'Metro cúbico':
      default:
        return Row(
          children: [
            Expanded(
              child: _miniStat('Volume',
                  '${(totais['volume'] as double).toStringAsFixed(1)} m³'),
            ),
            const SizedBox(width: 8),
            receber,
          ],
        );
    }
  }

  Widget _buildAcaoFechamento(
      Map<String, dynamic> funcionario, Map<String, dynamic> totais) {
    final status = totais['status']?.toString() ?? 'Pendente';
    final fechamentoId = totais['fechamentoId']?.toString();

    if (status == 'Pago') {
      return OutlinedButton.icon(
        onPressed: () => _reabrirFechamento(fechamentoId),
        icon: const Icon(Icons.lock_open_outlined, size: 18),
        label: const Text('Reabrir fechamento'),
        style: OutlinedButton.styleFrom(
          foregroundColor: BrandColors.success,
          side: const BorderSide(color: BrandColors.success),
        ),
      );
    }

    final temValor = (totais['quantidade'] as int) > 0;
    if (!temValor) return const SizedBox.shrink();

    return FilledButton.icon(
      onPressed: () => _fecharPagamento(funcionario),
      icon: const Icon(Icons.payments_outlined, size: 18),
      label: const Text('Marcar como pago'),
      style: FilledButton.styleFrom(backgroundColor: BrandColors.forest),
    );
  }

  Widget _miniStat(String label, String value, {bool highlight = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? BrandColors.forest.withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color:
                      highlight ? BrandColors.forest : BrandColors.forestDark)),
          Text(label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  static String _s(Map m, String k) => (m[k] ?? '').toString();
  static double _d(Map m, String k) =>
      double.tryParse('${m[k]}') ?? 0;

  static String _iniciais(String nome) {
    final parts = nome.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// Delegate que mantém o TabBar fixo durante a rolagem do conteúdo.
class _TabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabBar child;
  final Color backgroundColor;

  _TabBarHeaderDelegate({required this.child, required this.backgroundColor});

  @override
  double get minExtent => 62;

  @override
  double get maxExtent => 62;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: backgroundColor,
      height: 62,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_TabBarHeaderDelegate oldDelegate) =>
      oldDelegate.child != child ||
      oldDelegate.backgroundColor != backgroundColor;
}
