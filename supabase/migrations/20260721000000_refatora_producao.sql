-- SILVORA — Refatoração do módulo Produção
-- Objetivo: remover tipo de pagamento da tela de produção, calcular remuneração
-- individualmente conforme cadastro do funcionário e separar participantes em
-- producao_funcionarios.

-- =========================================================
-- 1. AJUSTA TABELA FUNCIONARIOS
-- =========================================================
-- Garante campos de configuração de remuneração
alter table public.funcionarios
  add column if not exists forma_remuneracao text default 'Metro cúbico'
    check (forma_remuneracao in ('Diária','Metro cúbico','Árvore','Hora','Produção fixa')),
  add column if not exists valor_diaria numeric default 0,
  add column if not exists valor_hora numeric default 0,
  add column if not exists valor_m3 numeric default 0,
  add column if not exists valor_arvore numeric default 0,
  add column if not exists valor_producao_fixa numeric default 0,
  add column if not exists situacao text default 'Ativo'
    check (situacao in ('Ativo','Inativo'));

-- Migra valores antigos se forma_pagamento ainda existir
update public.funcionarios
set forma_remuneracao = coalesce(forma_pagamento, 'Metro cúbico')
where forma_remuneracao is null;

-- =========================================================
-- 2. REFATORA TABELA PRODUÇÃO
-- =========================================================
-- Converte coluna data para date (caso ainda seja text)
alter table public.producao
  add column if not exists data_date date;

update public.producao
set data_date = case
  when data ~ '^\\d{4}-\\d{2}-\\d{2}$' then data::date
  when data ~ '^\\d{2}/\\d{2}/\\d{4}$' then to_date(data, 'DD/MM/YYYY')
  else null
end
where data_date is null and data is not null;

alter table public.producao drop column if exists data;
alter table public.producao rename column data_date to data;

-- Remove colunas que não serão mais usadas
alter table public.producao drop column if exists tipo_pagamento;
alter table public.producao drop column if exists valor_unitario;
alter table public.producao drop column if exists producao_origem_id;

-- Renomeia e ajusta colunas de vínculo
alter table public.producao drop column if exists equipe;
alter table public.producao drop column if exists talhao;

-- Garante colunas de vínculo e tipo
alter table public.producao
  add column if not exists tipo_producao text not null default 'Individual'
    check (tipo_producao in ('Individual','Equipe')),
  add column if not exists equipe_id uuid references public.equipes(id) on delete set null,
  add column if not exists talhao_id uuid references public.talhoes(id) on delete set null,
  add column if not exists funcionario_id uuid references public.funcionarios(id) on delete set null,
  add column if not exists volume_total numeric default 0,
  add column if not exists total_arvores int default 0,
  add column if not exists observacoes text;

-- =========================================================
-- 3. CRIA TABELA PRODUCAO_FUNCIONARIOS
-- =========================================================
create table if not exists public.producao_funcionarios (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  producao_id uuid not null references public.producao(id) on delete cascade,
  funcionario_id uuid not null references public.funcionarios(id) on delete cascade,
  participou boolean not null default true,
  forma_remuneracao text not null
    check (forma_remuneracao in ('Diária','Metro cúbico','Árvore','Hora','Produção fixa')),
  valor_unitario numeric not null default 0,
  quantidade_calculo numeric not null default 0,
  valor_total numeric not null default 0,
  created_at timestamptz not null default now()
);

alter table public.producao_funcionarios enable row level security;

drop policy if exists "producao_funcionarios_own" on public.producao_funcionarios;
create policy "producao_funcionarios_own" on public.producao_funcionarios for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- Índices úteis
 create index if not exists producao_funcionarios_producao_idx
  on public.producao_funcionarios(producao_id);
create index if not exists producao_funcionarios_funcionario_idx
  on public.producao_funcionarios(funcionario_id);

-- =========================================================
-- 4. FUNÇÃO DE CÁLCULO INDIVIDUAL
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
security definer set search_path = public
as $$
declare
  v_func public.funcionarios%rowtype;
  v_forma text;
  v_unitario numeric;
  v_qtd numeric;
  v_total numeric;
begin
  select * into v_func from public.funcionarios where id = p_funcionario_id;

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
-- 5. FUNÇÃO PARA CRIAR REGISTROS AUTOMATICAMENTE
-- =========================================================
create or replace function public.gerar_producao_funcionarios()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  -- Produção individual: cria um registro para o funcionário
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

-- Trigger para produção individual
drop trigger if exists producao_gerar_funcionarios_trigger on public.producao;
create trigger producao_gerar_funcionarios_trigger
  after insert on public.producao
  for each row execute function public.gerar_producao_funcionarios();

-- =========================================================
-- 6. FUNÇÃO PARA EXCLUIR PARTICIPANTES AO EXCLUIR PRODUÇÃO
-- =========================================================
create or replace function public.excluir_producao_funcionarios()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  delete from public.producao_funcionarios where producao_id = OLD.id;
  return OLD;
end;
$$;

drop trigger if exists producao_excluir_funcionarios_trigger on public.producao;
create trigger producao_excluir_funcionarios_trigger
  before delete on public.producao
  for each row execute function public.excluir_producao_funcionarios();

-- =========================================================
-- 7. PERMISSÃO PARA USUÁRIOS AUTENTICADOS EXECUTAREM FUNÇÕES
-- =========================================================
grant execute on function public.calcular_remuneracao_producao(uuid, numeric, int, numeric) to authenticated;
grant execute on function public.calcular_remuneracao_producao(uuid, numeric, int) to authenticated;
