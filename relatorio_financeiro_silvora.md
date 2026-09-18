# Relatório de Varredura — Módulo Financeiro do SILVORA

> Data da análise: 18/09/2026
> Base analisada: schema do Supabase (`supabase/migrations/`) + código Flutter (`lib/`)
> Nenhuma alteração foi realizada — este é um relatório de diagnóstico.

---

## 1. Tabelas ligadas ao Financeiro hoje

### 1.1 `public.lancamentos` (tabela principal do Financeiro)

Local de criação: `supabase/migrations/20260720000003_relations.sql` (linhas 73–88).

| Coluna | Tipo | Obrigatória | Default | Observações |
|---|---|---|---|---|
| `id` | uuid | sim | `gen_random_uuid()` | PK |
| `owner_id` | uuid | sim | `auth.uid()` | FK → `auth.users(id)`; base do RLS |
| `tipo` | text | sim | — | check (`'Receita'`, `'Despesa'`) |
| `descricao` | text | sim | — | Texto livre |
| `categoria` | text | não | — | Texto livre (sem FK para tabela de categorias) |
| `valor` | numeric | não | 0 | Valor monetário |
| `data` | date | não | — | Data do lançamento |
| `transporte_id` | uuid | não | — | FK → `public.transporte(id)` on delete set null; adicionada posteriormente por `20260806000001_adiciona_transporte_id_lancamentos.sql` |
| `created_at` | timestamptz | sim | `now()` | — |

**RLS:** `lancamentos_own` — usuário só vê/edita lançamentos onde `owner_id = auth.uid()`.

**Índice:** `lancamentos_transporte_idx` em `transporte_id`.

**Não existem** outras tabelas financeiras como `contas`, `centro_custo`, `planejamento_orcamentario`, `contas_a_pagar`, `contas_a_receber`, `bancos`, `cartoes`, etc. O financeiro é apenas a tabela `lancamentos`.

### 1.2 Tabelas auxiliares que alimentam/indicam o Financeiro

| Tabela | Relação com Financeiro |
|---|---|
| `public.transporte` | Gera receita automaticamente em `lancamentos` via triggers (ver item 2). |
| `public.producao` / `public.producao_funcionarios` | Custos de mão de obra calculados aqui são exibidos no dashboard/financeiro, mas **não geram lançamento de despesa**. |
| `public.pagamento_fechamentos` | Registra o fechamento de pagamento do funcionário, mas **não gera lançamento financeiro de despesa**. |
| `public.clientes` | Cliente do transporte; o preço por m³ influencia a receita de frete, mas não há tabela financeira de "contas a receber" ou "faturas". |

---

## 2. O Financeiro recebe dados automaticamente de outros módulos?

**Sim, mas de apenas um módulo: Transporte.**

### 2.1 Automação existente: Transporte → Receita

**Arquivo:** `supabase/migrations/20260811000000_separga_carga_frete_transporte.sql` (versão atualizada).

| Gatilho | Evento | Ação |
|---|---|---|
| `transporte_gera_receita_trigger` | `AFTER INSERT` em `transporte` | Insere um `lancamentos` do tipo `'Receita'`, categoria `'Frete'`, valor = `frete + calcular_frete_transporte(...)`, com `transporte_id`. |
| `transporte_atualiza_receita_trigger` | `AFTER UPDATE` em `transporte` | Atualiza o valor do lançamento de `'Frete'` vinculado quando o total do transporte muda. |

**Função auxiliar:** `public.calcular_frete_transporte(tipo_frete, distancia_km, valor_km, valor_combinado)`
- Se `tipo_frete = 'km'`: retorna `distancia_km * valor_km`
- Se `tipo_frete = 'combinado'`: retorna `valor_combinado`
- Senão: 0

**Observação importante:** a descrição do lançamento gerado é `'Frete: ' || origem || ' → ' || destino`. O campo `frete` da tabela `transporte` hoje representa a **carga** (volume × preço do cliente), e o cálculo separado representa o **frete propriamente dito**. O lançamento financeiro soma os dois, o que pode gerar confusão semântica: uma mesma viagem gera uma única receita chamada "Frete" que inclui carga + frete.

### 2.2 Módulos que NÃO alimentam o Financeiro automaticamente

| Módulo | Deveria gerar lançamento? | Hoje gera? | Como está |
|---|---|---|---|
| **Produção / Remuneração de funcionários** | Sim — despesa de mão de obra | **Não** | Os valores calculados em `producao_funcionarios` são exibidos em gráficos, mas nenhuma linha é inserida em `lancamentos`. |
| **Fechamento de pagamento** (`pagamento_fechamentos`) | Sim — despesa de pagamento a funcionário | **Não** | A RPC `fechar_pagamento_funcionario` apenas marca registros como pagos; não cria receita/despesa financeira. |
| **Transporte / Venda de carga para cliente** | Sim — receita de venda de madeira | **Não separadamente** | O valor da carga fica dentro do campo `frete` e é somado ao lançamento de "Frete"; não existe categoria `'Venda de madeira'` gerada automaticamente. |
| **Clientes / Pendências** | Possível — contas a receber | **Não** | A tabela `clientes` tem `pendencia numeric`, mas não há vínculo com `lancamentos`. |
| **Equipamentos / Manutenção** | Possível — despesa | **Não** | Apenas cadastro; sem geração financeira. |
| **Estoque** | Possível — despesa/compra | **Não** | Apenas cadastro; sem geração financeira. |
| **Veículos / Combustível** | Possível — despesa | **Não** | Apenas cadastro; sem geração financeira. |

---

## 3. Categorias de despesa/receita

### 3.1 No banco

A coluna `lancamentos.categoria` é **texto livre**, sem tabela auxiliar de categorias e sem constraint `check`. Não há categoria pré-cadastrada no schema.

### 3.2 No Flutter (`lib/data/entities.dart`, linhas 810–818)

O dropdown de cadastro de lançamento oferece as seguintes opções fixas:

- Venda de madeira
- Frete
- Combustível
- Salário
- Manutenção
- EPI / Ferramenta
- Outro

Essas categorias são **apenas sugestões de UI**. O banco aceita qualquer texto. Portanto:
- Não existe "categoria já cadastrada" no banco;
- Existe uma lista fixa de 7 opções no formulário de lançamento.

### 3.3 Categorias usadas automaticamente pelas triggers

Apenas uma: `'Frete'` (gerada pela trigger de transporte).

---

## 4. Pontos que deveriam gerar lançamento financeiro automático, mas hoje não geram

### 4.1 Fechamento de pagamento de funcionário → despesa

**Contexto:** a feature de fechamento de pagamento (`pagamento_fechamentos`) foi implementada recentemente. Ela registra o valor total a pagar por funcionário em um período e trava os registros pagos.

**Gap:** ao executar `fechar_pagamento_funcionario`, o sistema:
- Cria o registro em `pagamento_fechamentos`;
- Marca `producao_funcionarios.pago = true`;
- **Não insere** um lançamento do tipo `'Despesa'`, categoria `'Salário'` (ou similar), no valor do fechamento.

**Impacto:** o financeiro não reflete a saída de caixa real com folha de pagamento. O dashboard mostra "Despesas" zeradas (ou apenas lançamentos manuais) mesmo quando houve pagamento fechado.

### 4.2 Custo de produção (mão de obra) → despesa

**Contexto:** toda produção gera registros em `producao_funcionarios` com `valor_total` calculado.

**Gap:** esses valores são usados apenas para:
- Exibir custo por m³ na tela Financeiro;
- Exibir custo por equipe;
- **Mas nunca viram um `INSERT` em `lancamentos`.**

**Impacto:** o balanço financeiro fica incompleto. Uma produção gera despesa de mão de obra, mas essa despesa não aparece em "Despesas" do dashboard.

### 4.3 Venda de madeira (carga do transporte) → receita separada

**Contexto:** no transporte, o campo `frete` atualmente armazena o valor da carga (volume × preço do cliente), e existe um cálculo separado para o frete propriamente dito.

**Gap:** a trigger gera apenas **um** lançamento de `'Receita'` com categoria `'Frete'` contendo `carga + frete`.

**Impacto:** não é possível saber, no financeiro, quanto foi receita de **venda de madeira** e quanto foi receita de **prestação de serviço de frete**. A categoria `'Venda de madeira'` do dropdown existe, mas nunca é gerada automaticamente.

### 4.4 Pagamento de frete a terceiros / motoristas → despesa

**Contexto:** quando o frete é de terceiro, a empresa pode ter que repassar o valor do frete ao motorista/transportadora.

**Gap:** não existe nenhuma automação que crie uma despesa de `'Frete'` (ou `'Frete terceirizado'`) quando uma viagem gera frete.

**Impacto:** o lucro real de uma viagem (receita bruta - frete pago a terceiro) não é computado automaticamente.

### 4.5 Pendências de clientes → contas a receber

**Contexto:** a tabela `clientes` tem a coluna `pendencia numeric`.

**Gap:** não há integração entre `clientes.pendencia` e `lancamentos`. O valor pendente não vira receita a receber, nem há histórico de quitação.

### 4.6 Compras / estoque / manutenção

**Contexto:** módulos de `estoque`, `equipamentos`, `veiculos` existem.

**Gap:** nenhuma movimentação de compra, baixa de estoque, abastecimento ou manutenção gera despesa financeira automaticamente.

---

## 5. Resumo executivo

| Aspecto | Situação atual |
|---|---|
| Tabela financeira | Apenas `lancamentos` (simples, sem categorias normalizadas, sem contas). |
| Automação de entradas | **Somente Transporte** gera receita automaticamente. |
| Automação de saídas | **Nenhuma**. Não há geração automática de despesa. |
| Categorias | 7 opções fixas no Flutter; texto livre no banco; nenhuma pré-cadastrada. |
| Gaps críticos | 1) Fechamento de pagamento não gera despesa; 2) Produção não gera despesa de mão de obra; 3) Venda de madeira e frete estão somados numa única receita chamada "Frete"; 4) Não há contas a receber/pagar. |

---

## 6. Recomendações preliminares (sem implementar)

1. **Criar tabela `categorias_financeiras`** com `tipo` (Receita/Despesa), `nome` e `padrao`, e vincular `lancamentos.categoria_id` a ela, substituindo o texto livre.
2. **Ao fechar pagamento de funcionário:** inserir despesa em `lancamentos` (categoria `'Salário'` / `'Mão de obra'`) com referência ao `fechamento_id` (novo campo).
3. **Ao registrar produção:** inserir despesa(s) em `lancamentos` para cada `producao_funcionarios` (ou consolidar por dia/funcionário), vinculando via `producao_funcionario_id`.
4. **No transporte:** gerar **dois** lançamentos quando aplicável — um de receita `'Venda de madeira'` (carga) e outro `'Frete'` (frete) — ou, pelo menos, separar a categoria para refletir os dois componentes.
5. **Adicionar campos de vínculo:** `lancamentos.producao_funcionario_id`, `lancamentos.fechamento_id`, `lancamentos.cliente_id`, permitindo rastreabilidade e evitando duplicidade.
6. **Considerar uma tabela `contas`** (Caixa, Banco, etc.) para saber de qual conta o dinheiro saiu/entrou.

---

*Relatório gerado para apoio à decisão. Nenhuma alteração de código ou schema foi aplicada.*
