-- SILVORA — Adiciona coluna transporte_id em lancamentos
-- Data: 2026-08-06
-- Projeto: Silvora Florestal (jkwnynwxxfesaagifkhq)
-- Motivo: as funções transporte_gera_receita e transporte_atualiza_receita
-- precisam vincular o lançamento financeiro ao transporte. A migration
-- 20260720000003_relations.sql declara essa coluna, mas ela não existia
-- no banco de produção.

alter table public.lancamentos
  add column if not exists transporte_id uuid references public.transporte(id) on delete set null;

create index if not exists lancamentos_transporte_idx on public.lancamentos(transporte_id);
