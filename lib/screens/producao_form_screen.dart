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
  final Map<String, dynamic>? existing;
  const ProducaoFormScreen({super.key, this.existing});

  @override
  State<ProducaoFormScreen> createState() => _ProducaoFormScreenState();
}

class _ProducaoFormScreenState extends State<ProducaoFormScreen> {
  final _formKey = GlobalKey<FormState>();

  String _tipoProducao = 'Individual';

  String? _funcionarioId;
  String? _equipeId;
  String? _talhaoId;
  String? _producaoId;
  DateTime? _data;
  final _volumeCtrl = TextEditingController(text: '0');
  final _arvoresCtrl = TextEditingController(text: '0');
  final _horasCtrl = TextEditingController(text: '1');
  final _obsCtrl = TextEditingController();

  List<Map<String, dynamic>> _funcionarios = [];
  List<Map<String, dynamic>> _equipes = [];
  List<Map<String, dynamic>> _talhoes = [];

  List<Map<String, dynamic>> _participantes = [];

  bool _loading = false;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _data = DateTime.now();
    _loadOptions().then((_) => _carregarEdicao());
  }

  Future<void> _carregarEdicao() async {
    final existing = widget.existing;
    if (existing == null) return;

    setState(() => _loading = true);
    try {
      _producaoId = existing['id']?.toString();
      _tipoProducao = existing['tipo_producao']?.toString() ?? 'Individual';
      _funcionarioId = existing['funcionario_id']?.toString();
      _equipeId = existing['equipe_id']?.toString();
      _talhaoId = existing['talhao_id']?.toString();

      final dataRaw = existing['data']?.toString();
      if (dataRaw != null && dataRaw.isNotEmpty) {
        _data = DateTime.tryParse(dataRaw);
      }

      _volumeCtrl.text = _fmtNumber(existing['volume_total']);
      _arvoresCtrl.text = _fmtInt(existing['total_arvores']);
      _obsCtrl.text = existing['observacoes']?.toString() ?? '';

      if (_tipoProducao == 'Equipe' && _equipeId != null) {
        await _carregarParticipantes();
        await _marcarParticipantesExistentes();
      }
    } catch (e) {
      debugPrint('Erro ao carregar edição: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtNumber(dynamic v) {
    if (v == null) return '0';
    final n = v is num ? v : num.tryParse(v.toString());
    if (n == null) return '0';
    return n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2);
  }

  String _fmtInt(dynamic v) {
    if (v == null) return '0';
    final n = v is num ? v.toInt() : int.tryParse(v.toString());
    return '${n ?? 0}';
  }

  Future<void> _marcarParticipantesExistentes() async {
    if (_producaoId == null) return;
    try {
      final res = await Db.instance.client
          .from('producao_funcionarios')
          .select('funcionario_id, participou')
          .eq('producao_id', _producaoId!);

      final existentes = (res as List).cast<Map<String, dynamic>>();
      final ids = existentes
          .where((r) => r['participou'] == true)
          .map((r) => r['funcionario_id'].toString())
          .toSet();

      if (mounted) {
        setState(() {
          for (final p in _participantes) {
            final f = p['funcionario'] as Map<String, dynamic>;
            p['selecionado'] = ids.contains(f['id'].toString());
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao marcar participantes existentes: $e');
    }
  }

  Future<void> _loadOptions() async {
    setState(() => _loading = true);
    try {
      final funcionarios = await Db.instance.client
          .from('funcionarios')
          .select('id,nome,forma_remuneracao,valor_diaria,valor_hora,valor_m3,valor_arvore,valor_producao_fixa,situacao')
          .order('nome');
      final equipes = await Db.instance.client
          .from('equipes')
          .select('id,nome')
          .order('nome');
      final talhoes = await Db.instance.client
          .from('talhoes')
          .select('id,codigo')
          .order('codigo');

      final fList = (funcionarios as List).cast<Map<String, dynamic>>();
      final eList = (equipes as List).cast<Map<String, dynamic>>();
      final tList = (talhoes as List).cast<Map<String, dynamic>>();

      if (mounted) {
        setState(() {
          _funcionarios = fList
              .where((f) => (f['situacao'] ?? 'Ativo') == 'Ativo')
              .toList();
          _equipes = eList;
          _talhoes = tList;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar opções: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar dados: $e')),
        );
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
      final membros = await Db.instance.client
          .from('equipe_membros')
          .select('funcionario_id')
          .eq('equipe_id', _equipeId!);

      final funcionarioIds = (membros as List)
          .cast<Map<String, dynamic>>()
          .map((m) => m['funcionario_id'].toString())
          .toList();

      if (funcionarioIds.isEmpty) {
        if (mounted) setState(() => _participantes = []);
        return;
      }

      final funcionarios = await Db.instance.client
          .from('funcionarios')
          .select('id,nome,forma_remuneracao,valor_diaria,valor_hora,valor_m3,valor_arvore,valor_producao_fixa,situacao')
          .inFilter('id', funcionarioIds)
          .eq('situacao', 'Ativo');

      final lista = (funcionarios as List).cast<Map<String, dynamic>>().map((f) {
        return {
          'funcionario': f,
          'selecionado': true,
          'horas': 1.0,
        };
      }).toList();

      if (mounted) {
        setState(() => _participantes = lista);
      }
    } catch (e) {
      debugPrint('Erro ao carregar integrantes: $e');
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
  double get _horas => double.tryParse(_horasCtrl.text.replaceAll(',', '.')) ?? 1;

  Map<String, dynamic>? get _funcionarioSelecionado {
    if (_funcionarioId == null) return null;
    return _funcionarios.firstWhere(
      (f) => f['id'].toString() == _funcionarioId,
      orElse: () => {},
    );
  }

  String? get _formaIndividual => _funcionarioSelecionado?['forma_remuneracao']?.toString();

  bool get _mostrarVolumeArvores {
    if (_tipoProducao == 'Individual') {
      return _formaIndividual == 'Metro cúbico' || _formaIndividual == 'Árvore';
    }
    // Equipe: exibe se pelo menos um selecionado usa m³ ou árvore.
    final selecionados = _participantes.where((p) => p['selecionado'] == true);
    if (selecionados.isEmpty) return true; // mostra por padrão até escolher
    return selecionados.any((p) {
      final forma = p['funcionario']['forma_remuneracao']?.toString();
      return forma == 'Metro cúbico' || forma == 'Árvore';
    });
  }

  bool get _mostrarHorasIndividual => _formaIndividual == 'Hora';

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
          {
            'funcionario': f,
            'selecionado': true,
            'horas': _horas,
          }
        ];
      } else {
        participantes = _participantes;
      }

      if (_isEditing && _producaoId != null) {
        await ProducaoCalculoService.atualizarProducao(
          producaoId: _producaoId!,
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
      } else {
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
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing
                ? 'Produção atualizada com sucesso.'
                : 'Produção salva com sucesso.'),
          ),
        );
        Navigator.pop(context, true);
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
        title: Text(_isEditing ? 'Editar Produção' : 'Nova Produção'),
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
                    if (_mostrarHorasIndividual) ...[
                      TextFormField(
                        controller: _horasCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Horas trabalhadas',
                          suffixText: 'h',
                        ),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v?.isEmpty ?? true) return 'Informe';
                          final n = double.tryParse(v!.replaceAll(',', '.'));
                          if (n == null || n <= 0) return 'Inválido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_mostrarVolumeArvores)
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
    final forma = f['forma_remuneracao']?.toString() ?? '';
    final ehHora = forma == 'Hora';
    final calculo = selecionado
        ? ProducaoCalculoService.calcular(
            funcionario: f,
            volume: _volume,
            arvores: _arvores,
            horas: _parseDouble(p['horas'] ?? 1),
          )
        : null;

    String info = forma;
    if (calculo != null && calculo.valorTotal > 0) {
      info += ' • R\$ ${calculo.valorTotal.toStringAsFixed(2)}';
    }

    return Column(
      children: [
        CheckboxListTile(
          value: selecionado,
          onChanged: (v) => setState(() => p['selecionado'] = v == true),
          title: Text(f['nome']?.toString() ?? ''),
          subtitle: info.isNotEmpty ? Text(info) : null,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: BrandColors.forest,
        ),
        if (selecionado && ehHora)
          Padding(
            padding: const EdgeInsets.only(left: 56, right: 16, bottom: 8),
            child: TextFormField(
              initialValue: (p['horas'] ?? 1).toString(),
              decoration: const InputDecoration(
                labelText: 'Horas trabalhadas',
                suffixText: 'h',
                isDense: true,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) {
                final n = double.tryParse(v.replaceAll(',', '.'));
                setState(() => p['horas'] = n ?? 1);
              },
            ),
          ),
      ],
    );
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
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
    _horasCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }
}
