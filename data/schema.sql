--
-- PostgreSQL database dump
--

-- Dumped from database version 13.2
-- Dumped by pg_dump version 13.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: app_hidden; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA app_hidden;


--
-- Name: app_private; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA app_private;


--
-- Name: app_public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA app_public;


--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: app_languages; Type: TYPE; Schema: app_public; Owner: -
--

CREATE TYPE app_public.app_languages AS (
	supported_languages text[],
	default_language text
);


--
-- Name: claim_registration_token_output; Type: TYPE; Schema: app_public; Owner: -
--

CREATE TYPE app_public.claim_registration_token_output AS (
	registration_token text,
	update_token text
);


--
-- Name: create_event_quotas; Type: TYPE; Schema: app_public; Owner: -
--

CREATE TYPE app_public.create_event_quotas AS (
	"position" smallint,
	title jsonb,
	size smallint
);


--
-- Name: question_type; Type: TYPE; Schema: app_public; Owner: -
--

CREATE TYPE app_public.question_type AS ENUM (
    'short-text',
    'long-text',
    'option'
);


--
-- Name: update_event_quotas; Type: TYPE; Schema: app_public; Owner: -
--

CREATE TYPE app_public.update_event_quotas AS (
	id uuid,
	"position" smallint,
	title jsonb,
	size smallint
);


--
-- Name: assert_valid_password(text); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.assert_valid_password(new_password text) RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
  -- TODO: add better assertions!
  if length(new_password) < 8 then
    raise exception 'Password is too weak' using errcode = 'WEAKP';
  end if;
end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: users; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    username public.citext NOT NULL,
    name text,
    avatar_url text,
    is_admin boolean DEFAULT false NOT NULL,
    is_verified boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT users_avatar_url_check CHECK ((avatar_url ~ '^https?://[^/]+'::text)),
    CONSTRAINT users_username_check CHECK (((length((username)::text) >= 2) AND (length((username)::text) <= 24) AND (username OPERATOR(public.~) '^[a-zA-Z]([_]?[a-zA-Z0-9])+$'::public.citext)))
);


--
-- Name: TABLE users; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON TABLE app_public.users IS 'A user who can log in to the application.';


--
-- Name: COLUMN users.id; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.users.id IS 'Unique identifier for the user.';


--
-- Name: COLUMN users.username; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.users.username IS 'Public-facing username (or ''handle'') of the user.';


--
-- Name: COLUMN users.name; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.users.name IS 'Public-facing name (or pseudonym) of the user.';


--
-- Name: COLUMN users.avatar_url; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.users.avatar_url IS 'Optional avatar URL.';


--
-- Name: COLUMN users.is_admin; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.users.is_admin IS 'If true, the user has elevated privileges.';


--
-- Name: link_or_register_user(uuid, character varying, character varying, json, json); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.link_or_register_user(f_user_id uuid, f_service character varying, f_identifier character varying, f_profile json, f_auth_details json) RETURNS app_public.users
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_matched_user_id uuid;
  v_matched_authentication_id uuid;
  v_email citext;
  v_name text;
  v_avatar_url text;
  v_user app_public.users;
  v_user_email app_public.user_emails;
begin
  -- See if a user account already matches these details
  select id, user_id
    into v_matched_authentication_id, v_matched_user_id
    from app_public.user_authentications
    where service = f_service
    and identifier = f_identifier
    limit 1;

  if v_matched_user_id is not null and f_user_id is not null and v_matched_user_id <> f_user_id then
    raise exception 'A different user already has this account linked.' using errcode = 'TAKEN';
  end if;

  v_email = f_profile ->> 'email';
  v_name := f_profile ->> 'name';
  v_avatar_url := f_profile ->> 'avatar_url';

  if v_matched_authentication_id is null then
    if f_user_id is not null then
      -- Link new account to logged in user account
      insert into app_public.user_authentications (user_id, service, identifier, details) values
        (f_user_id, f_service, f_identifier, f_profile) returning id, user_id into v_matched_authentication_id, v_matched_user_id;
      insert into app_private.user_authentication_secrets (user_authentication_id, details) values
        (v_matched_authentication_id, f_auth_details);
      perform graphile_worker.add_job(
        'user__audit',
        json_build_object(
          'type', 'linked_account',
          'user_id', f_user_id,
          'extra1', f_service,
          'extra2', f_identifier,
          'current_user_id', app_public.current_user_id()
        ));
    elsif v_email is not null then
      -- See if the email is registered
      select * into v_user_email from app_public.user_emails where email = v_email and is_verified is true;
      if v_user_email is not null then
        -- User exists!
        insert into app_public.user_authentications (user_id, service, identifier, details) values
          (v_user_email.user_id, f_service, f_identifier, f_profile) returning id, user_id into v_matched_authentication_id, v_matched_user_id;
        insert into app_private.user_authentication_secrets (user_authentication_id, details) values
          (v_matched_authentication_id, f_auth_details);
        perform graphile_worker.add_job(
          'user__audit',
          json_build_object(
            'type', 'linked_account',
            'user_id', f_user_id,
            'extra1', f_service,
            'extra2', f_identifier,
            'current_user_id', app_public.current_user_id()
          ));
      end if;
    end if;
  end if;
  if v_matched_user_id is null and f_user_id is null and v_matched_authentication_id is null then
    -- Create and return a new user account
    return app_private.register_user(f_service, f_identifier, f_profile, f_auth_details, true);
  else
    if v_matched_authentication_id is not null then
      update app_public.user_authentications
        set details = f_profile
        where id = v_matched_authentication_id;
      update app_private.user_authentication_secrets
        set details = f_auth_details
        where user_authentication_id = v_matched_authentication_id;
      update app_public.users
        set
          name = coalesce(users.name, v_name),
          avatar_url = coalesce(users.avatar_url, v_avatar_url)
        where id = v_matched_user_id
        returning  * into v_user;
      return v_user;
    else
      -- v_matched_authentication_id is null
      -- -> v_matched_user_id is null (they're paired)
      -- -> f_user_id is not null (because the if clause above)
      -- -> v_matched_authentication_id is not null (because of the separate if block above creating a user_authentications)
      -- -> contradiction.
      raise exception 'This should not occur';
    end if;
  end if;
end;
$$;


--
-- Name: FUNCTION link_or_register_user(f_user_id uuid, f_service character varying, f_identifier character varying, f_profile json, f_auth_details json); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.link_or_register_user(f_user_id uuid, f_service character varying, f_identifier character varying, f_profile json, f_auth_details json) IS 'If you''re logged in, this will link an additional OAuth login to your account if necessary. If you''re logged out it may find if an account already exists (based on OAuth details or email address) and return that, or create a new user account if necessary.';


--
-- Name: sessions; Type: TABLE; Schema: app_private; Owner: -
--

CREATE TABLE app_private.sessions (
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_active timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: login(public.citext, text); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.login(username public.citext, password text) RETURNS app_private.sessions
    LANGUAGE plpgsql STRICT
    AS $$
declare
  v_user app_public.users;
  v_user_secret app_private.user_secrets;
  v_login_attempt_window_duration interval = interval '5 minutes';
  v_session app_private.sessions;
begin
  if username like '%@%' then
    -- It's an email
    select users.* into v_user
    from app_public.users
    inner join app_public.user_emails
    on (user_emails.user_id = users.id)
    where user_emails.email = login.username
    order by
      user_emails.is_verified desc, -- Prefer verified email
      user_emails.created_at asc -- Failing that, prefer the first registered (unverified users _should_ verify before logging in)
    limit 1;
  else
    -- It's a username
    select users.* into v_user
    from app_public.users
    where users.username = login.username;
  end if;

  if not (v_user is null) then
    -- Load their secrets
    select * into v_user_secret from app_private.user_secrets
    where user_secrets.user_id = v_user.id;

    -- Have there been too many login attempts?
    if (
      v_user_secret.first_failed_password_attempt is not null
    and
      v_user_secret.first_failed_password_attempt > NOW() - v_login_attempt_window_duration
    and
      v_user_secret.failed_password_attempts >= 3
    ) then
      raise exception 'User account locked - too many login attempts. Try again after 5 minutes.' using errcode = 'LOCKD';
    end if;

    -- Not too many login attempts, let's check the password.
    -- NOTE: `password_hash` could be null, this is fine since `NULL = NULL` is null, and null is falsy.
    if v_user_secret.password_hash = crypt(password, v_user_secret.password_hash) then
      -- Excellent - they're logged in! Let's reset the attempt tracking
      update app_private.user_secrets
      set failed_password_attempts = 0, first_failed_password_attempt = null, last_login_at = now()
      where user_id = v_user.id;
      -- Create a session for the user
      insert into app_private.sessions (user_id) values (v_user.id) returning * into v_session;
      -- And finally return the session
      return v_session;
    else
      -- Wrong password, bump all the attempt tracking figures
      update app_private.user_secrets
      set
        failed_password_attempts = (case when first_failed_password_attempt is null or first_failed_password_attempt < now() - v_login_attempt_window_duration then 1 else failed_password_attempts + 1 end),
        first_failed_password_attempt = (case when first_failed_password_attempt is null or first_failed_password_attempt < now() - v_login_attempt_window_duration then now() else first_failed_password_attempt end)
      where user_id = v_user.id;
      return null; -- Must not throw otherwise transaction will be aborted and attempts won't be recorded
    end if;
  else
    -- No user with that email/username was found
    return null;
  end if;
end;
$$;


--
-- Name: FUNCTION login(username public.citext, password text); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.login(username public.citext, password text) IS 'Returns a user that matches the username/password combo, or null on failure.';


--
-- Name: really_create_user(public.citext, text, text, text, text, boolean, boolean); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.really_create_user(username public.citext, email text, name text, avatar_url text, password text DEFAULT NULL::text, email_is_verified boolean DEFAULT false, is_admin boolean DEFAULT false) RETURNS app_public.users
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_user app_public.users;
  v_username citext = username;
begin
  if password is not null then
    perform app_private.assert_valid_password(password);
  end if;
  if email is null then
    raise exception 'Email is required' using errcode = 'MODAT';
  end if;

  -- Insert the new user
  insert into app_public.users (username, name, avatar_url, is_admin) values
    (v_username, name, avatar_url, is_admin)
    returning * into v_user;

	-- Add the user's email
  insert into app_public.user_emails (user_id, email, is_verified, is_primary)
  values (v_user.id, email, email_is_verified, email_is_verified);

  -- Store the password
  if password is not null then
    update app_private.user_secrets
    set password_hash = crypt(password, gen_salt('bf'))
    where user_id = v_user.id;
  end if;

  -- Refresh the user
  select * into v_user from app_public.users where id = v_user.id;

  return v_user;
end;
$$;


--
-- Name: FUNCTION really_create_user(username public.citext, email text, name text, avatar_url text, password text, email_is_verified boolean, is_admin boolean); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.really_create_user(username public.citext, email text, name text, avatar_url text, password text, email_is_verified boolean, is_admin boolean) IS 'Creates a user account. All arguments are optional, it trusts the calling method to perform sanitisation.';


--
-- Name: register_user(character varying, character varying, json, json, boolean); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.register_user(f_service character varying, f_identifier character varying, f_profile json, f_auth_details json, f_email_is_verified boolean DEFAULT false) RETURNS app_public.users
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_user app_public.users;
  v_email citext;
  v_name text;
  v_username citext;
  v_avatar_url text;
  v_user_authentication_id uuid;
begin
  -- Extract data from the user’s OAuth profile data.
  v_email := f_profile ->> 'email';
  v_name := f_profile ->> 'name';
  v_username := f_profile ->> 'username';
  v_avatar_url := f_profile ->> 'avatar_url';

  -- Sanitise the username, and make it unique if necessary.
  if v_username is null then
    v_username = coalesce(v_name, 'user');
  end if;
  v_username = regexp_replace(v_username, '^[^a-z]+', '', 'gi');
  v_username = regexp_replace(v_username, '[^a-z0-9]+', '_', 'gi');
  if v_username is null or length(v_username) < 3 then
    v_username = 'user';
  end if;
  select (
    case
    when i = 0 then v_username
    else v_username || i::text
    end
  ) into v_username from generate_series(0, 1000) i
  where not exists(
    select 1
    from app_public.users
    where users.username = (
      case
      when i = 0 then v_username
      else v_username || i::text
      end
    )
  )
  limit 1;

  -- Create the user account
  v_user = app_private.really_create_user(
    username => v_username,
    email => v_email,
    name => v_name,
    avatar_url => v_avatar_url,
    email_is_verified => f_email_is_verified
  );

  -- Insert the user’s private account data (e.g. OAuth tokens)
  insert into app_public.user_authentications (user_id, service, identifier, details) values
    (v_user.id, f_service, f_identifier, f_profile) returning id into v_user_authentication_id;
  insert into app_private.user_authentication_secrets (user_authentication_id, details) values
    (v_user_authentication_id, f_auth_details);

  return v_user;
end;
$$;


--
-- Name: FUNCTION register_user(f_service character varying, f_identifier character varying, f_profile json, f_auth_details json, f_email_is_verified boolean); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.register_user(f_service character varying, f_identifier character varying, f_profile json, f_auth_details json, f_email_is_verified boolean) IS 'Used to register a user from information gleaned from OAuth. Primarily used by link_or_register_user';


--
-- Name: reset_password(uuid, text, text); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.reset_password(user_id uuid, reset_token text, new_password text) RETURNS boolean
    LANGUAGE plpgsql STRICT
    AS $$
declare
  v_user app_public.users;
  v_user_secret app_private.user_secrets;
  v_token_max_duration interval = interval '3 days';
begin
  select users.* into v_user
  from app_public.users
  where id = user_id;

  if not (v_user is null) then
    -- Load their secrets
    select * into v_user_secret from app_private.user_secrets
    where user_secrets.user_id = v_user.id;

    -- Have there been too many reset attempts?
    if (
      v_user_secret.first_failed_reset_password_attempt is not null
    and
      v_user_secret.first_failed_reset_password_attempt > NOW() - v_token_max_duration
    and
      v_user_secret.failed_reset_password_attempts >= 20
    ) then
      raise exception 'Password reset locked - too many reset attempts' using errcode = 'LOCKD';
    end if;

    -- Not too many reset attempts, let's check the token
    if v_user_secret.reset_password_token = reset_token then
      -- Excellent - they're legit
      perform app_private.assert_valid_password(new_password);
      -- Let's reset the password as requested
      update app_private.user_secrets
      set
        password_hash = crypt(new_password, gen_salt('bf')),
        failed_password_attempts = 0,
        first_failed_password_attempt = null,
        reset_password_token = null,
        reset_password_token_generated = null,
        failed_reset_password_attempts = 0,
        first_failed_reset_password_attempt = null
      where user_secrets.user_id = v_user.id;
      perform graphile_worker.add_job(
        'user__audit',
        json_build_object(
          'type', 'reset_password',
          'user_id', v_user.id,
          'current_user_id', app_public.current_user_id()
        ));
      return true;
    else
      -- Wrong token, bump all the attempt tracking figures
      update app_private.user_secrets
      set
        failed_reset_password_attempts = (case when first_failed_reset_password_attempt is null or first_failed_reset_password_attempt < now() - v_token_max_duration then 1 else failed_reset_password_attempts + 1 end),
        first_failed_reset_password_attempt = (case when first_failed_reset_password_attempt is null or first_failed_reset_password_attempt < now() - v_token_max_duration then now() else first_failed_reset_password_attempt end)
      where user_secrets.user_id = v_user.id;
      return null;
    end if;
  else
    -- No user with that id was found
    return null;
  end if;
end;
$$;


--
-- Name: tg__add_audit_job(); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.tg__add_audit_job() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $_$
declare
  v_user_id uuid;
  v_type text = TG_ARGV[0];
  v_user_id_attribute text = TG_ARGV[1];
  v_extra_attribute1 text = TG_ARGV[2];
  v_extra_attribute2 text = TG_ARGV[3];
  v_extra_attribute3 text = TG_ARGV[4];
  v_extra1 text;
  v_extra2 text;
  v_extra3 text;
begin
  if v_user_id_attribute is null then
    raise exception 'Invalid tg__add_audit_job call';
  end if;

  execute 'select ($1.' || quote_ident(v_user_id_attribute) || ')::uuid'
    using (case when TG_OP = 'INSERT' then NEW else OLD end)
    into v_user_id;

  if v_extra_attribute1 is not null then
    execute 'select ($1.' || quote_ident(v_extra_attribute1) || ')::text'
      using (case when TG_OP = 'DELETE' then OLD else NEW end)
      into v_extra1;
  end if;
  if v_extra_attribute2 is not null then
    execute 'select ($1.' || quote_ident(v_extra_attribute2) || ')::text'
      using (case when TG_OP = 'DELETE' then OLD else NEW end)
      into v_extra2;
  end if;
  if v_extra_attribute3 is not null then
    execute 'select ($1.' || quote_ident(v_extra_attribute3) || ')::text'
      using (case when TG_OP = 'DELETE' then OLD else NEW end)
      into v_extra3;
  end if;

  if v_user_id is not null then
    perform graphile_worker.add_job(
      'user__audit',
      json_build_object(
        'type', v_type,
        'user_id', v_user_id,
        'extra1', v_extra1,
        'extra2', v_extra2,
        'extra3', v_extra3,
        'current_user_id', app_public.current_user_id(),
        'schema', TG_TABLE_SCHEMA,
        'table', TG_TABLE_NAME
      ));
  end if;

  return NEW;
end;
$_$;


--
-- Name: FUNCTION tg__add_audit_job(); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.tg__add_audit_job() IS 'For notifying a user that an auditable action has taken place. Call with audit event name, user ID attribute name, and optionally another value to be included (e.g. the PK of the table, or some other relevant information). e.g. `tg__add_audit_job(''added_email'', ''user_id'', ''email'')`';


--
-- Name: tg__add_job(); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.tg__add_job() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
begin
  perform graphile_worker.add_job(tg_argv[0], json_build_object('id', NEW.id));
  return NEW;
end;
$$;


--
-- Name: FUNCTION tg__add_job(); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.tg__add_job() IS 'Useful shortcut to create a job on insert/update. Pass the task name as the first trigger argument, and optionally the queue name as the second argument. The record id will automatically be available on the JSON payload.';


--
-- Name: tg__ownership_info(); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.tg__ownership_info() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
begin
  NEW.created_by = (case when TG_OP = 'INSERT' then app_public.current_user_id() else OLD.created_by end);
  NEW.updated_by = (case when TG_OP = 'UPDATE' then app_public.current_user_id() else OLD.updated_by end);
  return NEW;
end;
$$;


--
-- Name: FUNCTION tg__ownership_info(); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.tg__ownership_info() IS 'This trigger should be called on all tables with created_by, updated_by - it ensures that they cannot be manipulated.';


--
-- Name: tg__registration_is_valid(); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.tg__registration_is_valid() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
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
$$;


--
-- Name: FUNCTION tg__registration_is_valid(); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.tg__registration_is_valid() IS 'This trigger validates that a registration is valid. That is, the related event is open to registrations.';


--
-- Name: tg__timestamps(); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.tg__timestamps() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
begin
  NEW.created_at = (case when TG_OP = 'INSERT' then NOW() else OLD.created_at end);
  NEW.updated_at = (case when TG_OP = 'UPDATE' and OLD.updated_at >= NOW() then OLD.updated_at + interval '1 millisecond' else NOW() end);
  return NEW;
end;
$$;


--
-- Name: FUNCTION tg__timestamps(); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.tg__timestamps() IS 'This trigger should be called on all tables with created_at, updated_at - it ensures that they cannot be manipulated and that updated_at will always be larger than the previous updated_at.';


--
-- Name: tg_user_email_secrets__insert_with_user_email(); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.tg_user_email_secrets__insert_with_user_email() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_verification_token text;
begin
  if NEW.is_verified is false then
    v_verification_token = encode(gen_random_bytes(7), 'hex');
  end if;
  insert into app_private.user_email_secrets(user_email_id, verification_token) values(NEW.id, v_verification_token);
  return NEW;
end;
$$;


--
-- Name: FUNCTION tg_user_email_secrets__insert_with_user_email(); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.tg_user_email_secrets__insert_with_user_email() IS 'Ensures that every user_email record has an associated user_email_secret record.';


--
-- Name: tg_user_secrets__insert_with_user(); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.tg_user_secrets__insert_with_user() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
begin
  insert into app_private.user_secrets(user_id) values(NEW.id);
  return NEW;
end;
$$;


--
-- Name: FUNCTION tg_user_secrets__insert_with_user(); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.tg_user_secrets__insert_with_user() IS 'Ensures that every user record has an associated user_secret record.';


--
-- Name: accept_invitation_to_organization(uuid, text); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.accept_invitation_to_organization(invitation_id uuid, code text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_organization app_public.organizations;
begin
  v_organization = app_public.organization_for_invitation(invitation_id, code);

  -- Accept the user into the organization
  insert into app_public.organization_memberships (organization_id, user_id)
    values(v_organization.id, app_public.current_user_id())
    on conflict do nothing;

  -- Delete the invitation
  delete from app_public.organization_invitations where id = invitation_id;
end;
$$;


--
-- Name: change_password(text, text); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.change_password(old_password text, new_password text) RETURNS boolean
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_user app_public.users;
  v_user_secret app_private.user_secrets;
begin
  select users.* into v_user
  from app_public.users
  where id = app_public.current_user_id();

  if not (v_user is null) then
    -- Load their secrets
    select * into v_user_secret from app_private.user_secrets
    where user_secrets.user_id = v_user.id;

    if v_user_secret.password_hash = crypt(old_password, v_user_secret.password_hash) then
      perform app_private.assert_valid_password(new_password);
      -- Reset the password as requested
      update app_private.user_secrets
      set
        password_hash = crypt(new_password, gen_salt('bf'))
      where user_secrets.user_id = v_user.id;
      perform graphile_worker.add_job(
        'user__audit',
        json_build_object(
          'type', 'change_password',
          'user_id', v_user.id,
          'current_user_id', app_public.current_user_id()
        ));
      return true;
    else
      raise exception 'Incorrect password' using errcode = 'CREDS';
    end if;
  else
    raise exception 'You must log in to change your password' using errcode = 'LOGIN';
  end if;
end;
$$;


--
-- Name: FUNCTION change_password(old_password text, new_password text); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.change_password(old_password text, new_password text) IS 'Enter your old password and a new password to change your password.';


--
-- Name: check_language(jsonb); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.check_language(_column jsonb) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_supported_languages text[];
begin
  select supported_languages into v_supported_languages from app_public.languages();

  return (
    -- Check that supported_languages exist as top level keys in _column
    select _column ?| v_supported_languages
    -- ...and that _column contains no other top level keys than supported_languages
    and (select v_supported_languages @> array_agg(keys) from jsonb_object_keys(_column) as keys)
  );
end;
$$;


--
-- Name: claim_registration_token(uuid, uuid); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.claim_registration_token(event_id uuid, quota_id uuid) RETURNS app_public.claim_registration_token_output
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
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
$$;


--
-- Name: FUNCTION claim_registration_token(event_id uuid, quota_id uuid); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.claim_registration_token(event_id uuid, quota_id uuid) IS 'Generates a registration token that must be provided during registration. The token is used to prevent F5-wars.';


--
-- Name: confirm_account_deletion(text); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.confirm_account_deletion(token text) RETURNS boolean
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_user_secret app_private.user_secrets;
  v_token_max_duration interval = interval '3 days';
begin
  if app_public.current_user_id() is null then
    raise exception 'You must log in to delete your account' using errcode = 'LOGIN';
  end if;

  select * into v_user_secret
    from app_private.user_secrets
    where user_secrets.user_id = app_public.current_user_id();

  if v_user_secret is null then
    -- Success: they're already deleted
    return true;
  end if;

  -- Check the token
  if (
    -- token is still valid
    v_user_secret.delete_account_token_generated > now() - v_token_max_duration
  and
    -- token matches
    v_user_secret.delete_account_token = token
  ) then
    -- Token passes; delete their account :(
    delete from app_public.users where id = app_public.current_user_id();
    return true;
  end if;

  raise exception 'The supplied token was incorrect - perhaps you''re logged in to the wrong account, or the token has expired?' using errcode = 'DNIED';
end;
$$;


--
-- Name: FUNCTION confirm_account_deletion(token text); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.confirm_account_deletion(token text) IS 'If you''re certain you want to delete your account, use `requestAccountDeletion` to request an account deletion token, and then supply the token through this mutation to complete account deletion.';


--
-- Name: quotas; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.quotas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    "position" smallint NOT NULL,
    title jsonb NOT NULL,
    size smallint NOT NULL,
    questions_public json,
    questions_private json,
    created_by uuid,
    updated_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT _cnstr_check_title_language CHECK (app_public.check_language(title)),
    CONSTRAINT quotas_size_check CHECK ((size > 0))
);


--
-- Name: TABLE quotas; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON TABLE app_public.quotas IS 'Main table for registration quotas.';


--
-- Name: COLUMN quotas.event_id; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.quotas.event_id IS 'Identifier of the event that this quota is for.';


--
-- Name: COLUMN quotas."position"; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.quotas."position" IS 'Quota position. Used to order quotas.';


--
-- Name: COLUMN quotas.title; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.quotas.title IS 'Title for the quota.';


--
-- Name: COLUMN quotas.size; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.quotas.size IS 'Size of the quota.';


--
-- Name: COLUMN quotas.questions_public; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.quotas.questions_public IS 'Public questions related to the quota.';


--
-- Name: COLUMN quotas.questions_private; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.quotas.questions_private IS 'Private questions related to the quota.';


--
-- Name: create_event_quotas(uuid, app_public.create_event_quotas[]); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.create_event_quotas(event_id uuid, quotas app_public.create_event_quotas[]) RETURNS app_public.quotas[]
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
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
$$;


--
-- Name: FUNCTION create_event_quotas(event_id uuid, quotas app_public.create_event_quotas[]); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.create_event_quotas(event_id uuid, quotas app_public.create_event_quotas[]) IS 'Create multiple quotas at once.';


--
-- Name: organizations; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.organizations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slug public.citext NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: create_organization(public.citext, text); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.create_organization(slug public.citext, name text) RETURNS app_public.organizations
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_org app_public.organizations;
begin
  if app_public.current_user_id() is null then
    raise exception 'You must log in to create an organization' using errcode = 'LOGIN';
  end if;
  insert into app_public.organizations (slug, name) values (slug, name) returning * into v_org;
  insert into app_public.organization_memberships (organization_id, user_id, is_owner)
    values(v_org.id, app_public.current_user_id(), true);
  return v_org;
end;
$$;


--
-- Name: registrations; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.registrations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    quota_id uuid NOT NULL,
    first_name text,
    last_name text,
    email public.citext,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT registrations_email_check CHECK ((email OPERATOR(public.~) '[^@]+@[^@]+\.[^@]+'::public.citext))
);


--
-- Name: TABLE registrations; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON TABLE app_public.registrations IS 'Main table for registrations.';


--
-- Name: COLUMN registrations.id; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.registrations.id IS 'Unique identifier for the registration.';


--
-- Name: COLUMN registrations.event_id; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.registrations.event_id IS 'Identifier of a related event.';


--
-- Name: COLUMN registrations.quota_id; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.registrations.quota_id IS 'Identifier of a related quota.';


--
-- Name: COLUMN registrations.first_name; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.registrations.first_name IS 'First name of the person registering to an event.';


--
-- Name: COLUMN registrations.last_name; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.registrations.last_name IS 'Last name of the person registering to an event.';


--
-- Name: COLUMN registrations.email; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.registrations.email IS '@omit
Email address of the person registering to an event.';


--
-- Name: create_registration(text, uuid, uuid, text, text, public.citext); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.create_registration("registrationToken" text, "eventId" uuid, "quotaId" uuid, "firstName" text, "lastName" text, email public.citext) RETURNS app_public.registrations
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
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
$$;


--
-- Name: FUNCTION create_registration("registrationToken" text, "eventId" uuid, "quotaId" uuid, "firstName" text, "lastName" text, email public.citext); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.create_registration("registrationToken" text, "eventId" uuid, "quotaId" uuid, "firstName" text, "lastName" text, email public.citext) IS 'Register to an event. Checks that a valid registration token was suplied.';


--
-- Name: current_session_id(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.current_session_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select nullif(pg_catalog.current_setting('jwt.claims.session_id', true), '')::uuid;
$$;


--
-- Name: FUNCTION current_session_id(); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.current_session_id() IS 'Handy method to get the current session ID.';


--
-- Name: current_user(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public."current_user"() RETURNS app_public.users
    LANGUAGE sql STABLE
    AS $$
  select users.* from app_public.users where id = app_public.current_user_id();
$$;


--
-- Name: FUNCTION "current_user"(); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public."current_user"() IS 'The currently logged in user (or null if not logged in).';


--
-- Name: current_user_id(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.current_user_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
  select user_id from app_private.sessions where uuid = app_public.current_session_id();
$$;


--
-- Name: FUNCTION current_user_id(); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.current_user_id() IS 'Handy method to get the current user ID for use in RLS policies, etc; in GraphQL, use `currentUser{id}` instead.';


--
-- Name: current_user_invited_organization_ids(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.current_user_invited_organization_ids() RETURNS SETOF uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
  select organization_id from app_public.organization_invitations
    where user_id = app_public.current_user_id();
$$;


--
-- Name: current_user_is_admin(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.current_user_is_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
  select exists (select 1
    from app_public.users
    where
      id = app_public.current_user_id()
      and is_admin = true)
$$;


--
-- Name: current_user_is_owner_organization_member(uuid); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.current_user_is_owner_organization_member(owner_organization_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
  select exists (select 1
    from
      app_public.organization_memberships
    where
      user_id = app_public.current_user_id()
      and owner_organization_id = organization_id)
$$;


--
-- Name: current_user_member_organization_ids(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.current_user_member_organization_ids() RETURNS SETOF uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
  select organization_id from app_public.organization_memberships
    where user_id = app_public.current_user_id();
$$;


--
-- Name: delete_organization(uuid); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.delete_organization(organization_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
begin
  if exists(
    select 1
    from app_public.organization_memberships
    where user_id = app_public.current_user_id()
    and organization_memberships.organization_id = delete_organization.organization_id
    and is_owner is true
  ) then
    delete from app_public.organizations where id = organization_id;
  end if;
end;
$$;


--
-- Name: delete_registration(text); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.delete_registration("updateToken" text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
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
$$;


--
-- Name: FUNCTION delete_registration("updateToken" text); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.delete_registration("updateToken" text) IS 'Delete event registration.';


--
-- Name: events; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slug public.citext NOT NULL,
    name jsonb NOT NULL,
    description jsonb NOT NULL,
    event_start_time timestamp with time zone NOT NULL,
    event_end_time timestamp with time zone NOT NULL,
    registration_start_time timestamp with time zone NOT NULL,
    registration_end_time timestamp with time zone NOT NULL,
    is_highlighted boolean DEFAULT false NOT NULL,
    is_draft boolean DEFAULT true NOT NULL,
    header_image_file text,
    owner_organization_id uuid NOT NULL,
    category_id uuid NOT NULL,
    created_by uuid,
    updated_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT _cnstr_check_description_language CHECK (app_public.check_language(description)),
    CONSTRAINT _cnstr_check_event_registration_time CHECK ((registration_start_time < registration_end_time)),
    CONSTRAINT _cnstr_check_event_time CHECK ((event_start_time < event_end_time)),
    CONSTRAINT _cnstr_check_name_language CHECK (app_public.check_language(name)),
    CONSTRAINT _cnstr_check_registration_end_before_event_start CHECK ((registration_end_time < event_start_time))
);


--
-- Name: TABLE events; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON TABLE app_public.events IS 'Main table for events.';


--
-- Name: COLUMN events.id; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.events.id IS 'Unique identifier for the event.';


--
-- Name: COLUMN events.slug; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.events.slug IS 'Slug for the event.';


--
-- Name: COLUMN events.name; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.events.name IS 'Name of the event.';


--
-- Name: COLUMN events.description; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.events.description IS 'Description of the event.';


--
-- Name: COLUMN events.event_start_time; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.events.event_start_time IS 'Starting time of the event.';


--
-- Name: COLUMN events.event_end_time; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.events.event_end_time IS 'Ending time of the event.';


--
-- Name: COLUMN events.registration_start_time; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.events.registration_start_time IS 'Time of event registration open.';


--
-- Name: COLUMN events.registration_end_time; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.events.registration_end_time IS 'Time of event registration end.';


--
-- Name: COLUMN events.is_highlighted; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.events.is_highlighted IS 'A highlighted event.';


--
-- Name: COLUMN events.is_draft; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.events.is_draft IS 'A draft event that is not publicly visible.';


--
-- Name: COLUMN events.header_image_file; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.events.header_image_file IS 'Header image for the event';


--
-- Name: COLUMN events.owner_organization_id; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.events.owner_organization_id IS 'Id of the organizer.';


--
-- Name: COLUMN events.category_id; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.events.category_id IS 'Id of the event category.';


--
-- Name: events_signup_closed(app_public.events); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.events_signup_closed(e app_public.events) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  select now() > e.registration_end_time;
$$;


--
-- Name: FUNCTION events_signup_closed(e app_public.events); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.events_signup_closed(e app_public.events) IS 'Designates whether event signup is closed or not.';


--
-- Name: events_signup_open(app_public.events); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.events_signup_open(e app_public.events) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  select now() between e.registration_start_time and e.registration_end_time;
$$;


--
-- Name: FUNCTION events_signup_open(e app_public.events); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.events_signup_open(e app_public.events) IS 'Designates whether event signup is open or not.';


--
-- Name: events_signup_upcoming(app_public.events); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.events_signup_upcoming(e app_public.events) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  select now() < e.registration_start_time;
$$;


--
-- Name: FUNCTION events_signup_upcoming(e app_public.events); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.events_signup_upcoming(e app_public.events) IS 'Designates whether event signup is upcoming or not.';


--
-- Name: forgot_password(public.citext); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.forgot_password(email public.citext) RETURNS void
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_user_email app_public.user_emails;
  v_token text;
  v_token_min_duration_between_emails interval = interval '3 minutes';
  v_token_max_duration interval = interval '3 days';
  v_now timestamptz = clock_timestamp(); -- Function can be called multiple during transaction
  v_latest_attempt timestamptz;
begin
  -- Find the matching user_email:
  select user_emails.* into v_user_email
  from app_public.user_emails
  where user_emails.email = forgot_password.email
  order by is_verified desc, id desc;

  -- If there is no match:
  if v_user_email is null then
    -- This email doesn't exist in the system; trigger an email stating as much.

    -- We do not allow this email to be triggered more than once every 15
    -- minutes, so we need to track it:
    insert into app_private.unregistered_email_password_resets (email, latest_attempt)
      values (forgot_password.email, v_now)
      on conflict on constraint unregistered_email_pkey
      do update
        set latest_attempt = v_now, attempts = unregistered_email_password_resets.attempts + 1
        where unregistered_email_password_resets.latest_attempt < v_now - interval '15 minutes'
      returning latest_attempt into v_latest_attempt;

    if v_latest_attempt = v_now then
      perform graphile_worker.add_job(
        'user__forgot_password_unregistered_email',
        json_build_object('email', forgot_password.email::text)
      );
    end if;

    -- TODO: we should clear out the unregistered_email_password_resets table periodically.

    return;
  end if;

  -- There was a match.
  -- See if we've triggered a reset recently:
  if exists(
    select 1
    from app_private.user_email_secrets
    where user_email_id = v_user_email.id
    and password_reset_email_sent_at is not null
    and password_reset_email_sent_at > v_now - v_token_min_duration_between_emails
  ) then
    -- If so, take no action.
    return;
  end if;

  -- Fetch or generate reset token:
  update app_private.user_secrets
  set
    reset_password_token = (
      case
      when reset_password_token is null or reset_password_token_generated < v_now - v_token_max_duration
      then encode(gen_random_bytes(7), 'hex')
      else reset_password_token
      end
    ),
    reset_password_token_generated = (
      case
      when reset_password_token is null or reset_password_token_generated < v_now - v_token_max_duration
      then v_now
      else reset_password_token_generated
      end
    )
  where user_id = v_user_email.user_id
  returning reset_password_token into v_token;

  -- Don't allow spamming an email:
  update app_private.user_email_secrets
  set password_reset_email_sent_at = v_now
  where user_email_id = v_user_email.id;

  -- Trigger email send:
  perform graphile_worker.add_job(
    'user__forgot_password',
    json_build_object('id', v_user_email.user_id, 'email', v_user_email.email::text, 'token', v_token)
  );

end;
$$;


--
-- Name: FUNCTION forgot_password(email public.citext); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.forgot_password(email public.citext) IS 'If you''ve forgotten your password, give us one of your email addresses and we''ll send you a reset token. Note this only works if you have added an email address!';


--
-- Name: invite_to_organization(uuid, public.citext, public.citext); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.invite_to_organization(organization_id uuid, username public.citext DEFAULT NULL::public.citext, email public.citext DEFAULT NULL::public.citext) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_code text;
  v_user app_public.users;
begin
  -- Are we allowed to add this person
  -- Are we logged in
  if app_public.current_user_id() is null then
    raise exception 'You must log in to invite a user' using errcode = 'LOGIN';
  end if;

  select * into v_user from app_public.users where users.username = invite_to_organization.username;

  -- Are we the owner of this organization
  if not exists(
    select 1 from app_public.organization_memberships
      where organization_memberships.organization_id = invite_to_organization.organization_id
      and organization_memberships.user_id = app_public.current_user_id()
      and is_owner is true
  ) then
    raise exception 'You''re not the owner of this organization' using errcode = 'DNIED';
  end if;

  if v_user.id is not null and exists(
    select 1 from app_public.organization_memberships
      where organization_memberships.organization_id = invite_to_organization.organization_id
      and organization_memberships.user_id = v_user.id
  ) then
    raise exception 'Cannot invite someone who is already a member' using errcode = 'ISMBR';
  end if;

  if email is not null then
    v_code = encode(gen_random_bytes(7), 'hex');
  end if;

  if v_user.id is not null and not v_user.is_verified then
    raise exception 'The user you attempted to invite has not verified their account' using errcode = 'VRFY2';
  end if;

  if v_user.id is null and email is null then
    raise exception 'Could not find person to invite' using errcode = 'NTFND';
  end if;

  -- Invite the user
  insert into app_public.organization_invitations(organization_id, user_id, email, code)
    values (invite_to_organization.organization_id, v_user.id, email, v_code);
end;
$$;


--
-- Name: languages(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.languages() RETURNS app_public.app_languages
    LANGUAGE sql STABLE
    AS $$
  select array['fi', 'en'], 'fi';
$$;


--
-- Name: logout(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.logout() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
begin
  -- Delete the session
  delete from app_private.sessions where uuid = app_public.current_session_id();
  -- Clear the identifier from the transaction
  perform set_config('jwt.claims.session_id', '', true);
end;
$$;


--
-- Name: user_emails; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.user_emails (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid DEFAULT app_public.current_user_id() NOT NULL,
    email public.citext NOT NULL,
    is_verified boolean DEFAULT false NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_emails_email_check CHECK ((email OPERATOR(public.~) '[^@]+@[^@]+\.[^@]+'::public.citext)),
    CONSTRAINT user_emails_must_be_verified_to_be_primary CHECK (((is_primary IS FALSE) OR (is_verified IS TRUE)))
);


--
-- Name: TABLE user_emails; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON TABLE app_public.user_emails IS 'Information about a user''s email address.';


--
-- Name: COLUMN user_emails.email; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.user_emails.email IS 'The users email address, in `a@b.c` format.';


--
-- Name: COLUMN user_emails.is_verified; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.user_emails.is_verified IS 'True if the user has is_verified their email address (by clicking the link in the email we sent them, or logging in with a social login provider), false otherwise.';


--
-- Name: make_email_primary(uuid); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.make_email_primary(email_id uuid) RETURNS app_public.user_emails
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_user_email app_public.user_emails;
begin
  select * into v_user_email from app_public.user_emails where id = email_id and user_id = app_public.current_user_id();
  if v_user_email is null then
    raise exception 'That''s not your email' using errcode = 'DNIED';
    return null;
  end if;
  if v_user_email.is_verified is false then
    raise exception 'You may not make an unverified email primary' using errcode = 'VRFY1';
  end if;
  update app_public.user_emails set is_primary = false where user_id = app_public.current_user_id() and is_primary is true and id <> email_id;
  update app_public.user_emails set is_primary = true where user_id = app_public.current_user_id() and is_primary is not true and id = email_id returning * into v_user_email;
  return v_user_email;
end;
$$;


--
-- Name: FUNCTION make_email_primary(email_id uuid); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.make_email_primary(email_id uuid) IS 'Your primary email is where we''ll notify of account events; other emails may be used for discovery or login. Use this when you''re changing your email address.';


--
-- Name: organization_for_invitation(uuid, text); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.organization_for_invitation(invitation_id uuid, code text DEFAULT NULL::text) RETURNS app_public.organizations
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_invitation app_public.organization_invitations;
  v_organization app_public.organizations;
begin
  if app_public.current_user_id() is null then
    raise exception 'You must log in to accept an invitation' using errcode = 'LOGIN';
  end if;

  select * into v_invitation from app_public.organization_invitations where id = invitation_id;

  if v_invitation is null then
    raise exception 'We could not find that invitation' using errcode = 'NTFND';
  end if;

  if v_invitation.user_id is not null then
    if v_invitation.user_id is distinct from app_public.current_user_id() then
      raise exception 'That invitation is not for you' using errcode = 'DNIED';
    end if;
  else
    if v_invitation.code is distinct from code then
      raise exception 'Incorrect invitation code' using errcode = 'DNIED';
    end if;
  end if;

  select * into v_organization from app_public.organizations where id = v_invitation.organization_id;

  return v_organization;
end;
$$;


--
-- Name: organizations_current_user_is_owner(app_public.organizations); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.organizations_current_user_is_owner(org app_public.organizations) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  select exists(
    select 1
    from app_public.organization_memberships
    where organization_id = org.id
    and user_id = app_public.current_user_id()
    and is_owner is true
  )
$$;


--
-- Name: registration_by_update_token(text); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.registration_by_update_token("updateToken" text) RETURNS app_public.registrations
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
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
$$;


--
-- Name: FUNCTION registration_by_update_token("updateToken" text); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.registration_by_update_token("updateToken" text) IS 'Get registration by update token.';


--
-- Name: registrations_full_name(app_public.registrations); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.registrations_full_name(registration app_public.registrations) RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select registration.first_name || ' ' || registration.last_name
$$;


--
-- Name: FUNCTION registrations_full_name(registration app_public.registrations); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.registrations_full_name(registration app_public.registrations) IS 'Returns the full name of a registered person.';


--
-- Name: registrations_is_queued(app_public.registrations); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.registrations_is_queued(registration app_public.registrations) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
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
$$;


--
-- Name: FUNCTION registrations_is_queued(registration app_public.registrations); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.registrations_is_queued(registration app_public.registrations) IS 'Designates whether the registration is queued for a quota or not.';


--
-- Name: remove_from_organization(uuid, uuid); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.remove_from_organization(organization_id uuid, user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_my_membership app_public.organization_memberships;
begin
  select * into v_my_membership
    from app_public.organization_memberships
    where organization_memberships.organization_id = remove_from_organization.organization_id
    and organization_memberships.user_id = app_public.current_user_id();

  if (v_my_membership is null) then
    -- I'm not a member of that organization
    return;
  elsif v_my_membership.is_owner then
    if remove_from_organization.user_id <> app_public.current_user_id() then
      -- Delete it
    else
      -- Need to transfer ownership before I can leave
      return;
    end if;
  elsif v_my_membership.user_id = user_id then
    -- Delete it
  else
    -- Not allowed to delete it
    return;
  end if;

  delete from app_public.organization_memberships
    where organization_memberships.organization_id = remove_from_organization.organization_id
    and organization_memberships.user_id = remove_from_organization.user_id;

end;
$$;


--
-- Name: request_account_deletion(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.request_account_deletion() RETURNS boolean
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
  v_user_email app_public.user_emails;
  v_token text;
  v_token_max_duration interval = interval '3 days';
begin
  if app_public.current_user_id() is null then
    raise exception 'You must log in to delete your account' using errcode = 'LOGIN';
  end if;

  -- Get the email to send account deletion token to
  select * into v_user_email
    from app_public.user_emails
    where user_id = app_public.current_user_id()
    order by is_primary desc, is_verified desc, id desc
    limit 1;

  -- Fetch or generate token
  update app_private.user_secrets
  set
    delete_account_token = (
      case
      when delete_account_token is null or delete_account_token_generated < NOW() - v_token_max_duration
      then encode(gen_random_bytes(7), 'hex')
      else delete_account_token
      end
    ),
    delete_account_token_generated = (
      case
      when delete_account_token is null or delete_account_token_generated < NOW() - v_token_max_duration
      then now()
      else delete_account_token_generated
      end
    )
  where user_id = app_public.current_user_id()
  returning delete_account_token into v_token;

  -- Trigger email send
  perform graphile_worker.add_job('user__send_delete_account_email', json_build_object('email', v_user_email.email::text, 'token', v_token));
  return true;
end;
$$;


--
-- Name: FUNCTION request_account_deletion(); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.request_account_deletion() IS 'Begin the account deletion flow by requesting the confirmation email';


--
-- Name: resend_email_verification_code(uuid); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.resend_email_verification_code(email_id uuid) RETURNS boolean
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
begin
  if exists(
    select 1
    from app_public.user_emails
    where user_emails.id = email_id
    and user_id = app_public.current_user_id()
    and is_verified is false
  ) then
    perform graphile_worker.add_job('user_emails__send_verification', json_build_object('id', email_id));
    return true;
  end if;
  return false;
end;
$$;


--
-- Name: FUNCTION resend_email_verification_code(email_id uuid); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.resend_email_verification_code(email_id uuid) IS 'If you didn''t receive the verification code for this email, we can resend it. We silently cap the rate of resends on the backend, so calls to this function may not result in another email being sent if it has been called recently.';


--
-- Name: tg__graphql_subscription(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.tg__graphql_subscription() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
declare
  v_process_new bool = (TG_OP = 'INSERT' OR TG_OP = 'UPDATE');
  v_process_old bool = (TG_OP = 'UPDATE' OR TG_OP = 'DELETE');
  v_event text = TG_ARGV[0];
  v_topic_template text = TG_ARGV[1];
  v_attribute text = TG_ARGV[2];
  v_record record;
  v_sub text;
  v_topic text;
  v_i int = 0;
  v_last_topic text;
begin
  for v_i in 0..1 loop
    if (v_i = 0) and v_process_new is true then
      v_record = new;
    elsif (v_i = 1) and v_process_old is true then
      v_record = old;
    else
      continue;
    end if;
     if v_attribute is not null then
      execute 'select $1.' || quote_ident(v_attribute)
        using v_record
        into v_sub;
    end if;
    if v_sub is not null then
      v_topic = replace(v_topic_template, '$1', v_sub);
    else
      v_topic = v_topic_template;
    end if;
    if v_topic is distinct from v_last_topic then
      -- This if statement prevents us from triggering the same notification twice
      v_last_topic = v_topic;
      perform pg_notify(v_topic, json_build_object(
        'event', v_event,
        'subject', v_sub,
        'id', v_record.id
      )::text);
    end if;
  end loop;
  return v_record;
end;
$_$;


--
-- Name: FUNCTION tg__graphql_subscription(); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.tg__graphql_subscription() IS 'This function enables the creation of simple focussed GraphQL subscriptions using database triggers. Read more here: https://www.graphile.org/postgraphile/subscriptions/#custom-subscriptions';


--
-- Name: tg_user_emails__forbid_if_verified(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.tg_user_emails__forbid_if_verified() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
begin
  if exists(select 1 from app_public.user_emails where email = NEW.email and is_verified is true) then
    raise exception 'An account using that email address has already been created.' using errcode='EMTKN';
  end if;
  return NEW;
end;
$$;


--
-- Name: tg_user_emails__prevent_delete_last_email(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.tg_user_emails__prevent_delete_last_email() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
begin
  if exists (
    with remaining as (
      select user_emails.user_id
      from app_public.user_emails
      inner join deleted
      on user_emails.user_id = deleted.user_id
      -- Don't delete last verified email
      where (user_emails.is_verified is true or not exists (
        select 1
        from deleted d2
        where d2.user_id = user_emails.user_id
        and d2.is_verified is true
      ))
      order by user_emails.id asc

      /*
       * Lock this table to prevent race conditions; see:
       * https://www.cybertec-postgresql.com/en/triggers-to-enforce-constraints/
       */
      for update of user_emails
    )
    select 1
    from app_public.users
    where id in (
      select user_id from deleted
      except
      select user_id from remaining
    )
  )
  then
    raise exception 'You must have at least one (verified) email address' using errcode = 'CDLEA';
  end if;

  return null;
end;
$$;


--
-- Name: tg_user_emails__verify_account_on_verified(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.tg_user_emails__verify_account_on_verified() RETURNS trigger
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
begin
  update app_public.users set is_verified = true where id = new.user_id and is_verified is false;
  return new;
end;
$$;


--
-- Name: tg_users__deletion_organization_checks_and_actions(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.tg_users__deletion_organization_checks_and_actions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  -- Check they're not an organization owner
  if exists(
    select 1
    from app_public.organization_memberships
    where user_id = app_public.current_user_id()
    and is_owner is true
  ) then
    raise exception 'You cannot delete your account until you are not the owner of any organizations.' using errcode = 'OWNER';
  end if;

  return old;
end;
$$;


--
-- Name: transfer_organization_ownership(uuid, uuid); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.transfer_organization_ownership(organization_id uuid, user_id uuid) RETURNS app_public.organizations
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
declare
 v_org app_public.organizations;
begin
  if exists(
    select 1
    from app_public.organization_memberships
    where organization_memberships.user_id = app_public.current_user_id()
    and organization_memberships.organization_id = transfer_organization_ownership.organization_id
    and is_owner is true
  ) then
    update app_public.organization_memberships
      set is_owner = true
      where organization_memberships.organization_id = transfer_organization_ownership.organization_id
      and organization_memberships.user_id = transfer_organization_ownership.user_id;
    if found then
      update app_public.organization_memberships
        set is_owner = false
        where organization_memberships.organization_id = transfer_organization_ownership.organization_id
        and organization_memberships.user_id = app_public.current_user_id();

      select * into v_org from app_public.organizations where id = organization_id;
      return v_org;
    end if;
  end if;
  return null;
end;
$$;


--
-- Name: update_event_quotas(uuid, app_public.update_event_quotas[]); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.update_event_quotas(event_id uuid, quotas app_public.update_event_quotas[]) RETURNS app_public.quotas[]
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
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
$$;


--
-- Name: FUNCTION update_event_quotas(event_id uuid, quotas app_public.update_event_quotas[]); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.update_event_quotas(event_id uuid, quotas app_public.update_event_quotas[]) IS 'Update multiple quotas at once.';


--
-- Name: update_registration(text, text, text); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.update_registration("updateToken" text, "firstName" text, "lastName" text) RETURNS app_public.registrations
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
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
$$;


--
-- Name: FUNCTION update_registration("updateToken" text, "firstName" text, "lastName" text); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.update_registration("updateToken" text, "firstName" text, "lastName" text) IS 'Update event registration. Checks that a valid update token was suplied.';


--
-- Name: users_has_password(app_public.users); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.users_has_password(u app_public.users) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
  select (password_hash is not null) from app_private.user_secrets where user_secrets.user_id = u.id and u.id = app_public.current_user_id();
$$;


--
-- Name: users_primary_email(app_public.users); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.users_primary_email(u app_public.users) RETURNS public.citext
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
  select email
    from app_public.user_emails
    where
      user_emails.user_id = u.id
      and u.id = app_public.current_user_id()
      and user_emails.is_primary = true;
$$;


--
-- Name: FUNCTION users_primary_email(u app_public.users); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.users_primary_email(u app_public.users) IS 'Users primary email.';


--
-- Name: verify_email(uuid, text); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.verify_email(user_email_id uuid, token text) RETURNS boolean
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
begin
  update app_public.user_emails
  set
    is_verified = true,
    is_primary = is_primary or not exists(
      select 1 from app_public.user_emails other_email where other_email.user_id = user_emails.user_id and other_email.is_primary is true
    )
  where id = user_email_id
  and exists(
    select 1 from app_private.user_email_secrets where user_email_secrets.user_email_id = user_emails.id and verification_token = token
  );
  return found;
end;
$$;


--
-- Name: FUNCTION verify_email(user_email_id uuid, token text); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.verify_email(user_email_id uuid, token text) IS 'Once you have received a verification token for your email, you may call this mutation with that token to make your email verified.';


--
-- Name: registration_secrets; Type: TABLE; Schema: app_private; Owner: -
--

CREATE TABLE app_private.registration_secrets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    registration_token text DEFAULT encode(public.gen_random_bytes(7), 'hex'::text),
    update_token text DEFAULT encode(public.gen_random_bytes(7), 'hex'::text),
    confirmation_email_sent boolean DEFAULT false NOT NULL,
    registration_id uuid,
    event_id uuid NOT NULL,
    quota_id uuid NOT NULL
);


--
-- Name: TABLE registration_secrets; Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON TABLE app_private.registration_secrets IS 'The contents of this table should never be visible to the user. Contains data related to event registrations.';


--
-- Name: unregistered_email_password_resets; Type: TABLE; Schema: app_private; Owner: -
--

CREATE TABLE app_private.unregistered_email_password_resets (
    email public.citext NOT NULL,
    attempts integer DEFAULT 1 NOT NULL,
    latest_attempt timestamp with time zone NOT NULL
);


--
-- Name: TABLE unregistered_email_password_resets; Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON TABLE app_private.unregistered_email_password_resets IS 'If someone tries to recover the password for an email that is not registered in our system, this table enables us to rate-limit outgoing emails to avoid spamming.';


--
-- Name: COLUMN unregistered_email_password_resets.attempts; Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON COLUMN app_private.unregistered_email_password_resets.attempts IS 'We store the number of attempts to help us detect accounts being attacked.';


--
-- Name: COLUMN unregistered_email_password_resets.latest_attempt; Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON COLUMN app_private.unregistered_email_password_resets.latest_attempt IS 'We store the time the last password reset was sent to this email to prevent the email getting flooded.';


--
-- Name: user_authentication_secrets; Type: TABLE; Schema: app_private; Owner: -
--

CREATE TABLE app_private.user_authentication_secrets (
    user_authentication_id uuid NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: user_email_secrets; Type: TABLE; Schema: app_private; Owner: -
--

CREATE TABLE app_private.user_email_secrets (
    user_email_id uuid NOT NULL,
    verification_token text,
    verification_email_sent_at timestamp with time zone,
    password_reset_email_sent_at timestamp with time zone
);


--
-- Name: TABLE user_email_secrets; Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON TABLE app_private.user_email_secrets IS 'The contents of this table should never be visible to the user. Contains data mostly related to email verification and avoiding spamming users.';


--
-- Name: COLUMN user_email_secrets.password_reset_email_sent_at; Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON COLUMN app_private.user_email_secrets.password_reset_email_sent_at IS 'We store the time the last password reset was sent to this email to prevent the email getting flooded.';


--
-- Name: user_secrets; Type: TABLE; Schema: app_private; Owner: -
--

CREATE TABLE app_private.user_secrets (
    user_id uuid NOT NULL,
    password_hash text,
    last_login_at timestamp with time zone DEFAULT now() NOT NULL,
    failed_password_attempts integer DEFAULT 0 NOT NULL,
    first_failed_password_attempt timestamp with time zone,
    reset_password_token text,
    reset_password_token_generated timestamp with time zone,
    failed_reset_password_attempts integer DEFAULT 0 NOT NULL,
    first_failed_reset_password_attempt timestamp with time zone,
    delete_account_token text,
    delete_account_token_generated timestamp with time zone
);


--
-- Name: TABLE user_secrets; Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON TABLE app_private.user_secrets IS 'The contents of this table should never be visible to the user. Contains data mostly related to authentication.';


--
-- Name: event_categories; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.event_categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name jsonb NOT NULL,
    description jsonb NOT NULL,
    owner_organization_id uuid NOT NULL,
    created_by uuid,
    updated_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT _cnstr_check_description_language CHECK (app_public.check_language(description)),
    CONSTRAINT _cnstr_check_name_language CHECK (app_public.check_language(name))
);


--
-- Name: TABLE event_categories; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON TABLE app_public.event_categories IS 'Table for event categories.';


--
-- Name: COLUMN event_categories.id; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.event_categories.id IS 'Unique identifier for the event category.';


--
-- Name: COLUMN event_categories.name; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.event_categories.name IS 'Name of the event category.';


--
-- Name: COLUMN event_categories.description; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.event_categories.description IS 'Short description of the event category.';


--
-- Name: COLUMN event_categories.owner_organization_id; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.event_categories.owner_organization_id IS 'Identifier of the organizer.';


--
-- Name: event_questions; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.event_questions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    type app_public.question_type NOT NULL,
    options json,
    created_by uuid,
    updated_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: organization_invitations; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.organization_invitations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    code text,
    user_id uuid,
    email public.citext,
    CONSTRAINT organization_invitations_check CHECK (((user_id IS NULL) <> (email IS NULL))),
    CONSTRAINT organization_invitations_check1 CHECK (((code IS NULL) = (email IS NULL)))
);


--
-- Name: organization_memberships; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.organization_memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    is_owner boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: user_authentications; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.user_authentications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    service text NOT NULL,
    identifier text NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE user_authentications; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON TABLE app_public.user_authentications IS 'Contains information about the login providers this user has used, so that they may disconnect them should they wish.';


--
-- Name: COLUMN user_authentications.service; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.user_authentications.service IS 'The login service used, e.g. `twitter` or `github`.';


--
-- Name: COLUMN user_authentications.identifier; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.user_authentications.identifier IS 'A unique identifier for the user within the login service.';


--
-- Name: COLUMN user_authentications.details; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.user_authentications.details IS 'Additional profile details extracted from this login method';


--
-- Name: registration_secrets registration_secrets_pkey; Type: CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.registration_secrets
    ADD CONSTRAINT registration_secrets_pkey PRIMARY KEY (id);


--
-- Name: registration_secrets registration_secrets_registration_token_key; Type: CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.registration_secrets
    ADD CONSTRAINT registration_secrets_registration_token_key UNIQUE (registration_token);


--
-- Name: registration_secrets registration_secrets_update_token_key; Type: CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.registration_secrets
    ADD CONSTRAINT registration_secrets_update_token_key UNIQUE (update_token);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (uuid);


--
-- Name: unregistered_email_password_resets unregistered_email_pkey; Type: CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.unregistered_email_password_resets
    ADD CONSTRAINT unregistered_email_pkey PRIMARY KEY (email);


--
-- Name: user_authentication_secrets user_authentication_secrets_pkey; Type: CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.user_authentication_secrets
    ADD CONSTRAINT user_authentication_secrets_pkey PRIMARY KEY (user_authentication_id);


--
-- Name: user_email_secrets user_email_secrets_pkey; Type: CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.user_email_secrets
    ADD CONSTRAINT user_email_secrets_pkey PRIMARY KEY (user_email_id);


--
-- Name: user_secrets user_secrets_pkey; Type: CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.user_secrets
    ADD CONSTRAINT user_secrets_pkey PRIMARY KEY (user_id);


--
-- Name: event_categories event_categories_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.event_categories
    ADD CONSTRAINT event_categories_pkey PRIMARY KEY (id);


--
-- Name: event_questions event_questions_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.event_questions
    ADD CONSTRAINT event_questions_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: events events_slug_key; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.events
    ADD CONSTRAINT events_slug_key UNIQUE (slug);


--
-- Name: organization_invitations organization_invitations_organization_id_email_key; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organization_invitations
    ADD CONSTRAINT organization_invitations_organization_id_email_key UNIQUE (organization_id, email);


--
-- Name: organization_invitations organization_invitations_organization_id_user_id_key; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organization_invitations
    ADD CONSTRAINT organization_invitations_organization_id_user_id_key UNIQUE (organization_id, user_id);


--
-- Name: organization_invitations organization_invitations_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organization_invitations
    ADD CONSTRAINT organization_invitations_pkey PRIMARY KEY (id);


--
-- Name: organization_memberships organization_memberships_organization_id_user_id_key; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organization_memberships
    ADD CONSTRAINT organization_memberships_organization_id_user_id_key UNIQUE (organization_id, user_id);


--
-- Name: organization_memberships organization_memberships_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organization_memberships
    ADD CONSTRAINT organization_memberships_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_slug_key; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organizations
    ADD CONSTRAINT organizations_slug_key UNIQUE (slug);


--
-- Name: quotas quotas_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.quotas
    ADD CONSTRAINT quotas_pkey PRIMARY KEY (id);


--
-- Name: registrations registrations_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.registrations
    ADD CONSTRAINT registrations_pkey PRIMARY KEY (id);


--
-- Name: user_authentications uniq_user_authentications; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.user_authentications
    ADD CONSTRAINT uniq_user_authentications UNIQUE (service, identifier);


--
-- Name: user_authentications user_authentications_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.user_authentications
    ADD CONSTRAINT user_authentications_pkey PRIMARY KEY (id);


--
-- Name: user_emails user_emails_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.user_emails
    ADD CONSTRAINT user_emails_pkey PRIMARY KEY (id);


--
-- Name: user_emails user_emails_user_id_email_key; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.user_emails
    ADD CONSTRAINT user_emails_user_id_email_key UNIQUE (user_id, email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: registration_secrets_event_id_idx; Type: INDEX; Schema: app_private; Owner: -
--

CREATE INDEX registration_secrets_event_id_idx ON app_private.registration_secrets USING btree (event_id);


--
-- Name: registration_secrets_registration_id_idx; Type: INDEX; Schema: app_private; Owner: -
--

CREATE INDEX registration_secrets_registration_id_idx ON app_private.registration_secrets USING btree (registration_id);


--
-- Name: sessions_user_id_idx; Type: INDEX; Schema: app_private; Owner: -
--

CREATE INDEX sessions_user_id_idx ON app_private.sessions USING btree (user_id);


--
-- Name: event_categories_created_by_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX event_categories_created_by_idx ON app_public.event_categories USING btree (created_by);


--
-- Name: event_categories_name_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX event_categories_name_idx ON app_public.event_categories USING btree (name);


--
-- Name: event_categories_owner_organization_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX event_categories_owner_organization_id_idx ON app_public.event_categories USING btree (owner_organization_id);


--
-- Name: event_categories_updated_by_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX event_categories_updated_by_idx ON app_public.event_categories USING btree (updated_by);


--
-- Name: event_questions_created_by_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX event_questions_created_by_idx ON app_public.event_questions USING btree (created_by);


--
-- Name: event_questions_event_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX event_questions_event_id_idx ON app_public.event_questions USING btree (event_id);


--
-- Name: event_questions_updated_by_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX event_questions_updated_by_idx ON app_public.event_questions USING btree (updated_by);


--
-- Name: events_category_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX events_category_id_idx ON app_public.events USING btree (category_id);


--
-- Name: events_created_by_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX events_created_by_idx ON app_public.events USING btree (created_by);


--
-- Name: events_event_end_time_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX events_event_end_time_idx ON app_public.events USING btree (event_end_time);


--
-- Name: events_event_start_time_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX events_event_start_time_idx ON app_public.events USING btree (event_start_time);


--
-- Name: events_is_draft_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX events_is_draft_idx ON app_public.events USING btree (is_draft);


--
-- Name: events_owner_organization_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX events_owner_organization_id_idx ON app_public.events USING btree (owner_organization_id);


--
-- Name: events_registration_end_time_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX events_registration_end_time_idx ON app_public.events USING btree (registration_end_time);


--
-- Name: events_registration_start_time_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX events_registration_start_time_idx ON app_public.events USING btree (registration_start_time);


--
-- Name: events_updated_by_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX events_updated_by_idx ON app_public.events USING btree (updated_by);


--
-- Name: idx_user_emails_primary; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX idx_user_emails_primary ON app_public.user_emails USING btree (is_primary, user_id);


--
-- Name: idx_user_emails_user; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX idx_user_emails_user ON app_public.user_emails USING btree (user_id);


--
-- Name: organization_invitations_user_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX organization_invitations_user_id_idx ON app_public.organization_invitations USING btree (user_id);


--
-- Name: organization_memberships_user_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX organization_memberships_user_id_idx ON app_public.organization_memberships USING btree (user_id);


--
-- Name: quotas_created_by_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX quotas_created_by_idx ON app_public.quotas USING btree (created_by);


--
-- Name: quotas_event_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX quotas_event_id_idx ON app_public.quotas USING btree (event_id);


--
-- Name: quotas_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX quotas_id_idx ON app_public.quotas USING btree (id);


--
-- Name: quotas_position_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX quotas_position_idx ON app_public.quotas USING btree ("position");


--
-- Name: quotas_updated_by_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX quotas_updated_by_idx ON app_public.quotas USING btree (updated_by);


--
-- Name: registrations_created_at_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX registrations_created_at_idx ON app_public.registrations USING btree (created_at);


--
-- Name: registrations_event_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX registrations_event_id_idx ON app_public.registrations USING btree (event_id);


--
-- Name: registrations_quota_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX registrations_quota_id_idx ON app_public.registrations USING btree (quota_id);


--
-- Name: uniq_user_emails_primary_email; Type: INDEX; Schema: app_public; Owner: -
--

CREATE UNIQUE INDEX uniq_user_emails_primary_email ON app_public.user_emails USING btree (user_id) WHERE (is_primary IS TRUE);


--
-- Name: uniq_user_emails_verified_email; Type: INDEX; Schema: app_public; Owner: -
--

CREATE UNIQUE INDEX uniq_user_emails_verified_email ON app_public.user_emails USING btree (email) WHERE (is_verified IS TRUE);


--
-- Name: user_authentications_user_id_idx; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX user_authentications_user_id_idx ON app_public.user_authentications USING btree (user_id);


--
-- Name: event_categories _100_timestamps; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _100_timestamps BEFORE INSERT OR UPDATE ON app_public.event_categories FOR EACH ROW EXECUTE FUNCTION app_private.tg__timestamps();


--
-- Name: event_questions _100_timestamps; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _100_timestamps BEFORE INSERT OR UPDATE ON app_public.event_questions FOR EACH ROW EXECUTE FUNCTION app_private.tg__timestamps();


--
-- Name: events _100_timestamps; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _100_timestamps BEFORE INSERT OR UPDATE ON app_public.events FOR EACH ROW EXECUTE FUNCTION app_private.tg__timestamps();


--
-- Name: quotas _100_timestamps; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _100_timestamps BEFORE INSERT OR UPDATE ON app_public.quotas FOR EACH ROW EXECUTE FUNCTION app_private.tg__timestamps();


--
-- Name: registrations _100_timestamps; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _100_timestamps BEFORE INSERT OR UPDATE ON app_public.registrations FOR EACH ROW EXECUTE FUNCTION app_private.tg__timestamps();


--
-- Name: user_authentications _100_timestamps; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _100_timestamps BEFORE INSERT OR UPDATE ON app_public.user_authentications FOR EACH ROW EXECUTE FUNCTION app_private.tg__timestamps();


--
-- Name: user_emails _100_timestamps; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _100_timestamps BEFORE INSERT OR UPDATE ON app_public.user_emails FOR EACH ROW EXECUTE FUNCTION app_private.tg__timestamps();


--
-- Name: users _100_timestamps; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _100_timestamps BEFORE INSERT OR UPDATE ON app_public.users FOR EACH ROW EXECUTE FUNCTION app_private.tg__timestamps();


--
-- Name: user_emails _200_forbid_existing_email; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _200_forbid_existing_email BEFORE INSERT ON app_public.user_emails FOR EACH ROW EXECUTE FUNCTION app_public.tg_user_emails__forbid_if_verified();


--
-- Name: event_categories _200_ownership_info; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _200_ownership_info BEFORE INSERT OR UPDATE ON app_public.event_categories FOR EACH ROW EXECUTE FUNCTION app_private.tg__ownership_info();


--
-- Name: event_questions _200_ownership_info; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _200_ownership_info BEFORE INSERT OR UPDATE ON app_public.event_questions FOR EACH ROW EXECUTE FUNCTION app_private.tg__ownership_info();


--
-- Name: events _200_ownership_info; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _200_ownership_info BEFORE INSERT OR UPDATE ON app_public.events FOR EACH ROW EXECUTE FUNCTION app_private.tg__ownership_info();


--
-- Name: quotas _200_ownership_info; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _200_ownership_info BEFORE INSERT OR UPDATE ON app_public.quotas FOR EACH ROW EXECUTE FUNCTION app_private.tg__ownership_info();


--
-- Name: registrations _200_registration_is_valid; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _200_registration_is_valid BEFORE INSERT ON app_public.registrations FOR EACH ROW EXECUTE FUNCTION app_private.tg__registration_is_valid();


--
-- Name: registrations _300_send_registration_email; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _300_send_registration_email AFTER UPDATE ON app_public.registrations FOR EACH ROW EXECUTE FUNCTION app_private.tg__add_job('registration__send_confirmation_email');


--
-- Name: user_emails _500_audit_added; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _500_audit_added AFTER INSERT ON app_public.user_emails FOR EACH ROW EXECUTE FUNCTION app_private.tg__add_audit_job('added_email', 'user_id', 'id', 'email');


--
-- Name: user_authentications _500_audit_removed; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _500_audit_removed AFTER DELETE ON app_public.user_authentications FOR EACH ROW EXECUTE FUNCTION app_private.tg__add_audit_job('unlinked_account', 'user_id', 'service', 'identifier');


--
-- Name: user_emails _500_audit_removed; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _500_audit_removed AFTER DELETE ON app_public.user_emails FOR EACH ROW EXECUTE FUNCTION app_private.tg__add_audit_job('removed_email', 'user_id', 'id', 'email');


--
-- Name: users _500_deletion_organization_checks_and_actions; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _500_deletion_organization_checks_and_actions BEFORE DELETE ON app_public.users FOR EACH ROW WHEN ((app_public.current_user_id() IS NOT NULL)) EXECUTE FUNCTION app_public.tg_users__deletion_organization_checks_and_actions();


--
-- Name: registrations _500_gql_registration_updated; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _500_gql_registration_updated AFTER INSERT OR DELETE OR UPDATE ON app_public.registrations FOR EACH ROW EXECUTE FUNCTION app_public.tg__graphql_subscription('registrationUpdated', 'graphql:eventRegistrations:$1', 'event_id');


--
-- Name: users _500_gql_update; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _500_gql_update AFTER UPDATE ON app_public.users FOR EACH ROW EXECUTE FUNCTION app_public.tg__graphql_subscription('userChanged', 'graphql:user:$1', 'id');


--
-- Name: user_emails _500_insert_secrets; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _500_insert_secrets AFTER INSERT ON app_public.user_emails FOR EACH ROW EXECUTE FUNCTION app_private.tg_user_email_secrets__insert_with_user_email();


--
-- Name: users _500_insert_secrets; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _500_insert_secrets AFTER INSERT ON app_public.users FOR EACH ROW EXECUTE FUNCTION app_private.tg_user_secrets__insert_with_user();


--
-- Name: user_emails _500_prevent_delete_last; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _500_prevent_delete_last AFTER DELETE ON app_public.user_emails REFERENCING OLD TABLE AS deleted FOR EACH STATEMENT EXECUTE FUNCTION app_public.tg_user_emails__prevent_delete_last_email();


--
-- Name: organization_invitations _500_send_email; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _500_send_email AFTER INSERT ON app_public.organization_invitations FOR EACH ROW EXECUTE FUNCTION app_private.tg__add_job('organization_invitations__send_invite');


--
-- Name: user_emails _500_verify_account_on_verified; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _500_verify_account_on_verified AFTER INSERT OR UPDATE OF is_verified ON app_public.user_emails FOR EACH ROW WHEN ((new.is_verified IS TRUE)) EXECUTE FUNCTION app_public.tg_user_emails__verify_account_on_verified();


--
-- Name: user_emails _900_send_verification_email; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _900_send_verification_email AFTER INSERT ON app_public.user_emails FOR EACH ROW WHEN ((new.is_verified IS FALSE)) EXECUTE FUNCTION app_private.tg__add_job('user_emails__send_verification');


--
-- Name: registration_secrets registration_secrets_event_id_fkey; Type: FK CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.registration_secrets
    ADD CONSTRAINT registration_secrets_event_id_fkey FOREIGN KEY (event_id) REFERENCES app_public.events(id) ON DELETE CASCADE;


--
-- Name: registration_secrets registration_secrets_quota_id_fkey; Type: FK CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.registration_secrets
    ADD CONSTRAINT registration_secrets_quota_id_fkey FOREIGN KEY (quota_id) REFERENCES app_public.quotas(id) ON DELETE CASCADE;


--
-- Name: registration_secrets registration_secrets_registration_id_fkey; Type: FK CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.registration_secrets
    ADD CONSTRAINT registration_secrets_registration_id_fkey FOREIGN KEY (registration_id) REFERENCES app_public.registrations(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES app_public.users(id) ON DELETE CASCADE;


--
-- Name: user_authentication_secrets user_authentication_secrets_user_authentication_id_fkey; Type: FK CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.user_authentication_secrets
    ADD CONSTRAINT user_authentication_secrets_user_authentication_id_fkey FOREIGN KEY (user_authentication_id) REFERENCES app_public.user_authentications(id) ON DELETE CASCADE;


--
-- Name: user_email_secrets user_email_secrets_user_email_id_fkey; Type: FK CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.user_email_secrets
    ADD CONSTRAINT user_email_secrets_user_email_id_fkey FOREIGN KEY (user_email_id) REFERENCES app_public.user_emails(id) ON DELETE CASCADE;


--
-- Name: user_secrets user_secrets_user_id_fkey; Type: FK CONSTRAINT; Schema: app_private; Owner: -
--

ALTER TABLE ONLY app_private.user_secrets
    ADD CONSTRAINT user_secrets_user_id_fkey FOREIGN KEY (user_id) REFERENCES app_public.users(id) ON DELETE CASCADE;


--
-- Name: event_categories event_categories_created_by_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.event_categories
    ADD CONSTRAINT event_categories_created_by_fkey FOREIGN KEY (created_by) REFERENCES app_public.users(id) ON DELETE SET NULL;


--
-- Name: event_categories event_categories_owner_organization_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.event_categories
    ADD CONSTRAINT event_categories_owner_organization_id_fkey FOREIGN KEY (owner_organization_id) REFERENCES app_public.organizations(id) ON DELETE CASCADE;


--
-- Name: event_categories event_categories_updated_by_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.event_categories
    ADD CONSTRAINT event_categories_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES app_public.users(id) ON DELETE SET NULL;


--
-- Name: event_questions event_questions_created_by_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.event_questions
    ADD CONSTRAINT event_questions_created_by_fkey FOREIGN KEY (created_by) REFERENCES app_public.users(id) ON DELETE SET NULL;


--
-- Name: event_questions event_questions_event_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.event_questions
    ADD CONSTRAINT event_questions_event_id_fkey FOREIGN KEY (event_id) REFERENCES app_public.events(id) ON DELETE CASCADE;


--
-- Name: event_questions event_questions_updated_by_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.event_questions
    ADD CONSTRAINT event_questions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES app_public.users(id) ON DELETE SET NULL;


--
-- Name: events events_category_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.events
    ADD CONSTRAINT events_category_id_fkey FOREIGN KEY (category_id) REFERENCES app_public.event_categories(id) ON DELETE SET NULL;


--
-- Name: events events_created_by_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.events
    ADD CONSTRAINT events_created_by_fkey FOREIGN KEY (created_by) REFERENCES app_public.users(id) ON DELETE SET NULL;


--
-- Name: events events_owner_organization_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.events
    ADD CONSTRAINT events_owner_organization_id_fkey FOREIGN KEY (owner_organization_id) REFERENCES app_public.organizations(id) ON DELETE CASCADE;


--
-- Name: events events_updated_by_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.events
    ADD CONSTRAINT events_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES app_public.users(id) ON DELETE SET NULL;


--
-- Name: organization_invitations organization_invitations_organization_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organization_invitations
    ADD CONSTRAINT organization_invitations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES app_public.organizations(id) ON DELETE CASCADE;


--
-- Name: organization_invitations organization_invitations_user_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organization_invitations
    ADD CONSTRAINT organization_invitations_user_id_fkey FOREIGN KEY (user_id) REFERENCES app_public.users(id) ON DELETE CASCADE;


--
-- Name: organization_memberships organization_memberships_organization_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organization_memberships
    ADD CONSTRAINT organization_memberships_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES app_public.organizations(id) ON DELETE CASCADE;


--
-- Name: organization_memberships organization_memberships_user_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.organization_memberships
    ADD CONSTRAINT organization_memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES app_public.users(id) ON DELETE CASCADE;


--
-- Name: quotas quotas_created_by_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.quotas
    ADD CONSTRAINT quotas_created_by_fkey FOREIGN KEY (created_by) REFERENCES app_public.users(id) ON DELETE SET NULL;


--
-- Name: quotas quotas_event_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.quotas
    ADD CONSTRAINT quotas_event_id_fkey FOREIGN KEY (event_id) REFERENCES app_public.events(id) ON DELETE CASCADE;


--
-- Name: quotas quotas_updated_by_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.quotas
    ADD CONSTRAINT quotas_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES app_public.users(id) ON DELETE SET NULL;


--
-- Name: registrations registrations_event_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.registrations
    ADD CONSTRAINT registrations_event_id_fkey FOREIGN KEY (event_id) REFERENCES app_public.events(id) ON DELETE CASCADE;


--
-- Name: registrations registrations_quota_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.registrations
    ADD CONSTRAINT registrations_quota_id_fkey FOREIGN KEY (quota_id) REFERENCES app_public.quotas(id);


--
-- Name: user_authentications user_authentications_user_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.user_authentications
    ADD CONSTRAINT user_authentications_user_id_fkey FOREIGN KEY (user_id) REFERENCES app_public.users(id) ON DELETE CASCADE;


--
-- Name: user_emails user_emails_user_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.user_emails
    ADD CONSTRAINT user_emails_user_id_fkey FOREIGN KEY (user_id) REFERENCES app_public.users(id) ON DELETE CASCADE;


--
-- Name: registration_secrets; Type: ROW SECURITY; Schema: app_private; Owner: -
--

ALTER TABLE app_private.registration_secrets ENABLE ROW LEVEL SECURITY;

--
-- Name: sessions; Type: ROW SECURITY; Schema: app_private; Owner: -
--

ALTER TABLE app_private.sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: user_authentication_secrets; Type: ROW SECURITY; Schema: app_private; Owner: -
--

ALTER TABLE app_private.user_authentication_secrets ENABLE ROW LEVEL SECURITY;

--
-- Name: user_email_secrets; Type: ROW SECURITY; Schema: app_private; Owner: -
--

ALTER TABLE app_private.user_email_secrets ENABLE ROW LEVEL SECURITY;

--
-- Name: user_secrets; Type: ROW SECURITY; Schema: app_private; Owner: -
--

ALTER TABLE app_private.user_secrets ENABLE ROW LEVEL SECURITY;

--
-- Name: user_authentications delete_own; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY delete_own ON app_public.user_authentications FOR DELETE USING ((user_id = app_public.current_user_id()));


--
-- Name: user_emails delete_own; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY delete_own ON app_public.user_emails FOR DELETE USING ((user_id = app_public.current_user_id()));


--
-- Name: event_categories; Type: ROW SECURITY; Schema: app_public; Owner: -
--

ALTER TABLE app_public.event_categories ENABLE ROW LEVEL SECURITY;

--
-- Name: event_questions; Type: ROW SECURITY; Schema: app_public; Owner: -
--

ALTER TABLE app_public.event_questions ENABLE ROW LEVEL SECURITY;

--
-- Name: events; Type: ROW SECURITY; Schema: app_public; Owner: -
--

ALTER TABLE app_public.events ENABLE ROW LEVEL SECURITY;

--
-- Name: user_emails insert_own; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY insert_own ON app_public.user_emails FOR INSERT WITH CHECK ((user_id = app_public.current_user_id()));


--
-- Name: events manage_admin; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY manage_admin ON app_public.events USING (app_public.current_user_is_admin()) WITH CHECK (app_public.current_user_is_admin());


--
-- Name: event_questions manage_as_admin; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY manage_as_admin ON app_public.event_questions USING ((EXISTS ( SELECT 1
   FROM app_public.users
  WHERE ((users.is_admin IS TRUE) AND (users.id = app_public.current_user_id())))));


--
-- Name: quotas manage_as_admin; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY manage_as_admin ON app_public.quotas USING ((EXISTS ( SELECT 1
   FROM app_public.users
  WHERE ((users.is_admin IS TRUE) AND (users.id = app_public.current_user_id())))));


--
-- Name: registrations manage_as_admin; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY manage_as_admin ON app_public.registrations USING ((EXISTS ( SELECT 1
   FROM app_public.users
  WHERE ((users.is_admin IS TRUE) AND (users.id = app_public.current_user_id())))));


--
-- Name: event_categories manage_member; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY manage_member ON app_public.event_categories USING ((owner_organization_id IN ( SELECT app_public.current_user_member_organization_ids() AS current_user_member_organization_ids)));


--
-- Name: events manage_organization; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY manage_organization ON app_public.events USING (app_public.current_user_is_owner_organization_member(owner_organization_id)) WITH CHECK (app_public.current_user_is_owner_organization_member(owner_organization_id));


--
-- Name: event_questions manage_own; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY manage_own ON app_public.event_questions USING ((EXISTS ( SELECT 1
   FROM app_public.organization_memberships
  WHERE ((organization_memberships.user_id = app_public.current_user_id()) AND (organization_memberships.organization_id = ( SELECT events.owner_organization_id
           FROM app_public.events
          WHERE (events.id = event_questions.event_id)))))));


--
-- Name: quotas manage_own; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY manage_own ON app_public.quotas USING ((EXISTS ( SELECT 1
   FROM app_public.organization_memberships
  WHERE ((organization_memberships.user_id = app_public.current_user_id()) AND (organization_memberships.organization_id = ( SELECT events.owner_organization_id
           FROM app_public.events
          WHERE (events.id = quotas.event_id)))))));


--
-- Name: event_questions manage_own_category; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY manage_own_category ON app_public.event_questions USING ((EXISTS ( SELECT 1
   FROM app_public.organization_memberships
  WHERE ((organization_memberships.user_id = app_public.current_user_id()) AND (organization_memberships.organization_id = ( SELECT event_categories.owner_organization_id
           FROM app_public.event_categories
          WHERE (event_categories.id = ( SELECT events.category_id
                   FROM app_public.events
                  WHERE (events.id = event_questions.event_id)))))))));


--
-- Name: organization_invitations; Type: ROW SECURITY; Schema: app_public; Owner: -
--

ALTER TABLE app_public.organization_invitations ENABLE ROW LEVEL SECURITY;

--
-- Name: organization_memberships; Type: ROW SECURITY; Schema: app_public; Owner: -
--

ALTER TABLE app_public.organization_memberships ENABLE ROW LEVEL SECURITY;

--
-- Name: organizations; Type: ROW SECURITY; Schema: app_public; Owner: -
--

ALTER TABLE app_public.organizations ENABLE ROW LEVEL SECURITY;

--
-- Name: quotas; Type: ROW SECURITY; Schema: app_public; Owner: -
--

ALTER TABLE app_public.quotas ENABLE ROW LEVEL SECURITY;

--
-- Name: registrations; Type: ROW SECURITY; Schema: app_public; Owner: -
--

ALTER TABLE app_public.registrations ENABLE ROW LEVEL SECURITY;

--
-- Name: event_categories select_all; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY select_all ON app_public.event_categories FOR SELECT USING (true);


--
-- Name: event_questions select_all; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY select_all ON app_public.event_questions FOR SELECT USING (true);


--
-- Name: events select_all; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY select_all ON app_public.events FOR SELECT USING ((is_draft IS FALSE));


--
-- Name: organizations select_all; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY select_all ON app_public.organizations FOR SELECT USING (true);


--
-- Name: quotas select_all; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY select_all ON app_public.quotas FOR SELECT USING (true);


--
-- Name: registrations select_all; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY select_all ON app_public.registrations FOR SELECT USING (true);


--
-- Name: users select_all; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY select_all ON app_public.users FOR SELECT USING (true);


--
-- Name: organization_memberships select_invited; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY select_invited ON app_public.organization_memberships FOR SELECT USING ((organization_id IN ( SELECT app_public.current_user_invited_organization_ids() AS current_user_invited_organization_ids)));


--
-- Name: organization_memberships select_member; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY select_member ON app_public.organization_memberships FOR SELECT USING ((organization_id IN ( SELECT app_public.current_user_member_organization_ids() AS current_user_member_organization_ids)));


--
-- Name: user_authentications select_own; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY select_own ON app_public.user_authentications FOR SELECT USING ((user_id = app_public.current_user_id()));


--
-- Name: user_emails select_own; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY select_own ON app_public.user_emails FOR SELECT USING ((user_id = app_public.current_user_id()));


--
-- Name: registrations update_all; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY update_all ON app_public.registrations FOR UPDATE USING (true);


--
-- Name: organizations update_owner; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY update_owner ON app_public.organizations FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM app_public.organization_memberships
  WHERE ((organization_memberships.organization_id = organizations.id) AND (organization_memberships.user_id = app_public.current_user_id()) AND (organization_memberships.is_owner IS TRUE)))));


--
-- Name: users update_self; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY update_self ON app_public.users FOR UPDATE USING ((id = app_public.current_user_id()));


--
-- Name: user_authentications; Type: ROW SECURITY; Schema: app_public; Owner: -
--

ALTER TABLE app_public.user_authentications ENABLE ROW LEVEL SECURITY;

--
-- Name: user_emails; Type: ROW SECURITY; Schema: app_public; Owner: -
--

ALTER TABLE app_public.user_emails ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: app_public; Owner: -
--

ALTER TABLE app_public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA app_hidden; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA app_hidden TO ilmo_visitor;


--
-- Name: SCHEMA app_public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA app_public TO ilmo_visitor;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

REVOKE ALL ON SCHEMA public FROM timo;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO ilmo;
GRANT USAGE ON SCHEMA public TO ilmo_visitor;


--
-- Name: FUNCTION assert_valid_password(new_password text); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.assert_valid_password(new_password text) FROM PUBLIC;


--
-- Name: TABLE users; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT ON TABLE app_public.users TO ilmo_visitor;


--
-- Name: COLUMN users.username; Type: ACL; Schema: app_public; Owner: -
--

GRANT UPDATE(username) ON TABLE app_public.users TO ilmo_visitor;


--
-- Name: COLUMN users.name; Type: ACL; Schema: app_public; Owner: -
--

GRANT UPDATE(name) ON TABLE app_public.users TO ilmo_visitor;


--
-- Name: COLUMN users.avatar_url; Type: ACL; Schema: app_public; Owner: -
--

GRANT UPDATE(avatar_url) ON TABLE app_public.users TO ilmo_visitor;


--
-- Name: FUNCTION link_or_register_user(f_user_id uuid, f_service character varying, f_identifier character varying, f_profile json, f_auth_details json); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.link_or_register_user(f_user_id uuid, f_service character varying, f_identifier character varying, f_profile json, f_auth_details json) FROM PUBLIC;


--
-- Name: FUNCTION login(username public.citext, password text); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.login(username public.citext, password text) FROM PUBLIC;


--
-- Name: FUNCTION really_create_user(username public.citext, email text, name text, avatar_url text, password text, email_is_verified boolean, is_admin boolean); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.really_create_user(username public.citext, email text, name text, avatar_url text, password text, email_is_verified boolean, is_admin boolean) FROM PUBLIC;


--
-- Name: FUNCTION register_user(f_service character varying, f_identifier character varying, f_profile json, f_auth_details json, f_email_is_verified boolean); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.register_user(f_service character varying, f_identifier character varying, f_profile json, f_auth_details json, f_email_is_verified boolean) FROM PUBLIC;


--
-- Name: FUNCTION reset_password(user_id uuid, reset_token text, new_password text); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.reset_password(user_id uuid, reset_token text, new_password text) FROM PUBLIC;


--
-- Name: FUNCTION tg__add_audit_job(); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.tg__add_audit_job() FROM PUBLIC;


--
-- Name: FUNCTION tg__add_job(); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.tg__add_job() FROM PUBLIC;


--
-- Name: FUNCTION tg__ownership_info(); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.tg__ownership_info() FROM PUBLIC;


--
-- Name: FUNCTION tg__registration_is_valid(); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.tg__registration_is_valid() FROM PUBLIC;


--
-- Name: FUNCTION tg__timestamps(); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.tg__timestamps() FROM PUBLIC;


--
-- Name: FUNCTION tg_user_email_secrets__insert_with_user_email(); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.tg_user_email_secrets__insert_with_user_email() FROM PUBLIC;


--
-- Name: FUNCTION tg_user_secrets__insert_with_user(); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.tg_user_secrets__insert_with_user() FROM PUBLIC;


--
-- Name: FUNCTION accept_invitation_to_organization(invitation_id uuid, code text); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.accept_invitation_to_organization(invitation_id uuid, code text) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.accept_invitation_to_organization(invitation_id uuid, code text) TO ilmo_visitor;


--
-- Name: FUNCTION change_password(old_password text, new_password text); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.change_password(old_password text, new_password text) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.change_password(old_password text, new_password text) TO ilmo_visitor;


--
-- Name: FUNCTION check_language(_column jsonb); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.check_language(_column jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.check_language(_column jsonb) TO ilmo_visitor;


--
-- Name: FUNCTION claim_registration_token(event_id uuid, quota_id uuid); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.claim_registration_token(event_id uuid, quota_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.claim_registration_token(event_id uuid, quota_id uuid) TO ilmo_visitor;


--
-- Name: FUNCTION confirm_account_deletion(token text); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.confirm_account_deletion(token text) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.confirm_account_deletion(token text) TO ilmo_visitor;


--
-- Name: TABLE quotas; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.quotas TO ilmo_visitor;


--
-- Name: COLUMN quotas.event_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(event_id) ON TABLE app_public.quotas TO ilmo_visitor;


--
-- Name: COLUMN quotas."position"; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT("position"),UPDATE("position") ON TABLE app_public.quotas TO ilmo_visitor;


--
-- Name: COLUMN quotas.title; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(title),UPDATE(title) ON TABLE app_public.quotas TO ilmo_visitor;


--
-- Name: COLUMN quotas.size; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(size),UPDATE(size) ON TABLE app_public.quotas TO ilmo_visitor;


--
-- Name: FUNCTION create_event_quotas(event_id uuid, quotas app_public.create_event_quotas[]); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.create_event_quotas(event_id uuid, quotas app_public.create_event_quotas[]) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.create_event_quotas(event_id uuid, quotas app_public.create_event_quotas[]) TO ilmo_visitor;


--
-- Name: TABLE organizations; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT ON TABLE app_public.organizations TO ilmo_visitor;


--
-- Name: COLUMN organizations.slug; Type: ACL; Schema: app_public; Owner: -
--

GRANT UPDATE(slug) ON TABLE app_public.organizations TO ilmo_visitor;


--
-- Name: COLUMN organizations.name; Type: ACL; Schema: app_public; Owner: -
--

GRANT UPDATE(name) ON TABLE app_public.organizations TO ilmo_visitor;


--
-- Name: FUNCTION create_organization(slug public.citext, name text); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.create_organization(slug public.citext, name text) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.create_organization(slug public.citext, name text) TO ilmo_visitor;


--
-- Name: TABLE registrations; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.registrations TO ilmo_visitor;


--
-- Name: COLUMN registrations.event_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(event_id) ON TABLE app_public.registrations TO ilmo_visitor;


--
-- Name: COLUMN registrations.quota_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(quota_id) ON TABLE app_public.registrations TO ilmo_visitor;


--
-- Name: COLUMN registrations.first_name; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(first_name),UPDATE(first_name) ON TABLE app_public.registrations TO ilmo_visitor;


--
-- Name: COLUMN registrations.last_name; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(last_name),UPDATE(last_name) ON TABLE app_public.registrations TO ilmo_visitor;


--
-- Name: COLUMN registrations.email; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(email) ON TABLE app_public.registrations TO ilmo_visitor;


--
-- Name: FUNCTION create_registration("registrationToken" text, "eventId" uuid, "quotaId" uuid, "firstName" text, "lastName" text, email public.citext); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.create_registration("registrationToken" text, "eventId" uuid, "quotaId" uuid, "firstName" text, "lastName" text, email public.citext) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.create_registration("registrationToken" text, "eventId" uuid, "quotaId" uuid, "firstName" text, "lastName" text, email public.citext) TO ilmo_visitor;


--
-- Name: FUNCTION current_session_id(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.current_session_id() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.current_session_id() TO ilmo_visitor;


--
-- Name: FUNCTION "current_user"(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public."current_user"() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public."current_user"() TO ilmo_visitor;


--
-- Name: FUNCTION current_user_id(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.current_user_id() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.current_user_id() TO ilmo_visitor;


--
-- Name: FUNCTION current_user_invited_organization_ids(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.current_user_invited_organization_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.current_user_invited_organization_ids() TO ilmo_visitor;


--
-- Name: FUNCTION current_user_is_admin(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.current_user_is_admin() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.current_user_is_admin() TO ilmo_visitor;


--
-- Name: FUNCTION current_user_is_owner_organization_member(owner_organization_id uuid); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.current_user_is_owner_organization_member(owner_organization_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.current_user_is_owner_organization_member(owner_organization_id uuid) TO ilmo_visitor;


--
-- Name: FUNCTION current_user_member_organization_ids(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.current_user_member_organization_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.current_user_member_organization_ids() TO ilmo_visitor;


--
-- Name: FUNCTION delete_organization(organization_id uuid); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.delete_organization(organization_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.delete_organization(organization_id uuid) TO ilmo_visitor;


--
-- Name: FUNCTION delete_registration("updateToken" text); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.delete_registration("updateToken" text) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.delete_registration("updateToken" text) TO ilmo_visitor;


--
-- Name: TABLE events; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.events TO ilmo_visitor;


--
-- Name: COLUMN events.slug; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(slug),UPDATE(slug) ON TABLE app_public.events TO ilmo_visitor;


--
-- Name: COLUMN events.name; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(name),UPDATE(name) ON TABLE app_public.events TO ilmo_visitor;


--
-- Name: COLUMN events.description; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(description),UPDATE(description) ON TABLE app_public.events TO ilmo_visitor;


--
-- Name: COLUMN events.event_start_time; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(event_start_time),UPDATE(event_start_time) ON TABLE app_public.events TO ilmo_visitor;


--
-- Name: COLUMN events.event_end_time; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(event_end_time),UPDATE(event_end_time) ON TABLE app_public.events TO ilmo_visitor;


--
-- Name: COLUMN events.registration_start_time; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(registration_start_time),UPDATE(registration_start_time) ON TABLE app_public.events TO ilmo_visitor;


--
-- Name: COLUMN events.registration_end_time; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(registration_end_time),UPDATE(registration_end_time) ON TABLE app_public.events TO ilmo_visitor;


--
-- Name: COLUMN events.is_highlighted; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(is_highlighted),UPDATE(is_highlighted) ON TABLE app_public.events TO ilmo_visitor;


--
-- Name: COLUMN events.is_draft; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(is_draft),UPDATE(is_draft) ON TABLE app_public.events TO ilmo_visitor;


--
-- Name: COLUMN events.header_image_file; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(header_image_file),UPDATE(header_image_file) ON TABLE app_public.events TO ilmo_visitor;


--
-- Name: COLUMN events.owner_organization_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(owner_organization_id),UPDATE(owner_organization_id) ON TABLE app_public.events TO ilmo_visitor;


--
-- Name: COLUMN events.category_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(category_id),UPDATE(category_id) ON TABLE app_public.events TO ilmo_visitor;


--
-- Name: FUNCTION events_signup_closed(e app_public.events); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.events_signup_closed(e app_public.events) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.events_signup_closed(e app_public.events) TO ilmo_visitor;


--
-- Name: FUNCTION events_signup_open(e app_public.events); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.events_signup_open(e app_public.events) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.events_signup_open(e app_public.events) TO ilmo_visitor;


--
-- Name: FUNCTION events_signup_upcoming(e app_public.events); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.events_signup_upcoming(e app_public.events) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.events_signup_upcoming(e app_public.events) TO ilmo_visitor;


--
-- Name: FUNCTION forgot_password(email public.citext); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.forgot_password(email public.citext) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.forgot_password(email public.citext) TO ilmo_visitor;


--
-- Name: FUNCTION invite_to_organization(organization_id uuid, username public.citext, email public.citext); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.invite_to_organization(organization_id uuid, username public.citext, email public.citext) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.invite_to_organization(organization_id uuid, username public.citext, email public.citext) TO ilmo_visitor;


--
-- Name: FUNCTION languages(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.languages() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.languages() TO ilmo_visitor;


--
-- Name: FUNCTION logout(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.logout() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.logout() TO ilmo_visitor;


--
-- Name: TABLE user_emails; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.user_emails TO ilmo_visitor;


--
-- Name: COLUMN user_emails.email; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(email) ON TABLE app_public.user_emails TO ilmo_visitor;


--
-- Name: FUNCTION make_email_primary(email_id uuid); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.make_email_primary(email_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.make_email_primary(email_id uuid) TO ilmo_visitor;


--
-- Name: FUNCTION organization_for_invitation(invitation_id uuid, code text); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.organization_for_invitation(invitation_id uuid, code text) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.organization_for_invitation(invitation_id uuid, code text) TO ilmo_visitor;


--
-- Name: FUNCTION organizations_current_user_is_owner(org app_public.organizations); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.organizations_current_user_is_owner(org app_public.organizations) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.organizations_current_user_is_owner(org app_public.organizations) TO ilmo_visitor;


--
-- Name: FUNCTION registration_by_update_token("updateToken" text); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.registration_by_update_token("updateToken" text) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.registration_by_update_token("updateToken" text) TO ilmo_visitor;


--
-- Name: FUNCTION registrations_full_name(registration app_public.registrations); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.registrations_full_name(registration app_public.registrations) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.registrations_full_name(registration app_public.registrations) TO ilmo_visitor;


--
-- Name: FUNCTION registrations_is_queued(registration app_public.registrations); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.registrations_is_queued(registration app_public.registrations) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.registrations_is_queued(registration app_public.registrations) TO ilmo_visitor;


--
-- Name: FUNCTION remove_from_organization(organization_id uuid, user_id uuid); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.remove_from_organization(organization_id uuid, user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.remove_from_organization(organization_id uuid, user_id uuid) TO ilmo_visitor;


--
-- Name: FUNCTION request_account_deletion(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.request_account_deletion() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.request_account_deletion() TO ilmo_visitor;


--
-- Name: FUNCTION resend_email_verification_code(email_id uuid); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.resend_email_verification_code(email_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.resend_email_verification_code(email_id uuid) TO ilmo_visitor;


--
-- Name: FUNCTION tg__graphql_subscription(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.tg__graphql_subscription() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.tg__graphql_subscription() TO ilmo_visitor;


--
-- Name: FUNCTION tg_user_emails__forbid_if_verified(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.tg_user_emails__forbid_if_verified() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.tg_user_emails__forbid_if_verified() TO ilmo_visitor;


--
-- Name: FUNCTION tg_user_emails__prevent_delete_last_email(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.tg_user_emails__prevent_delete_last_email() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.tg_user_emails__prevent_delete_last_email() TO ilmo_visitor;


--
-- Name: FUNCTION tg_user_emails__verify_account_on_verified(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.tg_user_emails__verify_account_on_verified() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.tg_user_emails__verify_account_on_verified() TO ilmo_visitor;


--
-- Name: FUNCTION tg_users__deletion_organization_checks_and_actions(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.tg_users__deletion_organization_checks_and_actions() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.tg_users__deletion_organization_checks_and_actions() TO ilmo_visitor;


--
-- Name: FUNCTION transfer_organization_ownership(organization_id uuid, user_id uuid); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.transfer_organization_ownership(organization_id uuid, user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.transfer_organization_ownership(organization_id uuid, user_id uuid) TO ilmo_visitor;


--
-- Name: FUNCTION update_event_quotas(event_id uuid, quotas app_public.update_event_quotas[]); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.update_event_quotas(event_id uuid, quotas app_public.update_event_quotas[]) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.update_event_quotas(event_id uuid, quotas app_public.update_event_quotas[]) TO ilmo_visitor;


--
-- Name: FUNCTION update_registration("updateToken" text, "firstName" text, "lastName" text); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.update_registration("updateToken" text, "firstName" text, "lastName" text) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.update_registration("updateToken" text, "firstName" text, "lastName" text) TO ilmo_visitor;


--
-- Name: FUNCTION users_has_password(u app_public.users); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.users_has_password(u app_public.users) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.users_has_password(u app_public.users) TO ilmo_visitor;


--
-- Name: FUNCTION users_primary_email(u app_public.users); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.users_primary_email(u app_public.users) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.users_primary_email(u app_public.users) TO ilmo_visitor;


--
-- Name: FUNCTION verify_email(user_email_id uuid, token text); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.verify_email(user_email_id uuid, token text) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.verify_email(user_email_id uuid, token text) TO ilmo_visitor;


--
-- Name: TABLE event_categories; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.event_categories TO ilmo_visitor;


--
-- Name: COLUMN event_categories.name; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(name),UPDATE(name) ON TABLE app_public.event_categories TO ilmo_visitor;


--
-- Name: COLUMN event_categories.description; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(description),UPDATE(description) ON TABLE app_public.event_categories TO ilmo_visitor;


--
-- Name: COLUMN event_categories.owner_organization_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(owner_organization_id),UPDATE(owner_organization_id) ON TABLE app_public.event_categories TO ilmo_visitor;


--
-- Name: TABLE event_questions; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.event_questions TO ilmo_visitor;


--
-- Name: COLUMN event_questions.event_id; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(event_id),UPDATE(event_id) ON TABLE app_public.event_questions TO ilmo_visitor;


--
-- Name: COLUMN event_questions.type; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(type),UPDATE(type) ON TABLE app_public.event_questions TO ilmo_visitor;


--
-- Name: COLUMN event_questions.options; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(options),UPDATE(options) ON TABLE app_public.event_questions TO ilmo_visitor;


--
-- Name: TABLE organization_memberships; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT ON TABLE app_public.organization_memberships TO ilmo_visitor;


--
-- Name: TABLE user_authentications; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.user_authentications TO ilmo_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: app_hidden; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE ilmo IN SCHEMA app_hidden REVOKE ALL ON SEQUENCES  FROM ilmo;
ALTER DEFAULT PRIVILEGES FOR ROLE ilmo IN SCHEMA app_hidden GRANT SELECT,USAGE ON SEQUENCES  TO ilmo_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: app_hidden; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE ilmo IN SCHEMA app_hidden REVOKE ALL ON FUNCTIONS  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE ilmo IN SCHEMA app_hidden REVOKE ALL ON FUNCTIONS  FROM ilmo;
ALTER DEFAULT PRIVILEGES FOR ROLE ilmo IN SCHEMA app_hidden GRANT ALL ON FUNCTIONS  TO ilmo_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: app_public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE ilmo IN SCHEMA app_public REVOKE ALL ON SEQUENCES  FROM ilmo;
ALTER DEFAULT PRIVILEGES FOR ROLE ilmo IN SCHEMA app_public GRANT SELECT,USAGE ON SEQUENCES  TO ilmo_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: app_public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE ilmo IN SCHEMA app_public REVOKE ALL ON FUNCTIONS  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE ilmo IN SCHEMA app_public REVOKE ALL ON FUNCTIONS  FROM ilmo;
ALTER DEFAULT PRIVILEGES FOR ROLE ilmo IN SCHEMA app_public GRANT ALL ON FUNCTIONS  TO ilmo_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE ilmo IN SCHEMA public REVOKE ALL ON SEQUENCES  FROM ilmo;
ALTER DEFAULT PRIVILEGES FOR ROLE ilmo IN SCHEMA public GRANT SELECT,USAGE ON SEQUENCES  TO ilmo_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE ilmo IN SCHEMA public REVOKE ALL ON FUNCTIONS  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE ilmo IN SCHEMA public REVOKE ALL ON FUNCTIONS  FROM ilmo;
ALTER DEFAULT PRIVILEGES FOR ROLE ilmo IN SCHEMA public GRANT ALL ON FUNCTIONS  TO ilmo_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: -; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE ilmo REVOKE ALL ON FUNCTIONS  FROM PUBLIC;


--
-- PostgreSQL database dump complete
--

