-- SILVORA — Separação de Carga e Frete no módulo Transporte
-- Data: 2026-08-11
-- Projeto: Silvora Florestal (jkwnynwxxfesaagifkhq)
-- Objetivo: separar o valor da carga (volume x preço do cliente) do frete,
-- permitindo dois modos de cálculo do frete: por km ou valor combinado.

-- =========================================================
-- 1. ADICIONA NOVAS COLUNAS NA TABELA transporte
-- =========================================================
alter table public.transporte
  add column if not exists distancia_km numeric,
  add column if not exists valor_km numeric,
  add column if not exists tipo_frete text check (tipo_frete in ('km', 'combinado')),
  add column if not exists valor_combinado numeric;

-- Garante default defensivo para a carga (campo frete, renomeado na UI)
alter table public.transporte
  alter column frete set default 0;

-- =========================================================
-- 2. FUNÇÃO AUXILIAR: calcula o frete de um registro de transporte
-- =========================================================
create or replace function public.calcular_frete_transporte(
  p_tipo_frete text,
  p_distancia_km numeric,
  p_valor_km numeric,
  p_valor_combinado numeric
) returns numeric
language plpgsql
security invoker set search_path = public
as $$
begin
  if p_tipo_frete = 'km' then
    return coalesce(p_distancia_km, 0) * coalesce(p_valor_km, 0);
  elsif p_tipo_frete = 'combinado' then
    return coalesce(p_valor_combinado, 0);
  else
    return 0;
  end if;
end;
$$;

-- =========================================================
-- 3. transporte_gera_receita (AFTER INSERT em transporte)
-- =========================================================
create or replace function public.transporte_gera_receita()
returns trigger
language plpgsql
security invoker set search_path = public
as $$
declare
  v_frete numeric;
  v_total numeric;
begin
  v_frete := public.calcular_frete_transporte(
    NEW.tipo_frete,
    NEW.distancia_km,
    NEW.valor_km,
    NEW.valor_combinado
  );

  v_total := coalesce(NEW.frete, 0) + v_frete;

  if v_total > 0 then
    insert into public.lancamentos (
      owner_id, tipo, descricao, categoria, valor, data, transporte_id
    )
    values (
      auth.uid(),
      'Receita',
      'Frete: ' || coalesce(NEW.origem,'Origem') || ' → ' || coalesce(NEW.destino,'Destino'),
      'Frete',
      v_total,
      NEW.data,
      NEW.id
    );
  end if;

  return NEW;
end;
$$;

-- =========================================================
-- 4. transporte_atualiza_receita (AFTER UPDATE em transporte)
-- =========================================================
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
  v_frete_old := public.calcular_frete_transporte(
    OLD.tipo_frete,
    OLD.distancia_km,
    OLD.valor_km,
    OLD.valor_combinado
  );
  v_total_old := coalesce(OLD.frete, 0) + v_frete_old;

  v_frete_new := public.calcular_frete_transporte(
    NEW.tipo_frete,
    NEW.distancia_km,
    NEW.valor_km,
    NEW.valor_combinado
  );
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

-- =========================================================
-- 5. GARANTE PERMISSÕES DE EXECUÇÃO
-- =========================================================
grant execute on function public.calcular_frete_transporte(text, numeric, numeric, numeric) to authenticated;
grant execute on function public.transporte_gera_receita() to authenticated;
grant execute on function public.transporte_atualiza_receita() to authenticated;
