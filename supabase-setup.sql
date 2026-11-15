-- STORM: جداول وحماية قاعدة البيانات
create table if not exists public.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  nick text not null default 'لاعب',
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now());
alter table public.profiles enable row level security;
create policy "own profile read" on public.profiles for select using (auth.uid()=id);
create policy "own profile insert" on public.profiles for insert with check (auth.uid()=id);
create policy "own profile update" on public.profiles for update using (auth.uid()=id) with check (auth.uid()=id);
create policy "own profile delete" on public.profiles for delete using (auth.uid()=id);

create table if not exists public.scores(
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nick text not null,
  lang text not null check (lang in ('py','html','css','js')),
  score int not null check (score between 0 and 1440),
  created_at timestamptz not null default now());
alter table public.scores enable row level security;
create policy "own score insert" on public.scores for insert with check (auth.uid()=user_id);
create policy "own score read" on public.scores for select using (auth.uid()=user_id);
create policy "own score delete" on public.scores for delete using (auth.uid()=user_id);
create index if not exists scores_lang_time on public.scores(lang,created_at);

create or replace function public.leaderboard(l text,p text)
returns table(nick text,total bigint,mine boolean)
language sql stable security definer set search_path=public as $$
  select max(s.nick), sum(s.score)::bigint, bool_or(s.user_id=auth.uid())
  from public.scores s
  where s.lang=l and s.created_at>=date_trunc(case when p='month' then 'month' else 'week' end,now())
  group by s.user_id order by 2 desc limit 20 $$;
grant execute on function public.leaderboard(text,text) to anon, authenticated;

create or replace function public.scores_throttle() returns trigger language plpgsql as $$
begin
  if exists(select 1 from public.scores where user_id=new.user_id and created_at>now()-interval '90 seconds') then
    raise exception 'too fast';
  end if;
  return new;
end $$;
drop trigger if exists scores_throttle on public.scores;
create trigger scores_throttle before insert on public.scores for each row execute function public.scores_throttle();
