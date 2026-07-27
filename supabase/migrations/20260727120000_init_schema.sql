-- =============================================================================
-- AbroadTRIPsite — initial schema
-- =============================================================================
--
-- Sections:
--   1. Enums
--   2. Tables
--   3. Indexes
--   4. Access-control helper functions
--   5. RLS policies
--   6. New-user trigger
--
-- Two project settings shape everything below:
--
--   * "Automatically expose new tables" is ON — every table here is reachable
--     through the Data API the moment it exists.
--   * "Automatic RLS" is ON — RLS is enabled on new tables by default.
--
-- Together these mean a table without policies is *exposed but returns zero
-- rows*. It does not raise an error. A missing policy therefore looks exactly
-- like "no data yet", so every table below gets explicit policies.
--
-- No GRANT statements: Supabase manages role grants, and RLS is the access
-- control mechanism.
-- =============================================================================


-- =============================================================================
-- 1. ENUMS
-- =============================================================================

create type public.account_visibility as enum ('public', 'private');
create type public.trip_status         as enum ('idea', 'planned', 'booked', 'completed');
create type public.trip_visibility     as enum ('public', 'followers', 'custom', 'private');
create type public.segment_type        as enum ('flight', 'train', 'bus', 'stay', 'reservation');
create type public.segment_status      as enum ('wanted', 'booked');
create type public.participant_role    as enum ('owner', 'companion');
create type public.invite_status       as enum ('invited', 'accepted', 'declined');
create type public.follow_status       as enum ('pending', 'accepted');


-- =============================================================================
-- 2. TABLES
-- =============================================================================

-- ---------------------------------------------------------------------------
-- profiles — one row per auth user, created automatically by the trigger in §6.
-- ---------------------------------------------------------------------------
create table public.profiles (
  id                 uuid primary key references auth.users (id) on delete cascade,
  username           text not null unique,
  display_name       text,
  avatar_url         text,
  home_school        text,
  study_city         text,
  study_country      text,
  semester_start     date,
  semester_end       date,
  account_visibility public.account_visibility not null default 'public',
  created_at         timestamptz not null default now(),

  -- Usernames appear in URLs, so keep them lowercase and URL-safe.
  constraint profiles_username_format check (username ~ '^[a-z0-9_]{3,30}$'),
  constraint profiles_semester_order check (
    semester_start is null
    or semester_end is null
    or semester_end >= semester_start
  )
);

comment on table public.profiles is
  'Public-facing user profile. One row per auth.users row, created by the on_auth_user_created trigger.';
comment on column public.profiles.account_visibility is
  'Account-level default. A private account''s trips are only ever visible to accepted followers, even trips marked visibility = public.';

-- ---------------------------------------------------------------------------
-- trips — the central object. Every read of a trip resolves through §4/§5.
-- ---------------------------------------------------------------------------
create table public.trips (
  id                  uuid primary key default gen_random_uuid(),
  owner_id            uuid not null references public.profiles (id) on delete cascade,
  title               text not null,
  destination_city    text,
  destination_country text,
  latitude            numeric(9, 6),
  longitude           numeric(9, 6),
  start_date          date,
  end_date            date,
  status              public.trip_status not null default 'idea',
  visibility          public.trip_visibility not null default 'private',
  notes               text,
  rating              smallint,
  created_at          timestamptz not null default now(),

  constraint trips_rating_range check (rating is null or rating between 1 and 5),
  constraint trips_date_order check (
    start_date is null or end_date is null or end_date >= start_date
  ),
  constraint trips_latitude_range check (latitude is null or latitude between -90 and 90),
  constraint trips_longitude_range check (longitude is null or longitude between -180 and 180)
);

comment on column public.trips.visibility is
  'Who may read this trip. Resolution order is owner > participant > visibility. See public.can_read_trip().';
comment on column public.trips.rating is
  'Set after the trip is completed. 1-5.';

-- ---------------------------------------------------------------------------
-- trip_segments — the bookable pieces of a trip. Read access inherits from the
-- parent trip; writes are owner-only.
-- ---------------------------------------------------------------------------
create table public.trip_segments (
  id               uuid primary key default gen_random_uuid(),
  trip_id          uuid not null references public.trips (id) on delete cascade,
  type             public.segment_type not null,
  status           public.segment_status not null default 'wanted',
  provider         text,
  confirmation_ref text,
  starts_at        timestamptz,
  ends_at          timestamptz,
  cost_cents       integer,
  currency         text not null default 'EUR',
  details          jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now(),

  constraint trip_segments_cost_non_negative check (cost_cents is null or cost_cents >= 0),
  constraint trip_segments_time_order check (
    starts_at is null or ends_at is null or ends_at >= starts_at
  ),
  constraint trip_segments_currency_format check (currency ~ '^[A-Z]{3}$')
);

comment on column public.trip_segments.provider is
  'External booking provider, e.g. "Ryanair", "Hostelworld". We link out; we never book.';
comment on column public.trip_segments.details is
  'Unstructured provider-specific extras. Do not put anything security-relevant here — it is returned verbatim to any reader of the parent trip.';

-- ---------------------------------------------------------------------------
-- trip_participants — companions on a trip.
-- ---------------------------------------------------------------------------
create table public.trip_participants (
  trip_id       uuid not null references public.trips (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  role          public.participant_role not null default 'companion',
  invite_status public.invite_status not null default 'invited',
  created_at    timestamptz not null default now(),

  primary key (trip_id, user_id)
);

comment on table public.trip_participants is
  'Companions on a trip. A row with invite_status in (invited, accepted) grants read access, so an invitee can see what they were invited to before deciding. Declining revokes that access.';

-- ---------------------------------------------------------------------------
-- trip_shares — explicit per-user grants, used when visibility = 'custom'.
-- ---------------------------------------------------------------------------
create table public.trip_shares (
  trip_id             uuid not null references public.trips (id) on delete cascade,
  shared_with_user_id uuid not null references public.profiles (id) on delete cascade,
  created_at          timestamptz not null default now(),

  primary key (trip_id, shared_with_user_id)
);

comment on table public.trip_shares is
  'Explicit per-user read grants for trips with visibility = ''custom''.';

-- ---------------------------------------------------------------------------
-- recommendations — post-trip notes. Read access inherits from the parent trip.
-- ---------------------------------------------------------------------------
create table public.recommendations (
  id         uuid primary key default gen_random_uuid(),
  trip_id    uuid not null references public.trips (id) on delete cascade,
  place_name text not null,
  category   text,
  rating     smallint,
  note       text,
  latitude   numeric(9, 6),
  longitude  numeric(9, 6),
  created_at timestamptz not null default now(),

  constraint recommendations_rating_range check (rating is null or rating between 1 and 5),
  constraint recommendations_latitude_range check (latitude is null or latitude between -90 and 90),
  constraint recommendations_longitude_range check (longitude is null or longitude between -180 and 180)
);

-- ---------------------------------------------------------------------------
-- follows — the social graph. 'pending' exists so private accounts can approve.
-- ---------------------------------------------------------------------------
create table public.follows (
  follower_id  uuid not null references public.profiles (id) on delete cascade,
  following_id uuid not null references public.profiles (id) on delete cascade,
  status       public.follow_status not null default 'pending',
  created_at   timestamptz not null default now(),

  primary key (follower_id, following_id),
  constraint follows_no_self_follow check (follower_id <> following_id)
);

comment on table public.follows is
  'Only status = ''accepted'' grants any read access. A pending follow grants nothing.';

-- ---------------------------------------------------------------------------
-- destinations — seeded reference data. World-readable, written by nobody.
-- ---------------------------------------------------------------------------
create table public.destinations (
  id        uuid primary key default gen_random_uuid(),
  city      text not null,
  country   text not null,
  latitude  numeric(9, 6),
  longitude numeric(9, 6),
  region    text,

  constraint destinations_city_country_unique unique (city, country),
  constraint destinations_latitude_range check (latitude is null or latitude between -90 and 90),
  constraint destinations_longitude_range check (longitude is null or longitude between -180 and 180)
);

comment on table public.destinations is
  'Reference data seeded by us. Deliberately has no INSERT/UPDATE/DELETE policy, so it is read-only through the Data API.';


-- =============================================================================
-- 3. INDEXES
--
-- Primary keys are indexed automatically. These cover the foreign keys that RLS
-- policies dereference on every row — without them, policy evaluation degrades
-- into a sequential scan per row as tables grow.
-- =============================================================================

create index trips_owner_id_idx            on public.trips (owner_id);
create index trips_owner_start_date_idx    on public.trips (owner_id, start_date);
create index trips_visibility_idx          on public.trips (visibility) where visibility = 'public';
create index trip_segments_trip_id_idx     on public.trip_segments (trip_id);
create index trip_participants_user_id_idx on public.trip_participants (user_id);
create index trip_shares_user_id_idx       on public.trip_shares (shared_with_user_id);
create index recommendations_trip_id_idx   on public.recommendations (trip_id);
create index follows_following_status_idx  on public.follows (following_id, status);
create index follows_follower_status_idx   on public.follows (follower_id, status);
create index destinations_country_city_idx on public.destinations (country, city);


-- =============================================================================
-- 4. ACCESS-CONTROL HELPER FUNCTIONS
--
-- WHY THESE EXIST — do not inline them back into the policies.
--
-- The natural way to write the trips read policy is to consult
-- trip_participants; the natural way to write the trip_participants read policy
-- is to consult trips. Postgres evaluates one policy inside the other and errors
-- with "infinite recursion detected in policy for relation".
--
-- These functions break the cycle. They are SECURITY DEFINER and owned by the
-- migration role, which owns the tables, so their internal reads bypass RLS
-- entirely. Nothing recurses. This is the standard Supabase pattern.
--
-- Each is STABLE (evaluated once per row, cacheable within a statement) and
-- pinned to `search_path = ''` with fully-qualified table names, so a caller who
-- controls search_path cannot redirect them at a lookalike table.
-- =============================================================================

-- Does `_follower` have an ACCEPTED follow of `_following`? Pending never counts.
create or replace function public.is_accepted_follower(_follower uuid, _following uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.follows f
    where f.follower_id = _follower
      and f.following_id = _following
      and f.status = 'accepted'
  );
$$;

-- Is this account private? Drives the "private account clamp" in can_read_trip.
create or replace function public.account_is_private(_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = _user_id
      and p.account_visibility = 'private'
  );
$$;

-- Is the caller an active participant on this trip?
--
-- 'invited' counts: an invitee must be able to see the trip in order to decide
-- whether to accept. 'declined' does not: turning an invitation down revokes the
-- access that the invitation granted.
create or replace function public.is_trip_participant(_trip_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.trip_participants tp
    where tp.trip_id = _trip_id
      and tp.user_id = (select auth.uid())
      and tp.invite_status in ('invited', 'accepted')
  );
$$;

-- Has the owner explicitly shared this trip with the caller? (visibility = 'custom')
create or replace function public.is_trip_shared_with_me(_trip_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.trip_shares ts
    where ts.trip_id = _trip_id
      and ts.shared_with_user_id = (select auth.uid())
  );
$$;

-- Does the caller own this trip? Used by every child-table write policy.
create or replace function public.is_trip_owner(_trip_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.trips t
    where t.id = _trip_id
      and t.owner_id = (select auth.uid())
  );
$$;

-- =============================================================================
-- THE trip read rule. This is the single definition — everything else delegates.
--
-- It takes the row's columns rather than an id, so the `trips` SELECT policy can
-- call it with the row it already has. No lookup, no second definition to keep
-- in sync.
--
-- Deliberately NOT security definer: it touches no tables directly. Every table
-- read happens inside the security-definer helpers it calls, which is what keeps
-- the trips <-> trip_participants recursion from forming. Leaving this one as a
-- plain function keeps the privilege surface as small as possible.
-- =============================================================================
create or replace function public.can_read_trip_row(
  _trip_id    uuid,
  _owner_id   uuid,
  _visibility public.trip_visibility
)
returns boolean
language sql
stable
set search_path = ''
as $$
  select
    -- The owner always reads their own trips.
    _owner_id = (select auth.uid())

    -- Active participants always read. Declined invitees do not.
    or public.is_trip_participant(_trip_id)

    -- Otherwise fall through to the trip's visibility setting.
    or case _visibility
         when 'public' then
           -- A private account's PUBLIC trips are still followers-only.
           (not public.account_is_private(_owner_id))
           or public.is_accepted_follower((select auth.uid()), _owner_id)
         when 'followers' then
           public.is_accepted_follower((select auth.uid()), _owner_id)
         when 'custom' then
           -- An explicit share outranks the account-level default: the owner
           -- named this person deliberately.
           public.is_trip_shared_with_me(_trip_id)
         when 'private' then
           false
       end;
$$;

-- Thin id-based wrapper over can_read_trip_row, for callers that have only a
-- trip_id — namely the trip_segments and recommendations policies.
--
-- This one IS security definer, because it reads public.trips directly and must
-- bypass RLS to do so. Without that, evaluating a child table's policy would
-- re-enter the trips policy and recurse.
--
-- coalesce guards the no-such-trip case: a bare select returns NULL for a
-- missing row, and NULL in a policy is indistinguishable from false — but being
-- explicit costs nothing and documents the intent.
create or replace function public.can_read_trip(_trip_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select public.can_read_trip_row(t.id, t.owner_id, t.visibility)
      from public.trips t
      where t.id = _trip_id
    ),
    false
  );
$$;


-- =============================================================================
-- 5. RLS POLICIES
--
-- "Automatic RLS" already enabled RLS on these tables; the explicit ENABLE
-- statements make that a property of this file rather than of a dashboard
-- setting, so `supabase db reset` reproduces production exactly.
--
-- auth.uid() is wrapped as (select auth.uid()) throughout. Postgres then hoists
-- it into a one-time InitPlan instead of re-evaluating it per row — a large win
-- on list queries and the documented Supabase recommendation.
--
-- For an anonymous caller auth.uid() is NULL, so every `= (select auth.uid())`
-- comparison yields NULL and the row is filtered out. Anonymous access is
-- therefore limited to the policies that explicitly allow it.
-- =============================================================================

alter table public.profiles          enable row level security;
alter table public.trips             enable row level security;
alter table public.trip_segments     enable row level security;
alter table public.trip_participants enable row level security;
alter table public.trip_shares       enable row level security;
alter table public.recommendations   enable row level security;
alter table public.follows           enable row level security;
alter table public.destinations      enable row level security;


-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------

-- READ: own profile always; public accounts readable by anyone (including
-- signed-out visitors); private accounts only by accepted followers.
create policy "profiles are readable by self, publicly, or by accepted followers"
  on public.profiles for select
  to anon, authenticated
  using (
    id = (select auth.uid())
    or account_visibility = 'public'
    or public.is_accepted_follower((select auth.uid()), id)
  );

-- WRITE: strictly your own row. The trigger in §6 normally creates it, but an
-- INSERT policy is still required for the recovery path where it is missing.
create policy "users insert their own profile"
  on public.profiles for insert
  to authenticated
  with check (id = (select auth.uid()));

create policy "users update their own profile"
  on public.profiles for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- No DELETE policy: profiles disappear via cascade when the auth.users row is
-- deleted. Nobody deletes a profile through the API.


-- ---------------------------------------------------------------------------
-- trips — the core privacy rule
-- ---------------------------------------------------------------------------

-- READ: delegates to the one definition of the rule, passing this row's own
-- columns. No lookup against `trips` happens here, so there is nothing to keep
-- in sync and no recursion.
--
-- The resolution order — owner, then participant, then visibility — lives in
-- public.can_read_trip_row(). Change it there and every table that inherits trip
-- read access follows automatically.
create policy "trip reads resolve owner, then participant, then visibility"
  on public.trips for select
  to anon, authenticated
  using (public.can_read_trip_row(id, owner_id, visibility));

-- WRITE: owner only. `with check` on INSERT stops a user creating a trip owned
-- by somebody else; on UPDATE it stops them reassigning ownership away.
create policy "users create their own trips"
  on public.trips for insert
  to authenticated
  with check (owner_id = (select auth.uid()));

create policy "owners update their own trips"
  on public.trips for update
  to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy "owners delete their own trips"
  on public.trips for delete
  to authenticated
  using (owner_id = (select auth.uid()));


-- ---------------------------------------------------------------------------
-- trip_segments — read inherits from the parent trip, writes are owner-only
-- ---------------------------------------------------------------------------

create policy "segments are readable by anyone who can read the trip"
  on public.trip_segments for select
  to anon, authenticated
  using (public.can_read_trip(trip_id));

-- Companions cannot edit segments yet. Widening this later is a one-line change;
-- narrowing it after real data exists is not.
create policy "trip owners insert segments"
  on public.trip_segments for insert
  to authenticated
  with check (public.is_trip_owner(trip_id));

create policy "trip owners update segments"
  on public.trip_segments for update
  to authenticated
  using (public.is_trip_owner(trip_id))
  with check (public.is_trip_owner(trip_id));

create policy "trip owners delete segments"
  on public.trip_segments for delete
  to authenticated
  using (public.is_trip_owner(trip_id));


-- ---------------------------------------------------------------------------
-- recommendations — same inheritance as trip_segments
-- ---------------------------------------------------------------------------

create policy "recommendations are readable by anyone who can read the trip"
  on public.recommendations for select
  to anon, authenticated
  using (public.can_read_trip(trip_id));

create policy "trip owners insert recommendations"
  on public.recommendations for insert
  to authenticated
  with check (public.is_trip_owner(trip_id));

create policy "trip owners update recommendations"
  on public.recommendations for update
  to authenticated
  using (public.is_trip_owner(trip_id))
  with check (public.is_trip_owner(trip_id));

create policy "trip owners delete recommendations"
  on public.recommendations for delete
  to authenticated
  using (public.is_trip_owner(trip_id));


-- ---------------------------------------------------------------------------
-- trip_participants
-- ---------------------------------------------------------------------------

-- READ: anyone who can read the trip sees its roster. The `user_id` clause is
-- belt-and-braces so an invitee can always find their own invitation.
create policy "participants are visible to trip readers and to the invitee"
  on public.trip_participants for select
  to anon, authenticated
  using (
    user_id = (select auth.uid())
    or public.can_read_trip(trip_id)
  );

create policy "trip owners invite participants"
  on public.trip_participants for insert
  to authenticated
  with check (public.is_trip_owner(trip_id));

-- UPDATE: the owner manages the roster; the invitee may only answer a pending
-- invitation, and only once.
--
-- This encodes a ONE-WAY transition. On UPDATE, Postgres evaluates `using`
-- against the OLD row and `with check` against the NEW row, so:
--
--   using       — the participant may only act on a row still sitting at
--                 'invited'. Once it is 'accepted' or 'declined', the row is
--                 invisible to them and the UPDATE matches zero rows.
--   with check  — and they may only move it to a terminal state.
--
-- Without the invite_status clause in `using`, a declined invitee still owns
-- their row and could set invite_status back to 'accepted', walking straight
-- back into a trip they were removed from. That would silently defeat the
-- is_trip_participant() check.
--
-- Re-inviting someone who declined is therefore the OWNER's action — they pass
-- is_trip_owner() and can move the row to any state.
--
-- Side effect worth knowing: because `with check` requires a terminal state, a
-- pending invitee cannot update any OTHER column while leaving invite_status at
-- 'invited' — that attempt raises a policy violation. Participants have no
-- reason to edit their own row except to answer, so this is intended.
--
-- Note: an invitee can still set role = 'owner' on their own row as they accept.
-- That grants nothing — trip ownership is public.trips.owner_id, and every write
-- policy checks that column, not this one. This column is display metadata.
create policy "owners and the invitee update a participant row"
  on public.trip_participants for update
  to authenticated
  using (
    public.is_trip_owner(trip_id)
    -- a participant may only act on a row that is still pending
    or (user_id = (select auth.uid()) and invite_status = 'invited')
  )
  with check (
    public.is_trip_owner(trip_id)
    -- and may only move it to a terminal state
    or (user_id = (select auth.uid()) and invite_status in ('accepted', 'declined'))
  );

-- DELETE: the owner removes a companion, or a companion leaves.
create policy "owners remove participants and companions leave"
  on public.trip_participants for delete
  to authenticated
  using (
    user_id = (select auth.uid())
    or public.is_trip_owner(trip_id)
  );


-- ---------------------------------------------------------------------------
-- trip_shares
-- ---------------------------------------------------------------------------

-- READ: the owner sees the whole share list; a shared-with user sees only the
-- row naming them, never who else the trip was shared with.
create policy "share rows are visible to the trip owner and the named user"
  on public.trip_shares for select
  to authenticated
  using (
    shared_with_user_id = (select auth.uid())
    or public.is_trip_owner(trip_id)
  );

create policy "trip owners create shares"
  on public.trip_shares for insert
  to authenticated
  with check (public.is_trip_owner(trip_id));

create policy "trip owners revoke shares"
  on public.trip_shares for delete
  to authenticated
  using (public.is_trip_owner(trip_id));

-- No UPDATE policy: a share row is only (trip_id, shared_with_user_id), both of
-- which are the primary key. Changing one means deleting and re-creating.


-- ---------------------------------------------------------------------------
-- follows
-- ---------------------------------------------------------------------------

-- READ: only the two parties to the relationship. This deliberately keeps
-- follower/following lists private for now — surfacing "who follows this public
-- account" is a product decision, not an accident of the schema.
create policy "follow rows are visible to both parties"
  on public.follows for select
  to authenticated
  using (
    follower_id = (select auth.uid())
    or following_id = (select auth.uid())
  );

-- You may only create a follow in which you are the follower.
create policy "users create their own follows"
  on public.follows for insert
  to authenticated
  with check (follower_id = (select auth.uid()));

-- UPDATE: only the person BEING followed can change status, i.e. approve a
-- pending request. A follower cannot self-approve — that is the whole point of
-- 'pending', and it is what protects private accounts.
create policy "the followed user approves or rejects a follow"
  on public.follows for update
  to authenticated
  using (following_id = (select auth.uid()))
  with check (following_id = (select auth.uid()));

-- DELETE: unfollow (follower) or remove a follower (followed).
create policy "either party removes a follow"
  on public.follows for delete
  to authenticated
  using (
    follower_id = (select auth.uid())
    or following_id = (select auth.uid())
  );


-- ---------------------------------------------------------------------------
-- destinations
-- ---------------------------------------------------------------------------

-- World-readable reference data — needed by the signed-out landing page too.
create policy "destinations are readable by everyone"
  on public.destinations for select
  to anon, authenticated
  using (true);

-- Intentionally NO insert/update/delete policies. With RLS enabled and no
-- permissive policy for those commands, every write through the Data API is
-- denied. Seed this table from a migration.


-- =============================================================================
-- 6. NEW-USER TRIGGER
--
-- Every part of the app assumes profiles.id exists for the signed-in user. This
-- creates that row at signup so there is never a window where a session has no
-- profile.
--
-- The username here is PROVISIONAL — derived from the email local part. A real
-- username-picking flow is a product feature; until it exists, users can change
-- it via the profiles UPDATE policy.
-- =============================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  base_username  text;
  final_username text;
  attempt        integer := 0;
begin
  -- Strip the email down to the characters profiles_username_format allows.
  base_username := regexp_replace(
    lower(split_part(coalesce(new.email, ''), '@', 1)),
    '[^a-z0-9_]', '', 'g'
  );

  -- Pad short or empty results so the >= 3 character constraint always holds.
  if length(base_username) < 3 then
    base_username := 'traveler' || base_username;
  end if;

  -- Leave headroom for the numeric suffix within the 30 character limit.
  base_username := left(base_username, 24);
  final_username := base_username;

  -- Take the first free username. The loop handles the common case; the
  -- exception handler below handles two signups racing for the same one.
  while exists (select 1 from public.profiles p where p.username = final_username) loop
    attempt := attempt + 1;
    final_username := base_username || attempt::text;
  end loop;

  begin
    insert into public.profiles (id, username, display_name)
    values (
      new.id,
      final_username,
      nullif(new.raw_user_meta_data ->> 'full_name', '')
    );
  exception
    when unique_violation then
      -- Lost the race. Fall back to a username that cannot collide.
      insert into public.profiles (id, username, display_name)
      values (
        new.id,
        left(base_username, 22) || substr(replace(new.id::text, '-', ''), 1, 8),
        nullif(new.raw_user_meta_data ->> 'full_name', '')
      );
  end;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();
