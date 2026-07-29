# Relatório Estrutural Completo — SILVORA (rds_phorestal)

> Data: 2026-07-29
> Repositório: https://github.com/rdswallyson/Silvora_Florestal-
> Web: https://silvora-florestal.vercel.app
> Supabase Project: jkwnynwxxfesaagifkhq (sa-east-1)
> Autor: Wallyson (rdswallyson)

---

## 1. Visão Geral

SILVORA é um aplicativo web/mobile de gestão florestal. Stack principal:

- **Flutter 3.10+** com build Web (CanvasKit / HTML renderer automático)
- **Supabase** (Postgres + Auth + Realtime) como backend
- **Go Router** para navegação declarativa
- **Provider/Riverpod não é usado**; estado gerenciado com StatefulWidget + um helper simples `AppState`
- **Deploy automático na Vercel** via `vercel_build.sh` (clona Flutter stable e roda `flutter build web --release`)
- **Migrations do Supabase** versionadas em `supabase/migrations/` e aplicadas por GitHub Actions

O projeto nasceu como RDS Florestal e foi renomeado para SILVORA. O objetivo é operacional: cadastrar funcionários, equipes, talhões, registrar produção, transporte, estoque, equipamentos e financeiro, com dashboards e relatórios.

---

## 2. Estrutura de Pastas

```
rds_phorestal/
├── .github/workflows/supabase-migrations.yml   # CI de migrations no Supabase
├── lib/
│   ├── config/
│   │   └── supabase_config.dart                # url + anon key (hardcoded, defaultValue)
│   ├── data/
│   │   ├── entities.dart                       # definição de todas as entidades/telas
│   │   └── mock_data.dart                      # dados fake para visualização offline
│   ├── models/                                 # modelos tipados simples
│   ├── routing/
│   │   └── app_router.dart                     # GoRouter com shell e rotas
│   ├── screens/                                # todas as telas
│   │   ├── login_screen.dart
│   │   ├── cadastro_screen.dart
│   │   ├── app_shell.dart                      # layout com bottom tabs
│   │   ├── dashboard_screen.dart
│   │   ├── entity_list_screen.dart             # listagem genérica de qualquer entidade
│   │   ├── entity_detail_screen.dart           # detalhes/edição genérica
│   │   ├── entity_form_screen.dart             # formulário genérico
│   │   ├── financeiro_screen.dart
│   │   ├── relatorios_screen.dart
│   │   ├── ia_screen.dart                      # assistente IA (simulado)
│   │   ├── configuracoes_screen.dart
│   │   ├── producao_form_screen.dart           # NOVO: tela customizada de produção
│   │   └── (outras telas específicas)
│   ├── services/
│   │   ├── auth_service.dart                   # login/cadastro/recuperação
│   │   ├── db_service.dart                     # CRUD genérico no Supabase
│   │   └── producao_calculo_service.dart       # NOVO: cálculo de remuneração
│   ├── state/
│   │   └── app_state.dart                      # estado global mínimo
│   ├── theme/
│   │   └── app_theme.dart                      # BrandColors, tipografia, tema
│   ├── widgets/
│   │   └── common.dart                         # componentes reutilizáveis
│   └── main.dart                               # entrypoint
├── supabase/
│   └── migrations/
│       ├── 20260720000001_auth.sql             # auth + profiles
│       ├── 20260720000002_modules.sql          # tabelas principais
│       ├── 20260720000003_relations.sql        # FKs, equipe_membros, financeiro
│       └── 20260721000000_refatora_producao.sql # NOVO: refatoração produção
├── web/
│   ├── index.html
│   └── manifest.json
├── vercel.json                                 # regras de roteamento SPA/assets
├── vercel_build.sh                             # script de build Flutter na Vercel
└── pubspec.yaml
```

---

## 3. Arquitetura do Banco de Dados

### 3.1 Tabelas Principais (supabase/migrations/)

Todas as tabelas têm `id uuid`, `owner_id uuid default auth.uid()`, `created_at timestamptz default now()` e RLS por `owner_id`.

| Tabela | Responsabilidade |
|--------|------------------|
| `profiles` | Perfil do usuário autenticado (empresa, telefone, cidade, etc.) |
| `funcionarios` | Cadastro de funcionários com configuração de remuneração |
| `equipes` | Cadastro de equipes com líder e veículo |
| `equipe_membros` | Ligação N:N entre equipes e funcionários |
| `fazendas` | Cadastro de fazendas |
| `talhoes` | Talhões vinculados a fazendas |
| `producao` | Registro de produção (volume/árvores/data/talhão) |
| `producao_funcionarios` | Participantes e valores calculados por funcionário (NOVO) |
| `clientes` | Clientes de transporte |
| `veiculos` | Caminhões, muques, reboques |
| `transporte` | Viagens de transporte (origem/destino/frete) |
| `lancamentos` | Financeiro: receitas e despesas |
| `equipamentos` | Máquinas/equipamentos |
| `estoque` | Insumos/material |

### 3.2 Refatoração da Produção (20260721000000_refatora_producao.sql)

A tabela `producao` foi simplificada:

- Removeu: `equipe text`, `talhao text`, `data text`, `tipo_pagamento`, `valor_unitario`, `producao_origem_id`
- Adicionou: `tipo_producao`, `equipe_id`, `talhao_id`, `funcionario_id`, `data date`, `volume_total numeric`, `total_arvores int`, `observacoes text`

Nova tabela `producao_funcionarios` armazena:

- `producao_id`, `funcionario_id`, `participou`
- `forma_remuneracao`, `valor_unitario`, `quantidade_calculo`, `valor_total`

Regras:

- Cada funcionário calculado individualmente
- Nunca divide volume/valor entre participantes
- Valores históricos preservados em `producao_funcionarios`

Funções PL/pgSQL:

- `calcular_remuneracao_producao(uuid, numeric, int, numeric)` — retorna os dados de cálculo
- `gerar_producao_funcionarios()` — trigger `after insert` em `producao` para criar registro individual automaticamente
- `excluir_producao_funcionarios()` — trigger `before delete` em `producao` para limpar participantes

### 3.3 Configuração de Remuneração do Funcionário

Tabela `funcionarios` agora tem:

- `forma_remuneracao`: Diária, Metro cúbico, Árvore, Hora, Produção fixa
- `valor_diaria`, `valor_hora`, `valor_m3`, `valor_arvore`, `valor_producao_fixa`
- `situacao`: Ativo/Inativo

Campos antigos `forma_pagamento` e `valor_base` ainda existem para compatibilidade.

---

## 4. Camadas do Aplicativo Flutter

### 4.1 Configuração

`lib/config/supabase_config.dart` contém a URL e anon key do Supabase. Há um fallback para mock quando não conectado, o que historicamente causava bypass de login.

### 4.2 Serviços

`Db` (`lib/services/db_service.dart`) é um CRUD genérico:

- `list(table, {select, orderBy, ascending})`
- `options(table)`
- `insert(table, data)` — agora retorna `Map<String, dynamic>`
- `insertReturningId(table, data)`
- `insertMany(table, rows)`
- `update(table, id, data)`
- `delete(table, id)`
- `setJoin(...)`

`AuthService` faz login com e-mail, CPF ou telefone, cadastro, recuperação de senha e logout.

`ProducaoCalculoService` (NOVO):

- `calcular(funcionario, volume, arvores, horas)`
- `salvarProducao(...)` — cria `producao` + `producao_funcionarios`

### 4.3 Entidades

`lib/data/entities.dart` define `EntityDef` para cada módulo. Cada entidade descreve:

- `table`, `title`, `noun`, `icon`, `selectQuery`
- Lista de `FieldDef` (tipo, label, referência, obrigatoriedade, etc.)
- `formatRow`, `headerOf`, `detailBuilder`

As telas `entity_list_screen`, `entity_form_screen` e `entity_detail_screen` são genéricas e usam essas definições.

### 4.4 Navegação

Go Router em `app_router.dart`:

```
/login
/cadastro
/ (shell)
  /home       -> DashboardScreen
  /producao   -> EntityListScreen(entity: producao)
  /equipes    -> EntityListScreen(entity: equipes)
  /funcionarios -> EntityListScreen(entity: funcionarios)
  /talhoes    -> ...
  /transporte -> ...
  /financeiro -> FinanceiroScreen
  /relatorios -> RelatoriosScreen
  /ia         -> IaScreen
  /configuracoes -> ConfiguracoesScreen
```

### 4.5 Telas Específicas

- `DashboardScreen`: cards com resumo de produção, transporte, financeiro, estoque; gráficos de produção por dia/semana.
- `FinanceiroScreen`: resumo de receitas/despesas, gráficos por categoria, custos por equipe.
- `RelatoriosScreen`: visão consolidada com KPIs.
- `IaScreen`: assistente que responde perguntas sobre os dados do app.
- `ProducaoFormScreen` (NOVO): formulário customizado para Individual/Equipe.

---

## 5. Tela de Produção (NOVA)

Arquivo: `lib/screens/producao_form_screen.dart`

Fluxo:

1. Usuário seleciona `Individual` ou `Equipe`.
2. Se Individual: dropdown de funcionário ativo.
3. Se Equipe: dropdown de equipe + lista de integrantes ativos com checkbox (todos marcados por padrão).
4. Informa talhão, data, volume total, total de árvores, observação.
5. Ao salvar, `ProducaoCalculoService.salvarProducao`:
   - Insere em `producao`
   - Para cada participante selecionado, calcula conforme `forma_remuneracao` e insere em `producao_funcionarios`

A listagem (`entity_list_screen.dart`) tem um toggle para alternar entre:

- Visualização agrupada (registros de `producao`)
- Visualização individual (registros de `producao_funcionarios`)

---

## 6. Build e Deploy

### 6.1 Vercel

- Framework preset: Other
- Build command: `npm run vercel-build`
- Output directory: `build/web`
- `vercel_build.sh` clona Flutter stable para `/tmp/flutter` e roda `flutter build web --release`
- `vercel.json` serve arquivos estáticos (`flutter_bootstrap.js`, `assets/`, `icons/`, `.js`, `.wasm`, `.json`, `.png`) e faz fallback para `index.html` nas rotas SPA

### 6.2 Problemas Recentes de Build

- Build mais recente (commit `38cef97`) foi enviado para corrigir assinatura de `Db.list` e import relativo.
- Status aguardando confirmação.

### 6.3 CI do Supabase

`.github/workflows/supabase-migrations.yml` roda `supabase db push` a cada push na `main` usando secrets:

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_DB_PASSWORD`

---

## 7. Segurança e Pontos de Atenção

1. **Chave Supabase hardcoded** — anon key em `supabase_config.dart` com `defaultValue`. Não é um segredo crítico, mas idealmente deveria vir de variável de ambiente.
2. **Bypass de login** — quando o Supabase não está configurado, o app carrega mock data e permite navegação. Isso foi intencional para testes, mas deve ser removido em produção.
3. **Botão de logout** — em `app_shell.dart` pode não chamar `signOut()` corretamente.
4. **RLS** — todas as tabelas têm RLS por `owner_id`, mas funções PL/pgSQL usam `security definer`, então precisam ser auditadas.

---

## 8. Dependências Principais

```yaml
dependencies:
  flutter:
    sdk: flutter
  supabase_flutter: ^2.8.4
  go_router: ^14.8.1
  intl: ^0.19.0
  fl_chart: ^0.70.2
  shared_preferences: ^2.5.3
  # ... outras
```

---

## 9. Convenções de Código

- Nomenclatura em português para domínio e telas.
- Helpers `_s`, `_d`, `_i`, `_ref` em `entity_detail_screen.dart` para ler valores dinâmicos do Supabase.
- Uso extensivo de `Map<String, dynamic>` nos formulários genéricos.
- Widgets reutilizáveis em `lib/widgets/common.dart`: `SectionTitle`, `InfoRow`, `StatusChip`, etc.

---

## 10. Próximos Passos Sugeridos

1. Confirmar build na Vercel após último commit.
2. Aplicar migration `20260721000000_refatora_producao.sql` no Supabase (normalmente via GitHub Actions).
3. Testar cadastro de produção individual e em equipe.
4. Implementar módulo de Fechamento de Pagamentos (consolidar `producao_funcionarios` por período e exportar PDF/Excel).
5. Migrar anon key para variável de ambiente e remover bypass de login.

---

## 11. Links

- Repositório: https://github.com/rdswallyson/Silvora_Florestal-
- Deploy: https://silvora-florestal.vercel.app
- Supabase: https://supabase.com/dashboard/project/jkwnynwxxfesaagifkhq
