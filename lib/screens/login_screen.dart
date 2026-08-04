import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../config/supabase_config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _emailCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _emailCtrl.dispose();
    _senhaCtrl.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    // Modo mock só é permitido em desenvolvimento explícito (FLUTTER_ENV=dev).
    if (SupabaseConfig.isMockMode) {
      context.go('/dashboard');
      return;
    }
    if (!SupabaseConfig.isConfigured) {
      _erro('Servidor não configurado. Contate o administrador.');
      return;
    }
    if (_emailCtrl.text.trim().isEmpty || _senhaCtrl.text.isEmpty) {
      _erro('Preencha e-mail e senha.');
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.instance.signIn(_emailCtrl.text, _senhaCtrl.text);
      if (mounted) context.go('/dashboard');
    } catch (e) {
      _erro(AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cadastrar() async {
    if (SupabaseConfig.isMockMode) {
      showEmBreve(context, 'Cadastro indisponível no modo demonstração.');
      return;
    }
    if (!SupabaseConfig.isConfigured) {
      _erro('Servidor não configurado. Contate o administrador.');
      return;
    }
    final nomeCtrl = TextEditingController();
    final emailC = TextEditingController(text: _emailCtrl.text);
    final senhaC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Criar conta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nomeCtrl,
                decoration: const InputDecoration(labelText: 'Nome')),
            const SizedBox(height: 12),
            TextField(
                controller: emailC,
                decoration: const InputDecoration(labelText: 'E-mail')),
            const SizedBox(height: 12),
            TextField(
                controller: senhaC,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Senha (mín. 6)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cadastrar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      await AuthService.instance
          .signUp(emailC.text, senhaC.text, nome: nomeCtrl.text.trim());
      if (mounted) {
        _info('Conta criada! Verifique seu e-mail para confirmar (se exigido).');
      }
    } catch (e) {
      _erro(AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _esqueci() async {
    if (SupabaseConfig.isMockMode) {
      _erro('Recuperação de senha indisponível no modo demonstração.');
      return;
    }
    if (!SupabaseConfig.isConfigured) {
      _erro('Servidor não configurado. Contate o administrador.');
      return;
    }
    if (_emailCtrl.text.trim().isEmpty) {
      _erro('Digite seu e-mail para recuperar a senha.');
      return;
    }
    try {
      await AuthService.instance.resetPassword(_emailCtrl.text);
      _info('Enviamos um link de recuperação para seu e-mail.');
    } catch (e) {
      _erro(AuthService.friendlyError(e));
    }
  }

  void _erro(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: BrandColors.danger,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _info(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 900;
        final form = _buildForm(context, scheme);
        if (!wide) {
          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(children: [
                    const SizedBox(height: 20),
                    BrandLogo(size: 38, showTagline: true),
                    const SizedBox(height: 36),
                    form,
                  ]),
                ),
              ),
            ),
          );
        }
        return Row(children: [
          Expanded(child: _brandPanel()),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: form,
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _brandPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BrandColors.forestDark, BrandColors.forest],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30)),
              padding: const EdgeInsets.all(12),
              child: Image.asset('assets/silvora_mark.png',
                  fit: BoxFit.contain),
            ),
            const SizedBox(height: 24),
            const Text('SILVORA',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text('Tecnologia para gestão florestal',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bem-vindo de volta',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Acesse sua conta para continuar',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6))),
        if (SupabaseConfig.isMockMode) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: BrandColors.alert.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline,
                  color: BrandColors.alert, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Modo demonstração: qualquer login entra. '
                  'Use apenas em desenvolvimento.',
                  style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.8)),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
          ),
          child: TabBar(
            controller: _tab,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: scheme.onSurface.withValues(alpha: 0.7),
            tabs: const [
              Tab(text: 'E-mail'),
              Tab(text: 'CPF'),
              Tab(text: 'Telefone'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 76,
          child: TabBarView(
            controller: _tab,
            children: [
              _field(_emailCtrl, 'E-mail', Icons.mail_outline,
                  'nome@empresa.com',
                  keyboard: TextInputType.emailAddress),
              _field(_emailCtrl, 'CPF', Icons.badge_outlined,
                  '000.000.000-00'),
              _field(_emailCtrl, 'Telefone', Icons.phone_outlined,
                  '(00) 00000-0000'),
            ],
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _senhaCtrl,
          obscureText: _obscure,
          onSubmitted: (_) => _entrar(),
          decoration: InputDecoration(
            labelText: 'Senha',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _esqueci,
            child: const Text('Esqueci minha senha'),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _loading ? null : _entrar,
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white))
              : const Text('Entrar'),
        ),
        const SizedBox(height: 14),
        Row(children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('ou',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5))),
          ),
          const Expanded(child: Divider()),
        ]),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _loading ? null : _entrar,
          icon: const Icon(Icons.fingerprint, color: BrandColors.forest),
          label: const Text('Entrar com biometria'),
        ),
        const SizedBox(height: 20),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              Text('Não tem conta? ',
                  style:
                      TextStyle(color: scheme.onSurface.withValues(alpha: 0.7))),
              GestureDetector(
                onTap: _cadastrar,
                child: const Text('Cadastre-se',
                    style: TextStyle(
                        color: BrandColors.forest,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      String hint,
      {TextInputType? keyboard}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
    );
  }
}
