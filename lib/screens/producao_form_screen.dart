import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/entities.dart';
import '../services/db_service.dart';
import '../services/producao_calculo_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Tela customizada para lançamento de produção individual ou em equipe.
/// Não pergunta o tipo de pagamento. Calcula automaticamente conforme cadastro
/// de cada funcionário.
class ProducaoFormScreen extends StatefulWidget {
  const ProducaoFormScreen({super.key});

  @override
  State<ProducaoFormScreen> createState() => _ProducaoFormScreenState();
}

class _ProducaoFormScreenState extends State<ProducaoFormScreen> {
  final _formKey = GlobalKey<FormState>();

  String _tipoProducao = 'Individual';

  String? _funcionarioId;
  String? _equipeId;
  String? _talhaoId;
  DateTime? _data;
  final _volumeCtrl = TextEditingController(text: '0');
  final _arvoresCtrl = TextEditingController(text: '0');
  final _obsCtrl = TextEditingController();

  List<Map<String, dynamic>> _funcionarios = [];
  List<Map<String, dynamic>> _equipes = [];
  List<Map<String, dynamic>> _talhoes = [];

  List<Map<String, dynamic>> _participantes = [];

  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _data = DateTime.now();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    setState(() => _loading = true);
    try {
      final funcionarios = await Db.list('funcionarios',
          select: 'id,nome,forma_remuneracao,valor_diaria,valor_hora,valor_m3,valor_arvore,valor_producao_fixa,situacao',
          orderBy: 'nome');
      final equipes = await Db.list('equipes',
          select: 'id,nome,integrantes', orderBy: 'nome');
      final talhoes = await Db.list('talhoes',
          select: 'id,codigo', orderBy: 'codigo');

      if (mounted) {
        setState(() {
          _funcionarios = funcionarios
              .where((f) => (f['situacao'] ?? 'Ativo') == 'Ativo')
              .toList();
          _equipes = equipes;
          _talhoes = talhoes;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _carregarParticipantes() async {
    if (_equipeId == null) {
      setState(() => _participantes = []);
      return;
    }

    setState(() => _loading = true);
    try {
      // Busca membros ativos da equipe
      final membros = await Db.instance.client
          .from('equipe_membros')
          .select('funcionario_id, funcionario:funcionarios!inner(*)')
          .eq('equipe_id', _equipeId)
          .eq('funcionario.situacao', 'Ativo');

      final lista = (membros as List).map((m) {
        final f = m['funcionario'] as Map<String, dynamic>? ?? {};
        return {
          'funcionario': f,
          'selecionado': true,
          'horas': 1.0,
        };
      }).where((p) => (p['funcionario'] as Map)['id'] != null).toList();

      if (mounted) {
        setState(() => _participantes = lista);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar integrantes: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _volume => double.tryParse(_volumeCtrl.text.replaceAll(',', '.')) ?? 0;
  int get _arvores => int.tryParse(_arvoresCtrl.text) ?? 0;

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    if (_tipoProducao == 'Individual' && _funcionarioId == null) {
      _showError('Selecione o funcionário.');
      return;
    }
    if (_tipoProducao == 'Equipe' && _equipeId == null) {
      _showError('Selecione a equipe.');
      return;
    }
    if (_tipoProducao == 'Equipe' &&
        !_participantes.any((p) => p['selecionado'] == true)) {
      _showError('Selecione pelo menos um participante.');
      return;
    }
    if (_talhaoId == null) {
      _showError('Selecione o talhão.');
      return;
    }

    setState(() => _saving = true);
    try {
      List<Map<String, dynamic>> participantes;
      if (_tipoProducao == 'Individual') {
        final f = _funcionarios.firstWhere(
          (f) => f['id'].toString() == _funcionarioId,
          orElse: () => {},
        );
        if (f.isEmpty) throw Exception('Funcionário não encontrado');
        participantes = [
          {'funcionario': f, 'selecionado': true, 'horas': 1.0}
        ];
      } else {
        participantes = _participantes;
      }

      await ProducaoCalculoService.salvarProducao(
        tipoProducao: _tipoProducao,
        funcionarioId: _tipoProducao == 'Individual' ? _funcionarioId : null,
        equipeId: _tipoProducao == 'Equipe' ? _equipeId : null,
        talhaoId: _talhaoId,
        data: _data,
        volume: _volume,
        arvores: _arvores,
        observacoes: _obsCtrl.text,
        participantes: participantes,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Produção salva com sucesso.')),
        );
      }
    } catch (e) {
      if (mounted) _showError('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: BrandColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nova Produção'),
        centerTitle: true,
      ),
      body: _loading && _funcionarios.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTipoProducao(),
                    const SizedBox(height: 20),
                    if (_tipoProducao == 'Individual')
                      _buildFuncionarioField()
                    else
                      _buildEquipeField(),
                    const SizedBox(height: 16),
                    _buildTalhaoField(),
                    const SizedBox(height: 16),
                    _buildDataField(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _volumeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Volume total (m³)',
                              suffixText: 'm³',
                            ),
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            validator: (v) => (v?.isEmpty ?? true) ? 'Informe' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _arvoresCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Total de árvores',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) => (v?.isEmpty ?? true) ? 'Informe' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _obsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Observações',
                        alignLabelWithHint: true,
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),
                    _buildResumoCalculo(),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _salvar,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Salvar Produção'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTipoProducao() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tipo de Produção', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Individual', label: Text('Individual')),
            ButtonSegment(value: 'Equipe', label: Text('Equipe')),
          ],
          selected: <String>{_tipoProducao},
          onSelectionChanged: (set) {
            setState(() {
              _tipoProducao = set.first;
              _funcionarioId = null;
              _equipeId = null;
              _participantes = [];
            });
          },
        ),
      ],
    );
  }

  Widget _buildFuncionarioField() {
    return DropdownButtonFormField<String>(
      value: _funcionarioId,
      decoration: const InputDecoration(labelText: 'Funcionário'),
      items: _funcionarios.map((f) {
        final label = '${f['nome']} • ${f['forma_remuneracao']}';
        return DropdownMenuItem(
          value: f['id'].toString(),
          child: Text(label, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: (v) => setState(() => _funcionarioId = v),
      validator: (v) => v == null ? 'Selecione' : null,
    );
  }

  Widget _buildEquipeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _equipeId,
          decoration: const InputDecoration(labelText: 'Equipe'),
          items: _equipes.map((e) {
            return DropdownMenuItem(
              value: e['id'].toString(),
              child: Text(e['nome']?.toString() ?? ''),
            );
          }).toList(),
          onChanged: (v) async {
            setState(() => _equipeId = v);
            await _carregarParticipantes();
          },
          validator: (v) => v == null ? 'Selecione' : null,
        ),
        if (_participantes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Participantes', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ..._participantes.map(_buildParticipanteTile),
        ],
      ],
    );
  }

  Widget _buildParticipanteTile(Map<String, dynamic> p) {
    final f = p['funcionario'] as Map<String, dynamic>;
    final selecionado = p['selecionado'] == true;
    final calculo = selecionado
        ? ProducaoCalculoService.calcular(
            funcionario: f,
            volume: _volume,
            arvores: _arvores,
          )
        : null;

    String info = f['forma_remuneracao']?.toString() ?? '';
    if (calculo != null && calculo.valorTotal > 0) {
      info += ' • R\$ ${calculo.valorTotal.toStringAsFixed(2)}';
    }

    return CheckboxListTile(
      value: selecionado,
      onChanged: (v) => setState(() => p['selecionado'] = v == true),
      title: Text(f['nome']?.toString() ?? ''),
      subtitle: info.isNotEmpty ? Text(info) : null,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: BrandColors.forest,
    );
  }

  Widget _buildTalhaoField() {
    return DropdownButtonFormField<String>(
      value: _talhaoId,
      decoration: const InputDecoration(labelText: 'Talhão'),
      items: _talhoes.map((t) {
        return DropdownMenuItem(
          value: t['id'].toString(),
          child: Text(t['codigo']?.toString() ?? ''),
        );
      }).toList(),
      onChanged: (v) => setState(() => _talhaoId = v),
      validator: (v) => v == null ? 'Selecione' : null,
    );
  }

  Widget _buildDataField() {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _data ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) setState(() => _data = picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Data'),
        child: Text(
          _data == null
              ? 'Selecione'
              : DateFormat('dd/MM/yyyy').format(_data!),
        ),
      ),
    );
  }

  Widget _buildResumoCalculo() {
    final selecionados = _tipoProducao == 'Individual'
        ? (_funcionarioId != null ? 1 : 0)
        : _participantes.where((p) => p['selecionado'] == true).length;

    if (selecionados == 0) return const SizedBox.shrink();

    return Card(
      color: BrandColors.forest.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resumo', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text('Participantes: $selecionados'),
            Text('Volume total: ${_volume.toStringAsFixed(2)} m³'),
            Text('Total de árvores: $_arvores'),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _volumeCtrl.dispose();
    _arvoresCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }
}
