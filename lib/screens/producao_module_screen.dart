import 'package:flutter/material.dart';
import '../data/entities.dart';
import '../theme/app_theme.dart';
import 'consulta_producao_screen.dart';
import 'entity_list_screen.dart';

/// Módulo Produção com duas abas: Registros e Consulta.
class ProducaoModuleScreen extends StatefulWidget {
  const ProducaoModuleScreen({super.key});

  @override
  State<ProducaoModuleScreen> createState() => _ProducaoModuleScreenState();
}

class _ProducaoModuleScreenState extends State<ProducaoModuleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Produção'),
        backgroundColor: BrandColors.forest,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.7),
          tabs: const [
            Tab(icon: Icon(Icons.format_list_bulleted), text: 'Registros'),
            Tab(icon: Icon(Icons.search), text: 'Consulta'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          EntityListScreen(kEntities['producao']!),
          const ConsultaProducaoScreen(),
        ],
      ),
    );
  }
}
