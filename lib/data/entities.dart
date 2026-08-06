import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Tipo de campo em um formulário de módulo.
enum FieldType {
  text,
  phone,
  number,
  decimal,
  multiline,
  select,
  date,
  reference,
  multiReference,
}

/// Definição de um campo do formulário.
class FieldDef {
  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final List<String> options; // usado quando type == select
  final String? suffix;

  // --- referência (reference / multiReference) ---
  final String? refTable; // tabela de origem das opções
  final String Function(Map<String, dynamic>)? refLabelOf; // rótulo da opção

  // --- multiReference (tabela de ligação) ---
  final String? joinTable; // ex: equipe_membros
  final String? joinParentKey; // ex: equipe_id
  final String? joinChildKey; // ex: funcionario_id
  final String? joinAlias; // alias do embed na listagem (ex: membros)

  const FieldDef(
    this.key,
    this.label, {
    this.type = FieldType.text,
    this.required = false,
    this.options = const [],
    this.suffix,
    this.refTable,
    this.refLabelOf,
    this.joinTable,
    this.joinParentKey,
    this.joinChildKey,
    this.joinAlias,
  });
}

/// Definição de um módulo (tabela + como listar/cadastrar).
class EntityDef {
  final String table;
  final String noun; // ex: "funcionário"
  final IconData icon;
  final List<FieldDef> fields;
  final String selectQuery; // colunas + relacionamentos a carregar
  final String Function(Map<String, dynamic>) titleOf;
  final String Function(Map<String, dynamic>) subtitleOf;
  final Widget Function(Map<String, dynamic>)? leadingOf;
  final Widget? Function(Map<String, dynamic>)? trailingOf;
  final Widget? Function(List<Map<String, dynamic>>)? headerOf;

  const EntityDef({
    required this.table,
    required this.noun,
    required this.icon,
    required this.fields,
    required this.titleOf,
    required this.subtitleOf,
    this.selectQuery = '*',
    this.leadingOf,
    this.trailingOf,
    this.headerOf,
  });

  List<FieldDef> get referenceFields =>
      fields.where((f) => f.type == FieldType.reference).toList();
  List<FieldDef> get multiFields =>
      fields.where((f) => f.type == FieldType.multiReference).toList();

  bool matches(Map<String, dynamic> m, String q) {
    final query = q.toLowerCase();
    return ('${titleOf(m)} ${subtitleOf(m)}').toLowerCase().contains(query);
  }
}

// ---------- helpers ----------
String _s(Map m, String k) => (m[k] ?? '').toString();
double _d(Map m, String k) => double.tryParse('${m[k]}') ?? 0;
int _i(Map m, String k) => int.tryParse('${m[k]}'.split('.').first) ?? 0;

/// Lê o valor de um relacionamento embutido. Ex: _ref(m,'lider','nome').
String _ref(Map m, String alias, String field) {
  final v = m[alias];
  if (v is Map && v[field] != null) return v[field].toString();
  return '';
}

/// Nomes dos integrantes vindos do embed equipe_membros.
List<String> _membros(Map m) {
  final v = m['membros'];
  if (v is List) {
    return v
        .map((e) => (e is Map && e['funcionarios'] is Map)
            ? (e['funcionarios']['nome'] ?? '').toString()
            : '')
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return const [];
}

String _iniciais(String nome) {
  final parts = nome.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

Widget _iconAvatar(IconData icon, Color color) => CircleAvatar(
      radius: 24,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(icon, color: color),
    );

// ---------- rótulos de opções reutilizáveis ----------
String _lblNome(Map<String, dynamic> m) => _s(m, 'nome');
String _lblFuncionario(Map<String, dynamic> m) =>
    [_s(m, 'nome'), if (_s(m, 'cargo').isNotEmpty) '(${_s(m, 'cargo')})']
        .join(' ');
String _lblVeiculo(Map<String, dynamic> m) =>
    [_s(m, 'nome'), if (_s(m, 'tipo').isNotEmpty) '- ${_s(m, 'tipo')}']
        .join(' ');
String _lblTalhao(Map<String, dynamic> m) =>
    [_s(m, 'codigo'), if (_s(m, 'especie').isNotEmpty) _s(m, 'especie')]
        .where((e) => e.isNotEmpty)
        .join(' • ');

/// Registro central de todos os módulos, por rota.
double _calcValorProducao(Map<String, dynamic> m) {
  // Obsoleto: cálculo agora é feito em producao_funcionarios
  return 0;
}

String _valorFuncionarioLabel(Map<String, dynamic> m) {
  final forma = _s(m, 'forma_remuneracao');
  switch (forma) {
    case 'Diária':
      return 'R\$ ${_d(m, 'valor_diaria').toStringAsFixed(2)}/dia';
    case 'Hora':
      return 'R\$ ${_d(m, 'valor_hora').toStringAsFixed(2)}/h';
    case 'Metro cúbico':
      return 'R\$ ${_d(m, 'valor_m3').toStringAsFixed(2)}/m³';
    case 'Árvore':
      return 'R\$ ${_d(m, 'valor_arvore').toStringAsFixed(2)}/árvore';
    case 'Produção fixa':
      return 'R\$ ${_d(m, 'valor_producao_fixa').toStringAsFixed(2)} fixo';
    default:
      return '';
  }
}

final Map<String, EntityDef> kEntities = {
  // ============ BASES ============
  'funcionarios': EntityDef(
    table: 'funcionarios',
    noun: 'funcionário',
    icon: Icons.badge_outlined,
    fields: const [
      FieldDef('nome', 'Nome completo', required: true),
      FieldDef('cargo', 'Cargo', type: FieldType.select, options: [
        'Motosserrista',
        'Ajudante',
        'Operador',
        'Motorista',
        'Supervisor',
        'Gerente',
        'Administrador',
      ]),
      FieldDef('telefone', 'Telefone', type: FieldType.phone),
      FieldDef('cpf', 'CPF'),
      FieldDef('rg', 'RG'),
      FieldDef('endereco', 'Endereço'),
      FieldDef('data_admissao', 'Data de admissão', type: FieldType.date),
      FieldDef('forma_remuneracao', 'Forma de remuneração',
          type: FieldType.select, options: [
        'Diária',
        'Metro cúbico',
        'Árvore',
        'Hora',
        'Produção fixa',
      ]),
      FieldDef('valor_diaria', 'Valor da diária (R\$)',
          type: FieldType.decimal, suffix: 'R\$'),
      FieldDef('valor_hora', 'Valor por hora (R\$)',
          type: FieldType.decimal, suffix: 'R\$'),
      FieldDef('valor_m3', 'Valor por m³ (R\$)',
          type: FieldType.decimal, suffix: 'R\$'),
      FieldDef('valor_arvore', 'Valor por árvore (R\$)',
          type: FieldType.decimal, suffix: 'R\$'),
      FieldDef('valor_producao_fixa', 'Valor produção fixa (R\$)',
          type: FieldType.decimal, suffix: 'R\$'),
      FieldDef('pix', 'Chave PIX'),
      FieldDef('contato_emergencia', 'Contato de emergência'),
      FieldDef('situacao', 'Situação', type: FieldType.select, options: [
        'Ativo',
        'Inativo',
      ]),
    ],
    titleOf: (m) => _s(m, 'nome'),
    subtitleOf: (m) {
      final forma = _s(m, 'forma_remuneracao');
      String? valorLabel;
      switch (forma) {
        case 'Diária':
          valorLabel = _d(m, 'valor_diaria') > 0
              ? 'R\$ ${_d(m, 'valor_diaria').toStringAsFixed(2)}/dia'
              : null;
          break;
        case 'Hora':
          valorLabel = _d(m, 'valor_hora') > 0
              ? 'R\$ ${_d(m, 'valor_hora').toStringAsFixed(2)}/h'
              : null;
          break;
        case 'Metro cúbico':
          valorLabel = _d(m, 'valor_m3') > 0
              ? 'R\$ ${_d(m, 'valor_m3').toStringAsFixed(2)}/m³'
              : null;
          break;
        case 'Árvore':
          valorLabel = _d(m, 'valor_arvore') > 0
              ? 'R\$ ${_d(m, 'valor_arvore').toStringAsFixed(2)}/árvore'
              : null;
          break;
        case 'Produção fixa':
          valorLabel = _d(m, 'valor_producao_fixa') > 0
              ? 'R\$ ${_d(m, 'valor_producao_fixa').toStringAsFixed(2)} fixo'
              : null;
          break;
      }
      return [
        _s(m, 'cargo'),
        _s(m, 'telefone'),
        if (forma.isNotEmpty) forma,
        valorLabel,
      ].where((e) => e?.isNotEmpty ?? false).join(' • ');
    },
    leadingOf: (m) => CircleAvatar(
      radius: 24,
      backgroundColor: BrandColors.forest.withValues(alpha: 0.15),
      child: Text(_iniciais(_s(m, 'nome')),
          style: const TextStyle(
              color: BrandColors.forest, fontWeight: FontWeight.w700)),
    ),
    trailingOf: (m) {
      final sit = _s(m, 'situacao');
      if (sit.isEmpty) return null;
      final cor = sit == 'Ativo' ? BrandColors.success : BrandColors.alert;
      return StatusChip(sit, cor);
    },
  ),
  'fazendas': EntityDef(
    table: 'fazendas',
    noun: 'fazenda',
    icon: Icons.terrain_outlined,
    fields: const [
      FieldDef('nome', 'Nome da fazenda', required: true),
      FieldDef('proprietario', 'Proprietário'),
      FieldDef('municipio', 'Município'),
      FieldDef('uf', 'UF'),
      FieldDef('area_ha', 'Área total (ha)',
          type: FieldType.decimal, suffix: 'ha'),
    ],
    titleOf: (m) => 'Faz. ${_s(m, 'nome')}',
    subtitleOf: (m) {
      final loc =
          [_s(m, 'municipio'), _s(m, 'uf')].where((e) => e.isNotEmpty).join('/');
      final area = _d(m, 'area_ha') > 0
          ? '${_d(m, 'area_ha').toStringAsFixed(0)} ha'
          : '';
      return [
        _s(m, 'proprietario'),
        [loc, area].where((e) => e.isNotEmpty).join(' • ')
      ].where((e) => e.isNotEmpty).join('\n');
    },
    leadingOf: (m) => _iconAvatar(Icons.terrain, BrandColors.info),
  ),
  'clientes': EntityDef(
    table: 'clientes',
    noun: 'cliente',
    icon: Icons.handshake_outlined,
    fields: const [
      FieldDef('nome', 'Nome / razão social', required: true),
      FieldDef('tipo', 'Tipo', type: FieldType.select, options: [
        'Cerâmica',
        'Olaria',
        'Indústria',
        'Empresa',
        'Produtor',
      ]),
      FieldDef('cidade', 'Cidade/UF'),
      FieldDef('pendencia', 'Pendência (R\$)',
          type: FieldType.decimal, suffix: 'R\$'),
    ],
    titleOf: (m) => _s(m, 'nome'),
    subtitleOf: (m) =>
        [_s(m, 'tipo'), _s(m, 'cidade')].where((e) => e.isNotEmpty).join(' • '),
    leadingOf: (m) => _iconAvatar(Icons.handshake, BrandColors.forest),
    trailingOf: (m) => _d(m, 'pendencia') > 0
        ? StatusChip('Pend. R\$ ${_d(m, 'pendencia').toStringAsFixed(0)}',
            BrandColors.danger)
        : const StatusChip('Em dia', BrandColors.success),
  ),
  'veiculos': EntityDef(
    table: 'veiculos',
    noun: 'veículo',
    icon: Icons.local_shipping_outlined,
    fields: const [
      FieldDef('nome', 'Nome / placa', required: true),
      FieldDef('tipo', 'Tipo', type: FieldType.select, options: [
        'Caminhão',
        'Muque',
        'Reboque',
        'Caminhonete',
        'Outro',
      ]),
      FieldDef('modelo', 'Modelo'),
      FieldDef('situacao', 'Situação', type: FieldType.select, options: [
        'Disponível',
        'Em uso',
        'Manutenção',
      ]),
    ],
    titleOf: (m) => _s(m, 'nome'),
    subtitleOf: (m) =>
        [_s(m, 'tipo'), _s(m, 'modelo')].where((e) => e.isNotEmpty).join(' • '),
    leadingOf: (m) => _iconAvatar(Icons.local_shipping, BrandColors.info),
    trailingOf: (m) {
      final s = _s(m, 'situacao');
      if (s.isEmpty) return null;
      final cor = s == 'Disponível' ? BrandColors.success : BrandColors.alert;
      return StatusChip(s, cor);
    },
  ),
  'estoque': EntityDef(
    table: 'estoque',
    noun: 'item',
    icon: Icons.inventory_2_outlined,
    fields: const [
      FieldDef('nome', 'Item', required: true),
      FieldDef('quantidade', 'Quantidade', type: FieldType.number),
      FieldDef('minimo', 'Estoque mínimo', type: FieldType.number),
      FieldDef('unidade', 'Unidade', type: FieldType.select, options: [
        'un',
        'L',
        'par',
        'kg',
        'm',
      ]),
    ],
    titleOf: (m) => _s(m, 'nome'),
    subtitleOf: (m) => 'Mínimo: ${_i(m, 'minimo')} ${_s(m, 'unidade')}',
    leadingOf: (m) {
      final baixo = _i(m, 'quantidade') <= _i(m, 'minimo');
      return _iconAvatar(
          Icons.inventory_2, baixo ? BrandColors.danger : BrandColors.forest);
    },
    trailingOf: (m) {
      final baixo = _i(m, 'quantidade') <= _i(m, 'minimo');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${_i(m, 'quantidade')} ${_s(m, 'unidade')}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          if (baixo)
            const Text('Estoque baixo',
                style: TextStyle(
                    color: BrandColors.danger,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
        ],
      );
    },
  ),

  // ============ DEPENDENTES ============
  'equipamentos': EntityDef(
    table: 'equipamentos',
    noun: 'equipamento',
    icon: Icons.handyman_outlined,
    selectQuery: '*, responsavel:funcionarios!responsavel_id(nome)',
    fields: [
      const FieldDef('nome', 'Nome / modelo', required: true),
      const FieldDef('tipo', 'Tipo', type: FieldType.select, options: [
        'Motosserra',
        'Máquina',
        'EPI',
        'Ferramenta',
        'Outro',
      ]),
      FieldDef('responsavel_id', 'Responsável',
          type: FieldType.reference,
          refTable: 'funcionarios',
          refLabelOf: _lblFuncionario),
      const FieldDef('horas', 'Horas trabalhadas',
          type: FieldType.number, suffix: 'h'),
      const FieldDef('situacao', 'Situação',
          type: FieldType.select,
          options: ['Operando', 'Manutenção', 'Parado']),
    ],
    titleOf: (m) => _s(m, 'nome'),
    subtitleOf: (m) => [
      _s(m, 'tipo'),
      if (_ref(m, 'responsavel', 'nome').isNotEmpty)
        'Resp.: ${_ref(m, 'responsavel', 'nome')}',
      if (_i(m, 'horas') > 0) '${_i(m, 'horas')}h',
    ].where((e) => e.isNotEmpty).join(' • '),
    leadingOf: (m) {
      final cor = _s(m, 'situacao') == 'Operando'
          ? BrandColors.success
          : BrandColors.alert;
      return _iconAvatar(Icons.handyman, cor);
    },
    trailingOf: (m) {
      final s = _s(m, 'situacao');
      if (s.isEmpty) return null;
      final cor = s == 'Operando' ? BrandColors.success : BrandColors.alert;
      return StatusChip(s, cor);
    },
  ),
  'talhoes': EntityDef(
    table: 'talhoes',
    noun: 'talhão',
    icon: Icons.forest_outlined,
    selectQuery: '*, fazenda:fazendas!fazenda_id(nome)',
    fields: [
      const FieldDef('codigo', 'Código', required: true),
      FieldDef('fazenda_id', 'Fazenda',
          type: FieldType.reference,
          required: true,
          refTable: 'fazendas',
          refLabelOf: _lblNome),
      const FieldDef('especie', 'Espécie', type: FieldType.select, options: [
        'Eucalipto',
        'Pinus',
        'Teca',
        'Outra',
      ]),
      const FieldDef('idade_anos', 'Idade (anos)', type: FieldType.number),
      const FieldDef('area_ha', 'Área (ha)',
          type: FieldType.decimal, suffix: 'ha'),
      const FieldDef('volume_m3', 'Volume estimado (m³)',
          type: FieldType.decimal, suffix: 'm³'),
      const FieldDef('situacao', 'Situação', type: FieldType.select, options: [
        'Em crescimento',
        'Pronto p/ corte',
        'Em corte',
        'Cortado',
      ]),
    ],
    titleOf: (m) => '${_s(m, 'especie')} • ${_s(m, 'codigo')}',
    subtitleOf: (m) => [
      if (_ref(m, 'fazenda', 'nome').isNotEmpty)
        'Faz. ${_ref(m, 'fazenda', 'nome')}',
      if (_i(m, 'idade_anos') > 0) '${_i(m, 'idade_anos')} anos',
      if (_d(m, 'area_ha') > 0) '${_d(m, 'area_ha')} ha',
    ].join(' • '),
    leadingOf: (m) => CircleAvatar(
      radius: 24,
      backgroundColor: BrandColors.forest.withValues(alpha: 0.15),
      child: Text(_s(m, 'codigo'),
          style: const TextStyle(
              color: BrandColors.forest,
              fontWeight: FontWeight.w700,
              fontSize: 12)),
    ),
    trailingOf: (m) {
      final s = _s(m, 'situacao');
      if (s.isEmpty) return null;
      final cor = s == 'Pronto p/ corte'
          ? BrandColors.success
          : s == 'Em corte'
              ? BrandColors.alert
              : BrandColors.info;
      return StatusChip(s, cor);
    },
  ),
  'equipes': EntityDef(
    table: 'equipes',
    noun: 'equipe',
    icon: Icons.groups_outlined,
    selectQuery:
        '*, lider:funcionarios!lider_id(nome), veiculo:veiculos!veiculo_id(nome), membros:equipe_membros(funcionario_id, funcionarios!funcionario_id(nome))',
    fields: [
      const FieldDef('nome', 'Nome da equipe', required: true),
      FieldDef('lider_id', 'Líder',
          type: FieldType.reference,
          refTable: 'funcionarios',
          refLabelOf: _lblFuncionario),
      FieldDef('integrantes_ids', 'Integrantes',
          type: FieldType.multiReference,
          refTable: 'funcionarios',
          refLabelOf: _lblFuncionario,
          joinTable: 'equipe_membros',
          joinParentKey: 'equipe_id',
          joinChildKey: 'funcionario_id',
          joinAlias: 'membros'),
      FieldDef('veiculo_id', 'Caminhão',
          type: FieldType.reference,
          refTable: 'veiculos',
          refLabelOf: _lblVeiculo),
      const FieldDef('area', 'Área de trabalho'),
    ],
    titleOf: (m) => _s(m, 'nome'),
    subtitleOf: (m) {
      final membros = _membros(m);
      final l1 = [
        if (_ref(m, 'lider', 'nome').isNotEmpty)
          'Líder: ${_ref(m, 'lider', 'nome')}',
        if (membros.isNotEmpty) '${membros.length} integrantes',
      ].join(' • ');
      final l2 = [
        if (_ref(m, 'veiculo', 'nome').isNotEmpty)
          '🚛 ${_ref(m, 'veiculo', 'nome')}',
        _s(m, 'area'),
      ].where((e) => e.isNotEmpty).join(' • ');
      return [l1, l2].where((e) => e.isNotEmpty).join('\n');
    },
    leadingOf: (m) => const CircleAvatar(
      radius: 24,
      backgroundColor: BrandColors.forest,
      child: Icon(Icons.groups, color: Colors.white),
    ),
  ),
  'producao': EntityDef(
    table: 'producao',
    noun: 'produção',
    icon: Icons.grass_outlined,
    selectQuery:
        '*, equipe:equipes!equipe_id(nome), talhao:talhoes!talhao_id(codigo), funcionario:funcionarios!funcionario_id(nome), producao_funcionarios(*)',
    fields: [
      FieldDef('tipo_producao', 'Tipo de produção',
          type: FieldType.select,
          required: true,
          options: ['Individual', 'Equipe']),
      FieldDef('funcionario_id', 'Funcionário',
          type: FieldType.reference,
          refTable: 'funcionarios',
          refLabelOf: _lblFuncionario),
      FieldDef('equipe_id', 'Equipe',
          type: FieldType.reference,
          refTable: 'equipes',
          refLabelOf: _lblNome),
      FieldDef('talhao_id', 'Talhão',
          type: FieldType.reference,
          required: true,
          refTable: 'talhoes',
          refLabelOf: _lblTalhao),
      const FieldDef('data', 'Data', type: FieldType.date),
      const FieldDef('volume_total', 'Volume total (m³)',
          type: FieldType.decimal, suffix: 'm³'),
      const FieldDef('total_arvores', 'Total de árvores',
          type: FieldType.number),
      const FieldDef('observacoes', 'Observações',
          type: FieldType.multiline),
    ],
    titleOf: (m) => [
      if (_ref(m, 'equipe', 'nome').isNotEmpty) _ref(m, 'equipe', 'nome'),
      if (_ref(m, 'funcionario', 'nome').isNotEmpty)
        _ref(m, 'funcionario', 'nome'),
      if (_ref(m, 'talhao', 'codigo').isNotEmpty)
        'Talhão ${_ref(m, 'talhao', 'codigo')}',
    ].where((e) => e.isNotEmpty).join(' • '),
    subtitleOf: (m) => [
      _s(m, 'data'),
      _s(m, 'tipo_producao'),
      if (_i(m, 'total_arvores') > 0) '${_i(m, 'total_arvores')} árvores',
    ].where((e) => e.isNotEmpty).join(' • '),
    leadingOf: (m) => _iconAvatar(Icons.grass, BrandColors.forest),
    trailingOf: (m) => Text('${_d(m, 'volume_total').toStringAsFixed(1)} m³',
        style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: BrandColors.forest)),
    headerOf: (items) {
      final total = items.fold<double>(0, (s, m) => s + _d(m, 'volume_total'));
      final arvores =
          items.fold<int>(0, (s, m) => s + _i(m, 'total_arvores'));
      return Row(
        children: [
          Expanded(
              child: _MiniStat('Registros', '${items.length}', Icons.list_alt,
                  BrandColors.info)),
          const SizedBox(width: 12),
          Expanded(
              child: _MiniStat('Volume total',
                  '${total.toStringAsFixed(1)} m³', Icons.grass,
                  BrandColors.forest)),
          const SizedBox(width: 12),
          Expanded(
              child: _MiniStat('Árvores', '$arvores', Icons.park_outlined,
                  BrandColors.success)),
        ],
      );
    },
  ),
  'producao_funcionarios': EntityDef(
    table: 'producao_funcionarios',
    noun: 'participante',
    icon: Icons.person_outline,
    selectQuery:
        '*, funcionario:funcionarios!funcionario_id(nome, forma_remuneracao), producao:producao!producao_id(data, talhao:talhao_id(codigo), equipe:equipe_id(nome))',
    fields: const [],
    titleOf: (m) => _ref(m, 'funcionario', 'nome').isNotEmpty
        ? _ref(m, 'funcionario', 'nome')
        : 'Participante',
    subtitleOf: (m) => [
      _ref(m, 'funcionario', 'forma_remuneracao'),
      if (_d(m, 'valor_total') > 0)
        'R\$ ${_d(m, 'valor_total').toStringAsFixed(2)}',
      if (_d(m, 'quantidade_calculo') > 0)
        '${_d(m, 'quantidade_calculo').toStringAsFixed(0)} un',
    ].where((e) => e.isNotEmpty).join(' • '),
    leadingOf: (m) => _iconAvatar(Icons.person, BrandColors.forest),
    trailingOf: (m) {
      final participou = m['participou'] ?? true;
      if (participou == true) return null;
      return const StatusChip('Não participou', BrandColors.alert);
    },
  ),
  'transporte': EntityDef(
    table: 'transporte',
    noun: 'viagem',
    icon: Icons.route_outlined,
    selectQuery:
        '*, veiculo:veiculos!veiculo_id(nome), motorista:funcionarios!motorista_id(nome), cliente:clientes!cliente_id(nome), fazenda:fazendas!fazenda_id(nome)',
    fields: [
      FieldDef('veiculo_id', 'Veículo',
          type: FieldType.reference,
          required: true,
          refTable: 'veiculos',
          refLabelOf: _lblVeiculo),
      FieldDef('motorista_id', 'Motorista',
          type: FieldType.reference,
          refTable: 'funcionarios',
          refLabelOf: _lblFuncionario),
      FieldDef('fazenda_id', 'Origem (fazenda)',
          type: FieldType.reference,
          refTable: 'fazendas',
          refLabelOf: _lblNome),
      FieldDef('cliente_id', 'Destino (cliente)',
          type: FieldType.reference,
          refTable: 'clientes',
          refLabelOf: _lblNome),
      const FieldDef('volume_m3', 'Volume (m³)',
          type: FieldType.decimal, suffix: 'm³'),
      const FieldDef('frete', 'Valor do frete (R\$)',
          type: FieldType.decimal, suffix: 'R\$'),
      const FieldDef('data', 'Data'),
    ],
    titleOf: (m) => _ref(m, 'veiculo', 'nome').isNotEmpty
        ? _ref(m, 'veiculo', 'nome')
        : 'Viagem',
    subtitleOf: (m) {
      final rota = [_ref(m, 'fazenda', 'nome'), _ref(m, 'cliente', 'nome')]
          .where((e) => e.isNotEmpty)
          .join(' → ');
      final l2 = [
        if (_ref(m, 'motorista', 'nome').isNotEmpty)
          'Mot.: ${_ref(m, 'motorista', 'nome')}',
        if (_d(m, 'volume_m3') > 0) '${_d(m, 'volume_m3')} m³',
      ].join(' • ');
      return [rota, l2].where((e) => e.isNotEmpty).join('\n');
    },
    leadingOf: (m) => _iconAvatar(Icons.route, BrandColors.info),
    trailingOf: (m) => Text('R\$ ${_d(m, 'frete').toStringAsFixed(0)}',
        style: const TextStyle(
            fontWeight: FontWeight.w800, color: BrandColors.forest)),
  ),
  'lancamentos': EntityDef(
    table: 'lancamentos',
    noun: 'lançamento',
    icon: Icons.payments_outlined,
    selectQuery:
        '*, transporte:transporte!transporte_id(veiculo_id, frete)',
    fields: const [
      FieldDef('tipo', 'Tipo', type: FieldType.select, required: true, options: [
        'Receita',
        'Despesa',
      ]),
      FieldDef('descricao', 'Descrição', required: true),
      FieldDef('categoria', 'Categoria', type: FieldType.select, options: [
        'Venda de madeira',
        'Frete',
        'Combustível',
        'Salário',
        'Manutenção',
        'EPI / Ferramenta',
        'Outro',
      ]),
      FieldDef('data', 'Data'),
      FieldDef('valor', 'Valor (R\$)', type: FieldType.decimal, suffix: 'R\$'),
    ],
    titleOf: (m) => _s(m, 'descricao'),
    subtitleOf: (m) => [
      _s(m, 'tipo'),
      _s(m, 'categoria'),
      _s(m, 'data'),
    ].where((e) => e.isNotEmpty).join(' • '),
    leadingOf: (m) {
      final isReceita = _s(m, 'tipo') == 'Receita';
      return _iconAvatar(
          isReceita ? Icons.trending_up : Icons.trending_down,
          isReceita ? BrandColors.success : BrandColors.danger);
    },
    trailingOf: (m) => Text('R\$ ${_d(m, 'valor').toStringAsFixed(2)}',
        style: TextStyle(
            fontWeight: FontWeight.w800,
            color: _s(m, 'tipo') == 'Receita'
                ? BrandColors.success
                : BrandColors.danger)),
    headerOf: (items) {
      final receitas = items.fold<double>(
          0, (s, m) => _s(m, 'tipo') == 'Receita' ? s + _d(m, 'valor') : s);
      final despesas = items.fold<double>(
          0, (s, m) => _s(m, 'tipo') == 'Despesa' ? s + _d(m, 'valor') : s);
      return Row(
        children: [
          Expanded(
              child: _MiniStat('Receitas',
                  'R\$ ${receitas.toStringAsFixed(0)}', Icons.trending_up,
                  BrandColors.success)),
          const SizedBox(width: 12),
          Expanded(
              child: _MiniStat('Despesas',
                  'R\$ ${despesas.toStringAsFixed(0)}', Icons.trending_down,
                  BrandColors.danger)),
          const SizedBox(width: 12),
          Expanded(
              child: _MiniStat('Saldo',
                  'R\$ ${(receitas - despesas).toStringAsFixed(0)}',
                  Icons.account_balance_wallet, BrandColors.forest)),
        ],
      );
    },
  ),
};

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MiniStat(this.label, this.value, this.icon, this.color);
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 10),
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
