-- SILVORA — Tabelas dos módulos operacionais
-- Rode este SQL no painel: Supabase → SQL Editor → New query → Run.
-- Cada linha pertence ao usuário que a criou (owner_id). A segurança (RLS)
-- garante que cada conta só enxerga e edita os próprios dados.

-- =========================================================
-- Função auxiliar: aplica RLS "somente o dono" em uma tabela
-- (executada manualmente por tabela abaixo)
-- =========================================================

-- ---------- FUNCIONÁRIOS ----------
create table if not exists public.funcionarios (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nome text not null,
  cargo text,
  telefone text,
  cpf text,
  rg text,
  endereco text,
  data_admissao text,
  forma_pagamento text default 'Metro cúbico',
  valor_base numeric default 0,
  salario numeric default 0,
  pix text,
  contato_emergencia text,
  situacao text default 'Ativo',
  created_at timestamptz not null default now()
);
alter table public.funcionarios enable row level security;
drop policy if exists "funcionarios_own" on public.funcionarios;
create policy "funcionarios_own" on public.funcionarios for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- ---------- EQUIPES ----------
create table if not exists public.equipes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nome text not null,
  lider text,
  integrantes int default 0,
  caminhao text,
  area text,
  created_at timestamptz not null default now()
);
alter table public.equipes enable row level security;
drop policy if exists "equipes_own" on public.equipes;
create policy "equipes_own" on public.equipes for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- ---------- FAZENDAS ----------
create table if not exists public.fazendas (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nome text not null,
  proprietario text,
  municipio text,
  uf text,
  area_ha numeric default 0,
  created_at timestamptz not null default now()
);
alter table public.fazendas enable row level security;
drop policy if exists "fazendas_own" on public.fazendas;
create policy "fazendas_own" on public.fazendas for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- ---------- TALHÕES ----------
create table if not exists public.talhoes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  codigo text not null,
  especie text,
  idade_anos int default 0,
  area_ha numeric default 0,
  volume_m3 numeric default 0,
  situacao text default 'Em crescimento',
  created_at timestamptz not null default now()
);
alter table public.talhoes enable row level security;
drop policy if exists "talhoes_own" on public.talhoes;
create policy "talhoes_own" on public.talhoes for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- ---------- PRODUÇÃO ----------
create table if not exists public.producao (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  equipe text,
  talhao text,
  data text,
  volume_m3 numeric default 0,
  arvores int default 0,
  created_at timestamptz not null default now()
);
alter table public.producao enable row level security;
drop policy if exists "producao_own" on public.producao;
create policy "producao_own" on public.producao for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- ---------- CLIENTES ----------
create table if not exists public.clientes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nome text not null,
  tipo text,
  cidade text,
  pendencia numeric default 0,
  created_at timestamptz not null default now()
);
alter table public.clientes enable row level security;
drop policy if exists "clientes_own" on public.clientes;
create policy "clientes_own" on public.clientes for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- ---------- EQUIPAMENTOS ----------
create table if not exists public.equipamentos (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nome text not null,
  tipo text,
  horas int default 0,
  situacao text default 'Operando',
  created_at timestamptz not null default now()
);
alter table public.equipamentos enable row level security;
drop policy if exists "equipamentos_own" on public.equipamentos;
create policy "equipamentos_own" on public.equipamentos for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- ---------- ESTOQUE ----------
create table if not exists public.estoque (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nome text not null,
  quantidade int default 0,
  minimo int default 0,
  unidade text default 'un',
  created_at timestamptz not null default now()
);
alter table public.estoque enable row level security;
drop policy if exists "estoque_own" on public.estoque;
create policy "estoque_own" on public.estoque for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- ---------- TRANSPORTE ----------
create table if not exists public.transporte (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  caminhao text not null,
  origem text,
  destino text,
  volume_m3 numeric default 0,
  frete numeric default 0,
  created_at timestamptz not null default now()
);
alter table public.transporte enable row level security;
drop policy if exists "transporte_own" on public.transporte;
create policy "transporte_own" on public.transporte for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
