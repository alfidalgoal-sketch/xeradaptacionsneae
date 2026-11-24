-- =====================================================================
-- SOCIOGRAMA DE AULA — táboas e funcións para Supabase
-- Pégase enteiro en Supabase → SQL Editor → New query → Run.
-- Pódese executar máis dunha vez sen problema.
-- Non modifica ningunha táboa existente: só crea as que comezan por sg_
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Táboas ----------
create table if not exists public.sg_grupos (
  id         uuid primary key default gen_random_uuid(),
  owner      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nome       text not null,
  modelo     text not null check (modelo in ('A','B')),
  codigo     text not null unique,
  activo     boolean not null default true,
  creado_en  timestamptz not null default now()
);

create table if not exists public.sg_alumnos (
  id        uuid primary key default gen_random_uuid(),
  grupo_id  uuid not null references public.sg_grupos(id) on delete cascade,
  nome      text not null,
  codigo    text not null unique,
  orde      int  not null default 0
);
create index if not exists sg_alumnos_grupo_idx on public.sg_alumnos(grupo_id);

create table if not exists public.sg_respostas (
  alumno_id  uuid primary key references public.sg_alumnos(id) on delete cascade,
  grupo_id   uuid not null references public.sg_grupos(id) on delete cascade,
  datos      jsonb not null,
  creado_en  timestamptz not null default now()
);
create index if not exists sg_respostas_grupo_idx on public.sg_respostas(grupo_id);

-- ---------- Seguridade: cada orientador/a só ve os seus grupos ----------
alter table public.sg_grupos    enable row level security;
alter table public.sg_alumnos   enable row level security;
alter table public.sg_respostas enable row level security;

drop policy if exists sg_grupos_owner    on public.sg_grupos;
drop policy if exists sg_alumnos_owner   on public.sg_alumnos;
drop policy if exists sg_respostas_owner on public.sg_respostas;

create policy sg_grupos_owner on public.sg_grupos for all to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());

create policy sg_alumnos_owner on public.sg_alumnos for all to authenticated
  using (exists (select 1 from public.sg_grupos g where g.id = grupo_id and g.owner = auth.uid()))
  with check (exists (select 1 from public.sg_grupos g where g.id = grupo_id and g.owner = auth.uid()));

create policy sg_respostas_owner on public.sg_respostas for all to authenticated
  using (exists (select 1 from public.sg_grupos g where g.id = grupo_id and g.owner = auth.uid()))
  with check (exists (select 1 from public.sg_grupos g where g.id = grupo_id and g.owner = auth.uid()));

-- ---------- Funcións públicas (titores e alumnado, sen conta) ----------
-- Só permiten: ver a lista de nomes dun grupo activo e ENVIAR respostas.
-- Nunca permiten ler respostas nin resultados.

create or replace function public.sg_info(p_grupo text default null, p_alumno text default null)
returns jsonb language plpgsql security definer set search_path = public stable as $$
declare g public.sg_grupos; a public.sg_alumnos;
begin
  if coalesce(p_alumno,'') <> '' then
    select * into a from public.sg_alumnos where codigo = upper(trim(p_alumno));
    if a.id is null then return null; end if;
    select * into g from public.sg_grupos where id = a.grupo_id;
  else
    select * into g from public.sg_grupos where codigo = upper(trim(coalesce(p_grupo,'')));
  end if;
  if g.id is null then return null; end if;
  if not g.activo then return jsonb_build_object('pechado', true, 'nome', g.nome); end if;
  return jsonb_build_object(
    'nome', g.nome, 'modelo', g.modelo, 'codigo', g.codigo,
    'eu', case when a.id is null then null else jsonb_build_object(
            'id', a.id, 'nome', a.nome,
            'feito', exists (select 1 from public.sg_respostas r where r.alumno_id = a.id)) end,
    'alumnos', coalesce((
        select jsonb_agg(jsonb_build_object('id', x.id, 'nome', x.nome,
                 'feito', exists (select 1 from public.sg_respostas r where r.alumno_id = x.id))
               order by x.orde, x.nome)
        from public.sg_alumnos x where x.grupo_id = g.id), '[]'::jsonb));
end $$;

create or replace function public.sg_codigos(p_grupo text)
returns jsonb language plpgsql security definer set search_path = public stable as $$
declare g public.sg_grupos;
begin
  select * into g from public.sg_grupos where codigo = upper(trim(coalesce(p_grupo,'')));
  if g.id is null or not g.activo then return null; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('nome', x.nome, 'codigo', x.codigo) order by x.orde, x.nome)
                   from public.sg_alumnos x where x.grupo_id = g.id), '[]'::jsonb);
end $$;

create or replace function public.sg_enviar(p_grupo text, p_alumno_id uuid, p_codigo_alumno text, p_datos jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare a public.sg_alumnos; g public.sg_grupos;
begin
  if p_datos is null or jsonb_typeof(p_datos) <> 'object' or length(p_datos::text) > 100000 then
    raise exception 'datos_invalidos';
  end if;
  if coalesce(p_codigo_alumno,'') <> '' then
    select * into a from public.sg_alumnos where codigo = upper(trim(p_codigo_alumno));
  else
    select x.* into a from public.sg_alumnos x join public.sg_grupos y on y.id = x.grupo_id
     where x.id = p_alumno_id and y.codigo = upper(trim(coalesce(p_grupo,'')));
  end if;
  if a.id is null then raise exception 'non_atopado'; end if;
  select * into g from public.sg_grupos where id = a.grupo_id;
  if not g.activo then raise exception 'pechado'; end if;
  insert into public.sg_respostas(alumno_id, grupo_id, datos) values (a.id, a.grupo_id, p_datos)
  on conflict (alumno_id) do nothing;
  if not found then raise exception 'xa_respondido'; end if;
  return 'ok';
end $$;

revoke all on function public.sg_info(text,text)                 from public;
revoke all on function public.sg_codigos(text)                   from public;
revoke all on function public.sg_enviar(text,uuid,text,jsonb)    from public;
grant execute on function public.sg_info(text,text)              to anon, authenticated;
grant execute on function public.sg_codigos(text)                to anon, authenticated;
grant execute on function public.sg_enviar(text,uuid,text,jsonb) to anon, authenticated;
