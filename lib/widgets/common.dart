import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Logo textual + ícone da marca SILVORA.
class BrandLogo extends StatelessWidget {
  final double size;
  final bool showTagline;
  final Color? color;
  final bool light;
  const BrandLogo(
      {super.key, this.size = 40, this.showTagline = false, this.color, this.light = false});

  @override
  Widget build(BuildContext context) {
    final c = color ?? (light ? Colors.white : Theme.of(context).colorScheme.onSurface);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/silvora_mark.png',
              width: size * 1.15,
              height: size * 1.15,
              fit: BoxFit.contain,
              color: light ? Colors.white : null,
            ),
            SizedBox(width: size * 0.22),
            Text(
              'SILVORA',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: size * 0.55,
                letterSpacing: 1.0,
                color: c,
              ),
            ),
          ],
        ),
        if (showTagline) ...[
          SizedBox(height: size * 0.2),
          Text(
            'Tecnologia para gestão florestal',
            style: TextStyle(
                fontSize: size * 0.26,
                color: c.withValues(alpha: 0.7),
                letterSpacing: 0.5),
          ),
        ],
      ],
    );
  }
}

/// Card de indicador do dashboard.
class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? delta;
  final Color color;
  final bool light;
  final Widget? bottom;
  final VoidCallback? onTap;
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.delta,
    required this.color,
    this.light = false,
    this.bottom,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = light ? color : Colors.white;
    final fg = light ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return Card(
      color: bg,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: light
                          ? Colors.white.withValues(alpha: 0.2)
                          : color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon,
                        color: light ? Colors.white : color, size: 22),
                  ),
                  const Spacer(),
                  if (delta != null)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: light
                            ? Colors.white.withValues(alpha: 0.2)
                            : color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(delta!,
                          style: TextStyle(
                              color: light ? Colors.white : color,
                              fontWeight: FontWeight.w700,
                              fontSize: 11)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: fg,
                      fontSize: 26)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      color: light
                          ? Colors.white.withValues(alpha: 0.8)
                          : fg.withValues(alpha: 0.6),
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              if (bottom != null) ...[
                const SizedBox(height: 14),
                bottom!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Cabeçalho de seção.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Flexible(
            child: Text(title,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface)),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: Text(action!),
              style: TextButton.styleFrom(
                foregroundColor: BrandColors.forest,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Card com estilo de alerta.
class AlertCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? action;
  final Color color;
  final VoidCallback? onAction;
  const AlertCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.color = BrandColors.danger,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 13)),
                  if (action != null) ...[
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: onAction,
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        minimumSize: const Size(0, 34),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(action!,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tile estilo lista moderna.
class ModernListTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final String? trailing;
  final VoidCallback? onTap;
  const ModernListTile({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.55),
                            fontSize: 12)),
                  ],
                ),
              ),
              if (trailing != null)
                Text(trailing!,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: BrandColors.forest)),
              if (onTap != null)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.chevron_right,
                      color: Colors.grey, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip de status colorido.
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const StatusChip(this.label, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Placeholder padrão para telas de módulo com "em breve".
void showEmBreve(BuildContext context, String acao) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('$acao — disponível na versão completa (protótipo).'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
