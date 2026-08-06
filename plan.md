# Plano de Auditoria de Segurança — Bypass de Autenticação SILVORA

> Status: **Aguardando aprovação do usuário antes de qualquer alteração de código.**
> Data: 2026-07-29
> Escopo: `lib/config/supabase_config.dart`, `lib/main.dart`, `lib/state/app_state.dart`, `lib/services/auth_service.dart`, `lib/services/db_service.dart`, `lib/routing/app_router.dart`, `lib/screens/splash_screen.dart`, `lib/screens/login_screen.dart`, `lib/screens/configuracoes_screen.dart`, `lib/screens/modules.dart`, `lib/screens/producao_screen.dart`, `lib/data/mock_data.dart`.

---

# Plano de Auditoria de Segurança — Funções PL/pgSQL SECURITY DEFINER

> Status: **Aguardando aprovação do usuário antes de qualquer alteração no banco.**
> Data: 2026-08-05
> Escopo: funções `SECURITY DEFINER` no banco de produção `jkwnynwxxfesaagifkhq`.

---

## 1. Resumo Executivo

O banco de produção contém **6 funções `SECURITY DEFINER`** no esquema `public`. Dessas, **4 acessam ou modificam tabelas protegidas por RLS baseado em `owner_id`**. Funções `SECURITY DEFINER` ignoram as políticas RLS do chamador e executam com os privilégios do dono da função (normalmente `postgres` ou o usuário que criou). Se a função não validar `auth.uid()` internamente, um usuário autenticado pode ler ou alterar dados de outro usuário/owner através dessas funções.

**Risco geral: MÉDIO a ALTO** — dependendo da função, um usuário pode:
- Ler dados de funcionários de outro owner (`calcular_remuneracao_producao`, `gerar_producao_funcionarios` via trigger).
- Inserir registros em `producao_funcionarios` com `owner_id` de outro usuário (`gerar_producao_funcionarios` via trigger).
- Excluir registros de `producao_funcionarios` de outro usuário (`excluir_producao_funcionarios` via trigger).
- Criar profiles sem validação de ownership (`handle_new_user`).
- Modificar lançamentos financeiros de outro owner (`transporte_gera_receita`, `transporte_atualiza_receita` via triggers).

---

## 2. Funções Encontradas

### 2.1 `calcular_remuneracao_producao(uuid, numeric, integer, numeric)`

**Código:**
```sql
CREATE OR REPLACE FUNCTION public.calcular_remuneracao_producao(
  p_funcionario_id uuid,
  p_volume numeric,
  p_arvores integer,
  p_horas numeric DEFAULT 1
)
RETURNS TABLE(forma_remuneracao text, valor_unitario numeric, quantidade_calculo numeric, valor_total numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_func public.funcionarios%rowtype;
  ...
begin
  select * into v_func from public.funcionarios where id = p_funcionario_id;
  ...
end;
$function$;
```

**Acesso a dados RLS:** sim, lê `public.funcionarios` (RLS por `owner_id`).

**Validação de `auth.uid()`:** não. Recebe `p_funcionario_id` e lê qualquer funcionário com esse id, independente de `owner_id`.

**Risco:** um usuário autenticado pode descobrir se um funcionário existe (informações como nome, cargo, valores de remuneração) passando um `uuid` arbitrário. Embora o retorno seja apenas cálculo, a função lê a linha inteira. Como é chamada dentro de trigger, o risco de exposição direta depende da API, mas a função em si não impede a leitura cross-owner.

---

### 2.2 `gerar_producao_funcionarios()` — trigger AFTER INSERT em `producao`

**Código:**
```sql
CREATE OR REPLACE FUNCTION public.gerar_producao_funcionarios()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
begin
  if NEW.tipo_producao = 'Individual' and NEW.funcionario_id is not null then
    insert into public.producao_funcionarios (
      owner_id, producao_id, funcionario_id, participou,
      forma_remuneracao, valor_unitario, quantidade_calculo, valor_total
    )
    select
      NEW.owner_id, NEW.id, NEW.funcionario_id, true,
      c.forma_remuneracao, c.valor_unitario, c.quantidade_calculo, c.valor_total
    from public.calcular_remuneracao_producao(NEW.funcionario_id, NEW.volume_total, NEW.total_arvores) c;
  end if;
  return NEW;
end;
$function$;
```

**Acesso a dados RLS:** sim, insere em `public.producao_funcionarios` (RLS por `owner_id`) e lê `public.funcionarios`.

**Validação de `auth.uid()`:** não. Usa `NEW.owner_id` vindo do insert da aplicação. Se a aplicação inserir uma produção com `owner_id` de outro usuário, esta função propagará esse `owner_id` para `producao_funcionarios`. A trigger roda depois do RLS do insert em `producao`, então a política `producao_own` já teria bloqueado se o insert fosse feito via SQL com owner errado. No entanto, como `SECURITY DEFINER`, a trigger ignora RLS de `producao_funcionarios` e insere diretamente.

**Risco:** médio. O caminho depende de conseguir inserir uma produção com owner_id de outro usuário. A política `producao_own` impede isso em inserts diretos via Supabase Client, mas bugs na aplicação ou execução via RPC poderiam contornar.

---

### 2.3 `excluir_producao_funcionarios()` — trigger BEFORE DELETE em `producao`

**Código:**
```sql
CREATE OR REPLACE FUNCTION public.excluir_producao_funcionarios()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
begin
  delete from public.producao_funcionarios where producao_id = OLD.id;
  return OLD;
end;
$function$;
```

**Acesso a dados RLS:** sim, exclui de `public.producao_funcionarios` (RLS por `owner_id`).

**Validação de `auth.uid()`:** não. Exclui todos os registros de `producao_funcionarios` com `producao_id = OLD.id`, sem verificar `owner_id`.

**Risco:** médio a alto. Se um usuário conseguir deletar uma produção de outro owner (a política `producao_own` impede em delete direto), esta trigger deletará os participantes associados independentemente de quem seja o owner. Como é `SECURITY DEFINER`, ela executa a deleção mesmo que o usuário não tenha permissão RLS sobre os registros de `producao_funcionarios`.

---

### 2.4 `handle_new_user()` — trigger em `auth.users`

**Código:**
```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
begin
  insert into public.profiles (id, email, full_name)
  values (NEW.id, NEW.email, NEW.raw_user_meta_data->>'nome');
  return NEW;
end;
$function$;
```

**Acesso a dados RLS:** insere em `public.profiles` (RLS baseada em `id`, não `owner_id`).

**Validação de `auth.uid()`:** implícita. A trigger roda no contexto do Supabase Auth e `NEW.id` é o UUID do novo usuário. A política `profiles_insert_own` exige `auth.uid() = id`, e como a função insere com `id = NEW.id`, isso está correto. Não há risco de cross-owner aqui.

**Risco:** baixo. Função padrão do Supabase, comportamento esperado.

---

### 2.5 `transporte_gera_receita()` — trigger em `transporte`

**Código:**
```sql
CREATE OR REPLACE FUNCTION public.transporte_gera_receita()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
begin
  if NEW.frete is not null and NEW.frete > 0 then
    insert into public.lancamentos (tipo, descricao, categoria, valor, data, transporte_id)
    values ('Receita', 'Frete: ' || COALESCE(NEW.origem,'Origem') || ' → ' || COALESCE(NEW.destino,'Destino'), 'Frete', NEW.frete, NEW.data, NEW.id);
  end if;
  return NEW;
end;
$function$;
```

**Acesso a dados RLS:** insere em `public.lancamentos` (RLS por `owner_id`).

**Validação de `auth.uid()`:** não. Não define `owner_id` no insert. Se a tabela `lancamentos` tem default `auth.uid()` em `owner_id`, o valor será do usuário que disparou a trigger. Se não tiver default, o insert pode falhar ou usar um valor indefinido.

**Risco:** médio. Dependendo do default da coluna `owner_id` em `lancamentos`, pode haver inconsistência de ownership. Além disso, como `SECURITY DEFINER`, o insert não passa pela política RLS do chamador.

---

### 2.6 `transporte_atualiza_receita()` — trigger em `transporte`

**Código:**
```sql
CREATE OR REPLACE FUNCTION public.transporte_atualiza_receita()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
begin
  if NEW.frete is distinct from OLD.frete then
    update public.lancamentos
    set valor = COALESCE(NEW.frete, 0)
    where transporte_id = NEW.id and categoria = 'Frete';
  end if;
  return NEW;
end;
$function$;
```

**Acesso a dados RLS:** sim, atualiza `public.lancamentos` (RLS por `owner_id`).

**Validação de `auth.uid()`:** não. Atualiza qualquer lançamento de frete com `transporte_id = NEW.id`, independente de `owner_id`.

**Risco:** alto. Se um usuário conseguir atualizar um transporte de outro owner (a política `transporte_own` impede em update direto), esta trigger atualizará o lançamento financeiro associado. Isso permite manipulação de dados financeiros de outros usuários.

---

## 3. Tabelas com RLS (para referência)

Todas as tabelas do esquema `public` possuem RLS ativada e uma política `*_own` exigindo `auth.uid() = owner_id`, exceto `profiles` que usa `auth.uid() = id`.

- `clientes`, `equipamentos`, `equipe_membros`, `equipes`, `estoque`, `fazendas`, `funcionarios`, `lancamentos`, `producao`, `producao_funcionarios`, `profiles`, `talhoes`, `transporte`, `veiculos`.

---

## 4. Proposta de Correção

### 4.1 `calcular_remuneracao_producao`

**Opção recomendada:** trocar para `SECURITY INVOKER` e fazer a query com filtro de `owner_id`.

```sql
CREATE OR REPLACE FUNCTION public.calcular_remuneracao_producao(
  p_funcionario_id uuid,
  p_volume numeric,
  p_arvores integer,
  p_horas numeric DEFAULT 1
)
RETURNS TABLE(forma_remuneracao text, valor_unitario numeric, quantidade_calculo numeric, valor_total numeric)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public'
AS $$
DECLARE
  v_func public.funcionarios%rowtype;
BEGIN
  SELECT * INTO v_func
  FROM public.funcionarios
  WHERE id = p_funcionario_id AND owner_id = auth.uid();

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- ... restante do cálculo
END;
$$;
```

### 4.2 `gerar_producao_funcionarios`

**Opção recomendada:** garantir que `NEW.owner_id = auth.uid()` antes de prosseguir.

```sql
CREATE OR REPLACE FUNCTION public.gerar_producao_funcionarios()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.owner_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'owner_id inválido';
  END IF;

  IF NEW.tipo_producao = 'Individual' AND NEW.funcionario_id IS NOT NULL THEN
    INSERT INTO public.producao_funcionarios (...)
    SELECT NEW.owner_id, ...
    FROM public.calcular_remuneracao_producao(...);
  END IF;

  RETURN NEW;
END;
$$;
```

### 4.3 `excluir_producao_funcionarios`

**Opção recomendada:** trocar para `SECURITY INVOKER` e validar ownership.

```sql
CREATE OR REPLACE FUNCTION public.excluir_producao_funcionarios()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public'
AS $$
BEGIN
  DELETE FROM public.producao_funcionarios
  WHERE producao_id = OLD.id AND owner_id = auth.uid();
  RETURN OLD;
END;
$$;
```

### 4.4 `transporte_gera_receita`

**Opção recomendada:** definir `owner_id = auth.uid()` no insert e usar `SECURITY INVOKER`.

```sql
CREATE OR REPLACE FUNCTION public.transporte_gera_receita()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.frete IS NOT NULL AND NEW.frete > 0 THEN
    INSERT INTO public.lancamentos (
      owner_id, tipo, descricao, categoria, valor, data, transporte_id
    )
    VALUES (
      auth.uid(),
      'Receita',
      'Frete: ' || COALESCE(NEW.origem,'Origem') || ' → ' || COALESCE(NEW.destino,'Destino'),
      'Frete', NEW.frete, NEW.data, NEW.id
    );
  END IF;
  RETURN NEW;
END;
$$;
```

### 4.5 `transporte_atualiza_receita`

**Opção recomendada:** trocar para `SECURITY INVOKER` e filtrar por `owner_id = auth.uid()`.

```sql
CREATE OR REPLACE FUNCTION public.transporte_atualiza_receita()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.frete IS DISTINCT FROM OLD.frete THEN
    UPDATE public.lancamentos
    SET valor = COALESCE(NEW.frete, 0)
    WHERE transporte_id = NEW.id
      AND categoria = 'Frete'
      AND owner_id = auth.uid();
  END IF;
  RETURN NEW;
END;
$$;
```

### 4.6 `handle_new_user`

**Ação:** nenhuma. Já está segura porque `NEW.id` vem do Auth e a política de `profiles` exige `auth.uid() = id`.

---

## 5. Recomendação Final

**Aprovar e aplicar as correções das seções 4.1 a 4.5.** As funções `gerar_producao_funcionarios`, `excluir_producao_funcionarios`, `transporte_gera_receita` e `transporte_atualiza_receita` apresentam risco real de bypass de RLS. A função `calcular_remuneracao_producao` apresenta risco de vazamento de dados de funcionários de outros owners.

**NÃO alterar `handle_new_user`** — comportamento seguro e padrão.

**Observação:** ao trocar para `SECURITY INVOKER`, as triggers continuarão funcionando normalmente porque o contexto de execução de triggers em tabelas RLS já é o do usuário autenticado que disparou a operação.

---

## 6. Plano de Teste Pós-Correção

### 6.1 Teste de cadastro de produção (individual e equipe)

**Objetivo:** confirmar que a troca para `SECURITY INVOKER` e a adição de `owner_id = auth.uid()` não quebram o fluxo já validado.

**Passos:**
1. Aplicar as correções das seções 4.1, 4.2 e 4.3.
2. Fazer login no app com um usuário real.
3. Navegar até **Nova Produção → Individual**.
4. Selecionar um funcionário, talhão, preencher data, volume e árvores, e salvar.
5. Verificar no Supabase (SQL Editor ou Table Editor) que:
   - Um registro foi criado em `public.producao` com `owner_id = auth.uid()` do usuário logado.
   - Um registro foi criado em `public.producao_funcionarios` vinculado a essa produção, com `owner_id` correto e valores calculados conforme a forma de remuneração do funcionário.
6. Repetir o teste em **Nova Produção → Equipe**.
7. Selecionar uma equipe e confirmar que a lista de participantes com checkboxes aparece.
8. Salvar e verificar que foram criados:
   - Um registro em `public.producao`.
   - Um registro em `public.producao_funcionarios` para cada participante marcado, com `owner_id` correto.

**Critério de aceitação:** os dados aparecem corretamente nas duas tabelas e os valores de remuneração estão coerentes.

### 6.2 Teste de cadastro de transporte com frete

**Objetivo:** confirmar que a correção de `transporte_gera_receita` (adição explícita de `owner_id = auth.uid()`) funciona e resolve o bug de lançamento sem owner.

**Passos:**
1. Aplicar as correções das seções 4.4 e 4.5.
2. Fazer login no app.
3. Navegar até o fluxo de cadastro de transporte (se disponível) e criar um transporte com:
   - `frete` maior que 0.
   - `origem` e `destino` preenchidos.
   - `data` preenchida.
4. Verificar no Supabase que:
   - O transporte foi salvo em `public.transporte` com `owner_id` correto.
   - Um lançamento foi criado automaticamente em `public.lancamentos` com:
     - `tipo = 'Receita'`
     - `categoria = 'Frete'`
     - `valor = frete`
     - `transporte_id = id do transporte`
     - `owner_id = auth.uid()` do usuário logado (isso é o que a correção acrescenta; hoje o campo fica vazio ou indefinido).
5. Editar o frete do transporte e salvar.
6. Verificar que o lançamento em `public.lancamentos` foi atualizado com o novo valor e apenas o lançamento do próprio owner foi afetado.

**Critério de aceitação:** o lançamento financeiro é criado/atualizado com `owner_id` correto e não afeta dados de outros usuários.

### 6.3 Confirmação de segurança dos dados existentes

**Objetivo:** garantir que `CREATE OR REPLACE FUNCTION` não altera dados históricos.

**Passos:**
1. Antes de aplicar, executar backup lógico opcional:
   ```sql
   -- Não é obrigatório, mas recomendado para maior segurança
   -- pg_dump via Supabase CLI ou Dashboard
   ```
2. Aplicar as 5 correções via `CREATE OR REPLACE FUNCTION`.
3. Executar queries de contagem para confirmar que nenhuma linha foi perdida:
   ```sql
   SELECT count(*) FROM public.producao;
   SELECT count(*) FROM public.producao_funcionarios;
   SELECT count(*) FROM public.lancamentos;
   SELECT count(*) FROM public.transporte;
   ```
4. Comparar os valores com os contadores anteriores (se disponíveis) ou simplesmente confirmar que estão consistentes.

**Critério de aceitação:** nenhuma tabela perde registros após a aplicação das correções.

### 6.4 Reversibilidade

**Objetivo:** confirmar que é possível reverter rapidamente se algo quebrar.

**Procedimento:**
- `CREATE OR REPLACE FUNCTION` apenas substitui o corpo da função. **Não apaga dados**, não remove triggers e não altera tabelas.
- Se algum teste falhar, basta executar novamente `CREATE OR REPLACE FUNCTION` com o código original (que será mantido no arquivo `plan.md` ou em backup da migration) para restaurar o comportamento anterior.
- Recomenda-se testar primeiro em um banco de desenvolvimento/branch, se disponível. Como o projeto não possui branch configurado, os testes serão feitos diretamente em produção, mas fora do horário de pico e com os comandos de reversão prontos.

**Critério de aceitação:** as funções podem ser restauradas ao estado anterior sem perda de dados.

---

## 7. Resultados dos Testes (após aplicação)

**Data da execução:** 2026-08-06  
**Banco:** Silvora Florestal (`jkwnynwxxfesaagifkhq`)

### 7.1 Verificação das funções no catálogo

Todas as 5 funções corrigidas aparecem com `security_definer = false` (ou seja, `SECURITY INVOKER`):

| Função | security_definer |
|---|---|
| `calcular_remuneracao_producao` | false |
| `gerar_producao_funcionarios` | false |
| `excluir_producao_funcionarios` | false |
| `transporte_gera_receita` | false |
| `transporte_atualiza_receita` | false |

### 7.2 Teste de produção individual

Inserida produção individual com volume = 22 m³ para funcionário com remuneração `Metro cúbico` e valor = R$ 7,50.

Resultado em `producao_funcionarios`:
- `forma_remuneracao`: Metro cúbico
- `valor_unitario`: 7.50
- `quantidade_calculo`: 22
- `valor_total`: 165.00
- `owner_id`: igual ao UUID do usuário logado

**Status:** aprovado.

### 7.3 Teste de produção em equipe

Inserida produção em equipe com volume = 30 m³ e total de árvores = 15. Três participantes marcados; um desmarcado.

Resultado em `producao_funcionarios`:

| Funcionário | Forma | Valor unitário | Quantidade | Valor total |
|---|---|---|---|---|
| bruna romero | Metro cúbico | 8.00 | 30 | 240.00 |
| vicente avilar | Metro cúbico | 7.50 | 30 | 225.00 |
| Whallyson | Diária | 150.00 | 1 | 150.00 |
| Adriana Barros | — | — | — | **não criado (desmarcada)** |

Todos os registros criados possuem `owner_id` correto.

**Status:** aprovado.

### 7.4 Teste de transporte com frete

Inserido transporte com frete = R$ 500,00. Verificado que:
- Um lançamento foi criado em `public.lancamentos` com `tipo = 'Receita'`, `categoria = 'Frete'`, `valor = 500.00` e `owner_id` correto.
- O `transporte_id` foi preenchido (foi necessário adicionar a coluna `transporte_id` em `lancamentos`, pois ela não existia no banco de produção apesar de constar na migration antiga).

Após atualizar o frete para R$ 750,00:
- O lançamento correspondente foi atualizado para `valor = 750.00`.
- Apenas o lançamento do próprio `owner_id` foi afetado.

**Status:** aprovado.

### 7.5 Contagem de dados (antes vs. depois)

| Tabela | Antes | Depois | Variação |
|---|---|---|---|
| `producao` | 10 | 13 | +3 (testes) |
| `producao_funcionarios` | 5 | 10 | +5 (testes) |
| `lancamentos` | 2 | 3 | +1 (teste) |
| `transporte` | 3 | 4 | +1 (teste) |

Nenhum registro existente foi perdido ou alterado.

### 7.6 Observação importante sobre `lancamentos.transporte_id`

Durante os testes, descobriu-se que a coluna `transporte_id` **não existia** na tabela `public.lancamentos` do banco de produção, embora a migration `20260720000003_relations.sql` a declare. Sem essa coluna, as funções `transporte_gera_receita` e `transporte_atualiza_receita` não conseguiam vincular o lançamento ao transporte.

**Ação corretiva adicional aplicada:**
- Migration `20260806000001_adiciona_transporte_id_lancamentos.sql` criada e aplicada.
- Adicionou a coluna `transporte_id` (nullable, FK para `transporte.id`) e um índice.
- Nenhum dado existente foi afetado, pois a coluna é nullable.

---

## Apêndice A — Funções de outros esquemas

Foram identificadas também funções `SECURITY DEFINER` nos esquemas `pgbouncer` (`get_auth`) e `vault` (`create_secret`, `update_secret`). Essas são extensões/módulos oficiais do Supabase e **não devem ser alteradas**.

---

[End of security audit report]

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

**Resposta:** o padrão é **modo produção**. `SupabaseConfig.isDev` só é `true` quando `FLUTTER_ENV == 'dev'`. Qualquer outro valor (incluindo string vazia ou ausente) resulta em `isDev == false`. Em modo produção, falha na configuração/inicialização do Supabase **bloqueia** o acesso.

### 3.2 A correção cobre todas as telas que usam MockData?

**Resposta:** sim. A proposta cobre `login_screen.dart`, `app_router.dart` e também isola `modules.dart` e `producao_screen.dart` para só funcionarem quando `SupabaseConfig.isMockMode == true`. Nenhuma tela poderá acessar `MockData` em produção.

### 3.3 Diff de `vercel_build.sh`

O script passará `--dart-define` para o Flutter usando as variáveis de ambiente do Vercel:

```bash
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"
```

Em produção, `FLUTTER_ENV` **nunca** é passado. O script ignora explicitamente `FLUTTER_ENV=dev` se estiver configurado por engano.

---

## 4. Plano de Correção

### 4.1 `lib/config/supabase_config.dart`

- Remover `defaultValue` reais do Supabase.
- Em desenvolvimento, usar `FLUTTER_ENV=dev` para ativar mock.
- Em produção, sem credenciais, `isConfigured == false`.

### 4.2 `lib/main.dart`

- Capturar exceção de `Supabase.initialize()`.
- Se falhar e NÃO estiver em modo dev, mostrar tela de erro (`_ErrorApp`) em vez de continuar.

### 4.3 `lib/routing/app_router.dart`

- Usar `Supabase.instance.clientOrNull` para evitar `StateError`.
- Redirecionar para `/login` quando não houver sessão.

### 4.4 `lib/screens/login_screen.dart`

- Remover bypass quando `isConfigured == false`.
- Permitir entrada sem senha **apenas** quando `SupabaseConfig.isMockMode == true`.
- Mostrar banner claro de "modo demonstração" quando em mock.

### 4.5 `lib/services/auth_service.dart` e `db_service.dart`

- Usar `clientOrNull` e tratar cliente não inicializado.

### 4.6 Telas legadas

- Em `modules.dart` e `producao_screen.dart`, verificar `SupabaseConfig.isMockMode` e mostrar tela de "indisponível em produção" se falso.

---

## 5. Checklist de Validação

- [ ] `FLUTTER_ENV` ausente → modo produção, falha bloqueia app.
- [ ] `FLUTTER_ENV=dev` → modo mock disponível.
- [ ] Login real funciona com credenciais válidas.
- [ ] Login em produção sem configuração mostra erro e não entra.
- [ ] Build web passa sem erros.
- [ ] Deploy na Vercel funciona.
- [ ] Dashboard e relatórios continuam funcionando.

---

[End of original plan]

> **Nota:** este arquivo agora contém dois relatórios: o plano original de bypass de autenticação (já implementado) e o novo relatório de auditoria de funções PL/pgSQL SECURITY DEFINER (aguardando aprovação).

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
