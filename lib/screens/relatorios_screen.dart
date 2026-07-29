import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class RelatoriosScreen extends StatefulWidget {
  const RelatoriosScreen({super.key});

  @override
  State<RelatoriosScreen> createState() => _RelatoriosScreenState();
}

class _RelatoriosScreenState extends State<RelatoriosScreen> {
  late Future<RelatorioData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<RelatorioData> _load() async {
    try {
      final results = await Future.wait([
        Db.list('producao',
            select:
                '*, equipe:equipes!equipe_id(nome), talhao:talhoes!talhao_id(codigo), funcionario:funcionarios!funcionario_id(nome), producao_funcionarios(*, funcionario:funcionarios!funcionario_id(nome))'),
        Db.list('transporte', select: '*'),
        Db.list('lancamentos', select: '*'),
        Db.list('equipamentos', select: '*'),
        Db.list('estoque', select: '*'),
      ]);
      return RelatorioData(
        producoes: results[0],
        transporte: results[1],
        lancamentos: results[2],
        equipamentos: results[3],
        estoque: results[4],
      );
    } catch (_) {
      return RelatorioData.fallback();
    }
  }

  void _reload() => setState(() => _future = _load());

  void _mostrarRelatorio(BuildContext context, String tipo, RelatorioData data) {
    final hoje = DateTime.now();
    final hojeStr = hoje.toIso8601String().split('T').first;
    String periodo;
    List<Map<String, dynamic>> producoes;
    List<Map<String, dynamic>> transporte;
    List<Map<String, dynamic>> lancamentos;

    switch (tipo) {
      case 'Diário':
        periodo = hojeStr;
        producoes = data.producoes
            .where((m) => '${m['data']}'.startsWith(hojeStr))
            .toList();
        transporte = data.transporte
            .where((m) => '${m['data']}'.startsWith(hojeStr))
            .toList();
        lancamentos = data.lancamentos
            .where((m) => '${m['data']}'.startsWith(hojeStr))
            .toList();
        break;
      case 'Semanal':
        final inicio = hoje.subtract(Duration(days: hoje.weekday - 1));
        periodo =
            '${inicio.toIso8601String().split('T').first} a $hojeStr';
        producoes = data.producoes.where((m) {
          final d = '${m['data']}';
          return d.compareTo(inicio.toIso8601String().split('T').first) >= 0;
        }).toList();
        transporte = data.transporte.where((m) {
          final d = '${m['data']}';
          return d.compareTo(inicio.toIso8601String().split('T').first) >= 0;
        }).toList();
        lancamentos = data.lancamentos.where((m) {
          final d = '${m['data']}';
          return d.compareTo(inicio.toIso8601String().split('T').first) >= 0;
        }).toList();
        break;
      case 'Mensal':
        periodo =
            '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}';
        producoes = data.producoes
            .where((m) => '${m['data']}'.startsWith(periodo))
            .toList();
        transporte = data.transporte
            .where((m) => '${m['data']}'.startsWith(periodo))
            .toList();
        lancamentos = data.lancamentos
            .where((m) => '${m['data']}'.startsWith(periodo))
            .toList();
        break;
      case 'Anual':
      default:
        periodo = '${hoje.year}';
        producoes = data.producoes
            .where((m) => '${m['data']}'.startsWith(periodo))
            .toList();
        transporte = data.transporte
            .where((m) => '${m['data']}'.startsWith(periodo))
            .toList();
        lancamentos = data.lancamentos
            .where((m) => '${m['data']}'.startsWith(periodo))
            .toList();
    }

    final volume = producoes.fold<double>(
        0, (s, m) => s + (double.tryParse('${m['volume_total']}') ?? 0));
    final arvores = producoes.fold<int>(
        0, (s, m) => s + (int.tryParse('${m['total_arvores']}') ?? 0));
    final custoMaoObra = producoes.fold<double>(0, (s, m) {
      final pfs = m['producao_funcionarios'];
      if (pfs is List) {
        return s +
            pfs.fold<double>(
                0,
                (s2, p) =>
                    s2 + (double.tryParse('${p['valor_total']}') ?? 0));
      }
      return s;
    });
    final receitas = lancamentos
        .where((m) => '${m['tipo']}' == 'Receita')
        .fold<double>(0, (s, m) => s + (double.tryParse('${m['valor']}') ?? 0));
    final despesas = lancamentos
        .where((m) => '${m['tipo']}' == 'Despesa')
        .fold<double>(0, (s, m) => s + (double.tryParse('${m['valor']}') ?? 0));
    final frete = transporte.fold<double>(
        0, (s, m) => s + (double.tryParse('${m['frete']}') ?? 0));
    final manutencoes = data.equipamentos
        .where((m) => '${m['situacao']}' == 'Manutenção')
        .length;
    final estoqueBaixo = data.estoque.where((m) {
      final q = int.tryParse('${m['quantidade']}') ?? 0;
      final min = int.tryParse('${m['minimo']}') ?? 0;
      return q <= min && min > 0;
    }).length;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.all(20),
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
            Text('Relatório $tipo',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800)),
            Text('Período: $periodo',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            _relTile(Icons.grass, 'Volume produzido',
                '${volume.toStringAsFixed(1)} m³', BrandColors.forest),
            _relTile(Icons.park, 'Árvores cortadas', '$arvores',
                BrandColors.success),
            _relTile(Icons.people, 'Custo mão de obra',
                'R\$ ${custoMaoObra.toStringAsFixed(2)}', BrandColors.info),
            _relTile(Icons.attach_money, 'Receitas',
                'R\$ ${receitas.toStringAsFixed(2)}', BrandColors.success),
            _relTile(Icons.money_off, 'Despesas',
                'R\$ ${despesas.toStringAsFixed(2)}', BrandColors.danger),
            _relTile(Icons.account_balance_wallet, 'Saldo',
                'R\$ ${(receitas - despesas).toStringAsFixed(2)}',
                BrandColors.info),
            _relTile(Icons.local_shipping, 'Fretes',
                'R\$ ${frete.toStringAsFixed(2)}', BrandColors.alert),
            _relTile(Icons.build_circle, 'Manutenções pendentes',
                '$manutencoes', BrandColors.danger),
            _relTile(Icons.inventory_2, 'Itens com estoque baixo',
                '$estoqueBaixo', BrandColors.alert),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.pop(c),
              icon: const Icon(Icons.check),
              label: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _relTile(IconData icon, String label, String value, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(label, style: const TextStyle(fontSize: 13)),
        trailing: Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 15, color: color)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RelatorioData>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data ?? RelatorioData.fallback();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            const SectionHeader('Gerar relatório'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.7,
              children: [
                _reportCard(context, 'Diário', Icons.today, BrandColors.forest, data),
                _reportCard(context, 'Semanal', Icons.date_range, BrandColors.info, data),
                _reportCard(context, 'Mensal', Icons.calendar_month,
                    BrandColors.success, data),
                _reportCard(context, 'Anual', Icons.event_note, BrandColors.alert, data),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.ios_share, color: BrandColors.forest),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Exportar / compartilhar')),
                    _exp(context, Icons.picture_as_pdf, 'PDF'),
                    const SizedBox(width: 8),
                    _exp(context, Icons.grid_on, 'Excel'),
                    const SizedBox(width: 8),
                    _exp(context, Icons.chat, 'WhatsApp'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader('Notificações do sistema'),
            if (snap.connectionState != ConnectionState.done)
              const Center(child: CircularProgressIndicator())
            else
              ..._buildNotificacoes(data).map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AlertCard(
                      icon: a.icon,
                      title: a.titulo,
                      subtitle: a.descricao,
                      color: a.cor,
                    ),
                  )),
          ],
        );
      },
    );
  }

  List<_Notify> _buildNotificacoes(RelatorioData data) {
    final list = <_Notify>[];
    for (final m in data.estoque) {
      final q = int.tryParse('${m['quantidade']}') ?? 0;
      final min = int.tryParse('${m['minimo']}') ?? 0;
      if (q <= min && min > 0) {
        list.add(_Notify(
          icon: Icons.inventory_2_outlined,
          titulo: 'Estoque baixo: ${m['nome']}',
          descricao: 'Restam apenas $q unidades.',
          cor: BrandColors.danger,
        ));
      }
    }
    for (final m in data.equipamentos) {
      if ('${m['situacao']}' == 'Manutenção') {
        list.add(_Notify(
          icon: Icons.build_circle_outlined,
          titulo: 'Manutenção pendente',
          descricao: '${m['nome']} precisa de revisão',
          cor: BrandColors.alert,
        ));
      }
    }
    if (list.isEmpty) {
      list.add(_Notify(
        icon: Icons.check_circle_outline,
        titulo: 'Tudo sob controle',
        descricao: 'Não há alertas no momento.',
        cor: BrandColors.success,
      ));
    }
    return list;
  }

  Widget _reportCard(BuildContext context, String label, IconData icon,
      Color color, RelatorioData data) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _mostrarRelatorio(context, label, data),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 10),
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              const Text('Toque para gerar',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _exp(BuildContext context, IconData icon, String label) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: () => _mostrarExportar(context, label),
    );
  }

  void _mostrarExportar(BuildContext context, String formato) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Exportar $formato'),
        content: Text(
            'Na versão web, a exportação em $formato será gerada a partir dos dados reais do banco.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('OK')),
        ],
      ),
    );
  }
}

class RelatorioData {
  final List<Map<String, dynamic>> producoes;
  final List<Map<String, dynamic>> transporte;
  final List<Map<String, dynamic>> lancamentos;
  final List<Map<String, dynamic>> equipamentos;
  final List<Map<String, dynamic>> estoque;

  RelatorioData({
    required this.producoes,
    required this.transporte,
    required this.lancamentos,
    required this.equipamentos,
    required this.estoque,
  });

  factory RelatorioData.fallback() => RelatorioData(
        producoes: const [],
        transporte: const [],
        lancamentos: const [],
        equipamentos: const [],
        estoque: const [],
      );
}

class _Notify {
  final IconData icon;
  final String titulo;
  final String descricao;
  final Color cor;
  _Notify({
    required this.icon,
    required this.titulo,
    required this.descricao,
    required this.cor,
  });
}
