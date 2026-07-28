-- SILVORA — Ajustes extras: tabela de perfis, RLS e colunas faltantes.
-- Rode no Supabase → SQL Editor → New query → Run.

-- Garante que a tabela profiles existe (Supabase Auth costuma criar, mas
-- caso não exista, criamos aqui com a mesma estrutura esperada).
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  empresa text,
  telefone text,
  cidade text,
  estado text,
  cpf text,
  cargo text,
  avatar_url text,
  updated_at timestamptz default now(),
  created_at timestamptz default now()
);

-- Habilita RLS
alter table public.profiles enable row level security;

-- Política: cada usuário vê e edita apenas o próprio perfil
drop policy if exists "profiles_own" on public.profiles;
create policy "profiles_own" on public.profiles for all
  using (auth.uid() = id) with check (auth.uid() = id);

-- Garante todas as colunas que o app Configurações espera
alter table public.profiles
  add column if not exists full_name text,
  add column if not exists email text,
  add column if not exists empresa text,
  add column if not exists telefone text,
  add column if not exists cidade text,
  add column if not exists estado text,
  add column if not exists cpf text,
  add column if not exists cargo text,
  add column if not exists avatar_url text,
  add column if not exists updated_at timestamptz default now(),
  add column if not exists created_at timestamptz default now();

-- Trigger: ao criar usuário no auth, cria perfil vazio automaticamente
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, full_name)
  values (NEW.id, NEW.email, NEW.raw_user_meta_data->>'nome');
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
