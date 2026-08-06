-- SILVORA — Correção de segurança em funções SECURITY DEFINER
-- Data: 2026-08-06
-- Projeto: Silvora Florestal (jkwnynwxxfesaagifkhq)
-- Objetivo: trocar funções que acessam/modificam tabelas RLS por owner_id
-- para SECURITY INVOKER, garantindo que auth.uid() seja respeitado.

-- =========================================================
-- 1. calcular_remuneracao_producao
-- =========================================================
create or replace function public.calcular_remuneracao_producao(
  p_funcionario_id uuid,
  p_volume numeric,
  p_arvores int,
  p_horas numeric default 1
) returns table(
  forma_remuneracao text,
  valor_unitario numeric,
  quantidade_calculo numeric,
  valor_total numeric
)
language plpgsql
security invoker set search_path = public
as $$
declare
  v_func public.funcionarios%rowtype;
  v_forma text;
  v_unitario numeric;
  v_qtd numeric;
  v_total numeric;
begin
  select * into v_func
  from public.funcionarios
  where id = p_funcionario_id
    and owner_id = auth.uid();

  if not found then
    return;
  end if;

  v_forma := coalesce(v_func.forma_remuneracao, 'Metro cúbico');

  case v_forma
    when 'Diária' then
      v_unitario := coalesce(v_func.valor_diaria, 0);
      v_qtd := 1;
      v_total := v_unitario;
    when 'Hora' then
      v_unitario := coalesce(v_func.valor_hora, 0);
      v_qtd := coalesce(p_horas, 1);
      v_total := v_unitario * v_qtd;
    when 'Metro cúbico' then
      v_unitario := coalesce(v_func.valor_m3, 0);
      v_qtd := coalesce(p_volume, 0);
      v_total := v_unitario * v_qtd;
    when 'Árvore' then
      v_unitario := coalesce(v_func.valor_arvore, 0);
      v_qtd := coalesce(p_arvores, 0);
      v_total := v_unitario * v_qtd;
    when 'Produção fixa' then
      v_unitario := coalesce(v_func.valor_producao_fixa, 0);
      v_qtd := 1;
      v_total := v_unitario;
    else
      v_unitario := 0;
      v_qtd := 0;
      v_total := 0;
  end case;

  return query select v_forma, v_unitario, v_qtd, v_total;
end;
$$;

-- =========================================================
-- 2. gerar_producao_funcionarios (trigger AFTER INSERT em producao)
-- =========================================================
create or replace function public.gerar_producao_funcionarios()
returns trigger
language plpgsql
security invoker set search_path = public
as $$
begin
  if NEW.owner_id is distinct from auth.uid() then
    raise exception 'owner_id inválido na produção';
  end if;

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
$$;

-- =========================================================
-- 3. excluir_producao_funcionarios (trigger BEFORE DELETE em producao)
-- =========================================================
create or replace function public.excluir_producao_funcionarios()
returns trigger
language plpgsql
security invoker set search_path = public
as $$
begin
  delete from public.producao_funcionarios
  where producao_id = OLD.id
    and owner_id = auth.uid();
  return OLD;
end;
$$;

-- =========================================================
-- 4. transporte_gera_receita (trigger AFTER INSERT em transporte)
-- =========================================================
create or replace function public.transporte_gera_receita()
returns trigger
language plpgsql
security invoker set search_path = public
as $$
begin
  if NEW.frete is not null and NEW.frete > 0 then
    insert into public.lancamentos (
      owner_id, tipo, descricao, categoria, valor, data, transporte_id
    )
    values (
      auth.uid(),
      'Receita',
      'Frete: ' || coalesce(NEW.origem,'Origem') || ' → ' || coalesce(NEW.destino,'Destino'),
      'Frete',
      NEW.frete,
      NEW.data,
      NEW.id
    );
  end if;
  return NEW;
end;
$$;

-- =========================================================
-- 5. transporte_atualiza_receita (trigger AFTER UPDATE em transporte)
-- =========================================================
create or replace function public.transporte_atualiza_receita()
returns trigger
language plpgsql
security invoker set search_path = public
as $$
begin
  if NEW.frete is distinct from OLD.frete then
    update public.lancamentos
    set valor = coalesce(NEW.frete, 0)
    where transporte_id = NEW.id
      and categoria = 'Frete'
      and owner_id = auth.uid();
  end if;
  return NEW;
end;
$$;

-- =========================================================
-- 6. GARANTE PERMISSÕES DE EXECUÇÃO
-- =========================================================
grant execute on function public.calcular_remuneracao_producao(uuid, numeric, int, numeric) to authenticated;
grant execute on function public.gerar_producao_funcionarios() to authenticated;
grant execute on function public.excluir_producao_funcionarios() to authenticated;
grant execute on function public.transporte_gera_receita() to authenticated;
grant execute on function public.transporte_atualiza_receita() to authenticated;
