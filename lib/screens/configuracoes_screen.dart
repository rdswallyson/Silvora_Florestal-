import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class ConfiguracoesScreen extends StatefulWidget {
  const ConfiguracoesScreen({super.key});
  @override
  State<ConfiguracoesScreen> createState() => _ConfiguracoesScreenState();
}

class _ConfiguracoesScreenState extends State<ConfiguracoesScreen> {
  bool _notif = true;
  bool _sync = true;
  bool _biometria = true;
  bool _loading = true;
  bool _saving = false;

  final _nomeCtrl = TextEditingController();
  final _empresaCtrl = TextEditingController();
  final _telefoneCtrl = TextEditingController();
  final _cidadeCtrl = TextEditingController();
  final _estadoCtrl = TextEditingController();
  final _cpfCtrl = TextEditingController();
  final _cargoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _empresaCtrl.dispose();
    _telefoneCtrl.dispose();
    _cidadeCtrl.dispose();
    _estadoCtrl.dispose();
    _cpfCtrl.dispose();
    _cargoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final client = Supabase.instance.clientOrNull;
    if (client == null || !SupabaseConfig.isConfigured) {
      setState(() => _loading = false);
      return;
    }
    final user = AuthService.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final res = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (res != null && mounted) {
        setState(() {
          _nomeCtrl.text = (res['full_name'] ?? '').toString();
          _empresaCtrl.text = (res['empresa'] ?? '').toString();
          _telefoneCtrl.text = (res['telefone'] ?? '').toString();
          _cidadeCtrl.text = (res['cidade'] ?? '').toString();
          _estadoCtrl.text = (res['estado'] ?? '').toString();
          _cpfCtrl.text = (res['cpf'] ?? '').toString();
          _cargoCtrl.text = (res['cargo'] ?? '').toString();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('Erro ao carregar perfil: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    final client = Supabase.instance.clientOrNull;
    if (client == null || !SupabaseConfig.isConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supabase não configurado.')),
        );
      }
      return;
    }
    final user = AuthService.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuário não autenticado.')),
        );
      }
      return;
    }
    setState(() => _saving = true);
    try {
      await client.from('profiles').upsert({
        'id': user.id,
        'full_name': _nomeCtrl.text.trim(),
        'empresa': _empresaCtrl.text.trim(),
        'telefone': _telefoneCtrl.text.trim(),
        'cidade': _cidadeCtrl.text.trim(),
        'estado': _estadoCtrl.text.trim(),
        'cpf': _cpfCtrl.text.trim(),
        'cargo': _cargoCtrl.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      AppState.instance.updateUserName(_nomeCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil salvo com sucesso.')),
        );
      }
    } catch (e) {
      debugPrint('Erro ao salvar perfil: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar perfil: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final email = AuthService.instance.currentUser?.email ?? '';
    final initials = email.isNotEmpty
        ? email.split('@').first.substring(0, 1).toUpperCase()
        : '?';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: BrandColors.forest,
                  child: Text(initials,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(app.userName,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(email,
                          style: const TextStyle(color: Colors.grey)),
                      const Text('SILVORA',
                          style:
                              TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _group('Meu perfil', [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _field('Nome completo', _nomeCtrl),
                  _field('Empresa', _empresaCtrl),
                  _field('Cargo', _cargoCtrl),
                  _field('CPF', _cpfCtrl),
                  _field('Telefone', _telefoneCtrl),
                  _field('Cidade', _cidadeCtrl),
                  _field('Estado', _estadoCtrl),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _saveProfile,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Salvando...' : 'Salvar perfil'),
                  ),
                ],
              ),
            ),
        ]),
        _group('Aparência', [
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Modo escuro'),
            subtitle: const Text('Ideal para uso noturno'),
            value: app.isDark,
            onChanged: (_) => setState(() => app.toggleTheme()),
          ),
        ]),
        _group('Preferências', [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Notificações'),
            value: _notif,
            onChanged: (v) => setState(() => _notif = v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.sync),
            title: const Text('Sincronização automática'),
            subtitle: const Text('Sincroniza quando houver internet'),
            value: _sync,
            onChanged: (v) => setState(() => _sync = v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Login por biometria'),
            value: _biometria,
            onChanged: (v) => setState(() => _biometria = v),
          ),
        ]),
        _group('Sistema', [
          _navTile(context, Icons.backup_outlined, 'Backup de dados'),
          _navTile(context, Icons.shield_outlined, 'Segurança e auditoria'),
        ]),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            if (SupabaseConfig.isConfigured &&
                Supabase.instance.clientOrNull != null) {
              try {
                await AuthService.instance.signOut();
              } catch (e) {
                debugPrint('Erro ao sair: $e');
              }
            }
            if (context.mounted) context.go('/login');
          },
          style: OutlinedButton.styleFrom(foregroundColor: BrandColors.danger),
          icon: const Icon(Icons.logout),
          label: const Text('Sair da conta'),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text('SILVORA • v1.0.0',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _group(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title),
          Card(child: Column(children: children)),
        ],
      ),
    );
  }

  Widget _navTile(BuildContext context, IconData icon, String title,
      {String? trailing}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null)
            Text(trailing, style: const TextStyle(color: Colors.grey)),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => showEmBreve(context, title),
    );
  }
}
