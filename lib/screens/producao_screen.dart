import 'package:flutter/material.dart';
import '../config/supabase_config.dart';
import '../data/mock_data.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class ProducaoScreen extends StatelessWidget {
  const ProducaoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isMockMode) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.construction, size: 48, color: BrandColors.alert),
              const SizedBox(height: 16),
              Text(
                'Produção em desenvolvimento',
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

    final data = MockData.producoes;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        Row(
          children: [
            Expanded(
              child: _miniStat('Hoje', '140,5 m³', Icons.today, BrandColors.forest),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _miniStat('Semana', '892 m³', Icons.date_range, BrandColors.info),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _miniStat('Mês', '3.284 m³', Icons.calendar_month, BrandColors.success),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const SectionHeader('Registros de produção'),
        ...data.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: BrandColors.forest.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.grass,
                                color: BrandColors.forest),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${p.equipe} • Talhão ${p.talhao}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15)),
                                Text(p.data,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6))),
                              ],
                            ),
                          ),
                          Text('${p.volumeM3.toStringAsFixed(1)} m³',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  color: BrandColors.forest)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _pill(Icons.park_outlined, '${p.arvores} árvores'),
                          const SizedBox(width: 8),
                          _pill(Icons.photo_camera_outlined, '4 fotos'),
                          const SizedBox(width: 8),
                          _pill(Icons.location_on_outlined, 'GPS ok'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )),
      ],
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 10),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 18)),
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
