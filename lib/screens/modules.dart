import 'package:flutter/material.dart';
import '../config/supabase_config.dart';
import '../data/mock_data.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class _ListScaffold extends StatelessWidget {
  final int count;
  final Widget Function(BuildContext, int) itemBuilder;
  final String? searchHint;
  const _ListScaffold(
      {required this.count, required this.itemBuilder, this.searchHint});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: searchHint ?? 'Buscar...',
              prefixIcon: const Icon(Icons.search),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            itemCount: count,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: itemBuilder,
          ),
        ),
      ],
    );
  }
}

Widget _disabledInProduction(BuildContext context, String nome) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.construction, size: 48, color: BrandColors.alert),
          const SizedBox(height: 16),
          Text(
            '$nome em desenvolvimento',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Esta tela usa dados de demonstração e está disponível apenas no modo de desenvolvimento.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    ),
  );
}

Widget _tile({
  required Widget leading,
  required String title,
  required String subtitle,
  Widget? trailing,
}) {
  return Builder(builder: (context) {
    return Card(
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
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6))),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  });
}

// ---------------- Funcionários ----------------
class FuncionariosScreen extends StatelessWidget {
  const FuncionariosScreen({super.key});
  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isMockMode) return _disabledInProduction(context, 'Funcionários');
    final data = MockData.funcionarios;
    return _ListScaffold(
      searchHint: 'Buscar funcionário...',
      count: data.length,
      itemBuilder: (context, i) {
        final f = data[i];
        final ativo = f.situacao == 'Ativo';
        return _tile(
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: BrandColors.forest.withValues(alpha: 0.15),
            child: Text(f.iniciais,
                style: const TextStyle(
                    color: BrandColors.forest, fontWeight: FontWeight.w700)),
          ),
          title: f.nome,
          subtitle: '${f.cargo} • ${f.telefone}',
          trailing: StatusChip(f.situacao,
              ativo ? BrandColors.success : BrandColors.alert),
        );
      },
    );
  }
}

// ---------------- Equipes ----------------
class EquipesScreen extends StatelessWidget {
  const EquipesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isMockMode) return _disabledInProduction(context, 'Equipes');
    final data = MockData.equipes;
    return _ListScaffold(
      searchHint: 'Buscar equipe...',
      count: data.length,
      itemBuilder: (context, i) {
        final e = data[i];
        return _tile(
          leading: const CircleAvatar(
            radius: 24,
            backgroundColor: BrandColors.forest,
            child: Icon(Icons.groups, color: Colors.white),
          ),
          title: e.nome,
          subtitle:
              'Líder: ${e.lider} • ${e.integrantes} membros\n${e.caminhao} • ${e.area}',
        );
      },
    );
  }
}

// ---------------- Fazendas ----------------
class FazendasScreen extends StatelessWidget {
  const FazendasScreen({super.key});
  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isMockMode) return _disabledInProduction(context, 'Fazendas');
    final data = MockData.fazendas;
    return _ListScaffold(
      searchHint: 'Buscar fazenda...',
      count: data.length,
      itemBuilder: (context, i) {
        final f = data[i];
        return _tile(
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: BrandColors.info.withValues(alpha: 0.15),
            child: const Icon(Icons.terrain, color: BrandColors.info),
          ),
          title: 'Faz. ${f.nome}',
          subtitle:
              '${f.proprietario}\n${f.municipio}/${f.uf} • ${f.areaHa.toStringAsFixed(0)} ha',
        );
      },
    );
  }
}

// ---------------- Talhões ----------------
class TalhoesScreen extends StatelessWidget {
  const TalhoesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isMockMode) return _disabledInProduction(context, 'Talhões');
    final data = MockData.talhoes;
    return _ListScaffold(
      searchHint: 'Buscar talhão...',
      count: data.length,
      itemBuilder: (context, i) {
        final t = data[i];
        final cor = t.situacao == 'Pronto p/ corte'
            ? BrandColors.success
            : t.situacao == 'Em corte'
                ? BrandColors.alert
                : BrandColors.info;
        return _tile(
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: BrandColors.forest.withValues(alpha: 0.15),
            child: Text(t.codigo,
                style: const TextStyle(
                    color: BrandColors.forest,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ),
          title: '${t.especie} • ${t.codigo}',
          subtitle:
              '${t.idadeAnos} anos • ${t.areaHa} ha • ${t.volumeM3.toStringAsFixed(0)} m³',
          trailing: StatusChip(t.situacao, cor),
        );
      },
    );
  }
}

// ---------------- Transporte ----------------
class TransporteScreen extends StatelessWidget {
  const TransporteScreen({super.key});
  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isMockMode) return _disabledInProduction(context, 'Transporte');
    final data = MockData.transportes;
    return _ListScaffold(
      searchHint: 'Buscar viagem...',
      count: data.length,
      itemBuilder: (context, i) {
        final t = data[i];
        return _tile(
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: BrandColors.info.withValues(alpha: 0.15),
            child: const Icon(Icons.local_shipping, color: BrandColors.info),
          ),
          title: t.caminhao,
          subtitle: '${t.origem} → ${t.destino}\n${t.volumeM3} m³',
          trailing: Text('R\$ ${t.frete.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: BrandColors.forest)),
        );
      },
    );
  }
}

// ---------------- Clientes ----------------
class ClientesScreen extends StatelessWidget {
  const ClientesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isMockMode) return _disabledInProduction(context, 'Clientes');
    final data = MockData.clientes;
    return _ListScaffold(
      searchHint: 'Buscar cliente...',
      count: data.length,
      itemBuilder: (context, i) {
        final c = data[i];
        return _tile(
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: BrandColors.forest.withValues(alpha: 0.15),
            child: const Icon(Icons.handshake, color: BrandColors.forest),
          ),
          title: c.nome,
          subtitle: '${c.tipo} • ${c.cidade}',
          trailing: c.pendencia > 0
              ? StatusChip('Pend. R\$ ${c.pendencia.toStringAsFixed(0)}',
                  BrandColors.danger)
              : const StatusChip('Em dia', BrandColors.success),
        );
      },
    );
  }
}

// ---------------- Equipamentos ----------------
class EquipamentosScreen extends StatelessWidget {
  const EquipamentosScreen({super.key});
  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isMockMode) return _disabledInProduction(context, 'Equipamentos');
    final data = MockData.equipamentos;
    return _ListScaffold(
      searchHint: 'Buscar equipamento...',
      count: data.length,
      itemBuilder: (context, i) {
        final e = data[i];
        final cor = e.situacao == 'Operando'
            ? BrandColors.success
            : BrandColors.alert;
        return _tile(
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: cor.withValues(alpha: 0.15),
            child: Icon(Icons.handyman, color: cor),
          ),
          title: e.nome,
          subtitle: '${e.tipo} • ${e.horas}h trabalhadas',
          trailing: StatusChip(e.situacao, cor),
        );
      },
    );
  }
}

// ---------------- Estoque ----------------
class EstoqueScreen extends StatelessWidget {
  const EstoqueScreen({super.key});
  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isMockMode) return _disabledInProduction(context, 'Estoque');
    final data = MockData.estoque;
    return _ListScaffold(
      searchHint: 'Buscar item...',
      count: data.length,
      itemBuilder: (context, i) {
        final it = data[i];
        return _tile(
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: (it.baixo ? BrandColors.danger : BrandColors.forest)
                .withValues(alpha: 0.15),
            child: Icon(Icons.inventory_2,
                color: it.baixo ? BrandColors.danger : BrandColors.forest),
          ),
          title: it.nome,
          subtitle: 'Mínimo: ${it.minimo} ${it.unidade}',
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${it.quantidade} ${it.unidade}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              if (it.baixo)
                const Text('Estoque baixo',
                    style: TextStyle(
                        color: BrandColors.danger,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
            ],
          ),
        );
      },
    );
  }
}
