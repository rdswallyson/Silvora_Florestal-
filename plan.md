# Plano de Auditoria de Segurança — Bypass de Autenticação SILVORA

> Status: **Aguardando aprovação do usuário antes de qualquer alteração de código.**
> Data: 2026-07-29
> Escopo: `lib/config/supabase_config.dart`, `lib/main.dart`, `lib/state/app_state.dart`, `lib/services/auth_service.dart`, `lib/services/db_service.dart`, `lib/routing/app_router.dart`, `lib/screens/splash_screen.dart`, `lib/screens/login_screen.dart`, `lib/screens/configuracoes_screen.dart`, `lib/screens/modules.dart`, `lib/screens/producao_screen.dart`, `lib/data/mock_data.dart`.

---

## 1. Resumo Executivo

O app SILVORA possui **caminhos explícitos de bypass de autenticação** que são ativados quando a configuração do Supabase não é detectada (`SupabaseConfig.isConfigured == false`). Esse comportamento foi criado propositalmente para testes/demonstração, mas **não está isolado em ambiente de desenvolvimento**: em um build de produção na Vercel, se a variável de ambiente `SUPABASE_PUBLISHABLE_KEY` não for injetada ou se o valor default for aceito, o app abre como "modo demonstração", permitindo acesso a todas as telas e ações sem login real.

Além disso, telas legadas (`modules.dart`, `producao_screen.dart`) usam `MockData` fixo e **não verificam autenticação**, embora atualmente não estejam roteadas no `app_router.dart` (usam `EntityListScreen` no lugar). Isso representa um risco residual se alguma dessas telas for reativada.

---

## 2. Código Envolvido e Condições de Bypass

### 2.1 `lib/config/supabase_config.dart`

```dart
static const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://jkwnynwxxfesaagifkhq.supabase.co',
);

static const String supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_JUUrV_RGS8Cjp3x8r1R5gw_CBVlaygw',
);

static bool get isConfigured =>
    supabaseUrl.startsWith('http') &&
    supabasePublishableKey.length > 20 &&
    !supabasePublishableKey.contains('COLE_AQUI');
```

**Condição de bypass:** `isConfigured` é `true` se houver qualquer URL http e chave com mais de 20 caracteres. O `defaultValue` real do projeto satisfaz essa condição, então **o bypass NUNCA é acionado por ausência de variável de ambiente** no build padrão.

**Risco em produção:**
- **Baixo** para o caso "variável ausente", porque o default já preenche.
- **Alto** para o caso "chave inválida/expirada/alterada": se o valor da variável de ambiente for uma string longa mas incorreta, `isConfigured` ainda será `true`, `Supabase.initialize()` será chamado e **falhará silenciosamente ou em runtime**, e o app continuará rodando. Não há captura de exceção em `main()`.
- **Alto** para o caso "URL malformada": `isConfigured` pode ser `false` se a URL não começar com `http`, mas isso só acontece se a variável de ambiente for deliberadamente alterada para algo curto/errado.

### 2.2 `lib/main.dart`

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      publishableKey: SupabaseConfig.supabasePublishableKey,
    );
  }
  runApp(const RdsPhorestalApp());
}
```

**Condição de bypass:** se `isConfigured == false`, o Supabase não é inicializado, mas o app roda normalmente.

**Risco em produção:**
- Se `Supabase.initialize()` lançar exceção (chave inválida, timeout de rede, resposta inesperada), a exceção **não é capturada**. Isso pode causar:
  - Crash na inicialização (melhor cenário de segurança, pois nega acesso).
  - Ou, dependendo do erro, inicialização parcial que permite bypass.
- Atualmente, como `isConfigured` é `true` no default, `Supabase.initialize()` sempre é chamado. Se a chave estiver errada, o app pode crashar ao tentar usá-la, o que é melhor do que permitir acesso, mas a UX é ruim (tela branca/travada).

### 2.3 `lib/routing/app_router.dart`

```dart
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    if (SupabaseConfig.isConfigured) {
      _sub = AuthService.instance.onAuthStateChange.listen((_) {
        notifyListeners();
      });
    }
  }
  ...
}

final appRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: _AuthRefresh(),
  redirect: (context, state) {
    // Sem Supabase configurado: sem guarda (modo demonstração).
    if (!SupabaseConfig.isConfigured) return null;
    final loggedIn = AuthService.instance.isLoggedIn;
    final loc = state.uri.path;
    final onSplash = loc == '/';
    final onLogin = loc == '/login';
    if (onSplash) return null;
    if (!loggedIn && !onLogin) return '/login';
    if (loggedIn && onLogin) return '/dashboard';
    return null;
  },
  ...
);
```

**Condição de bypass:** quando `!SupabaseConfig.isConfigured`, o `redirect` retorna `null` para qualquer rota, desativando completamente o guarda de autenticação.

**Risco em produção:**
- **Alto** se `isConfigured` for `false` por qualquer motivo: qualquer pessoa acessa `/dashboard`, `/producao`, `/financeiro`, `/relatorios`, `/configuracoes`, etc.
- `_AuthRefresh` não escuta mudanças de auth no modo não-configurado, então transições de login não são monitoradas — isso é consistente com o bypass, mas é uma falha de design.

### 2.4 `lib/screens/splash_screen.dart`

```dart
Future.delayed(const Duration(milliseconds: 2200), () {
  if (!mounted) return;
  if (SupabaseConfig.isConfigured && AuthService.instance.isLoggedIn) {
    context.go('/dashboard');
  } else {
    context.go('/login');
  }
});
```

**Condição de bypass:** se `isConfigured == false`, sempre redireciona para `/login`.

**Risco em produção:**
- O redirect em `app_router.dart` já desarma o guarda quando `isConfigured == false`, então mesmo indo para `/login`, o usuário pode navegar manualmente para qualquer rota.
- Se `isConfigured == true` mas `Supabase.instance.client` não estiver inicializado (exceção em `main`), `AuthService.instance.isLoggedIn` acessará `Supabase.instance.client` e **lançará `StateError` (client not initialized)**. Isso pode travar a splash ou gerar tela vermelha.

### 2.5 `lib/screens/login_screen.dart`

```dart
Future<void> _entrar() async {
  // Sem credenciais configuradas: fluxo de demonstração (mock).
  if (!SupabaseConfig.isConfigured) {
    context.go('/dashboard');
    return;
  }
  ...
}

Future<void> _cadastrar() async {
  if (!SupabaseConfig.isConfigured) {
    showEmBreve(context, 'Cadastro (configure o Supabase)');
    return;
  }
  ...
}

Future<void> _esqueci() async {
  if (!SupabaseConfig.isConfigured) {
    showEmBreve(context, 'Recuperação de senha (configure o Supabase)');
    return;
  }
  ...
}
```

E no build:

```dart
if (!SupabaseConfig.isConfigured) ...[
  const SizedBox(height: 12),
  Container(
    ...
    child: Text(
      'Modo demonstração: qualquer login entra. '
      'Configure o Supabase para login real.',
      ...
    ),
  ),
],
```

**Condição de bypass:** ao pressionar "Entrar" com `isConfigured == false`, o app vai direto para `/dashboard` sem validar campos.

**Risco em produção:**
- **Alto** se `isConfigured == false`. Qualquer pessoa entra com um clique.
- O botão "Entrar com biometria" também chama `_entrar()`, então também bypassa.
- Cadastro e recuperação de senha são bloqueados visualmente, mas isso é irrelevante porque o login principal está aberto.

### 2.6 `lib/services/auth_service.dart`

```dart
SupabaseClient get _client => Supabase.instance.client;

User? get currentUser => _client.auth.currentUser;
bool get isLoggedIn => currentUser != null;

Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;
```

**Condição de bypass:** não há bypass direto aqui, mas **não há proteção contra `Supabase.instance.client` não inicializado**. Se `main()` não inicializou o Supabase, qualquer acesso a `_client` lança `StateError`.

**Risco em produção:**
- **Médio/Alto**: se `main()` falhar silenciosamente ou `isConfigured` oscilar, o app pode crashar em vez de mostrar erro amigável.
- `friendlyError` usa `kDebugMode` para decidir se expõe a mensagem técnica. Em release, a mensagem é genérica, o que é bom, mas não resolve o bypass.

### 2.7 `lib/services/db_service.dart`

```dart
static SupabaseClient get _c => Supabase.instance.client;
```

**Condição de bypass:** como `Db` acessa `Supabase.instance.client` diretamente, se o cliente não estiver inicializado, todas as operações de CRUD falham com exceção.

**Risco em produção:**
- **Baixo para segurança** (falha fechada), mas **alto para UX** (telas quebradas, listas vazias, botões sem ação).
- Não há fallback para mock no `Db`, o que é positivo do ponto de vista de segurança.

### 2.8 `lib/screens/configuracoes_screen.dart`

```dart
Future<void> _loadProfile() async {
  if (!SupabaseConfig.isConfigured) {
    setState(() => _loading = false);
    return;
  }
  ...
}

Future<void> _saveProfile() async {
  if (!SupabaseConfig.isConfigured) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supabase não configurado.')),
      );
    }
    return;
  }
  ...
}

OutlinedButton.icon(
  onPressed: () async {
    if (SupabaseConfig.isConfigured) {
      await AuthService.instance.signOut();
    }
    if (context.mounted) context.go('/login');
  },
  icon: const Icon(Icons.logout),
  label: const Text('Sair da conta'),
),
```

**Condição de bypass:**
- Perfil não carrega se não configurado (aceitável).
- Salvamento é bloqueado (aceitável).
- Logout: se não configurado, apenas redireciona para `/login`. Não há sessão real para encerrar.

**Risco em produção:**
- **Médio**: em modo não-configurado, o botão "Sair da conta" dá a falsa impressão de segurança, mas nunca houve sessão. Se o usuário voltar ao `/dashboard` pela URL, entra novamente.
- O cabeçalho mostra `email = AuthService.instance.currentUser?.email ?? ''`, que pode lançar exceção se `Supabase.instance.client` não estiver inicializado.

### 2.9 Telas legadas com mock fixo

Arquivos:
- `lib/screens/modules.dart` — importa `MockData` e renderiza listas fake para funcionários, equipes, fazendas, talhões, transportes, clientes, equipamentos, estoque.
- `lib/screens/producao_screen.dart` — importa `MockData.producoes`.

**Condição de bypass:** essas telas **não verificam autenticação**. Elas não estão atualmente no roteamento do `app_router.dart` (substituídas por `EntityListScreen`), mas permanecem no código.

**Risco em produção:**
- **Médio**: se reintroduzidas no roteamento por engano, expõem dados mock sem autenticação.
- **Baixo**: enquanto não forem roteadas, são código morto, mas aumentam a superfície de ataque.

### 2.10 `lib/state/app_state.dart`

```dart
class AppState extends ChangeNotifier {
  static final AppState instance = AppState._();
  AppState._();

  ThemeMode _themeMode = ThemeMode.light;
  ...

  String userName = 'João Pereira';
  String userRole = 'Gerente';
}
```

**Condição de bypass:** `AppState` não armazena estado de autenticação. Os valores `userName` e `userRole` são fixos e usados na UI.

**Risco em produção:**
- **Baixo/Médio**: mesmo sem autenticação, a tela mostra "João Pereira / Gerente", reforçando a falsa sensação de que alguém está logado.
- Não há risco de acesso direto aqui, mas contribui para a confusão de UX no modo mock.

---

## 3. Matriz de Risco

| Cenário | Pode ocorrer em produção? | Severidade | Motivo |
|---------|---------------------------|------------|--------|
| `SUPABASE_URL` ou `SUPABASE_PUBLISHABLE_KEY` ausentes | **Não** (há default real) | Baixa | Os defaults são válidos e `isConfigured` fica `true` |
| Variáveis de ambiente injetadas com valores inválidos | **Sim** | Alta | `isConfigured` continua `true`, `Supabase.initialize()` falha em runtime |
| `Supabase.initialize()` lança exceção | **Sim** | Alta | `main()` não captura; pode crashar ou deixar cliente não inicializado |
| `isConfigured` deliberadamente `false` (URL curta/errada) | **Sim** (erro humano) | Alta | Bypass total de autenticação via `app_router` e `_entrar()` |
| Reintrodução de telas `modules.dart`/`producao_screen.dart` no roteamento | **Sim** (erro futuro) | Média | Mock fixo sem autenticação |
| Logout em modo não-configurado redireciona sem encerrar sessão | **Sim** | Média | Sensação falsa de segurança |
| `AuthService.isLoggedIn` acessa cliente não inicializado | **Sim** | Média | Pode lançar `StateError` na splash/login |

---

## 4. Proposta de Correção

### 4.1 Objetivos

1. **Eliminar qualquer caminho** onde falha de conexão/configuração do Supabase resulte em acesso sem autenticação.
2. **Mostrar tela de erro clara** ("Não foi possível conectar ao servidor") quando não for possível inicializar o Supabase em produção.
3. **Manter modo mock apenas com flag explícita de desenvolvimento** (`FLUTTER_ENV=dev`), nunca como fallback automático.

### 4.2 Mudanças Propostas

#### A. `lib/config/supabase_config.dart`

- Remover os `defaultValue` reais de `supabaseUrl` e `supabasePublishableKey`.
- Deixar apenas `defaultValue: ''` ou um placeholder claramente inválido.
- Adicionar flag de ambiente de desenvolvimento:

```dart
static const bool isDev = bool.fromEnvironment('FLUTTER_ENV') == 'dev';
```

**Comportamento padrão quando `FLUTTER_ENV` está ausente:**
- `String.fromEnvironment('FLUTTER_ENV')` retorna `''` (string vazia).
- Portanto `isDev` é `false`.
- `isMockMode` será `false`.
- O app opera em **modo produção**.
- Em caso de falha de configuração/inicialização do Supabase, o acesso será **bloqueado** e uma tela de erro será exibida.
- **O modo mock só será ativado quando `FLUTTER_ENV=dev` for passado explicitamente via `--dart-define` no momento do build.**

- `isConfigured` passa a exigir que ambas as variáveis sejam não vazias e válidas.
- Adicionar `isMockMode = isDev && !isConfigured` (mock só em dev e só quando não configurado).

#### B. `lib/main.dart`

- Tornar `main()` robusto com try/catch em `Supabase.initialize()`.
- Se `isConfigured == false` e `isMockMode == false`:
  - Mostrar `ErrorApp` com mensagem "Configuração incompleta".
- Se `Supabase.initialize()` lançar exceção:
  - Em `isMockMode`: logar e iniciar em modo mock.
  - Em produção: mostrar `ErrorApp` com "Não foi possível conectar ao servidor".
- Nunca iniciar o app normalmente sem Supabase inicializado em produção.

#### C. `lib/routing/app_router.dart`

- Remover o early return `if (!SupabaseConfig.isConfigured) return null;`.
- O guarda de autenticação deve sempre exigir `loggedIn == true` para rotas protegidas.
- Em modo mock (`isMockMode`), simular um usuário logado ou forçar login fake controlado (opcional).

#### D. `lib/screens/splash_screen.dart`

- Se `Supabase.instance.client` não estiver inicializado e não estiver em modo mock, mostrar tela de erro.
- Se `isMockMode`, permitir prosseguir para `/login` ou `/dashboard` com usuário simulado.
- Em produção normal, redirecionar para `/login` se não houver sessão.

#### E. `lib/screens/login_screen.dart`

- Remover bypass `if (!SupabaseConfig.isConfigured) context.go('/dashboard')`.
- Em `isMockMode`, permitir login de desenvolvimento com credenciais fixas e óbvias (ex: `dev`/`dev`), com banner visível.
- Em produção sem configuração, mostrar mensagem de erro e bloquear entrada.
- Cadastro e recuperação de senha devem continuar exigindo Supabase configurado.

#### F. `lib/services/auth_service.dart`

- Proteger getters contra cliente não inicializado:

```dart
SupabaseClient? get _client => Supabase.instance.clientOrNull;
User? get currentUser => _client?.auth.currentUser;
bool get isLoggedIn => currentUser != null;
Stream<AuthState>? get onAuthStateChange => _client?.auth.onAuthStateChange;
```

- Adicionar `bool get isInitialized => Supabase.instance.clientOrNull != null;`.

#### G. `lib/screens/configuracoes_screen.dart`

- Ajustar logout para usar `_client?.auth.signOut()` de forma segura.
- Em modo não-configurado, mostrar banner "Modo de desenvolvimento".

#### H. Telas legadas `modules.dart` e `producao_screen.dart`

**Importante:** a correção cobre TODAS as telas que hoje usam `MockData` fixo, não apenas `login_screen.dart` e `app_router.dart`.

- `lib/screens/modules.dart` — importa `MockData` e renderiza listas fake para funcionários, equipes, fazendas, talhões, transportes, clientes, equipamentos, estoque.
- `lib/screens/producao_screen.dart` — importa `MockData.producoes`.

Ações:

- **Remover do repositório** ou mover para pasta `lib/dev/` com imports condicionais.
- Se mantidas por algum motivo histórico, adicionar `assert(SupabaseConfig.isMockMode)` no início do build para garantir que só renderizem em desenvolvimento.
- Substituir qualquer uso ativo dessas telas no roteamento por `EntityListScreen` com dados reais.
- O objetivo é: **nenhuma tela do app deve renderizar dados mock em produção, mesmo que seja acessada diretamente por URL.**

- Adicionar variáveis de ambiente no dashboard da Vercel:
  - `SUPABASE_URL`
  - `SUPABASE_PUBLISHABLE_KEY`
  - **NUNCA** definir `FLUTTER_ENV=dev` em produção.
- Atualizar `vercel_build.sh` para passar `--dart-define` durante `flutter build web`.

**Diff completo de `vercel_build.sh`:**

```bash
#!/bin/bash
set -e

# Instala Flutter na build do Vercel
FLUTTER_VERSION=${FLUTTER_VERSION:-stable}

if [ ! -d "$HOME/flutter" ]; then
  echo "Instalando Flutter $FLUTTER_VERSION..."
  git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" --depth 1 "$HOME/flutter"
fi

export PATH="$HOME/flutter/bin:$HOME/flutter/bin/cache/dart-sdk/bin:$PATH"

flutter config --no-analytics
flutter doctor
flutter config --enable-web
flutter pub get

# Passa as variáveis de ambiente como --dart-define para o build.
# Em produção, FLUTTER_ENV não deve estar definida como 'dev'.
flutter build web --release \
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="${SUPABASE_PUBLISHABLE_KEY:-}"

# Garante que o Vercel sirva a pasta correta
mkdir -p build/web
echo "Conteúdo de build/web:"
ls -la build/web
```

**Confirmação sobre `FLUTTER_ENV=dev`:**
- O script acima **não passa `FLUTTER_ENV`**.
- Se a variável de ambiente `FLUTTER_ENV` não estiver definida no dashboard da Vercel (e não deve estar), `String.fromEnvironment('FLUTTER_ENV')` retorna `''` e `isDev` será `false`.
- Para ativar o modo mock em desenvolvimento local, o desenvolvedor deve rodar:
  ```bash
  flutter run --dart-define=FLUTTER_ENV=dev
  ```
- **Builds de produção na Vercel nunca receberão `FLUTTER_ENV=dev` por engano**, desde que a variável não seja adicionada manualmente no dashboard.

**Importante:** `String.fromEnvironment` só lê valores passados via `--dart-define` no momento do build. Variáveis de ambiente do Vercel não são automaticamente visíveis para Flutter. O script de build deve explicitamente passá-las.

### 4.3 Comportamento Esperado Após Correção

| Cenário | Comportamento |
|---------|---------------|
| Produção com Supabase configurado e funcionando | Login normal, guarda ativo, todas as rotas protegidas |
| Produção com chave inválida | Tela de erro: "Não foi possível conectar ao servidor" |
| Produção sem variáveis de ambiente | Tela de erro: "Configuração incompleta" (não entra no app) |
| Desenvolvimento (`FLUTTER_ENV=dev`) sem Supabase | Modo mock com banner visível e login dev/dev |
| `Supabase.initialize()` falha em produção | Tela de erro, nunca fallback silencioso |

---

## 5. Arquivos a Serem Alterados

1. `lib/config/supabase_config.dart`
2. `lib/main.dart`
3. `lib/routing/app_router.dart`
4. `lib/screens/splash_screen.dart`
5. `lib/screens/login_screen.dart`
6. `lib/services/auth_service.dart`
7. `lib/screens/configuracoes_screen.dart`
8. `lib/screens/modules.dart` (remover ou isolar)
9. `lib/screens/producao_screen.dart` (remover ou isolar)
10. `vercel_build.sh`
11. Dashboard Vercel (variáveis de ambiente)

---

## 6. Notas para o Claude

- O app não usa `Provider`/`Riverpod`; o estado é local (StatefulWidget) ou via `AppState` (ChangeNotifier simples para tema).
- A autenticação é baseada em `SupabaseAuth` e escutada pelo `_AuthRefresh` do GoRouter.
- O modo mock atual é **global e silencioso**: basta `isConfigured == false` para desarmar a segurança.
- A correção proposta mantém a conveniência de desenvolvimento, mas exige **explicitamente** a flag `FLUTTER_ENV=dev`.
- A chave Supabase atualmente está hardcoded no código-fonte. Mesmo que seja uma publishable key (pública por design), a melhor prática é removê-la do repositório e injetá-la via `--dart-define`.

---

**Aguardando aprovação para iniciar a implementação.**
