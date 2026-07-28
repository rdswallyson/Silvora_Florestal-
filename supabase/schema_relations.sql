-- SILVORA — Relacionamentos entre os módulos
-- Rode este SQL DEPOIS do schema_modules.sql.
-- Supabase → SQL Editor → New query → cole tudo → Run.
-- Cria a tabela de veículos, a ligação equipe↔funcionários e as
-- colunas de vínculo (chaves estrangeiras) entre os módulos.

-- ---------- VEÍCULOS (caminhões / muques / reboques) ----------
create table if not exists public.veiculos (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nome text not null,
  tipo text,
  modelo text,
  situacao text default 'Disponível',
  created_at timestamptz not null default now()
);
alter table public.veiculos enable row level security;
drop policy if exists "veiculos_own" on public.veiculos;
create policy "veiculos_own" on public.veiculos for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- ---------- VÍNCULOS (chaves estrangeiras) ----------
-- Talhão pertence a uma Fazenda
alter table public.talhoes
  add column if not exists fazenda_id uuid references public.fazendas(id) on delete set null;

-- Equipamento tem um Responsável (funcionário)
alter table public.equipamentos
  add column if not exists responsavel_id uuid references public.funcionarios(id) on delete set null;

-- Equipe tem Líder (funcionário) e Caminhão (veículo)
alter table public.equipes
  add column if not exists lider_id uuid references public.funcionarios(id) on delete set null,
  add column if not exists veiculo_id uuid references public.veiculos(id) on delete set null;

-- Produção liga Equipe, Talhão e Funcionário
alter table public.producao
  add column if not exists equipe_id uuid references public.equipes(id) on delete set null,
  add column if not exists talhao_id uuid references public.talhoes(id) on delete set null,
  add column if not exists funcionario_id uuid references public.funcionarios(id) on delete set null,
  add column if not exists tipo_pagamento text default 'Metro cúbico',
  add column if not exists valor_unitario numeric default 0,
  add column if not exists observacoes text,
  add column if not exists producao_origem_id uuid references public.producao(id) on delete set null;

-- Transporte liga Veículo, Motorista, Cliente (destino) e Fazenda (origem)
alter table public.transporte
  add column if not exists veiculo_id uuid references public.veiculos(id) on delete set null,
  add column if not exists motorista_id uuid references public.funcionarios(id) on delete set null,
  add column if not exists cliente_id uuid references public.clientes(id) on delete set null,
  add column if not exists fazenda_id uuid references public.fazendas(id) on delete set null,
  add column if not exists data date;

-- O caminhão do transporte agora vem do vínculo; o texto antigo deixa de ser obrigatório
alter table public.transporte alter column caminhao drop not null;

-- ---------- LIGAÇÃO Equipe ↔ Funcionários (integrantes) ----------
create table if not exists public.equipe_membros (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  equipe_id uuid not null references public.equipes(id) on delete cascade,
  funcionario_id uuid references public.funcionarios(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.equipe_membros enable row level security;
drop policy if exists "equipe_membros_own" on public.equipe_membros;
create policy "equipe_membros_own" on public.equipe_membros for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

create index if not exists equipe_membros_equipe_idx
  on public.equipe_membros(equipe_id);

-- ---------- FINANCEIRO (lançamentos) ----------
create table if not exists public.lancamentos (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  tipo text not null check (tipo in ('Receita','Despesa')),
  descricao text not null,
  categoria text,
  valor numeric default 0,
  data date,
  transporte_id uuid references public.transporte(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.lancamentos enable row level security;
drop policy if exists "lancamentos_own" on public.lancamentos;
create policy "lancamentos_own" on public.lancamentos for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- Gera lançamento de receita automaticamente ao inserir transporte com frete
create or replace function public.transporte_gera_receita()
returns trigger as $$
begin
  if NEW.frete is not null and NEW.frete > 0 then
    insert into public.lancamentos (tipo, descricao, categoria, valor, data, transporte_id)
    values ('Receita', 'Frete: ' || COALESCE(NEW.origem,'Origem') || ' → ' || COALESCE(NEW.destino,'Destino'), 'Frete', NEW.frete, NEW.data, NEW.id);
  end if;
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists transporte_gera_receita_trigger on public.transporte;
create trigger transporte_gera_receita_trigger
  after insert on public.transporte
  for each row execute function public.transporte_gera_receita();

-- Atualiza receita vinculada quando o frete muda
 create or replace function public.transporte_atualiza_receita()
returns trigger as $$
begin
  if NEW.frete is distinct from OLD.frete then
    update public.lancamentos
    set valor = COALESCE(NEW.frete, 0)
    where transporte_id = NEW.id and categoria = 'Frete';
  end if;
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists transporte_atualiza_receita_trigger on public.transporte;
create trigger transporte_atualiza_receita_trigger
  after update on public.transporte
  for each row execute function public.transporte_atualiza_receita();

-- ---------- PERFIL DO USUÁRIO (campos extras) ----------
alter table public.profiles
  add column if not exists empresa text,
  add column if not exists telefone text,
  add column if not exists cidade text,
  add column if not exists estado text,
  add column if not exists cpf text,
  add column if not exists cargo text,
  add column if not exists avatar_url text;
