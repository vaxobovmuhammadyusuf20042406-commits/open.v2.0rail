-- Open Rail: database schema for Supabase
-- Paste this whole file into Supabase > SQL Editor > New query, then click Run.
-- It is safe to run on a fresh project. Running it twice will fail on "already exists";
-- if you need to start over, delete the project or drop the tables first.

-- ============================================================
-- 1. Tables
-- ============================================================

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  area         text check (char_length(area) <= 60),          -- neighbourhood / town, helps plan handovers
  created_at   timestamptz not null default now()
);

create table public.items (
  id           uuid primary key default gen_random_uuid(),
  owner        uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  title        text not null check (char_length(title) between 1 and 60),
  category     text not null check (category in ('Tops','Bottoms','Dresses','Knitwear','Outerwear','Shoes','Accessories','Kids')),
  size         text check (char_length(size) <= 20),
  condition    text not null check (condition in ('New with tags','Like new','Good','Well loved')),
  color        text not null default 'Grey' check (char_length(color) <= 20),
  fabric       text check (char_length(fabric) <= 40),
  note         text check (char_length(note) <= 400),
  photo_path   text check (char_length(photo_path) <= 200),  -- path inside the "photos" storage bucket
  status       text not null default 'available' check (status in ('available','reserved','swapped')),
  reserved_for uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now()
);
create index items_created_idx on public.items (created_at desc);
create index items_owner_idx on public.items (owner);
create index items_reserved_for_idx on public.items (reserved_for);

create table public.swap_requests (
  id            uuid primary key default gen_random_uuid(),
  item_id       uuid not null references public.items (id) on delete cascade,
  requester     uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  message       text not null check (char_length(message) between 1 and 400),
  offer_item_id uuid references public.items (id) on delete set null,
  status        text not null default 'pending' check (status in ('pending','accepted','declined','withdrawn','completed')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index swap_requests_item_idx on public.swap_requests (item_id);
create index swap_requests_requester_idx on public.swap_requests (requester);
create index swap_requests_offer_item_idx on public.swap_requests (offer_item_id);
-- one open request per person per item
create unique index swap_requests_one_open
  on public.swap_requests (item_id, requester)
  where status in ('pending','accepted');

create table public.messages (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references public.swap_requests (id) on delete cascade,
  sender      uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 1000),
  created_at  timestamptz not null default now()
);
create index messages_request_idx on public.messages (request_id, created_at);
create index messages_sender_idx on public.messages (sender);

-- ============================================================
-- 2. Helper: is the signed-in user part of this request?
-- ============================================================

create schema if not exists private;
grant usage on schema private to authenticated;

create or replace function private.is_request_party(req uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.swap_requests r
    join public.items i on i.id = r.item_id
    where r.id = req
      and (r.requester = auth.uid() or i.owner = auth.uid())
  );
$$;

-- ============================================================
-- 3. Row Level Security
-- ============================================================

alter table public.profiles      enable row level security;
alter table public.items         enable row level security;
alter table public.swap_requests enable row level security;
alter table public.messages      enable row level security;

-- Profiles: anyone can see names; you edit only your own.
create policy "profiles are public" on public.profiles
  for select using (true);
create policy "insert own profile" on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy "update own profile" on public.profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Items: anyone (even signed out) can browse; owners manage their own.
create policy "items are public" on public.items
  for select using (true);
create policy "insert own items" on public.items
  for insert to authenticated with check (owner = (select auth.uid()));
create policy "update own items" on public.items
  for update to authenticated using (owner = (select auth.uid())) with check (owner = (select auth.uid()));
create policy "delete own items" on public.items
  for delete to authenticated using (owner = (select auth.uid()));

-- Swap requests: only the requester and the item's owner can see them.
create policy "parties read requests" on public.swap_requests
  for select to authenticated
  using (
    requester = (select auth.uid())
    or exists (select 1 from public.items i where i.id = item_id and i.owner = (select auth.uid()))
  );
create policy "request someone else's item" on public.swap_requests
  for insert to authenticated
  with check (
    requester = (select auth.uid())
    and status = 'pending'
    and exists (
      select 1 from public.items i
      where i.id = item_id and i.owner <> (select auth.uid()) and i.status <> 'swapped'
    )
    and (
      offer_item_id is null
      or exists (select 1 from public.items o where o.id = offer_item_id and o.owner = (select auth.uid()))
    )
  );
create policy "parties update requests" on public.swap_requests
  for update to authenticated
  using (private.is_request_party(id))
  with check (private.is_request_party(id));

-- Messages: only the two people in the request can read or write.
create policy "parties read messages" on public.messages
  for select to authenticated using (private.is_request_party(request_id));
create policy "parties send messages" on public.messages
  for insert to authenticated
  with check (sender = (select auth.uid()) and private.is_request_party(request_id));

-- ============================================================
-- 4. Triggers
-- ============================================================

-- Create a profile automatically when someone signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, area)
  values (
    new.id,
    coalesce(nullif(left(trim(new.raw_user_meta_data ->> 'display_name'), 40), ''), split_part(new.email, '@', 1)),
    nullif(left(trim(new.raw_user_meta_data ->> 'area'), 60), '')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Guard who may change a request, and how.
--   requester: may only withdraw
--   item owner: may accept, decline, complete, or reopen (back to pending)
create or replace function public.guard_request_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  item_owner uuid;
begin
  if new.item_id <> old.item_id or new.requester <> old.requester
     or new.message <> old.message or new.created_at <> old.created_at
     or new.offer_item_id is distinct from old.offer_item_id then
    raise exception 'Only the status of a request can change';
  end if;

  select owner into item_owner from public.items where id = old.item_id;

  if auth.uid() = old.requester and new.status <> old.status then
    if new.status <> 'withdrawn' or old.status not in ('pending','accepted') then
      raise exception 'You can only withdraw your own open request';
    end if;
  elsif auth.uid() = item_owner and new.status <> old.status then
    if new.status not in ('accepted','declined','completed','pending') then
      raise exception 'Not a valid status for the owner to set';
    end if;
    if old.status = 'withdrawn' then
      raise exception 'This request was withdrawn';
    end if;
  elsif new.status <> old.status then
    raise exception 'Not allowed';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger guard_request_update
  before update on public.swap_requests
  for each row execute function public.guard_request_update();

-- Owners can only reserve an item for someone who actually asked for it.
create or replace function public.guard_item_reserved_for()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.reserved_for is not null
     and new.reserved_for is distinct from old.reserved_for
     and not exists (
       select 1 from public.swap_requests r
       where r.item_id = new.id and r.requester = new.reserved_for
     ) then
    raise exception 'Can only reserve for someone who requested this item';
  end if;
  return new;
end;
$$;

create trigger guard_item_reserved_for
  before update on public.items
  for each row execute function public.guard_item_reserved_for();

-- Helper functions are not part of the public API.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.guard_request_update() from public, anon, authenticated;
revoke execute on function public.guard_item_reserved_for() from public, anon, authenticated;
revoke execute on function private.is_request_party(uuid) from public, anon;
grant execute on function private.is_request_party(uuid) to authenticated;

-- ============================================================
-- 5. Photo storage
-- ============================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', true, 5242880, array['image/jpeg','image/png','image/webp']);

-- Files live at photos/<user id>/<file name>. Anyone can view; you manage your own folder.
create policy "photos are public" on storage.objects
  for select using (bucket_id = 'photos');
create policy "upload to own folder" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "delete own photos" on storage.objects
  for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- ============================================================
-- 6. Live updates
-- ============================================================

alter publication supabase_realtime add table public.items, public.swap_requests, public.messages;
