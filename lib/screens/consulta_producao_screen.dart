import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/db_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'consulta_producao_funcionario_screen.dart';

/// Tela de consulta de produção por funcionário/equipe em um período.
class ConsultaProducaoScreen extends StatefulWidget {
  const ConsultaProducaoScreen({super.key});

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
    _tabController = TabController(length: 2, vsync: this);
    final hoje = DateTime.now();
    _dataInicio = DateTime(hoje.year, hoje.month, 1);
    _dataFim = DateTime(hoje.year, hoje.month, hoje.day);
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
      final producoesFuture = Db.list('producao',
          select:
              '*, equipe:equipes!equipe_id(nome), talhao:talhoes!talhao_id(codigo), funcionario:funcionarios!funcionario_id(nome)');
      final pfFuture = Db.list('producao_funcionarios',
          select:
              '*, funcionario:funcionarios!funcionario_id(nome, forma_remuneracao, situacao), producao:producao!producao_id(data, volume_total, total_arvores, talhao:talhao_id(codigo), equipe:equipe_id(nome))');

      final results = await Future.wait([
        funcionariosFuture,
        equipesFuture,
        producoesFuture,
        pfFuture,
      ]);

      final todasProducoes = (results[2] as List).cast<Map<String, dynamic>>();
      final todosPf = (results[3] as List).cast<Map<String, dynamic>>();

      final producoesNoPeriodo = todasProducoes.where((p) {
        final data = _parseDate(p['data']);
        return data != null &&
            !data.isBefore(_dataInicio!) &&
            !data.isAfter(_dataFim!);
      }).toList();

      final producaoIds = producoesNoPeriodo.map((p) => '${p['id']}').toSet();
      final pfNoPeriodo = todosPf
          .where((pf) => producaoIds.contains('${pf['producao_id']}'))
          .toList();

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
    if (value is DateTime) return value;
    try {
      return DateTime.parse(value.toString());
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
    if (_incluirInativos) return _funcionarios;
    return _funcionarios.where((f) => _s(f, 'situacao') != 'Inativo').toList();
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

    return {
      'quantidade': pfs.length,
      'volume': volume,
      'arvores': arvores,
      'horas': horas,
      'valor': valor,
      'forma': forma,
    };
  }

  Map<String, dynamic> _totaisEquipe(String equipeId) {
    final producoes = _producoes
        .where((p) => '${p['equipe_id']}' == equipeId)
        .toList();
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
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildFiltros(),
          TabBar(
            controller: _tabController,
            labelColor: BrandColors.forest,
            unselectedLabelColor: Colors.grey,
            indicatorColor: BrandColors.forest,
            tabs: const [
              Tab(icon: Icon(Icons.person_outline), text: 'Por funcionário'),
              Tab(icon: Icon(Icons.groups_outlined), text: 'Por equipe'),
            ],
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPorFuncionario(),
                      _buildPorEquipe(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros() {
    final fmt = DateFormat('dd/MM/yyyy');
    return Card(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Período',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selecionarDataInicio,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_dataInicio == null
                        ? 'Início'
                        : fmt.format(_dataInicio!)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selecionarDataFim,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_dataFim == null
                        ? 'Fim'
                        : fmt.format(_dataFim!)),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _carregar,
                  child: const Icon(Icons.search),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _incluirInativos,
                  onChanged: (v) => setState(() => _incluirInativos = v ?? false),
                ),
                const Text('Incluir inativos'),
              ],
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
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15)),
                            Text(
                              '${totais['quantidade']} produção(ões)',
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
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          Text(
                            '${totais['quantidade']} produção(ões)',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
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
        );
      },
    );
  }

  Widget _buildStatsRow(Map<String, dynamic> totais, String forma) {
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
            Expanded(
              child: _miniStat(
                  'A receber',
                  _currency.format(totais['valor']),
                  highlight: true),
            ),
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
            Expanded(
              child: _miniStat(
                  'A receber',
                  _currency.format(totais['valor']),
                  highlight: true),
            ),
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
            Expanded(
              child: _miniStat(
                  'A receber',
                  _currency.format(totais['valor']),
                  highlight: true),
            ),
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
            Expanded(
              child: _miniStat(
                  'A receber',
                  _currency.format(totais['valor']),
                  highlight: true),
            ),
          ],
        );
    }
  }

  Widget _miniStat(String label, String value, {bool highlight = false}) {
    return Container(
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
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color:
                      highlight ? BrandColors.forest : BrandColors.forestDark)),
          Text(label,
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
