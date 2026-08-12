---

# Plano de Feature — Preço por m³ por Cliente

> Status: **Aguardando aprovação do usuário antes de qualquer alteração de código.**
> Data: 2026-08-06
> Escopo: módulos Clientes e Transporte do app SILVORA.

---

## 1. Contexto e Objetivo

Hoje o campo `frete` no módulo Transporte é preenchido manualmente a cada viagem, sem referência ao preço praticado com cada cliente. Isso gera risco de erro humano e inconsistência.

O objetivo é permitir cadastrar um **preço por m³ para cada cliente** e usá-lo para **preencher automaticamente o frete** ao registrar um transporte. O usuário poderá editar o valor manualmente quando necessário.

---

## 2. Requisitos

1. Cada cliente deve ter um preço por m³ cadastrado.
2. O preço pode mudar ao longo do tempo. Transportes já registrados no passado **não podem ter seus lançamentos financeiros recalculados retroativamente**.
3. Ao criar/editar um transporte e selecionar um cliente, o campo `frete` deve ser preenchido automaticamente com `preço_vigente × volume_m3`.
4. O campo `frete` continua editável manualmente.
5. A mudança de preço do cliente não deve alterar transportes históricos.

---

## 3. Modelo de Dados Proposto

### 3.1 Abordagem escolhida: histórico de preços

Em vez de adicionar apenas `valor_m3` na tabela `clientes` (único valor atual), propomos uma **tabela separada de histórico de preços**:

**`public.cliente_precos`**

| Coluna | Tipo | Obrigatório | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | sim | `gen_random_uuid()` | PK |
| `owner_id` | uuid | sim | `auth.uid()` | Isolamento entre usuários |
| `cliente_id` | uuid | sim | — | FK para `clientes.id` |
| `valor_m3` | numeric | sim | — | Preço por m³ naquele período |
| `vigente_desde` | date | sim | `current_date` | Data de início da vigência |
| `vigente_ate` | date | não | — | Data de fim da vigência (NULL = vigente) |
| `created_at` | timestamptz | sim | `now()` | — |

A tabela `clientes` também ganha um campo `valor_m3` (opcional, pode ser usado como valor padrão), mas o **preço vigente real é buscado em `cliente_precos`**, ordenando por `vigente_desde DESC`.

### 3.2 Trade-off da abordagem

**Vantagens:**
- Preserva histórico completo de preços.
- Permite saber qual preço estava vigente em qualquer data do passado.
- Transportes antigos não são afetados por mudanças futuras.
- Facilita relatórios de evolução de preço por cliente.

**Desvantagens:**
- Maior complexidade: toda consulta ao preço vigente precisa filtrar por data.
- Necessita de validação para evitar sobreposição de vigências do mesmo cliente.

**Alternativa descartada:** campo único `clientes.valor_m3`. É mais simples, mas quebra a regra de não recalcular transportes antigos se o preço mudar (pois não haveria como saber qual era o preço no dia do transporte).

---

## 4. Tabelas e Colunas Alteradas

### 4.1 Nova tabela

```sql
CREATE TABLE public.cliente_precos (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  owner_id uuid NOT NULL DEFAULT auth.uid(),
  cliente_id uuid NOT NULL REFERENCES public.clientes(id) ON DELETE CASCADE,
  valor_m3 numeric NOT NULL,
  vigente_desde date NOT NULL DEFAULT current_date,
  vigente_ate date,
  created_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT cliente_precos_owner_check CHECK (owner_id = auth.uid())
);

ALTER TABLE public.cliente_precos ENABLE ROW LEVEL SECURITY;
CREATE POLICY cliente_precos_own ON public.cliente_precos
  FOR ALL USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());

CREATE INDEX idx_cliente_precos_cliente_vigencia
  ON public.cliente_precos(cliente_id, vigente_desde DESC);
```

### 4.2 Tabela clientes (campo opcional auxiliar)

```sql
ALTER TABLE public.clientes
  ADD COLUMN IF NOT EXISTS valor_m3 numeric;
```

Esse campo serve como **atalho visual** na tela de cadastro de clientes. Ao salvar um novo `valor_m3` em `clientes`, o sistema insere automaticamente um registro em `cliente_precos` com `vigente_desde = current_date`. Assim o usuário não precisa gerenciar duas telas.

### 4.3 Tabela transporte (sem alteração estrutural)

A tabela `transporte` já possui `cliente_id`, `volume_m3` e `frete`. Nenhuma coluna nova é necessária. O preenchimento automático do frete acontece **no frontend**, no momento da seleção do cliente/volume.

### 4.4 Triggers ajustadas

As triggers `transporte_gera_receita` e `transporte_atualiza_receita` continuam funcionando da mesma forma: criam/atualizam o lançamento financeiro baseado no valor de `frete`. Não haverá recálculo automático retroativo.

---

## 5. Telas Flutter a Serem Alteradas

### 5.1 Tela de cadastro/edição de cliente

**Arquivo:** `lib/screens/entity_list_screen.dart` (formulário genérico de clientes)

**Mudanças:**
- Exibir campo `valor_m3` no formulário de clientes.
- Ao salvar, além de atualizar `clientes.valor_m3`, inserir um novo registro em `cliente_precos` com `vigente_desde = current_date` (apenas se o valor mudou).
- Opcional: mostrar histórico de preços do cliente em um expansion tile ou tela secundária.

### 5.2 Tela de Transporte

**Arquivo:** `lib/screens/entity_list_screen.dart` (formulário genérico de transporte)

**Mudanças:**
- Detectar quando o usuário altera `cliente_id` ou `volume_m3`.
- Buscar preço vigente em `cliente_precos` para o cliente selecionado.
- Se houver preço vigente e `volume_m3` > 0, preencher `frete = valor_m3 × volume_m3`.
- O campo `frete` continua editável.
- Ao carregar uma edição existente, não recalcular o frete automaticamente (preservar o valor histórico).

### 5.3 Service de preço

**Novo arquivo:** `lib/services/cliente_preco_service.dart`

**Responsabilidades:**
- `Future<double?> buscarPrecoVigente(String clienteId, DateTime data)`
- `Future<void> salvarPreco(String clienteId, double valorM3)`
- `Future<List<Map>> listarHistorico(String clienteId)`

---

## 6. Fluxo de Uso Esperado

### Cadastro de cliente
1. Usuário abre cadastro de cliente.
2. Preenche nome, cidade, tipo e **preço por m³**.
3. Ao salvar, o sistema grava `clientes.valor_m3` e insere um registro em `cliente_precos`.

### Mudança de preço
1. Usuário edita o cliente e altera o preço por m³.
2. O sistema fecha a vigência do preço anterior (preenche `vigente_ate`) e cria um novo registro com `vigente_desde = current_date`.
3. Transportes antigos permanecem inalterados.

### Novo transporte
1. Usuário seleciona cliente.
2. Sistema busca preço vigente em `cliente_precos`.
3. Quando o usuário preenche `volume_m3`, o sistema calcula e preenche `frete`.
4. Usuário pode ajustar o frete manualmente.
5. Ao salvar, trigger cria/atualiza lançamento financeiro com base no `frete` final.

---

## 7. Plano de Teste

### Teste 1: cadastro de cliente com preço
- Cadastrar cliente com `valor_m3 = 10,00`.
- Verificar que `clientes.valor_m3 = 10,00`.
- Verificar que existe 1 registro em `cliente_precos` com `valor_m3 = 10,00` e `vigente_ate IS NULL`.

### Teste 2: mudança de preço
- Alterar cliente para `valor_m3 = 12,00`.
- Verificar que o registro antigo em `cliente_precos` tem `vigente_ate` preenchido.
- Verificar que existe novo registro com `valor_m3 = 12,00` e `vigente_ate IS NULL`.

### Teste 3: preenchimento automático do frete
- Criar transporte com cliente do teste 1, `volume_m3 = 30`.
- Confirmar que `frete` foi preenchido com `300,00` (30 × 10).
- Verificar lançamento financeiro criado com `valor = 300,00`.

### Teste 4: preservação do histórico
- Alterar preço do cliente para 12,00.
- Confirmar que o transporte do teste 3 ainda tem `frete = 300,00`.
- Confirmar que o lançamento financeiro antigo não foi alterado.

### Teste 5: novo transporte após mudança de preço
- Criar novo transporte com `volume_m3 = 30`.
- Confirmar que `frete` foi preenchido com `360,00` (30 × 12).

### Teste 6: edição manual do frete
- Criar transporte com frete automático.
- Alterar manualmente o frete para outro valor.
- Salvar e confirmar que o valor manual foi persistido.

---

## 8. Migrações Necessárias

1. `20260807000000_adiciona_valor_m3_clientes.sql`
   - Adiciona `clientes.valor_m3`.

2. `20260807000001_cria_tabela_cliente_precos.sql`
   - Cria `cliente_precos` com RLS e índices.

3. `20260807000002_migra_precos_iniciais.sql` (opcional)
   - Para cada cliente com `valor_m3` preenchido, insere um registro inicial em `cliente_precos` com `vigente_desde = data de criação do cliente`.

---

## 9. Riscos e Considerações

- **Sobreposição de vigências:** a migration deve incluir validação ou trigger para impedir duas vigências abertas (`vigente_ate IS NULL`) para o mesmo cliente.
- **Cliente sem preço cadastrado:** se não houver preço vigente para a data do transporte, o campo `frete` fica vazio (ou zero) e editável para o usuário preencher manualmente. O cadastro do transporte **não é bloqueado** e não exibe erro ao usuário. O sistema apenas não preenche o frete automaticamente.
- **Volume zero ou nulo:** se `volume_m3` for zero ou nulo, o frete permanece zero ou manual.
- **Performance:** a consulta de preço vigente é simples (índice em `cliente_id, vigente_desde DESC`) e não deve impactar a usabilidade.

---

## 10. Decisões Definidas

As decisões pendentes foram respondidas pelo usuário:

1. **Campo `clientes.valor_m3`:** NÃO será criado. O preço será gerenciado exclusivamente pela tabela `cliente_precos`, buscando o valor vigente quando necessário.

2. **Fechamento de vigência anterior:** Automático. Ao cadastrar um novo preço, o sistema define `vigente_ate` do registro anterior como a data do novo cadastro.

3. **Histórico de preços:** Sim, exibido na tela de detalhe do cliente, em lista simples (preço, vigente de, vigente até).

4. **Busca do preço vigente:** Pela **data do transporte**, não pela data atual. Isso garante que registros retroativos usem o preço correto daquele dia.

---

## 11. Ajustes no Plano Original

Com base nas decisões acima, as seguintes correções se aplicam:

- **Remover a seção 4.2** (campo `clientes.valor_m3`). Não haverá atalho.
- **Tela de cadastro de cliente:** ao salvar, ao invés de atualizar `clientes.valor_m3`, o sistema:
  - Busca o preço vigente atual (último com `vigente_ate IS NULL`).
  - Se o novo valor for diferente, preenche `vigente_ate` do registro atual com `current_date`.
  - Insere novo registro em `cliente_precos` com `valor_m3 = novo valor` e `vigente_desde = current_date`.
- **Tela de transporte:** ao selecionar cliente e informar `data` e `volume_m3`, o sistema busca o preço vigente na data do transporte:
  ```sql
  select valor_m3 from cliente_precos
  where cliente_id = :cliente_id
    and vigente_desde <= :data_transporte
    and (vigente_ate is null or vigente_ate >= :data_transporte)
  order by vigente_desde desc
  limit 1;
  ```
- **Detalhe do cliente:** adicionar lista de histórico de preços abaixo das informações principais.

---

[End of feature plan]

---

# Plano de Auditoria de Segurança — Bypass de Autenticação SILVORA

> Status: **Aguardando aprovação do usuário antes de qualquer alteração de código.**
> Data: 2026-07-29
> Escopo: `lib/config/supabase_config.dart`, `lib/main.dart`, `lib/state/app_state.dart`, `lib/services/auth_service.dart`, `lib/services/db_service.dart`, `lib/routing/app_router.dart`, `lib/screens/splash_screen.dart`, `lib/screens/login_screen.dart`, `lib/screens/configuracoes_screen.dart`, `lib/screens/modules.dart`, `lib/screens/producao_screen.dart`, `lib/data/mock_data.dart`.

> Status: **Aguardando aprovação do usuário antes de qualquer alteração no banco.**
> Data: 2026-08-05
> Escopo: funções `SECURITY DEFINER` no banco de produção `jkwnynwxxfesaagifkhq`.

---

# Relatório de Estrutura — Usuários e Permissões (SILVORA)

> Status: **Documentação apenas. Nenhuma alteração foi feita.**
> Data: 2026-08-06
> Banco analisado: `Silvora Florestal` (`jkwnynwxxfesaagifkhq`)

---

## 1. Hierarquia de usuários

**Resposta curta: não existe hierarquia.**

Hoje, cada usuário autenticado no Supabase Auth é tratado como um **owner isolado**. O isolamento é feito exclusivamente pela política de RLS:

```sql
(auth.uid() = owner_id)
```

Essa política se repete em praticamente todas as tabelas de negócio:

- `producao`
- `producao_funcionarios`
- `funcionarios`
- `equipes`
- `equipe_membros`
- `talhoes`
- `fazendas`
- `transporte`
- `lancamentos`
- `clientes`
- `estoque`
- `veiculos`
- `equipamentos`

Cada usuário só enxerga e manipula registros onde `owner_id` é igual ao próprio UUID (`auth.uid()`). Não existe nenhuma política que permita, por exemplo, um usuário ler dados de outro, nem nenhum conceito de "super administrador" ou "dono da organização".

---

## 2. A tabela `profiles` possui campo de role/permissão?

**Estrutura real da tabela `public.profiles`:**

| Coluna | Tipo | Obrigatório | Default |
|---|---|---|---|
| `id` | uuid | sim | — |
| `nome` | text | não | — |
| `email` | text | não | — |
| `cargo` | text | não | — |
| `telefone` | text | não | — |
| `avatar_url` | text | não | — |
| `created_at` | timestamptz | sim | `now()` |
| `updated_at` | timestamptz | sim | `now()` |
| `empresa` | text | não | — |
| `cidade` | text | não | — |
| `estado` | text | não | — |
| `cpf` | text | não | — |
| `full_name` | text | não | — |

**Existe `cargo` e existe `empresa`, mas ambos são campos de texto livre** (`text`, nullable), sem validação, sem enumeração e sem uso em regras de acesso.

**Políticas de RLS em `profiles`:**

| Policy | Comando | Regra |
|---|---|---|
| `profiles_insert_own` | INSERT | `auth.uid() = id` |
| `profiles_own` | ALL | `auth.uid() = id` |
| `profiles_select_own` | SELECT | `auth.uid() = id` |
| `profiles_update_own` | UPDATE | `auth.uid() = id` |

Ou seja, o `cargo` e a `empresa` são meramente informativos. **Nenhuma tela, RLS ou regra de negócio usa esses campos para permitir/proibir ações.**

---

## 3. O "Administrador" na tela de perfil é real ou hardcoded?

**É hardcoded.**

No arquivo `lib/widgets/app_shell.dart`, o texto "Administrador" aparece literalmente na interface, sem consultar nenhum campo do banco:

```dart
Text('Administrador',
    style: TextStyle(
        color: Colors.white.withValues(alpha: 0.6),
        fontSize: 12)),
```

A tela de configurações (`lib/screens/configuracoes_screen.dart`) permite editar o campo `cargo` do próprio profile, mas esse valor não é usado para nada funcional. O app simplesmente exibe "Administrador" fixo no drawer/cabeçalho.

Há também um valor `'Administrador'` dentro do enum de cargos da entidade `funcionarios` (`lib/data/entities.dart`), mas isso se refere ao **cargo de um funcionário cadastrado no sistema**, não ao tipo de usuário logado.

---

## 4. O que representa a tabela `clientes`?

**Estrutura real:**

| Coluna | Tipo | Obrigatório | Default |
|---|---|---|---|
| `id` | uuid | sim | `gen_random_uuid()` |
| `owner_id` | uuid | sim | `auth.uid()` |
| `nome` | text | sim | — |
| `tipo` | text | não | — |
| `cidade` | text | não | — |
| `pendencia` | numeric | não | `0` |
| `created_at` | timestamptz | sim | `now()` |

**Conceito:** representa **clientes externos** que compram produtos/serviços da empresa do usuário. Não representa filiais/subsidiárias (não há tabela de unidades/empresas).

**Relacionamentos:**

- `transporte.cliente_id` referencia `clientes.id`: um transporte pode estar vinculado a um cliente (provavelmente entrega de madeira/produto).
- Não há FK de `clientes` para `lancamentos`. Os lançamentos financeiros (`lancamentos`) são gerados pelas triggers de transporte (`transporte_gera_receita`) ou inseridos manualmente, sempre com `owner_id` do usuário logado.

A coluna `tipo` e `pendencia` sugerem que a ideia original era controlar saldo devedor do cliente, mas não há triggers ou rotinas que atualizem `pendencia` automaticamente com base em transportes ou lançamentos.

---

## 5. Existe conceito de "empresa" ou "organização"?

**Não.**

Não existem tabelas como `empresas`, `organizations`, `companies`, `filiais` ou `unidades`. O campo `empresa` em `profiles` é um campo de texto livre, sem FK, sem relação com nenhuma outra tabela.

Cada `profile`/`owner_id` é tratado como uma **empresa isolada**. O app é multi-tenant por usuário, não por organização. Não há como dois usuários diferentes compartilharem os mesmos funcionários, equipes, talhões, etc.

---

## 6. É possível dar acesso a um funcionário com permissões diferenciadas?

**Não, com a estrutura atual não é possível.**

Hoje, qualquer usuário que fizer login no app tem acesso total a todos os módulos do próprio `owner_id`. Não existe mecanismo de:

- Roles ou perfis de acesso
- Permissões por tela ou por ação
- Convite de usuários para compartilhar a mesma base de dados
- Hierarquia admin/operador

**Para implementar isso do zero, seria necessário criar, no mínimo:**

1. **Tabela de organizações/empresas** (`empresas`):
   - `id`, `nome`, `owner_id` (dono/administrador principal)

2. **Tabela de vínculo usuário-organização** (`organizacao_membros` ou similar):
   - `organizacao_id`, `user_id`, `role` (ex: `admin`, `operador`, `financeiro`, `producao`)

3. **Ajuste no cadastro de todas as tabelas de negócio**:
   - Adicionar `organizacao_id` (além ou no lugar de `owner_id`)
   - Alterar todas as políticas RLS de `auth.uid() = owner_id` para `auth.uid() in (select user_id from organizacao_membros where organizacao_id = tabela.organizacao_id)`

4. **Controle de permissões no app**:
   - Centralizar a role do usuário logado em um serviço
   - Ocultar/bloquear menus, botões e telas conforme a role
   - Validar permissões também no banco (RLS) para não depender só do frontend

5. **Convite de usuários**:
   - Fluxo para enviar convite por e-mail
   - Aceite e criação do vínculo na tabela de membros

**Resumo:** a arquitetura atual é simples e funciona para um único dono operando sozinho. Qualquer cenário de "funcionário acessa o app com permissões limitadas" exigiria uma refatoração significativa do modelo de dados e das regras de segurança.

---

## Conclusão

O SILVORA hoje é um app **single-owner por design**. O usuário logado é o dono isolado de todos os dados. Os campos `cargo` e `empresa` existem, mas são informativos e não afetam permissões. O texto "Administrador" na interface é fixo. Não há hierarquia, roles funcionais nem compartilhamento de dados entre usuários.

---

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
    await Supabase.initialize(...);
  }
  runApp(const MyApp());
}
```

**Condição de bypass:** se `Supabase.initialize()` falhar ou não for chamado, o app continua rodando normalmente. Não há tela de erro nem bloqueio.

**Risco em produção:** se a chave/URL estiverem erradas, o app pode crashar em runtime ao acessar `Supabase.instance.client`, ou pior, pode cair em fallback para mock se houver lógica condicional.

### 2.3 `lib/routing/app_router.dart`

```dart
final loggedIn = Supabase.instance.client.auth.currentUser != null;
```

**Condição de bypass:** usa `Supabase.instance.client` diretamente. Se o cliente não foi inicializado, lança `StateError`. Em produção, isso pode causar crash em vez de redirecionar para login.

**Risco em produção:** médio. Não permite bypass direto, mas pode deixar o app instável.

### 2.4 `lib/screens/login_screen.dart`

```dart
Future<void> _entrar() async {
  if (!SupabaseConfig.isConfigured) {
    context.go('/dashboard');
    return;
  }
  ...
}
```

**Condição de bypass:** se `isConfigured == false`, qualquer pessoa clica em "Entrar" e vai direto para `/dashboard`.

**Risco em produção:** alto. Se as credenciais não forem detectadas, o app fica aberto.

### 2.5 `lib/state/app_state.dart`

```dart
bool get isAuthenticated =>
    Supabase.instance.client.auth.currentUser != null;
```

**Condição de bypass:** sem fallback. Se o cliente não estiver inicializado, lança exceção.

### 2.6 Telas legadas (`lib/screens/modules.dart`, `lib/screens/producao_screen.dart`)

Usam `MockData` fixo e não verificam autenticação. Atualmente não estão roteadas diretamente, mas se forem reativadas representam risco.

---

## 3. Perguntas do Usuário e Respostas

### 3.1 Comportamento padrão quando FLUTTER_ENV está ausente

**Resposta:** o padrão é **modo produção**. `SupabaseConfig.isDev` só é `true` quando `FLUTTER_ENV == 'dev'`. Qualquer outro valor (incluindo string vazia ou ausente) resulta em `isDev == false`. Em modo produção, se `Supabase.initialize()` falhar, o app mostra tela de erro e **não** cai para mock.

### 3.2 Cobertura das telas legadas

**Resposta:** a correção cobre **todas** as telas que usam `MockData` ou bypass. Telas legadas (`modules.dart`, `producao_screen.dart`) serão isoladas: continuam existindo para uso em dev, mas nunca são roteadas quando `isDev == false`. O `app_router.dart` só aponta para `EntityListScreen`/`ProducaoFormScreen`/`EntityDetailScreen`.

### 3.3 Diff de `vercel_build.sh`

O arquivo `vercel_build.sh` passa `--dart-define=FLUTTER_ENV=prod` explicitamente para builds de produção na Vercel. Nunca passa `FLUTTER_ENV=dev`. O diff está documentado na seção de correção.

---

## 4. Proposta de Correção

### 4.1 `lib/config/supabase_config.dart`

- Remover `defaultValue` reais de URL e publishable key.
- Usar `const bool.fromEnvironment('FLUTTER_ENV', defaultValue: 'prod')` para detectar dev.
- `isConfigured` continua verificando se valores não estão vazios.

### 4.2 `lib/main.dart`

- Tentar `Supabase.initialize()` dentro de `try/catch`.
- Se falhar e NÃO estiver em dev, mostrar `ErrorScreen` com mensagem "Não foi possível conectar ao servidor".
- Se falhar e estiver em dev, permitir fallback mock.

### 4.3 `lib/routing/app_router.dart`

- Usar flag `supabaseInitialized` (controlada por `main.dart`) em vez de acessar `Supabase.instance.client` diretamente.
- Se não inicializado e não estiver em dev, redirecionar para tela de erro.

### 4.4 `lib/screens/login_screen.dart`

- Bloquear modo mock em produção.
- Se `isConfigured == false` e não estiver em dev, mostrar erro.
- Se estiver em dev, manter bypass rápido.

### 4.5 `lib/services/auth_service.dart`, `lib/services/db_service.dart`

- Proteger métodos contra cliente não inicializado.
- Lançar `StateError('Supabase não inicializado')` se `supabaseInitialized == false`.

### 4.6 Telas legadas

- Mover `modules.dart` e `producao_screen.dart` para uma pasta `lib/screens/legacy/`.
- Nunca referenciá-los em `app_router.dart` quando `isDev == false`.

---

## 5. Recomendação Final

Aprovar e aplicar a correção. O risco de bypass em produção é real no caso de falha de inicialização do Supabase, e a proposta elimina o fallback silencioso para mock fora do ambiente de desenvolvimento.

---

# Plano de Auditoria de Segurança — Funções PL/pgSQL SECURITY DEFINER

> Status: **Aprovado e aplicado em 2026-08-06.**
> Data: 2026-08-05
> Escopo: funções `SECURITY DEFINER` no banco de produção `jkwnynwxxfesaagifkhq`.

---

## 1. Resumo Executivo

O banco de produção continha **6 funções `SECURITY DEFINER`** no esquema `public`. Dessas, **4 acessavam ou modificavam tabelas protegidas por RLS baseado em `owner_id`**. As correções foram aplicadas trocando essas funções para `SECURITY INVOKER` e adicionando filtros de `auth.uid()` onde necessário.

---

## 2. Funções Corrigidas

| Função | Ação | Status |
|---|---|---|
| `calcular_remuneracao_producao` | Trocada para `SECURITY INVOKER`; filtra funcionário por `owner_id = auth.uid()` | Aplicado |
| `gerar_producao_funcionarios` | Trocada para `SECURITY INVOKER`; valida `NEW.owner_id = auth.uid()` | Aplicado |
| `excluir_producao_funcionarios` | Trocada para `SECURITY INVOKER`; deleta apenas registros do próprio owner | Aplicado |
| `transporte_gera_receita` | Trocada para `SECURITY INVOKER`; define `owner_id = auth.uid()` no insert | Aplicado |
| `transporte_atualiza_receita` | Trocada para `SECURITY INVOKER`; atualiza apenas lançamentos do próprio owner | Aplicado |
| `handle_new_user` | Mantida inalterada (já segura) | Inalterada |

---

## 3. Plano de Teste Pós-Correção

Verificar se produção individual/equipe continua salvando corretamente; testar transporte com frete; confirmar que `CREATE OR REPLACE FUNCTION` não afeta dados existentes e é reversível.

---

## 4. Resultados dos Testes

Todas as funções foram verificadas no catálogo com `security_definer = false`. Testes de produção individual/equipe e transporte com frete executados com sucesso. Nenhum dado existente foi perdido.

---

## 5. Observação Adicional

Foi detectada e corrigida a ausência da coluna `transporte_id` em `public.lancamentos`. Migration `20260806000001_adiciona_transporte_id_lancamentos.sql` adicionou a coluna (nullable + FK) sem afetar dados existentes.

---

# Plano de Feature — Separação de Carga e Frete no Módulo Transporte

> Status: **Aguardando aprovação do usuário antes de qualquer alteração de código.**
> Data: 2026-08-11
> Escopo: módulo Transporte do app SILVORA.

---

## 1. Contexto e Objetivo

Hoje o campo `frete` no módulo Transporte acumula dois conceitos financeiramente distintos:
1. **Carga**: valor da madeira/produto entregue = `volume_m3 × preço vigente do cliente`.
2. **Frete**: valor do transporte, que pode ser calculado de duas formas:
   - **Por quilômetro**: `distancia_km × valor_km`.
   - **Valor combinado**: valor fechado digitado diretamente, sem relação com distância.

A separação torna a precificação transparente e permite que usuários (ex: transportadoras próprias) registrem apenas a carga, sem frete separado, ou registrem o frete da forma que foi negociado.

**Objetivo:** reestruturar a tabela, triggers e interface do Transporte para tratar Carga e Frete como valores independentes, com Total calculado automaticamente.

---

## 2. Requisitos

1. Adicionar `distancia_km`, `valor_km`, `tipo_frete` e `valor_combinado` em `public.transporte`.
2. Manter o cálculo automático da **Carga** (`volume_m3 × preço do cliente`) no campo que hoje é `frete`.
3. Adicionar cálculo do **Frete** com dois modos:
   - Se `tipo_frete = 'km'`: Frete = `distancia_km × valor_km`.
   - Se `tipo_frete = 'combinado'`: Frete = `valor_combinado`.
   - Se `tipo_frete` for nulo ou os campos estiverem vazios: Frete = 0.
4. Calcular **Total** = Carga + Frete.
5. A trigger `transporte_gera_receita` deve gerar o lançamento financeiro baseado no **Total**.
6. Na UI de cadastro/edição, exibir:
   - Carga (calculada automaticamente, editável).
   - Toggle/seletor "Frete por km" / "Frete combinado".
   - Campos correspondentes ao modo selecionado.
   - Frete calculado e Total (read-only).
7. Todos os campos de frete são opcionais — usuário pode deixar vazio e registrar só a carga.

---

## 3. Modelo de Dados

### 3.1 Alterações em `public.transporte`

| Coluna | Tipo | Nullable | Default | Descrição |
|---|---|---|---|---|
| `frete` | numeric | sim | `0` | Passa a representar a **Carga** (volume × preço cliente). Ver decisão de nomenclatura na seção 8. |
| `distancia_km` | numeric | sim | `NULL` | Quilômetros percorridos (modo km). |
| `valor_km` | numeric | sim | `NULL` | Valor cobrado por km (modo km). |
| `tipo_frete` | text | sim | `NULL` | Modo de cálculo do frete: `'km'` ou `'combinado'`. |
| `valor_combinado` | numeric | sim | `NULL` | Valor fechado do frete (modo combinado). |

### 3.2 Novo cálculo

```text
Carga  = COALESCE(volume_m3, 0) × preco_vigente_cliente

Frete  = CASE
          WHEN tipo_frete = 'km'      THEN COALESCE(distancia_km, 0) × COALESCE(valor_km, 0)
          WHEN tipo_frete = 'combinado' THEN COALESCE(valor_combinado, 0)
          ELSE 0
         END

Total  = Carga + Frete
```

---

## 4. Migration

### 4.1 Nova migration: `20260811000000_separga_carga_frete_transporte.sql`

```sql
-- Adiciona colunas de distância, valor por km, tipo de frete e valor combinado
alter table public.transporte
  add column if not exists distancia_km numeric,
  add column if not exists valor_km numeric,
  add column if not exists tipo_frete text check (tipo_frete in ('km', 'combinado')),
  add column if not exists valor_combinado numeric;

-- Garante que frete exista (já deve existir, mas defensivo)
alter table public.transporte
  alter column frete set default 0;

-- Atualiza função que gera receita: usa Total = carga (frete) + frete calculado
create or replace function public.transporte_gera_receita()
returns trigger
language plpgsql
security invoker set search_path = public
as $$
declare
  v_frete numeric;
  v_total numeric;
begin
  v_frete := case
    when NEW.tipo_frete = 'km' then
      coalesce(NEW.distancia_km, 0) * coalesce(NEW.valor_km, 0)
    when NEW.tipo_frete = 'combinado' then
      coalesce(NEW.valor_combinado, 0)
    else 0
  end;

  v_total := coalesce(NEW.frete, 0) + v_frete;

  if v_total > 0 then
    insert into public.lancamentos (
      owner_id, tipo, descricao, categoria, valor, data, transporte_id
    )
    values (
      auth.uid(),
      'Receita',
      'Viagem: ' || coalesce(NEW.origem,'Origem') || ' → ' || coalesce(NEW.destino,'Destino'),
      'Frete',
      v_total,
      NEW.data,
      NEW.id
    );
  end if;
  return NEW;
end;
$$;

-- Atualiza função que atualiza receita em updates
create or replace function public.transporte_atualiza_receita()
returns trigger
language plpgsql
security invoker set search_path = public
as $$
declare
  v_frete_old numeric;
  v_total_old numeric;
  v_frete_new numeric;
  v_total_new numeric;
begin
  v_frete_old := case
    when OLD.tipo_frete = 'km' then
      coalesce(OLD.distancia_km, 0) * coalesce(OLD.valor_km, 0)
    when OLD.tipo_frete = 'combinado' then
      coalesce(OLD.valor_combinado, 0)
    else 0
  end;
  v_total_old := coalesce(OLD.frete, 0) + v_frete_old;

  v_frete_new := case
    when NEW.tipo_frete = 'km' then
      coalesce(NEW.distancia_km, 0) * coalesce(NEW.valor_km, 0)
    when NEW.tipo_frete = 'combinado' then
      coalesce(NEW.valor_combinado, 0)
    else 0
  end;
  v_total_new := coalesce(NEW.frete, 0) + v_frete_new;

  if v_total_new is distinct from v_total_old then
    update public.lancamentos
    set valor = v_total_new
    where transporte_id = NEW.id
      and categoria = 'Frete'
      and owner_id = auth.uid();
  end if;
  return NEW;
end;
$$;
```

---

## 5. Telas Flutter Afetadas

### 5.1 `lib/data/entities.dart`

Atualizar definição de `transporte`:

```dart
'transporte': EntityDef(
  table: 'transporte',
  noun: 'viagem',
  // ...
  fields: [
    // referências (veiculo, motorista, fazenda, cliente)
    const FieldDef('volume_m3', 'Volume (m³)', type: FieldType.decimal, suffix: 'm³'),
    const FieldDef('frete', 'Valor da carga (R\$)', type: FieldType.decimal, suffix: 'R\$'),
    const FieldDef('tipo_frete', 'Tipo de frete', type: FieldType.select, options: [
      'km',
      'combinado',
    ]),
    const FieldDef('distancia_km', 'Distância (km)', type: FieldType.decimal, suffix: 'km'),
    const FieldDef('valor_km', 'Valor por km (R\$)', type: FieldType.decimal, suffix: 'R\$/km'),
    const FieldDef('valor_combinado', 'Valor combinado (R\$)', type: FieldType.decimal, suffix: 'R\$'),
    const FieldDef('data', 'Data'),
  ],
  titleOf: (m) => _ref(m, 'veiculo', 'nome').isNotEmpty ? _ref(m, 'veiculo', 'nome') : 'Viagem',
  subtitleOf: (m) {
    final rota = [_ref(m, 'fazenda', 'nome'), _ref(m, 'cliente', 'nome')]
        .where((e) => e.isNotEmpty)
        .join(' → ');
    final l2 = [
      if (_ref(m, 'motorista', 'nome').isNotEmpty) 'Mot.: ${_ref(m, 'motorista', 'nome')}',
      if (_d(m, 'volume_m3') > 0) '${_d(m, 'volume_m3')} m³',
    ].join(' • ');
    return [rota, l2].where((e) => e.isNotEmpty).join('\n');
  },
  leadingOf: (m) => _iconAvatar(Icons.route, BrandColors.info),
  trailingOf: (m) {
    final carga = _d(m, 'frete');
    final frete = _calcularFrete(m);
    final total = carga + frete;
    return Text('R\$ ${total.toStringAsFixed(0)}',
        style: const TextStyle(fontWeight: FontWeight.w800, color: BrandColors.forest));
  },
),
```

O helper `_calcularFrete`:

```dart
double _calcularFrete(Map m) {
  final tipo = m['tipo_frete']?.toString();
  if (tipo == 'km') {
    return _d(m, 'distancia_km') * _d(m, 'valor_km');
  }
  if (tipo == 'combinado') {
    return _d(m, 'valor_combinado');
  }
  return 0;
}
```

### 5.2 `lib/screens/entity_list_screen.dart`

- Renomear método `_atualizarFreteAutomatico` para `_atualizarCargaAutomatica`.
- Manter preenchimento automático do campo `frete` (agora "Valor da carga") a partir do preço do cliente × volume.
- Adicionar controle de estado para `tipo_frete` (padrão: nenhum/seleção vazia).
- Quando `tipo_frete = 'km'`, mostrar campos `distancia_km` e `valor_km`; calcular Frete = distancia_km × valor_km.
- Quando `tipo_frete = 'combinado'`, mostrar campo `valor_combinado`; usar esse valor diretamente como Frete.
- Quando `tipo_frete` for nulo, Frete = 0.
- Exibir cards/read-only com:
  - Carga (editável, preenchido automaticamente)
  - Tipo de frete (seletor)
  - Campos condicionais (km/valor_km ou valor_combinado)
  - Frete calculado (read-only)
  - Total = Carga + Frete (read-only)
- Adicionar listeners em `cliente_id`, `volume_m3`, `tipo_frete`, `distancia_km`, `valor_km` e `valor_combinado` para recalcular os valores em tempo real.

### 5.3 `lib/screens/entity_detail_screen.dart`

- Se houver detalhe de transporte, atualizar os cards para mostrar Carga, Tipo de frete, Frete e Total separadamente.

---

## 6. Regras de Negócio e Comportamentos Esperados

| Cenário | Comportamento |
|---|---|
| Usuário preenche cliente + volume | Carga preenchida automaticamente (preço cliente × volume). |
| Usuário não seleciona tipo de frete | Frete = 0; Total = Carga. |
| `tipo_frete = 'km'` e km/valor_km preenchidos | Frete = km × valor_km; Total = Carga + Frete. |
| `tipo_frete = 'combinado'` e valor preenchido | Frete = valor_combinado; Total = Carga + Frete. |
| Usuário edita carga manualmente | Valor editável; Total recalculado. |
| Usuário muda o tipo de frete | Campos correspondentes aparecem; Frete e Total recalculados. |
| Cliente sem preço cadastrado | Carga fica 0/vazia; usuário pode preencher manualmente. |
| Transportadora própria (só carga) | Não seleciona tipo de frete; lançamento usa apenas carga. |

---

## 7. Plano de Teste

### 7.1 Teste de schema

1. Aplicar migration.
2. Confirmar que `distancia_km`, `valor_km`, `tipo_frete` e `valor_combinado` existem em `public.transporte`.
3. Confirmar que `transporte_gera_receita` e `transporte_atualiza_receita` foram substituídas.

### 7.2 Teste de cálculo no banco

```sql
-- Cenário 1: só carga (sem frete separado)
INSERT INTO public.transporte (owner_id, cliente_id, volume_m3, frete, data)
VALUES (auth.uid(), 'cliente-com-preco', 27, 2295, CURRENT_DATE);
-- Esperado: lançamento de R$ 2.295,00.

-- Cenário 2: carga + frete por km
INSERT INTO public.transporte (owner_id, cliente_id, volume_m3, frete, tipo_frete, distancia_km, valor_km, data)
VALUES (auth.uid(), 'cliente-com-preco', 27, 2295, 'km', 100, 3.50, CURRENT_DATE);
-- Esperado: lançamento de R$ 2.645,00 (2.295 + 350).

-- Cenário 3: carga + frete combinado
INSERT INTO public.transporte (owner_id, cliente_id, volume_m3, frete, tipo_frete, valor_combinado, data)
VALUES (auth.uid(), 'cliente-com-preco', 27, 2295, 'combinado', 500.00, CURRENT_DATE);
-- Esperado: lançamento de R$ 2.795,00 (2.295 + 500).

-- Cenário 4: sem preço de cliente, só frete por km
INSERT INTO public.transporte (owner_id, cliente_id, volume_m3, frete, tipo_frete, distancia_km, valor_km, data)
VALUES (auth.uid(), 'cliente-sem-preco', 0, 0, 'km', 80, 4.00, CURRENT_DATE);
-- Esperado: lançamento de R$ 320,00.

-- Cenário 5: sem preço de cliente, só frete combinado
INSERT INTO public.transporte (owner_id, cliente_id, volume_m3, frete, tipo_frete, valor_combinado, data)
VALUES (auth.uid(), 'cliente-sem-preco', 0, 0, 'combinado', 600.00, CURRENT_DATE);
-- Esperado: lançamento de R$ 600,00.
```

### 7.3 Teste no app

1. Abrir Nova Viagem.
2. Selecionar cliente com preço (ex: Magarida, R$ 85/m³).
3. Preencher volume = 27.
4. Confirmar que "Valor da carga" = R$ 2.295,00.
5. **Sem tipo de frete selecionado:** salvar. Verificar lançamento de R$ 2.295,00.
6. **Frete por km:** selecionar tipo "Por km", preencher km = 100 e valor/km = 3,50. Confirmar Frete = R$ 350,00 e Total = R$ 2.645,00. Salvar e verificar lançamento.
7. **Frete combinado:** editar a viagem, trocar tipo para "Valor combinado", preencher R$ 500,00. Confirmar Frete = R$ 500,00 e Total = R$ 2.795,00. Salvar e verificar lançamento atualizado.
8. **Regressão:** viagens antigas sem `tipo_frete` continuam com Total = Carga.

### 7.4 Teste de regressão

- Viagens antigas (sem `tipo_frete`) continuam com Total = Carga.
- Updates em viagens antigas não quebram o lançamento financeiro.

---

## 8. Notas de Implementação

### 8.1 Nomenclatura da coluna `frete`

**Pergunta do usuário:** por que manter o nome `frete` no banco representando Carga, em vez de renomear para `valor_carga`?

**Resposta:** renomear é tecnicamente simples (`ALTER TABLE transporte RENAME COLUMN frete TO valor_carga;`), mas o nome `frete` já é referenciado em vários lugares do sistema. Para fazer "certo", seria necessário atualizar:

- Triggers `transporte_gera_receita` e `transporte_atualiza_receita` (migration nova).
- `lib/data/entities.dart` (definição do campo e cálculos).
- `lib/screens/entity_list_screen.dart` (formulário de cadastro/edição e cálculo automático).
- `lib/screens/entity_detail_screen.dart` (detalhes, se houver).
- Telas legadas: `lib/screens/modules.dart`, `dashboard_screen.dart`, `financeiro_screen.dart`, `relatorios_screen.dart`, `ia_screen.dart`.
- `lib/data/mock_data.dart`.
- Documentação (`RELATORIO_ESTRUTURAL_SILVORA.md`, `plan.md`).

Não há FKs nem índices diretos sobre a coluna `frete`, então a operação em si é segura. O custo é puramente de refatoração de código.

**Decisão:** nesta primeira etapa, manter o nome `frete` no banco e renomear apenas na interface para "Valor da carga (R$)". Isso minimiza o risco de regressão e acelera a entrega. Se o usuário quiser, uma etapa posterior pode renomear a coluna formalmente via migration.

### 8.2 Outras notas

- Todos os cálculos de Total consideram `COALESCE(..., 0)` para tratar nulos.
- As triggers continuam com `SECURITY INVOKER`, respeitando RLS.
- O campo `tipo_frete` utiliza `CHECK` para garantir apenas `'km'` ou `'combinado'`.

---

[End of plan.md]
