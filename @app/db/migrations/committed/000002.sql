--! Previous: sha1:0a25569004ac1791eb01a81be9db61570d6a4912
--! Hash: sha1:9f7e4b5a22a4a4ac93d4b8d2e49fb97b5b3a2fad

--! split: 0001-computed-columns.sql
/*
 * Get the user primary email as a computed column.
 */
drop function if exists app_public.users_primary_email;

create function app_public.users_primary_email(u app_public.users) returns citext as $$
  select email
    from app_public.user_emails
    where
      user_emails.user_id = u.id
      and u.id = app_public.current_user_id()
      and user_emails.is_primary = true;
$$ language sql stable security definer set search_path to pg_catalog, public, pg_temp;
comment on function app_public.users_primary_email(u app_public.users) is
  E'Users primary email.';

--! split: 0002-rls-functions.sql
drop function if exists app_public.current_user_is_admin cascade;

create function app_public.current_user_is_admin() returns boolean as $$
  select exists (select 1
    from app_public.users
    where
      id = app_public.current_user_id()
      and is_admin = true)
$$ language sql stable security definer set search_path to pg_catalog, public, pg_temp;

drop function if exists app_public.current_user_is_owner_organization_member cascade;

create function app_public.current_user_is_owner_organization_member(owner_organization_id uuid) returns boolean as $$
  select exists (select 1
    from
      app_public.organization_memberships
    where
      user_id = app_public.current_user_id()
      and owner_organization_id = organization_id)
$$ language sql stable security definer set search_path to pg_catalog, public, pg_temp;

--! split: 0003-triggers.sql
/*
 * This trigger is used on tables with created_by and updated_by to ensure that
 * they are valid (namely: `created_by` cannot be changed after initial INSERT,
 * and `updated_by` is updated after UPDATE statement).
 */
drop function if exists app_private.tg__ownership_info() cascade;

create function app_private.tg__ownership_info() returns trigger as $$
begin
  NEW.created_by = (case when TG_OP = 'INSERT' then app_public.current_user_id() else OLD.created_by end);
  NEW.updated_by = (case when TG_OP = 'UPDATE' then app_public.current_user_id() else OLD.updated_by end);
  return NEW;
end;
$$ language plpgsql volatile set search_path to pg_catalog, public, pg_temp;
comment on function app_private.tg__ownership_info() is
  E'This trigger should be called on all tables with created_by, updated_by - it ensures that they cannot be manipulated.';

--! split: 0010-event_categories.sql
/*
 * The event categories table is to categorize events and to enforce RLS policies
 * on events. For example, only the members of owner_organization_id organization
 * can see private event registration information (such as allergies) and update
 * event details.
 */
drop table if exists app_public.event_categories cascade;

create table app_public.event_categories(
  id uuid primary key default gen_random_uuid(),
  name jsonb not null,
  description jsonb not null,
  owner_organization_id uuid not null references app_public.organizations on delete cascade,

  created_by uuid references app_public.users on delete set null,
  updated_by uuid references app_public.users on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()

  constraint _cnstr_check_name_language check(check_language(name))
  constraint _cnstr_check_description_language check(check_language(description))
);
alter table app_public.event_categories enable row level security;

-- Indices
create index on app_public.event_categories(owner_organization_id);
create index on app_public.event_categories(created_by);
create index on app_public.event_categories(updated_by);
create index on app_public.event_categories(name);

-- Triggers
create trigger _100_timestamps
  before insert or update on app_public.event_categories for each row
  execute procedure app_private.tg__timestamps();

create trigger _200_ownership_info
  before insert or update on app_public.event_categories for each row
  execute procedure app_private.tg__ownership_info();

-- Comments
comment on table app_public.event_categories is
  E'Table for event categories.';
comment on column app_public.event_categories.id is
  E'Unique identifier for the event category.';
comment on column app_public.event_categories.name is
  E'Name of the event category.';
comment on column app_public.event_categories.description is
  E'Short description of the event category.';
comment on column app_public.event_categories.owner_organization_id is
  E'Identifier of the organizer.';

-- RLS policies and grants
grant
  select,
  insert (name, description, owner_organization_id),
  update (name, description, owner_organization_id),
  delete
on app_public.event_categories to :DATABASE_VISITOR;

create policy select_all on app_public.event_categories
  for select using (true);

create policy manage_member on app_public.event_categories
  for all using (owner_organization_id in (select app_public.current_user_member_organization_ids()));

--! split: 0011-events.sql
/*
 * The events table stores events that a user of the application can register to.
 * Events can either be upcoming, open to registration or closed.
 */

drop table if exists app_public.events cascade;
create table app_public.events(
  id uuid primary key default gen_random_uuid(),
  slug citext not null unique,
  name jsonb not null,
  description jsonb not null,
  event_start_time timestamptz not null,
  event_end_time timestamptz not null,
  registration_start_time timestamptz not null,
  registration_end_time timestamptz not null,
  is_highlighted boolean not null default false,
  is_draft boolean not null default true,
  header_image_file text,
  owner_organization_id uuid not null references app_public.organizations on delete cascade,
  category_id uuid not null references app_public.event_categories on delete set null,

  created_by uuid references app_public.users on delete set null,
  updated_by uuid references app_public.users on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()

  constraint _cnstr_check_event_time check(event_start_time < event_end_time)
  constraint _cnstr_check_event_registration_time check(registration_start_time < registration_end_time)
  constraint _cnstr_check_registration_end_before_event_start check(registration_end_time < event_start_time)
  constraint _cnstr_check_name_language check(check_language(name))
  constraint _cnstr_check_description_language check(check_language(description))
);
alter table app_public.events enable row level security;

-- Indices
create index on app_public.events(event_start_time);
create index on app_public.events(event_end_time);
create index on app_public.events(registration_start_time);
create index on app_public.events(registration_end_time);
create index on app_public.events(owner_organization_id);
create index on app_public.events(category_id);
create index on app_public.events(is_draft);
create index on app_public.events(created_by);
create index on app_public.events(updated_by);

-- Triggers
create trigger _100_timestamps
  before insert or update on app_public.events for each row
  execute procedure app_private.tg__timestamps();

create trigger _200_ownership_info
  before insert or update on app_public.events for each row
  execute procedure app_private.tg__ownership_info();

-- Computed columns (https://www.graphile.org/postgraphile/computed-columns/)
create function app_public.events_signup_upcoming(e app_public.events)
returns boolean as $$
  select now() < e.registration_start_time;
$$ language sql stable;
comment on function app_public.events_signup_upcoming(e app_public.events) is
  E'Designates whether event signup is upcoming or not.';

create function app_public.events_signup_open(e app_public.events)
returns boolean as $$
  select now() between e.registration_start_time and e.registration_end_time;
$$ language sql stable;
comment on function app_public.events_signup_open(e app_public.events) is
  E'Designates whether event signup is open or not.';

create function app_public.events_signup_closed(e app_public.events)
returns boolean as $$
  select now() > e.registration_end_time;
$$ language sql stable;
comment on function app_public.events_signup_closed(e app_public.events) is
  E'Designates whether event signup is closed or not.';

-- Comments
comment on table app_public.events is
  E'Main table for events.';
comment on column app_public.events.id is
  E'Unique identifier for the event.';
comment on column app_public.events.name is
  E'Name of the event.';
comment on column app_public.events.slug is
  E'Slug for the event.';
comment on column app_public.events.description is
  E'Description of the event.';
comment on column app_public.events.event_start_time is
  E'Starting time of the event.';
comment on column app_public.events.event_end_time is
  E'Ending time of the event.';
  comment on column app_public.events.registration_start_time is
  E'Time of event registration open.';
comment on column app_public.events.registration_end_time is
  E'Time of event registration end.';
comment on column app_public.events.is_highlighted is
  E'A highlighted event.';
comment on column app_public.events.is_draft is
  E'A draft event that is not publicly visible.';
comment on column app_public.events.header_image_file is
  E'Header image for the event';
comment on column app_public.events.owner_organization_id is
  E'Id of the organizer.';
comment on column app_public.events.category_id is
  E'Id of the event category.';

-- RLS policies and grants
grant
  select,
  insert (name, slug, description, event_start_time, event_end_time, registration_start_time, registration_end_time, is_highlighted, is_draft, header_image_file, owner_organization_id, category_id),
  update (name, slug, description, event_start_time, event_end_time, registration_start_time, registration_end_time, is_highlighted, is_draft, header_image_file, owner_organization_id, category_id),
  delete
on app_public.events to :DATABASE_VISITOR;

create policy select_all on app_public.events for select using (is_draft is false);
create policy manage_admin on app_public.events for all using(app_public.current_user_is_admin()) with check(app_public.current_user_is_admin());
create policy manage_organization on app_public.events for all using(app_public.current_user_is_owner_organization_member(owner_organization_id)) with check(app_public.current_user_is_owner_organization_member(owner_organization_id));

--! split: 0012-event_questions.sql
/*
 * The events_questions table stores questions that can be asked during event
 * registration. TODO: not implemented yet.
 */

drop type if exists app_public.question_type cascade;
drop table if exists app_public.event_questions cascade;

create type app_public.question_type as enum (
  'short-text',
  'long-text',
  'option'
);

create table app_public.event_questions(
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references app_public.events(id) on delete cascade,
  type app_public.question_type not null,
  options json,

  created_by uuid references app_public.users on delete set null,
  updated_by uuid references app_public.users on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table app_public.event_questions enable row level security;

-- Indices
create index on app_public.event_questions(event_id);
create index on app_public.event_questions(created_by);
create index on app_public.event_questions(updated_by);

-- Triggers
create trigger _100_timestamps
  before insert or update on app_public.event_questions for each row
  execute procedure app_private.tg__timestamps();

create trigger _200_ownership_info
  before insert or update on app_public.event_questions for each row
  execute procedure app_private.tg__ownership_info();

-- RLS policies and grants
grant
  select,
  insert (event_id, type, options),
  update (event_id, type, options),
  delete
on app_public.event_questions to :DATABASE_VISITOR;

create policy select_all on app_public.event_questions for select using (true);

create policy manage_own on app_public.event_questions
  for all
  using (exists (select 1
  from
    app_public.organization_memberships
  where
    user_id = app_public.current_user_id() and organization_id = (select owner_organization_id
    from
      app_public.events
    where
      events.id = event_questions.event_id)));

create policy manage_own_category on app_public.event_questions
  for all
  using (exists (select 1
  from
    app_public.organization_memberships
  where
    user_id = app_public.current_user_id() and organization_id = (select owner_organization_id
    from
      app_public.event_categories
    where
      event_categories.id = (select category_id
      from
        app_public.events
      where
        events.id = event_questions.event_id))));

create policy manage_as_admin on app_public.event_questions
  for all
  using (exists (select 1
  from
    app_public.users
  where
    is_admin is true and id = app_public.current_user_id()));

--! split: 0020-quotas.sql
/*
 * The quotas table defines quotas for event registrations. Once a quota is full
 * no more registrations are allowed and additional registrations are considered
 * to be in queue for the quota. There may be multiple quotas with different
 * sizes for a single event.
 */

drop table if exists app_public.quotas cascade;
create table app_public.quotas(
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references app_public.events on delete cascade,
  position smallint not null,
  title jsonb not null,
  size smallint not null check (size > 0),
  -- TODO: Implement questions
  questions_public json,
  questions_private json,

  created_by uuid references app_public.users on delete set null,
  updated_by uuid references app_public.users on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint _cnstr_check_title_language check(check_language(title))
);
alter table app_public.quotas enable row level security;

-- Indices
create index on app_public.quotas(id);
create index on app_public.quotas(event_id);
create index on app_public.quotas(position);
create index on app_public.quotas(created_by);
create index on app_public.quotas(updated_by);

-- Triggers
create trigger _100_timestamps
  before insert or update on app_public.quotas for each row
  execute procedure app_private.tg__timestamps();

create trigger _200_ownership_info
  before insert or update on app_public.quotas for each row
  execute procedure app_private.tg__ownership_info();

-- Comments
comment on table app_public.quotas is
  E'Main table for registration quotas.';
comment on column app_public.quotas.event_id is
  E'Identifier of the event that this quota is for.';
comment on column app_public.quotas.position is
  E'Quota position. Used to order quotas.';
comment on column app_public.quotas.title is
  E'Title for the quota.';
comment on column app_public.quotas.size is
  E'Size of the quota.';
comment on column app_public.quotas.questions_public is
  E'Public questions related to the quota.';
comment on column app_public.quotas.questions_private is
  E'Private questions related to the quota.';

-- RLS policies and grants
grant
  select,
  -- Allow update only on position, title and size. This means that once
  -- a quota is created it cannot be moved to another event.
  insert (event_id, position, title, size),
  update (position, title, size),
  delete
on app_public.quotas to :DATABASE_VISITOR;

create policy select_all on app_public.quotas
  for select
    using (true);

create policy manage_own on app_public.quotas
  for all
  using (exists (select 1
  from
    app_public.organization_memberships
  where
    user_id = app_public.current_user_id() and organization_id = (select owner_organization_id
    from
      app_public.events
    where
      events.id = quotas.event_id)));

create policy manage_as_admin on app_public.quotas
  for all
  using (exists (select 1
  from
    app_public.users
  where
    is_admin is true and id = app_public.current_user_id()));

--! split: 0021-quotas-crud-functions.sql
/*
 * These functions define create and update mutations that support operating on
 * multiple quotas at once. These functions allow us to create or update all
 * quotas related to a single event via a single mutation.
 *
 * By default PostGraphile creates CRUD mutations for database tables
 * (https://www.graphile.org/postgraphile/crud-mutations/). We have omitted the
 * create, insert, update and delete mutations for the quotas table and use
 * these functions instead. The default mutations are omitted in
 * @app/server/postgraphile.tags.jsonc file.
 */

drop type if exists app_public.create_event_quotas cascade;
drop type if exists app_public.update_event_quotas cascade;
drop function if exists app_public.create_event_quotas(event_id uuid, quotas app_public.create_event_quotas[]);
drop function if exists app_public.update_event_quotas(event_id uuid, quotas app_public.update_event_quotas[]);

-- Input type for app_public.create_event_quotas
create type app_public.create_event_quotas as (
  position smallint,
  title jsonb,
  size smallint
);

create function app_public.create_event_quotas(
  event_id uuid,
  quotas app_public.create_event_quotas[]
)
returns app_public.quotas[]
as $$
  declare
    v_input app_public.create_event_quotas;
    v_quota app_public.quotas;
    v_ret app_public.quotas[] default '{}';
  begin
    -- Check permissions
    if app_public.current_user_id() is null then
      raise exception 'You must log in to create event quotas' using errcode = 'LOGIN';
    end if;

    -- Must specify at least one quota
    if (select array_length(quotas, 1)) is null then
      raise exception 'You must specify at least one quota' using errcode = 'DNIED';
    end if;

    -- Create quotas
    foreach v_input in array quotas loop
      insert into app_public.quotas(event_id, position, title, size)
        values (event_id, v_input.position, v_input.title, v_input.size)
        returning * into v_quota;

      v_ret := array_append(v_ret, v_quota);
    end loop;

    return v_ret;
  end;
$$ language plpgsql volatile security definer set search_path = pg_catalog, public, pg_temp;
comment on function app_public.create_event_quotas(event_id uuid, quotas app_public.create_event_quotas[]) is
  E'Create multiple quotas at once.';

-- Input type for app_public.update_event_quotas
create type app_public.update_event_quotas as (
  id uuid,
  position smallint,
  title jsonb,
  size smallint
);

create function app_public.update_event_quotas(
  event_id uuid,
  quotas app_public.update_event_quotas[]
)
returns app_public.quotas[]
as $$
#variable_conflict use_variable
  declare
  v_test int;
    v_quota_ids_to_delete uuid[];
    v_input app_public.update_event_quotas;
    v_quota app_public.quotas;
    v_ret app_public.quotas[] default '{}';
  begin
    -- Check permissions
    if app_public.current_user_id() is null then
      raise exception 'You must log in to update event quotas' using errcode = 'LOGIN';
    end if;

    -- Must specify at least one quota
    if (select array_length(quotas, 1)) is null then
      raise exception 'You must specify at least one quota' using errcode = 'DNIED';
    end if;

    select array(
      select id from app_public.quotas as q
      where q.event_id = event_id
      and q.id not in (select id from unnest(quotas))
    )
    into v_quota_ids_to_delete;

    -- Delete existing event quotas that were not supplied
    -- as input to this function
    delete from app_public.quotas as q
      where q.id = any(v_quota_ids_to_delete);

    -- Update existing event quotas by id
    foreach v_input in array quotas loop
      if exists(select 1 from app_public.quotas where id = v_input.id) then
        update app_public.quotas
          set position = v_input.position, title = v_input.title, size = v_input.size
          where id = v_input.id
        returning * into v_quota;
      else
        -- Create new quotas that didn't exits before
        insert into app_public.quotas(event_id, position, title, size)
          values (event_id, v_input.position, v_input.title, v_input.size)
        returning * into v_quota;
      end if;

      v_ret := array_append(v_ret, v_quota);
    end loop;

    return v_ret;
  end;
$$ language plpgsql volatile security definer set search_path = pg_catalog, public, pg_temp;
comment on function app_public.update_event_quotas(event_id uuid, quotas app_public.update_event_quotas[]) is
  E'Update multiple quotas at once.';

--! split: 0030-registration-triggers.sql
/*
 * This trigger is used to validate inserts on app_public.registrations. The
 * trigger makes sure that only valid registrations can be inserted into the
 * database. That is, the related event is open to registrations.
 */

drop function if exists tg__registration_is_valid() cascade;
create function app_private.tg__registration_is_valid() returns trigger as $$
declare
  v_event app_public.events;
  v_event_signup_open boolean;
begin
  select * into v_event from app_public.events where id = NEW.event_id;
  select app_public.events_signup_open(v_event) into v_event_signup_open;

  if v_event_signup_open is false then
    raise exception 'Event registration is not open.' using errcode = 'DNIED';
  end if;

  return NEW;
end;
$$ language plpgsql volatile set search_path to pg_catalog, public, pg_temp;
comment on function app_private.tg__registration_is_valid() is
  E'This trigger validates that a registration is valid. That is, the related event is open to registrations.';

--! split: 0031-registrations.sql
/*
 * The registrations table stores event registrations.
 */

drop table if exists app_public.registrations cascade;
create table app_public.registrations(
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references app_public.events on delete cascade,
  quota_id uuid not null references app_public.quotas on delete no action,
  first_name text null,
  last_name text null,
  email citext null check (email ~ '[^@]+@[^@]+\.[^@]+'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table app_public.registrations enable row level security;

-- Indices
create index on app_public.registrations(event_id);
create index on app_public.registrations(quota_id);
create index on app_public.registrations(created_at);

-- Triggers
create trigger _100_timestamps
  before insert or update on app_public.registrations for each row
  execute procedure app_private.tg__timestamps();

create trigger _200_registration_is_valid
  before insert on app_public.registrations for each row
  execute procedure app_private.tg__registration_is_valid();

create trigger _300_send_registration_email
  -- Send email upon successful registration. We run this trigger on update because
  -- the registration is initially created with claim_registration_token and we
  -- don't know the users email at that point. The registration__send_confirmation_email
  -- task validates that only send one email per registration. This is tracked
  -- in app_private.registration_secrets.confirmation_email_sent.
  after update on app_public.registrations
  for each row execute procedure app_private.tg__add_job('registration__send_confirmation_email');

create trigger _500_gql_registration_updated
  -- Expose new registrations via a GraphQl subscription. Used for live updating
  -- views in the frontend application.
  after insert or update or delete on app_public.registrations
  for each row
  execute procedure app_public.tg__graphql_subscription(
    'registrationUpdated', -- the "event" string, useful for the client to know what happened
    'graphql:eventRegistrations:$1', -- the "topic" the event will be published to, as a template
    'event_id' -- If specified, `$1` above will be replaced with NEW.id or OLD.id from the trigger.
  );

-- Computed columns (https://www.graphile.org/postgraphile/computed-columns/)
create function app_public.registrations_full_name(registration app_public.registrations)
returns text as $$
  select registration.first_name || ' ' || registration.last_name
$$ language sql stable;
grant execute on function app_public.registrations_full_name(registration app_public.registrations) to :DATABASE_VISITOR;
comment on function app_public.registrations_full_name(registration app_public.registrations) is
  E'Returns the full name of a registered person.';

create function app_public.registrations_is_queued(registration app_public.registrations)
  returns boolean as $$
declare
  v_registrations_before_self integer;
  v_quota app_public.quotas;
begin
  select * into v_quota from app_public.quotas where id = registration.quota_id;

  select count(*)
  into v_registrations_before_self
  from app_public.registrations
  where created_at < registration.created_at
    and event_id = registration.event_id
    and quota_id = registration.quota_id;

  if v_registrations_before_self >= v_quota.size then
    return true;
  else
    return false;
  end if;
end;
$$ language plpgsql stable;
grant execute on function app_public.registrations_is_queued(registration app_public.registrations) to :DATABASE_VISITOR;
comment on function app_public.registrations_is_queued(registration app_public.registrations) is
  E'Designates whether the registration is queued for a quota or not.';

-- Comments
comment on table app_public.registrations is
  E'Main table for registrations.';
comment on column app_public.registrations.id is
  E'Unique identifier for the registration.';
comment on column app_public.registrations.event_id is
  E'Identifier of a related event.';
comment on column app_public.registrations.quota_id is
  E'Identifier of a related quota.';
comment on column app_public.registrations.first_name is
  E'First name of the person registering to an event.';
comment on column app_public.registrations.last_name is
  E'Last name of the person registering to an event.';
-- Use @omit to prevet exposing emails via the GraphQL API
comment on column app_public.registrations.email is
  E'@omit\nEmail address of the person registering to an event.';

-- RLS policies and grants
grant
  select,
  insert (event_id, quota_id, first_name, last_name, email),
  -- Don't allow updating an existing registration to another event or quota
  -- Don't allow updating registration email
  update (first_name, last_name),
  delete
on app_public.registrations to :DATABASE_VISITOR;

create policy update_all on app_public.registrations
  for update
    using (true);

create policy select_all on app_public.registrations
  for select
    using (true);

create policy manage_as_admin on app_public.registrations
  for all
  using (exists (select 1
  from
    app_public.users
  where
    is_admin is true and id = app_public.current_user_id()));

--! split: 0032-registration_secrets.sql
/*
 * The registrations_secrets table stores event secrets related to event
 * registrations.
 *
 * In order to create a registration a registration_token (obtained via the
 * claim_registration_token function) must be provided. To update a registration
 * an update_token must be provided. Upon registration, an email containing an
 * update_token is sent to the user.
 */

drop table if exists app_private.registration_secrets cascade;
create table app_private.registration_secrets(
  id uuid primary key default gen_random_uuid(),
  registration_token text default encode(gen_random_bytes(7), 'hex'),
  update_token text default encode(gen_random_bytes(7), 'hex'),
  confirmation_email_sent boolean not null default false,

  -- When a registration is deleted, also delete the secrets
  registration_id uuid null references app_public.registrations on delete cascade,
  event_id uuid not null references app_public.events on delete cascade,
  quota_id uuid not null references app_public.quotas on delete cascade,

  unique(registration_token),
  unique(update_token)
);
alter table app_private.registration_secrets enable row level security;

-- Indices
create index on app_private.registration_secrets(event_id);
create index on app_private.registration_secrets(registration_id);

-- Comments
comment on table app_private.registration_secrets is
  E'The contents of this table should never be visible to the user. Contains data related to event registrations.';

--! split: 0033-registrations-crud-functions.sql
/*
 * These functions define create, update and delete mutations for event
 * registrations. This allows us to specify additional conditions in order to
 * operate on registrations. For example, in order to create a registration a
 * valid registration token must be provided. Similarly, to update or delete a
 * registration a valid update token must be provided. The regitrationToken is
 * obtained via the claim_registration_token function and the update token is
 * emailed to the user on successful event registration.
 *
 * By default PostGraphile creates CRUD mutations for database tables
 * (https://www.graphile.org/postgraphile/crud-mutations/). We have omitted the
 * create, insert, update and delete mutations for the registrations table and
 * use these functions instead. The default mutations are omitted in
 * @app/server/postgraphile.tags.jsonc file.
 */

drop function if exists app_public.create_registration(text, uuid, uuid, text, text, citext);
drop function if exists app_public.update_registration(text, text, text);
drop function if exists app_public.delete_registration(text);

create function app_public.create_registration(
  "registrationToken" text,
  "eventId" uuid,
  "quotaId" uuid,
  "firstName" text,
  "lastName" text,
  email citext
)
  returns app_public.registrations
  as $$
declare
  v_registration app_public.registrations;
  v_registration_id uuid;
  v_quota app_public.quotas;
  v_event app_public.events;
  v_event_signup_open boolean;
begin
  select * into v_quota from app_public.quotas where id = "quotaId";
  select * into v_event from app_public.events where id = "eventId";

  -- If either event or quota are not found, prevent event registration
  if v_quota.id is null then
    raise exception 'Quota not found.' using errcode = 'NTFND';
  end if;

  if v_event.id is null then
    raise exception 'Event not found.' using errcode = 'NTFND';
  end if;

  -- If the registration is not open yet, prevent event registration
  v_event_signup_open := (select app_public.events_signup_open(v_event));
  if not v_event_signup_open then
    raise exception 'Event registration is not open.' using errcode = 'DNIED';
  end if;

  -- Get registration id matching registration token
  select registration_id into v_registration_id
  from app_private.registration_secrets
  where registration_token = "registrationToken"
    and event_id = "eventId"
    and quota_id = "quotaId";

  -- If the provided token does not exist or is not valid for the specified event
  -- prevent event registration
  if v_registration_id is null then
    raise exception 'Registration token was not valid. Please reload the page.' using errcode = 'DNIED';
  end if;

  -- Update registration that was created by calling claim_registration_token
  update app_public.registrations
    set first_name = "firstName", last_name = "lastName", email = create_registration.email
    where id = v_registration_id
  returning
    * into v_registration;

  if v_registration.id is null then
    raise exception 'Registration failed. Registration matching token was not found.' using errcode = 'NTFND';
  end if;

  -- Set the used token to null and set registration_id
  update app_private.registration_secrets
    set registration_token = null, registration_id = v_registration.id
    where registration_secrets.registration_token = "registrationToken";

  return v_registration;
end;
$$ language plpgsql volatile security definer set search_path = pg_catalog, public, pg_temp;
comment on function app_public.create_registration("registrationToken" text, "eventId" uuid, "quotaId" uuid, "firstName" text, "lastName" text, email citext) is
  E'Register to an event. Checks that a valid registration token was suplied.';

create function app_public.update_registration(
  "updateToken" text,
  "firstName" text,
  "lastName" text
)
  returns app_public.registrations
  as $$
declare
  v_registration_id uuid;
  v_registration app_public.registrations;
begin
  select registration_id into v_registration_id
    from app_private.registration_secrets
    where update_token = "updateToken";

  if v_registration_id is null then
    raise exception 'Registration matching token was not found.' using errcode = 'NTFND';
  end if;

  update app_public.registrations
    set first_name = "firstName", last_name = "lastName"
    where id = v_registration_id
  returning
    * into v_registration;

  return v_registration;
end;
$$ language plpgsql volatile security definer set search_path = pg_catalog, public, pg_temp;
comment on function app_public.update_registration("updateToken" text, "firstName" text, "lastName" text) is
  E'Update event registration. Checks that a valid update token was suplied.';

create function app_public.delete_registration("updateToken" text)
  returns boolean
  as $$
declare
  v_registration_id uuid;
begin
  select registration_id into v_registration_id
    from app_private.registration_secrets
    where update_token = "updateToken";

  if v_registration_id is null then
    raise exception 'Registration matching token was not found.' using errcode = 'NTFND';
  end if;

  -- Delete registration and associated secrets (foreign key has on delete)
  delete from app_public.registrations where id = v_registration_id;

  return true;
end;
$$ language plpgsql volatile security definer set search_path = pg_catalog, public, pg_temp;
comment on function app_public.delete_registration("updateToken" text) is
  E'Delete event registration.';

create function app_public.registration_by_update_token("updateToken" text)
  returns app_public.registrations
  as $$
declare
  v_registration_id uuid;
  v_registration app_public.registrations;
begin
  select registration_id into v_registration_id
    from app_private.registration_secrets
    where update_token = "updateToken";

  if v_registration_id is null then
    return null;
  end if;

  select * into v_registration
    from app_public.registrations
    where id = v_registration_id;

  return v_registration;
end;
$$ language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp;
grant execute on function  app_public.registration_by_update_token("updateToken" text) to :DATABASE_VISITOR;

comment on function app_public.registration_by_update_token("updateToken" text) is
  E'Get registration by update token.';

--! split: 0034-registration_secrets-functions.sql
/*
 * These functions are used to create registration secrets that are required
 * to create, update or delete registrations.
 */
drop function if exists app_public.claim_registration_token(uuid, uuid);
drop type if exists app_public.claim_registration_token_output;

-- Output type for app_public.claim_registration_token
create type app_public.claim_registration_token_output as (
  registration_token text,
  update_token text
);

create function app_public.claim_registration_token(event_id uuid, quota_id uuid)
  returns app_public.claim_registration_token_output
  as $$
declare
  v_output app_public.claim_registration_token_output;
  v_registration_id uuid;
begin
  -- Create a new registration secret
  insert into app_private.registration_secrets(event_id, quota_id)
    values (event_id, quota_id)
  returning
    registration_token, update_token into v_output;

  -- Create a registration. This means that a spot in the specified event and
  -- quota is reserved for a user when this function is called. The user can
  -- then proceed to enter their information at their own pace without worrying
  -- that the quota would already be filled by the time they finished.
  insert into app_public.registrations(event_id, quota_id)
    values (event_id, quota_id)
  returning
    id into v_registration_id;

  -- Set registration_id to the corresponding row in registration_secrets table
  update app_private.registration_secrets
    set registration_id = v_registration_id
    where registration_token = v_output.registration_token;

  -- Schedule graphile worker task for token deletion
  perform graphile_worker.add_job(
    'registration__schedule_unfinished_registration_delete',
    json_build_object('token', v_output.registration_token)
  );

  return v_output;
end;
$$ language plpgsql volatile security definer set search_path = pg_catalog, public, pg_temp;
comment on function app_public.claim_registration_token(event_id uuid, quota_id uuid) is
  E'Generates a registration token that must be provided during registration. The token is used to prevent F5-wars.';
