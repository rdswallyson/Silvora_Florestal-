import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../data/entities.dart';
import '../services/db_service.dart';
import '../services/cliente_preco_service.dart';
import '../theme/app_theme.dart';
import 'entity_detail_screen.dart';

import 'producao_form_screen.dart';

/// Tela genérica de módulo: lista os registros da tabela e permite
/// cadastrar, editar e excluir — tudo salvo no Supabase.
class EntityListScreen extends StatefulWidget {
  final EntityDef def;
  const EntityListScreen(this.def, {super.key});

  @override
  State<EntityListScreen> createState() => _EntityListScreenState();
}

class _EntityListScreenState extends State<EntityListScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String _query = '';
  String? _filtroEquipeId;
  String? _filtroFuncionarioId;
  List<Map<String, dynamic>> _equipesOptions = [];
  List<Map<String, dynamic>> _funcionariosOptions = [];
  bool _modoIndividualProducao = false;
  Future<List<Map<String, dynamic>>>? _futureIndividual;

  EntityDef get def => widget.def;

  @override
  void initState() {
    super.initState();
    _future = Db.list(def.table, select: def.selectQuery);
    _loadFilterOptions();
  }

  Future<void> _loadFilterOptions() async {
    if (def.table != 'producao') return;
    try {
      final equipes = await Db.options('equipes');
      final funcionarios = await Db.options('funcionarios');
      if (mounted) {
        setState(() {
          _equipesOptions = equipes;
          _funcionariosOptions = funcionarios;
        });
      }
    } catch (_) {}
  }

  void _reload() {
    setState(() {
      _future = Db.list(def.table, select: def.selectQuery);
      if (def.table == 'producao') {
        _futureIndividual = Db.list('producao_funcionarios',
            select:
                '*, funcionario:funcionarios!funcionario_id(nome, forma_remuneracao), producao:producao!producao_id(data, talhao:talhao_id(codigo), equipe:equipe_id(nome))');
      }
    });
  }

  Future<void> _openForm([Map<String, dynamic>? existing]) async {
    if (def.table == 'producao') {
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ProducaoFormScreen(existing: existing),
        ),
      );
      if (saved == true && mounted) {
        _reload();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(existing == null
                ? 'Produção cadastrada com sucesso.'
                : 'Alterações salvas.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EntityForm(def: def, existing: existing),
    );
    if (saved == true && mounted) {
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existing == null
              ? '${_capital(def.noun)} cadastrado com sucesso.'
              : 'Alterações salvas.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (ctx) => EntityDetailScreen(
          def: def,
          item: item,
          onEdit: () async {
            Navigator.pop(ctx);
            await _openForm(item);
          },
          onDelete: () async {
            await Db.delete(def.table, '${item['id']}');
            if (ctx.mounted) Navigator.pop(ctx, true);
          },
        ),
      ),
    );
    if (changed == true && mounted) _reload();
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
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
            style: FilledButton.styleFrom(backgroundColor: BrandColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await Db.delete(def.table, '${item['id']}');
        _reload();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao excluir: $e')),
          );
        }
      }
    }
  }

  bool _matchesSearch(Map<String, dynamic> m) {
    if (_query.isEmpty) return true;
    return def.matches(m, _query);
  }

  @override
  Widget build(BuildContext context) {
    if (def.table == 'producao' && _modoIndividualProducao) {
      return _buildProducaoIndividualView();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Novo'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorState(onRetry: _reload, error: '${snap.error}');
          }
          final all = snap.data ?? const [];
          final items = all.where((m) {
            if (!_matchesSearch(m)) {
              return false;
            }
            if (def.table == 'producao') {
              if (_filtroEquipeId != null &&
                  '${m['equipe_id']}' != _filtroEquipeId) {
                return false;
              }
              if (_filtroFuncionarioId != null &&
                  '${m['funcionario_id']}' != _filtroFuncionarioId) {
                return false;
              }
            }
            return true;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar ${def.noun}...',
                    prefixIcon: const Icon(Icons.search),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (def.table == 'producao')
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _FilterBar(
                          equipes: _equipesOptions,
                          funcionarios: _funcionariosOptions,
                          equipeId: _filtroEquipeId,
                          funcionarioId: _filtroFuncionarioId,
                          onEquipeChanged: (v) =>
                              setState(() => _filtroEquipeId = v),
                          onFuncionarioChanged: (v) =>
                              setState(() => _filtroFuncionarioId = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        onPressed: () => setState(() =>
                            _modoIndividualProducao = !_modoIndividualProducao),
                        icon: const Icon(Icons.person_outline),
                        tooltip: 'Ver por funcionário',
                      ),
                    ],
                  ),
                ),
              if (def.headerOf != null && items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: def.headerOf!(items),
                ),
              Expanded(
                child: all.isEmpty
                    ? _EmptyState(def: def, onAdd: () => _openForm())
                    : RefreshIndicator(
                        onRefresh: () async => _reload(),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                          itemCount: items.length,
                          itemBuilder: (context, i) => _EntityTile(
                            def: def,
                            item: items[i],
                            onTap: () => _openDetail(items[i]),
                            onEdit: () => _openForm(items[i]),
                            onDelete: () => _confirmDelete(items[i]),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProducaoIndividualView() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _modoIndividualProducao = false),
        icon: const Icon(Icons.view_agenda_outlined),
        label: const Text('Agrupada'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _futureIndividual,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorState(onRetry: _reload, error: '${snap.error}');
          }
          final all = snap.data ?? const [];
          final items = all.where((m) {
            if (_query.isNotEmpty && !def.matches(m, _query)) return false;
            return true;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Buscar participante...',
                    prefixIcon: Icon(Icons.search),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('Nenhum participante encontrado.'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final m = items[i];
                          final f = m['funcionario'] as Map? ?? {};
                          final p = m['producao'] as Map? ?? {};
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: _iconAvatar(
                                  Icons.person, BrandColors.forest),
                              title: Text(f['nome']?.toString() ?? ''),
                              subtitle: Text([
                                f['forma_remuneracao']?.toString() ?? '',
                                if ((m['valor_total'] ?? 0) > 0)
                                  'R\$ ${(m['valor_total'] as num).toStringAsFixed(2)}',
                                p['data']?.toString() ?? '',
                              ].where((e) => e.isNotEmpty).join(' • ')),
                              trailing: Text(
                                '${(m['quantidade_calculo'] as num?)?.toStringAsFixed(0) ?? '0'} un',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Widget _iconAvatar(IconData icon, Color color) {
  return CircleAvatar(
    radius: 24,
    backgroundColor: color.withValues(alpha: 0.12),
    child: Icon(icon, color: color),
  );
}

class _EntityTile extends StatelessWidget {
  final EntityDef def;
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _EntityTile({
    required this.def,
    required this.item,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = def.subtitleOf(item);
    final trailing = def.trailingOf?.call(item);
    final leading = def.leadingOf?.call(item) ??
        CircleAvatar(
          radius: 24,
          backgroundColor: BrandColors.forest.withValues(alpha: 0.15),
          child: Icon(def.icon, color: BrandColors.forest),
        );
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(def.titleOf(item),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.3,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6))),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
              const SizedBox(width: 4),
              _IconButton(
                icon: Icons.edit_outlined,
                onTap: onEdit,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (v) {
                  if (v == 'editar') onEdit();
                  if (v == 'excluir') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'editar', child: Text('Editar')),
                  PopupMenuItem(value: 'excluir', child: Text('Excluir')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: BrandColors.forest.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: BrandColors.forest),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final EntityDef def;
  final VoidCallback onAdd;
  const _EmptyState({required this.def, required this.onAdd});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(def.icon, size: 64, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('Nenhum ${def.noun} cadastrado',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            Text('Toque em "Novo" para adicionar o primeiro.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.withValues(alpha: 0.9))),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Novo'),
              style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final String error;
  const _ErrorState({required this.onRetry, required this.error});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 56, color: BrandColors.alert),
            const SizedBox(height: 16),
            const Text('Não foi possível carregar os dados',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            Text(error,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.withValues(alpha: 0.9))),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(180, 48)),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================
// Formulário de criação/edição
// =========================================================
class _EntityForm extends StatefulWidget {
  final EntityDef def;
  final Map<String, dynamic>? existing;
  const _EntityForm({required this.def, this.existing});

  @override
  State<_EntityForm> createState() => _EntityFormState();
}

class _EntityFormState extends State<_EntityForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, String?> _selects = {};
  final Map<String, String?> _refValues = {};
  final Map<String, Set<String>> _multiValues = {};
  final Map<String, List<Map<String, dynamic>>> _optionsByTable = {};
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  double? _precoVigente;
  bool _cargaEditadaManualmente = false;

  EntityDef get def => widget.def;

  @override
  void initState() {
    super.initState();
    for (final f in def.fields) {
      final initial = widget.existing?[f.key];
      switch (f.type) {
        case FieldType.select:
          final val = initial?.toString();
          _selects[f.key] =
              (val != null && f.options.contains(val)) ? val : null;
          break;
        case FieldType.reference:
          _refValues[f.key] = initial?.toString();
          break;
        case FieldType.multiReference:
          _multiValues[f.key] = _initialMulti(f);
          break;
        case FieldType.date:
          final initial = widget.existing?[f.key]?.toString();
          _ctrls[f.key] = TextEditingController(
              text: initial == null || initial.isEmpty ? '' : initial);
          break;
        default:
          _ctrls[f.key] = TextEditingController(
              text: initial == null ? '' : _fmtInitial(initial));
      }
    }
    _loadOptions();
    _carregarPrecoVigente();
  }

  Future<void> _carregarPrecoVigente() async {
    if (def.table != 'clientes' || widget.existing == null) return;
    try {
      final preco = await ClientePrecoService.buscarPrecoVigente(
        '${widget.existing!['id']}',
        DateTime.now(),
      );
      if (mounted) {
        setState(() {
          _precoVigente = preco;
          if (preco != null && _ctrls['valor_m3'] != null) {
            _ctrls['valor_m3']!.text = _fmtInitial(preco);
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar preço vigente: $e');
    }
  }

  Set<String> _initialMulti(FieldDef f) {
    final embed = widget.existing?[f.joinAlias];
    if (embed is List) {
      return embed
          .map((e) => e is Map ? '${e[f.joinChildKey]}' : '')
          .where((e) => e.isNotEmpty)
          .toSet();
    }
    return <String>{};
  }

  Future<void> _loadOptions() async {
    try {
      final tables = <String>{
        for (final f in def.referenceFields) f.refTable!,
        for (final f in def.multiFields) f.refTable!,
      };
      for (final t in tables) {
        _optionsByTable[t] = await Db.options(t);
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '$e';
        });
      }
    }
  }

  String _fmtInitial(Object v) {
    final s = v.toString();
    if (s.endsWith('.0')) return s.substring(0, s.length - 2);
    return s;
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final data = <String, dynamic>{};
    for (final f in def.fields) {
      if (f.type == FieldType.multiReference) continue;
      dynamic value;
      if (f.type == FieldType.select) {
        value = _selects[f.key];
      } else if (f.type == FieldType.reference) {
        value = _refValues[f.key];
      } else if (f.type == FieldType.date) {
        final raw = _ctrls[f.key]!.text.trim();
        value = raw.isEmpty ? null : raw;
      } else {
        final raw = _ctrls[f.key]!.text.trim();
        if (raw.isEmpty) {
          value = null;
        } else if (f.type == FieldType.number) {
          value = int.tryParse(raw.replaceAll(RegExp(r'[^0-9-]'), ''));
        } else if (f.type == FieldType.decimal) {
          value = double.tryParse(raw.replaceAll(',', '.'));
        } else {
          value = raw;
        }
      }
      data[f.key] = value;
    }
    // O campo valor_m3 do cliente é virtual: persistido em cliente_precos,
    // nunca na tabela clientes.
    if (def.table == 'clientes') {
      data.remove('valor_m3');
    }
    try {
      String id;
      if (widget.existing == null) {
        id = await Db.insertReturningId(def.table, data);
      } else {
        id = '${widget.existing!['id']}';
        await Db.update(def.table, id, data);
      }
      // sincroniza relações muitos-para-muitos (ex: integrantes)
      for (final f in def.multiFields) {
        await Db.setJoin(
          joinTable: f.joinTable!,
          parentKey: f.joinParentKey!,
          parentId: id,
          childKey: f.joinChildKey!,
          childIds: _multiValues[f.key]!.toList(),
        );
      }
      // Cliente: salva/atualiza preço vigente quando o usuário informou o campo
      if (def.table == 'clientes' && _ctrls['valor_m3'] != null) {
        final raw = _ctrls['valor_m3']!.text.trim();
        final novoValor = raw.isEmpty ? null : double.tryParse(raw.replaceAll(',', '.'));
        if (novoValor != null && novoValor != _precoVigente) {
          await ClientePrecoService.salvarPreco(id, novoValor);
        }
      }
      // Produção: obsoleto — nova tela ProducaoFormScreen trata o cálculo individual.
      // Mantido apenas para edição de registros antigos, sem replicação.
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    }
  }

  Future<void> _replicarProducaoParaEquipe(
      String producaoId, Map<String, dynamic> base) async {
    // Método obsoleto: a nova tela ProducaoFormScreen já cria os registros individuais.
    return;
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollCtrl) => Form(
          key: _formKey,
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: BrandColors.forest.withValues(alpha: 0.15),
                    child: Icon(def.icon, color: BrandColors.forest),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    editing ? 'Editar ${def.noun}' : 'Novo ${def.noun}',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_loadError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text('Erro ao carregar opções: $_loadError',
                      style: const TextStyle(color: BrandColors.danger)),
                )
              else ...[
                ...def.fields.map(_buildField),
                if (def.table == 'transporte') _buildTransporteResumo(),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check),
                  label: Text(_saving ? 'Salvando...' : 'Salvar'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(FieldDef f) {
    Widget field;
    switch (f.type) {
      case FieldType.select:
        final isTipoFrete = def.table == 'transporte' && f.key == 'tipo_frete';
        field = DropdownButtonFormField<String?>(
          initialValue: _selects[f.key],
          isExpanded: true,
          decoration: InputDecoration(labelText: f.label),
          items: isTipoFrete
              ? [
                  const DropdownMenuItem<String?>(value: null, child: Text('— sem frete separado —')),
                  const DropdownMenuItem<String?>(value: 'km', child: Text('Por quilômetro')),
                  const DropdownMenuItem<String?>(value: 'combinado', child: Text('Valor combinado')),
                ]
              : [
                  if (!f.required)
                    const DropdownMenuItem<String?>(value: null, child: Text('— nenhum —')),
                  ...f.options.map((o) => DropdownMenuItem(value: o, child: Text(o))),
                ],
          validator: (v) =>
              f.required && (v == null) ? 'Campo obrigatório' : null,
          onChanged: (v) {
            setState(() => _selects[f.key] = v);
            if (isTipoFrete) {
              _atualizarResumoFrete();
            }
          },
        );
        break;
      case FieldType.reference:
        field = _buildReference(f);
        break;
      case FieldType.multiReference:
        field = _buildMulti(f);
        break;
      case FieldType.date:
        field = _buildDate(f);
        break;
      default:
        field = TextFormField(
          controller: _ctrls[f.key],
          keyboardType: _keyboard(f.type),
          inputFormatters: _formatters(f.type),
          maxLines: f.type == FieldType.multiline ? 3 : 1,
          decoration: InputDecoration(
            labelText: f.label,
            suffixText: f.suffix,
          ),
          onChanged: (_) {
            if (def.table == 'transporte') {
              if (f.key == 'volume_m3') {
                _atualizarCargaAutomatica();
              }
              if (f.key == 'frete') {
                _cargaEditadaManualmente = true;
                if (_ctrls['frete']?.text.trim().isEmpty ?? true) {
                  _cargaEditadaManualmente = false;
                }
              }
              if (['distancia_km', 'valor_km', 'valor_combinado'].contains(f.key)) {
                _atualizarResumoFrete();
              }
            }
          },
          validator: (v) => f.required && (v == null || v.trim().isEmpty)
              ? 'Campo obrigatório'
              : null,
        );
    }
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: field);
  }

  Widget _buildDate(FieldDef f) {
    final ctrl = _ctrls.putIfAbsent(f.key, () => TextEditingController());
    if (ctrl.text.isEmpty) {
      ctrl.text = _today;
    }
    return TextFormField(
      controller: ctrl,
      readOnly: true,
      decoration: InputDecoration(
        labelText: f.label,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.calendar_today, size: 20),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  ctrl.text = DateFormat('dd/MM/yyyy').format(picked);
                  if (def.table == 'transporte' && f.key == 'data') {
                    _atualizarCargaAutomatica();
                  }
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.today, size: 20),
              tooltip: 'Hoje',
              onPressed: () {
                ctrl.text = _today;
                if (def.table == 'transporte' && f.key == 'data') {
                  _atualizarCargaAutomatica();
                }
              },
            ),
          ],
        ),
      ),
      validator: (v) => f.required && (v == null || v.trim().isEmpty)
          ? 'Campo obrigatório'
          : null,
    );
  }

  String get _today {
    final hoje = DateTime.now();
    return '${hoje.day.toString().padLeft(2, '0')}/${hoje.month.toString().padLeft(2, '0')}/${hoje.year}';
  }

  Widget _buildReference(FieldDef f) {
    final opts = _optionsByTable[f.refTable] ?? const [];
    if (opts.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: f.label,
          errorText: f.required ? 'Cadastre "${f.label}" primeiro' : null,
        ),
        child: Text('Nenhum ${f.label.toLowerCase()} cadastrado ainda',
            style: TextStyle(color: Colors.grey.withValues(alpha: 0.9))),
      );
    }
    final selectedValue =
        opts.any((o) => '${o['id']}' == _refValues[f.key]) ? _refValues[f.key] : null;
    return DropdownButtonFormField<String?>(
      initialValue: selectedValue,
      isExpanded: true,
      decoration: InputDecoration(labelText: f.label),
      items: [
        if (!f.required)
          const DropdownMenuItem<String?>(
              value: null, child: Text('— nenhum —')),
        ...opts.map((o) => DropdownMenuItem(
              value: '${o['id']}',
              child: Text(f.refLabelOf!(o), overflow: TextOverflow.ellipsis),
            )),
      ],
      validator: (v) =>
          f.required && (v == null) ? 'Selecione um(a) ${f.label}' : null,
      onChanged: (v) {
        setState(() => _refValues[f.key] = v);
        if (def.table == 'transporte' && f.key == 'cliente_id') {
          _atualizarCargaAutomatica();
        }
      },
    );
  }

  Future<void> _atualizarCargaAutomatica() async {
    if (def.table != 'transporte') return;

    final clienteId = _refValues['cliente_id'];
    if (clienteId == null || clienteId.isEmpty) return;

    final dataCtrl = _ctrls['data'];
    final volumeCtrl = _ctrls['volume_m3'];
    final freteCtrl = _ctrls['frete'];
    if (dataCtrl == null || volumeCtrl == null || freteCtrl == null) return;

    DateTime? data = _parseDate(dataCtrl.text);
    data ??= DateTime.now();

    final volume = double.tryParse(volumeCtrl.text.replaceAll(',', '.'));
    if (volume == null || volume <= 0) return;

    final preco = await ClientePrecoService.buscarPrecoVigente(clienteId, data);
    if (preco == null) return;

    final calculado = preco * volume;
    final freteAtual = double.tryParse(freteCtrl.text.replaceAll(',', '.'));

    // Só atualiza automaticamente se o usuário ainda não editou manualmente
    // ou se apagou o valor (volta ao modo automático).
    if (!_cargaEditadaManualmente ||
        freteCtrl.text.trim().isEmpty ||
        freteAtual == null ||
        freteAtual == 0) {
      freteCtrl.text = calculado.toStringAsFixed(2);
      _cargaEditadaManualmente = false;
    }
  }

  void _atualizarResumoFrete() {
    if (def.table != 'transporte') return;
    setState(() {});
  }

  double _calcularFreteTransporte() {
    final tipo = _selects['tipo_frete'];
    if (tipo == 'km') {
      final km = double.tryParse(_ctrls['distancia_km']?.text.replaceAll(',', '.') ?? '') ?? 0;
      final valor = double.tryParse(_ctrls['valor_km']?.text.replaceAll(',', '.') ?? '') ?? 0;
      return km * valor;
    }
    if (tipo == 'combinado') {
      return double.tryParse(_ctrls['valor_combinado']?.text.replaceAll(',', '.') ?? '') ?? 0;
    }
    return 0;
  }

  double _calcularTotalTransporte() {
    final carga = double.tryParse(_ctrls['frete']?.text.replaceAll(',', '.') ?? '') ?? 0;
    return carga + _calcularFreteTransporte();
  }

  Widget _buildTransporteResumo() {
    final frete = _calcularFreteTransporte();
    final total = _calcularTotalTransporte();
    final tipo = _selects['tipo_frete'];

    return Card(
      margin: const EdgeInsets.only(top: 8, bottom: 14),
      color: BrandColors.forest.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resumo da viagem',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800, color: BrandColors.forest)),
            const SizedBox(height: 12),
            _buildResumoRow('Carga', _ctrls['frete']?.text ?? '0'),
            if (tipo != null && tipo.isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildResumoRow('Frete', frete.toStringAsFixed(2)),
            ],
            const Divider(height: 18),
            _buildResumoRow('Total', total.toStringAsFixed(2), isTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _buildResumoRow(String label, String valor, {bool isTotal = false}) {
    final v = double.tryParse(valor.replaceAll(',', '.')) ?? 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
              fontSize: isTotal ? 16 : 14,
            )),
        Text('R\$ ${v.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.w900 : FontWeight.w700,
              fontSize: isTotal ? 18 : 14,
              color: isTotal ? BrandColors.forest : null,
            )),
      ],
    );
  }

  DateTime? _parseDate(String text) {
    try {
      final partes = text.split('/');
      if (partes.length == 3) {
        final dia = int.parse(partes[0]);
        final mes = int.parse(partes[1]);
        final ano = int.parse(partes[2]);
        return DateTime(ano, mes, dia);
      }
      return DateTime.tryParse(text);
    } catch (_) {
      return null;
    }
  }

  Future<void> _aplicarFormaPagamentoDoFuncionario(String funcId) async {
    // Obsoleto: a nova tela ProducaoFormScreen já busca a forma de remuneração.
    return;
  }

  Future<void> _aplicarFormaPagamentoDaEquipe(String equipeId) async {
    // Obsoleto: a nova tela ProducaoFormScreen já busca os integrantes ativos.
    return;
  }

  Widget _buildMulti(FieldDef f) {
    final opts = _optionsByTable[f.refTable] ?? const [];
    final selected = _multiValues[f.key]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${f.label} (${selected.length})',
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 8),
        if (opts.isEmpty)
          Text('Cadastre funcionários primeiro para adicioná-los.',
              style: TextStyle(color: Colors.grey.withValues(alpha: 0.9)))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: opts.map((o) {
              final id = '${o['id']}';
              final on = selected.contains(id);
              return FilterChip(
                label: Text(f.refLabelOf!(o)),
                selected: on,
                onSelected: (v) => setState(() {
                  if (v) {
                    selected.add(id);
                  } else {
                    selected.remove(id);
                  }
                }),
              );
            }).toList(),
          ),
      ],
    );
  }

  TextInputType? _keyboard(FieldType t) {
    switch (t) {
      case FieldType.phone:
        return TextInputType.phone;
      case FieldType.number:
        return TextInputType.number;
      case FieldType.decimal:
        return const TextInputType.numberWithOptions(decimal: true);
      case FieldType.multiline:
        return TextInputType.multiline;
      case FieldType.date:
        return TextInputType.datetime;
      default:
        return TextInputType.text;
    }
  }

  List<TextInputFormatter>? _formatters(FieldType t) {
    if (t == FieldType.number) {
      return [FilteringTextInputFormatter.digitsOnly];
    }
    if (t == FieldType.decimal) {
      return [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    }
    return null;
  }
}

class _FilterBar extends StatelessWidget {
  final List<Map<String, dynamic>> equipes;
  final List<Map<String, dynamic>> funcionarios;
  final String? equipeId;
  final String? funcionarioId;
  final ValueChanged<String?> onEquipeChanged;
  final ValueChanged<String?> onFuncionarioChanged;

  const _FilterBar({
    required this.equipes,
    required this.funcionarios,
    this.equipeId,
    this.funcionarioId,
    required this.onEquipeChanged,
    required this.onFuncionarioChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: equipeId,
                decoration: const InputDecoration(
                  labelText: 'Filtrar por equipe',
                  prefixIcon: Icon(Icons.groups),
                ),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Todas as equipes')),
                  ...equipes.map((e) => DropdownMenuItem(
                        value: '${e['id']}',
                        child: Text(_lblNome(e)),
                      )),
                ],
                onChanged: onEquipeChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: funcionarioId,
                decoration: const InputDecoration(
                  labelText: 'Filtrar por funcionário',
                  prefixIcon: Icon(Icons.person),
                ),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Todos os funcionários')),
                  ...funcionarios.map((f) => DropdownMenuItem(
                        value: '${f['id']}',
                        child: Text(_lblFuncionario(f)),
                      )),
                ],
                onChanged: onFuncionarioChanged,
              ),
            ),
          ],
        ),
        if (equipeId != null || funcionarioId != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  onEquipeChanged(null);
                  onFuncionarioChanged(null);
                },
                icon: const Icon(Icons.clear),
                label: const Text('Limpar filtros'),
              ),
            ),
          ),
      ],
    );
  }
}

String _lblFuncionario(Map m) {
  final nome = m['nome']?.toString() ?? '';
  final cargo = m['cargo']?.toString() ?? '';
  return [nome, cargo].where((e) => e.isNotEmpty).join(' - ');
}

String _lblNome(Map m) => m['nome']?.toString() ?? '';

String _capital(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
