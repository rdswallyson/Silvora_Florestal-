import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../state/app_state.dart';
import '../services/auth_service.dart';
import 'common.dart';

class NavItem {
  final String route;
  final String label;
  final IconData icon;
  const NavItem(this.route, this.label, this.icon);
}

const kNavItems = <NavItem>[
  NavItem('/dashboard', 'Início', Icons.dashboard_outlined),
  NavItem('/producao', 'Produção', Icons.grass_outlined),
  NavItem('/consulta-producao', 'Consulta de Produção', Icons.search_outlined),
  NavItem('/funcionarios', 'Funcionários', Icons.badge_outlined),
  NavItem('/equipes', 'Equipes', Icons.groups_outlined),
  NavItem('/fazendas', 'Fazendas', Icons.terrain_outlined),
  NavItem('/talhoes', 'Talhões', Icons.forest_outlined),
  NavItem('/veiculos', 'Veículos', Icons.local_shipping_outlined),
  NavItem('/transporte', 'Transporte', Icons.route_outlined),
  NavItem('/clientes', 'Clientes', Icons.handshake_outlined),
  NavItem('/equipamentos', 'Equipamentos', Icons.handyman_outlined),
  NavItem('/estoque', 'Estoque', Icons.inventory_2_outlined),
  NavItem('/financeiro', 'Financeiro', Icons.payments_outlined),
  NavItem('/gps', 'GPS / Mapa', Icons.map_outlined),
  NavItem('/relatorios', 'Relatórios', Icons.summarize_outlined),
  NavItem('/ia', 'SILVORA IA', Icons.auto_awesome_outlined),
  NavItem('/configuracoes', 'Configurações', Icons.settings_outlined),
];

class AppShell extends StatelessWidget {
  final Widget child;
  final String location;
  const AppShell({super.key, required this.child, required this.location});

  int get _index {
    final i = kNavItems.indexWhere((e) => location.startsWith(e.route));
    return i < 0 ? 0 : i;
  }

  String get _title {
    final i = _index;
    return kNavItems[i].label == 'Início'
        ? 'SILVORA'
        : kNavItems[i].label;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1000;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: wide
          ? null
          : AppBar(
              title: Text(_title),
              actions: [
                IconButton(
                  tooltip: 'Notificações',
                  icon: Badge(
                    label: const Text('4'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                  onPressed: () => context.go('/relatorios'),
                ),
                IconButton(
                  tooltip: 'Alternar tema',
                  icon: Icon(AppState.instance.isDark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined),
                  onPressed: () => AppState.instance.toggleTheme(),
                ),
                const SizedBox(width: 4),
                const _UserAvatar(),
                const SizedBox(width: 12),
              ],
            ),
      drawer: wide ? null : _DrawerContent(index: _index),
      body: Row(
        children: [
          if (wide)
            SizedBox(width: 280, child: _DrawerContent(index: _index)),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar();
  @override
  Widget build(BuildContext context) {
    final email = AuthService.instance.currentUser?.email ?? '';
    final initials = email.isNotEmpty
        ? email.split('@').first.substring(0, 1).toUpperCase()
        : '?';
    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'sair') context.go('/login');
        if (v == 'perfil') context.go('/configuracoes');
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'perfil', child: Text('Meu perfil')),
        PopupMenuItem(value: 'sair', child: Text('Sair')),
      ],
      child: CircleAvatar(
        radius: 18,
        backgroundColor: BrandColors.forest,
        child: Text(initials,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _DrawerContent extends StatelessWidget {
  final int index;
  const _DrawerContent({required this.index});

  @override
  Widget build(BuildContext context) {
    final isDark = AppState.instance.isDark;
    final bg = isDark ? BrandColors.graySurface : BrandColors.forestDark;
    final selectedColor = BrandColors.alert;
    final unselectedText = Colors.white.withValues(alpha: 0.75);

    return Drawer(
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      backgroundColor: bg,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Row(
                children: [
                  Image.asset(
                    'assets/silvora_mark.png',
                    width: 42,
                    height: 42,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SILVORA',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2)),
                      Text('GESTÃO FLORESTAL',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.6),
                              letterSpacing: 1.5)),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                itemCount: kNavItems.length,
                itemBuilder: (context, i) {
                  final item = kNavItems[i];
                  final selected = i == index;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Material(
                      color: selected ? selectedColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        leading: Icon(item.icon,
                            size: 22,
                            color: selected
                                ? Colors.white
                                : unselectedText),
                        title: Text(item.label,
                            style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? Colors.white
                                    : unselectedText)),
                        trailing: Icon(Icons.chevron_right,
                            size: 18,
                            color: selected
                                ? Colors.white.withValues(alpha: 0.8)
                                : unselectedText.withValues(alpha: 0.4)),
                        onTap: () {
                          if (Scaffold.of(context).hasDrawer &&
                              Scaffold.of(context).isDrawerOpen) {
                            Navigator.of(context).pop();
                          }
                          context.go(item.route);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: BrandColors.forestLight,
                    child: _initials(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_userName(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                        Text('Administrador',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout,
                        color: Colors.white70, size: 20),
                    onPressed: () => context.go('/login'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _initials() {
    final email = AuthService.instance.currentUser?.email ?? '';
    final name = email.split('@').first;
    final initials = name.isNotEmpty
        ? name.substring(0, 1).toUpperCase()
        : '?';
    return Text(initials,
        style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15));
  }

  String _userName() {
    final email = AuthService.instance.currentUser?.email ?? 'Usuário';
    return email.split('@').first;
  }
}
