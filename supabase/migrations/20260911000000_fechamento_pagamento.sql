-- SILVORA — Fechamento de pagamento com trava de dados no banco
-- Data: 2026-09-11
-- Objetivo: permitir fechar pagamento de um funcionário num período,
-- travar alteração/exclusão de registros pagos e reabrir o fechamento.

-- =========================================================
-- 1. TABELA DE FECHAMENTOS
-- =========================================================
create table if not exists public.pagamento_fechamentos (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  funcionario_id uuid not null references public.funcionarios(id) on delete cascade,
  periodo_inicio date not null,
  periodo_fim date not null,
  valor_total numeric not null default 0,
  total_registros integer not null default 0,
  data_pagamento timestamptz not null default now(),
  pago_por uuid references auth.users(id) default auth.uid(),
  observacoes text,
  created_at timestamptz not null default now(),
  constraint chk_periodo check (periodo_fim >= periodo_inicio)
);

alter table public.pagamento_fechamentos enable row level security;

drop policy if exists "pagamento_fechamentos_own" on public.pagamento_fechamentos;
create policy "pagamento_fechamentos_own" on public.pagamento_fechamentos
  for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create index if not exists pagamento_fechamentos_periodo_idx
  on public.pagamento_fechamentos (owner_id, funcionario_id, periodo_inicio, periodo_fim);

-- =========================================================
-- 2. COLUNAS DE PAGAMENTO EM producao_funcionarios
-- =========================================================
alter table public.producao_funcionarios
  add column if not exists pago boolean not null default false,
  add column if not exists data_pagamento timestamptz,
  add column if not exists fechamento_id uuid references public.pagamento_fechamentos(id) on delete set null;

create index if not exists producao_funcionarios_pago_idx
  on public.producao_funcionarios (owner_id, funcionario_id, pago);

create index if not exists producao_funcionarios_fechamento_idx
  on public.producao_funcionarios (fechamento_id);

-- =========================================================
-- 3. TRIGGER: BLOQUEIA ALTERAÇÃO/EXCLUSÃO DE REGISTRO PAGO
-- =========================================================
create or replace function public.bloqueia_producao_funcionario_pago()
returns trigger
language plpgsql
security invoker set search_path = public
as $$
begin
  if OLD.pago = true then
    if TG_OP = 'DELETE' then
      raise exception 'Registro de produção já pago. Reabra o fechamento antes de excluir.';
    end if;

    if NEW.funcionario_id is distinct from OLD.funcionario_id
      or NEW.producao_id is distinct from OLD.producao_id
      or NEW.participou is distinct from OLD.participou
      or NEW.forma_remuneracao is distinct from OLD.forma_remuneracao
      or NEW.valor_unitario is distinct from OLD.valor_unitario
      or NEW.quantidade_calculo is distinct from OLD.quantidade_calculo
      or NEW.valor_total is distinct from OLD.valor_total then
      raise exception 'Registro de produção já pago. Reabra o fechamento antes de alterar.';
    end if;
  end if;

  return NEW;
end;
$$;

drop trigger if exists producao_funcionarios_bloqueia_pago_trigger on public.producao_funcionarios;
create trigger producao_funcionarios_bloqueia_pago_trigger
  before update or delete on public.producao_funcionarios
  for each row execute function public.bloqueia_producao_funcionario_pago();

-- =========================================================
-- 4. TRIGGER: BLOQUEIA ALTERAÇÃO DE PRODUÇÃO COM PARTICIPANTE PAGO
-- =========================================================
create or replace function public.bloqueia_producao_com_pagamento()
returns trigger
language plpgsql
security invoker set search_path = public
as $$
declare
  v_periodo text;
begin
  if exists (
    select 1 from public.producao_funcionarios
    where producao_id = OLD.id
      and pago = true
      and owner_id = auth.uid()
  ) then
    if NEW.volume_total is distinct from OLD.volume_total
      or NEW.total_arvores is distinct from OLD.total_arvores
      or NEW.data is distinct from OLD.data
      or NEW.tipo_producao is distinct from OLD.tipo_producao
      or NEW.equipe_id is distinct from OLD.equipe_id
      or NEW.funcionario_id is distinct from OLD.funcionario_id
      or NEW.talhao_id is distinct from OLD.talhao_id then

      select coalesce(
        'Fechamento de ' || to_char(min(pf.data_pagamento), 'DD/MM/YYYY') || ' a ' || to_char(max(pf.data_pagamento), 'DD/MM/YYYY'),
        'pagamento fechado'
      ) into v_periodo
      from public.producao_funcionarios pf
      where pf.producao_id = OLD.id and pf.pago = true and pf.owner_id = auth.uid();

      raise exception 'Produção com pagamento fechado (%). Reabra o fechamento antes de alterar campos que afetam cálculo.', v_periodo;
    end if;
  end if;

  return NEW;
end;
$$;

drop trigger if exists producao_bloqueia_pagamento_trigger on public.producao;
create trigger producao_bloqueia_pagamento_trigger
  before update on public.producao
  for each row execute function public.bloqueia_producao_com_pagamento();

-- =========================================================
-- 5. TRIGGER: EXCLUIR PRODUÇÃO COM PARTICIPANTE PAGO
-- =========================================================
create or replace function public.excluir_producao_funcionarios()
returns trigger
language plpgsql
security invoker set search_path = public
as $$
begin
  if exists (
    select 1 from public.producao_funcionarios
    where producao_id = OLD.id
      and pago = true
      and owner_id = auth.uid()
  ) then
    raise exception 'Não é possível excluir produção com pagamento fechado. Reabra o fechamento antes de excluir.';
  end if;

  delete from public.producao_funcionarios
  where producao_id = OLD.id
    and owner_id = auth.uid();
  return OLD;
end;
$$;

drop trigger if exists producao_excluir_funcionarios_trigger on public.producao;
create trigger producao_excluir_funcionarios_trigger
  before delete on public.producao
  for each row execute function public.excluir_producao_funcionarios();

-- =========================================================
-- 6. RPC: FECHAR PAGAMENTO DE UM FUNCIONÁRIO NO PERÍODO
-- =========================================================
create or replace function public.fechar_pagamento_funcionario(
  p_funcionario_id uuid,
  p_inicio date,
  p_fim date
) returns uuid
language plpgsql
security invoker set search_path = public
as $$
declare
  v_existente public.pagamento_fechamentos%rowtype;
  v_valor_total numeric;
  v_total_registros integer;
  v_fechamento_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  -- bloqueia período sobreposto
  select * into v_existente
  from public.pagamento_fechamentos
  where owner_id = auth.uid()
    and funcionario_id = p_funcionario_id
    and periodo_inicio <= p_fim
    and periodo_fim >= p_inicio
  limit 1;

  if found then
    raise exception 'Já existe fechamento para este funcionário no período de % a %. Reabra-o antes de fechar novamente.',
      to_char(v_existente.periodo_inicio, 'DD/MM/YYYY'),
      to_char(v_existente.periodo_fim, 'DD/MM/YYYY');
  end if;

  -- calcula valor e quantidade de registros pendentes no período
  select
    coalesce(sum(pf.valor_total), 0),
    count(*)
  into v_valor_total, v_total_registros
  from public.producao_funcionarios pf
  join public.producao p on p.id = pf.producao_id
  where pf.owner_id = auth.uid()
    and pf.funcionario_id = p_funcionario_id
    and pf.participou = true
    and pf.pago = false
    and p.data between p_inicio and p_fim;

  if v_total_registros = 0 then
    raise exception 'Nenhuma produção pendente no período selecionado.';
  end if;

  -- cria o fechamento
  insert into public.pagamento_fechamentos (
    owner_id, funcionario_id, periodo_inicio, periodo_fim,
    valor_total, total_registros, data_pagamento, pago_por
  ) values (
    auth.uid(), p_funcionario_id, p_inicio, p_fim,
    v_valor_total, v_total_registros, now(), auth.uid()
  ) returning id into v_fechamento_id;

  -- marca os registros como pagos
  update public.producao_funcionarios
  set pago = true,
      data_pagamento = now(),
      fechamento_id = v_fechamento_id
  from public.producao p
  where producao_funcionarios.producao_id = p.id
    and producao_funcionarios.owner_id = auth.uid()
    and producao_funcionarios.funcionario_id = p_funcionario_id
    and producao_funcionarios.participou = true
    and producao_funcionarios.pago = false
    and p.data between p_inicio and p_fim;

  return v_fechamento_id;
end;
$$;

-- =========================================================
-- 7. RPC: REABRIR FECHAMENTO
-- =========================================================
create or replace function public.reabrir_pagamento_funcionario(
  p_fechamento_id uuid
) returns void
language plpgsql
security invoker set search_path = public
as $$
declare
  v_fechamento public.pagamento_fechamentos%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  select * into v_fechamento
  from public.pagamento_fechamentos
  where id = p_fechamento_id
    and owner_id = auth.uid();

  if not found then
    raise exception 'Fechamento não encontrado.';
  end if;

  update public.producao_funcionarios
  set pago = false,
      data_pagamento = null,
      fechamento_id = null
  where fechamento_id = p_fechamento_id
    and owner_id = auth.uid();

  delete from public.pagamento_fechamentos
  where id = p_fechamento_id
    and owner_id = auth.uid();
end;
$$;

-- =========================================================
-- 8. PERMISSÕES
-- =========================================================
grant execute on function public.fechar_pagamento_funcionario(uuid, date, date) to authenticated;
grant execute on function public.reabrir_pagamento_funcionario(uuid) to authenticated;
