--! Previous: sha1:e6bd89aa12b755d5cbf4ffea0d60e949107e9e05
--! Hash: sha1:49cae749db28f0883c59b1599ca34b15e3a3c1f9

drop table if exists app_public.event_categories;

create table app_public.event_categories (
  id uuid primary key default gen_random_uuid(),
  name text,
  description text,
  owner_organization_id uuid not null references app_public.organizations on delete cascade,
  is_public boolean not null default true,
  created_at timestamptz not null default now()
);

alter table app_public.event_categories enable row level security;

create index on app_public.event_categories (owner_organization_id);

grant
  select,
  insert (name, description, owner_organization_id, is_public),
  update (name, description, owner_organization_id, is_public),
  delete
on app_public.event_categories to :DATABASE_VISITOR;

create policy select_all on app_public.event_categories for select using (is_public);
create policy manage_own on app_public.event_categories for all using (exists (select 1 from app_public.organization_memberships where user_id = app_public.current_user_id() and owner_organization_id = organization_id));
create policy manage_as_admin on app_public.event_categories for all using (exists (select 1 from app_public.users where is_admin is true and id = app_public.current_user_id()));

comment on table app_public.event_categories is
  E'Table for event_categories.';

comment on column app_public.event_categories.id is
  E'Unique identifier for the event category.';
comment on column app_public.event_categories.name is
  E'Name of the event category.';
comment on column app_public.event_categories.description is
  E'Short description of the event category.';
comment on column app_public.event_categories.owner_organization_id is
  E'Id of the hosting organization.';
comment on column app_public.event_categories.is_public is
  E'Are events of this category available for everyone.';

drop table if exists app_public.events;

create table app_public.events (
  id uuid primary key default gen_random_uuid(),
  name text,
  description text,
  start_time timestamp not null default now(),
  owner_organization_id uuid not null references app_public.organizations on delete cascade,
  category_id uuid not null references app_public.event_categories,
  created_at timestamptz not null default now()
);
alter table app_public.events enable row level security;

create index on app_public.events using btree (start_time);
create index on app_public.events (owner_organization_id);
create index on app_public.events (category_id);

grant
  select,
  insert (name, description, start_time, owner_organization_id, category_id),
  update (name, description, start_time, owner_organization_id, category_id),
  delete
on app_public.events to :DATABASE_VISITOR;

create policy select_all on app_public.events for select using (true);
create policy manage_own on app_public.events for all using (exists (select 1 from app_public.organization_memberships where user_id = app_public.current_user_id() and owner_organization_id = organization_id));
create policy manage_as_admin on app_public.events for all using (exists (select 1 from app_public.users where is_admin is true and id = app_public.current_user_id()));

comment on table app_public.events is
  E'Main table for events.';

comment on column app_public.events.id is
  E'Unique identifier for the event.';
comment on column app_public.events.name is
  E'Name of the event.';
comment on column app_public.events.description is
  E'Description of the event.';
comment on column app_public.events.start_time is
  E'Starting time of the event.';
comment on column app_public.events.owner_organization_id is
  E'Id of the organizing organization.';
comment on column app_public.events.category_id is
  E'Id of the event category.';