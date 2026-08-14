# Plano de Feature — Tela de Consulta de Produção por Funcionário/Equipe

> Status: **Aguardando aprovação do usuário antes de qualquer alteração de código.**
> Data: 2026-08-13
> Escopo: módulo Produção do app SILVORA.

---

## 1. Contexto e Objetivo

Hoje o módulo Produção registra produções Individuais e de Equipe, e já calcula automaticamente o valor a receber por funcionário participante na tabela `producao_funcionarios`. No entanto, não existe uma tela consolidada que permita ao usuário visualizar, em um período selecionado, o total produzido e o total a receber por cada funcionário, nem a produtividade das equipes.

O objetivo desta feature é criar uma **tela somente de consulta** (read-only, sem travamento de pagamentos) que mostre:

- **Por funcionário:** volume total (m³), total de árvores e valor total a receber no período (somando produções Individuais + participações em Equipes).
- **Por equipe:** volume total (m³) e total de árvores produzidos pela equipe como um todo no período (visão de produtividade).
- **Detalhamento por funcionário:** lista das produções que compuseram os totais daquele funcionário.

---

## 2. Localização no App

Opções analisadas:

| Opção | Prós | Contras |
|---|---|---|
| **A. Novo item no menu lateral "Consulta de Produção"** | Fácil acesso, visível, não polui telas existentes. | Adiciona mais um item no menu. |
| **B. Aba dentro da tela de Produção existente** | Mantém contexto do módulo. | Tela de listagem já tem filtros e cards; pode ficar carregada. |
| **C. Dentro de Relatórios** | Conceitualmente é um relatório. | Relatórios hoje pode ter formato diferente; perde visibilidade. |
| **D. Dentro do cadastro de Funcionários (botão "Ver produção")** | Lógica centrada no funcionário. | Não cobre visão por equipe; exigiria entrar em cada funcionário. |

**Recomendação:** opção **A** — novo item no menu lateral chamado **"Consulta de Produção"**, posicionado logo abaixo de "Produção". Também adicionar um atalho/mini-card na dashboard apontando para essa tela, se desejado.

Motivo: é uma funcionalidade independente de consulta/relatório, e o usuário precisará acessá-la com frequência para acompanhar pagamentos futuros. Manter separado evita sobrecarregar a listagem atual de produções.

---

## 3. Telas Flutter

### 3.1 Tela principal — `consulta_producao_screen.dart`

Layout sugerido:

- **Topo:** seletor de período (Data inicial + Data final) e botão "Consultar".
- **Resumo geral:** cards com total geral do período (volume, árvores, valor total a pagar).
- **Abas:**
  - **"Por Funcionário"** (default)
  - **"Por Equipe"**
- **Lista por funcionário:**
  - Avatar/nome do funcionário.
  - Volume total, árvores totais, valor total a receber.
  - Toque abre tela de detalhamento.
- **Lista por equipe:**
  - Nome da equipe.
  - Volume total, árvores totais.
  - Toque pode expandir para listar as produções da equipe no período.

### 3.2 Tela de detalhamento — `consulta_producao_funcionario_screen.dart`

- Nome do funcionário e período.
- Cards com os totais.
- Lista cronológica das produções:
  - Data, talhão, tipo (Individual/Equipe), volume/árvores da produção, valor recebido por ele.
- Opcional: agrupar por semana/quinzena se a lista for grande.

---

## 4. Queries Necessárias

### 4.1 Totais por funcionário no período

```sql
SELECT
  f.id AS funcionario_id,
  f.nome AS funcionario_nome,
  COALESCE(SUM(p.volume_total), 0) AS volume_total,
  COALESCE(SUM(p.total_arvores), 0) AS total_arvores,
  COALESCE(SUM(pf.valor_total), 0) AS valor_total
FROM public.funcionarios f
LEFT JOIN public.producao_funcionarios pf
  ON pf.funcionario_id = f.id
LEFT JOIN public.producao p
  ON p.id = pf.producao_id
  AND p.data BETWEEN $1 AND $2
WHERE f.owner_id = auth.uid()
  AND f.situacao = 'Ativo'
GROUP BY f.id, f.nome
ORDER BY valor_total DESC;
```

> Nota: os filtros de período devem ser aplicados tanto em `producao.data` quanto garantir que só somem `producao_funcionarios` daquele período. Se `p.data` for NULL para algum registro, ele não entra no período.

### 4.2 Totais por equipe no período

```sql
SELECT
  e.id AS equipe_id,
  e.nome AS equipe_nome,
  COALESCE(SUM(p.volume_total), 0) AS volume_total,
  COALESCE(SUM(p.total_arvores), 0) AS total_arvores
FROM public.equipes e
LEFT JOIN public.producao p
  ON p.equipe_id = e.id
  AND p.data BETWEEN $1 AND $2
WHERE e.owner_id = auth.uid()
GROUP BY e.id, e.nome
ORDER BY volume_total DESC;
```

### 4.3 Detalhamento das produções de um funcionário no período

```sql
SELECT
  p.id AS producao_id,
  p.data,
  p.tipo_producao,
  t.nome AS talhao_nome,
  p.volume_total,
  p.total_arvores,
  pf.forma_pagamento,
  pf.valor_unitario,
  pf.quantidade_calculo,
  pf.valor_total
FROM public.producao_funcionarios pf
JOIN public.producao p ON p.id = pf.producao_id
LEFT JOIN public.talhoes t ON t.id = p.talhao_id
WHERE pf.funcionario_id = $1
  AND p.data BETWEEN $2 AND $3
  AND p.owner_id = auth.uid()
ORDER BY p.data DESC;
```

### 4.4 Resumo geral do período

```sql
SELECT
  COALESCE(SUM(p.volume_total), 0) AS volume_total,
  COALESCE(SUM(p.total_arvores), 0) AS total_arvores,
  COALESCE(SUM(pf.valor_total), 0) AS valor_total
FROM public.producao p
LEFT JOIN public.producao_funcionarios pf ON pf.producao_id = p.id
WHERE p.owner_id = auth.uid()
  AND p.data BETWEEN $1 AND $2;
```

---

## 5. Considerações Técnicas

- A tela será **read-only**: nenhum insert/update/delete.
- Utilizar `DbService` existente para reutilizar a conexão com Supabase e as políticas de RLS.
- Considerar adicionar um índice em `producao(data)` se ainda não existir, para acelerar filtros por período.
- Campos de data devem ser do tipo `date` (já padronizado na migration de refatoração).
- Tratar funcionários inativos: por padrão, mostrar apenas "Ativo" na listagem, mas oferecer um toggle "Incluir inativos" se o usuário quiser consultar histórico de ex-funcionários.
- A tela não deve carregar dados automaticamente ao abrir — exige confirmação do período para evitar consultas pesadas desde o início dos registros.

---

## 6. Plano de Testes

1. **Cenário base:**
   - Cadastrar uma produção Individual para o funcionário "Vicente Avilar" com 4 m³ no dia 10/08/2026.
   - Cadastrar uma produção de Equipe no dia 12/08/2026 com volume 10 m³, incluindo Vicente como participante.
   - Abrir a tela de consulta, selecionar período 01/08/2026 a 31/08/2026.
   - Verificar se Vicente aparece com volume total 14 m³ e valor total = soma dos dois registros de `producao_funcionarios`.

2. **Filtro de período:**
   - Selecionar um período que não contenha nenhuma produção.
   - Verificar se a lista aparece vazia com mensagem "Nenhum registro no período".

3. **Detalhamento:**
   - Clicar em Vicente e confirmar que aparecem as duas produções (Individual e Equipe) com datas, talhões e valores corretos.

4. **Visão por equipe:**
   - Selecionar o mesmo período.
   - Verificar se a equipe da produção de equipe aparece com volume 10 m³.

5. **Funcionário inativo:**
   - Desativar um funcionário que tenha produção no período.
   - Verificar se ele some da lista padrão e aparece ao ativar "Incluir inativos".

---

## 7. Arquivos Envolvidos (previsão)

- `lib/screens/consulta_producao_screen.dart` (novo)
- `lib/screens/consulta_producao_funcionario_screen.dart` (novo)
- `lib/services/db_service.dart` (possíveis helpers reutilizáveis)
- `lib/widgets/app_drawer.dart` ou local onde o menu lateral é montado (adicionar novo item)
- `lib/screens/dashboard_screen.dart` (opcional: atalho na dashboard)

---

## 8. Decisões Pendentes do Usuário

1. Confirma a localização recomendada (novo item no menu "Consulta de Produção")?
2. Deseja incluir o toggle "Incluir inativos" por padrão ou sempre mostrar todos os funcionários?
3. Deseja um atalho na Dashboard para essa tela?
4. A tela de detalhamento deve permitir exportação (PDF/Excel) nesta primeira versão ou fica para evolução futura?

Aguardo aprovação para iniciar a implementação.
