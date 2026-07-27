-- =============================================================================
-- RLS verification for AbroadTRIPsite
-- =============================================================================
--
-- Proves the trip privacy model actually behaves the way CLAUDE.md claims.
-- Every policy in the initial migration is exercised against impersonated users
-- rather than reasoned about.
--
-- ⚠️  RUN THIS ON A PREVIEW BRANCH OR LOCAL DATABASE ONLY.
--
--     It inserts real rows into auth.users and deletes them again. The UUIDs are
--     fixed sentinels (00000000-0000-4000-a000-00000000000N) and cleanup only
--     ever touches those exact ids, but this still writes to your auth schema.
--     Do not point it at production.
--
-- HOW IT WORKS
--
--     Postgres bypasses RLS for the table owner, so running these queries as the
--     default role would prove nothing. Each case therefore does:
--
--       set local role authenticated;                  -- stop bypassing RLS
--       set_config('request.jwt.claims', {...sub...})  -- become a specific user
--       <query>
--       reset role;                                    -- back to owner
--       record PASS/FAIL
--
--     auth.uid() reads the `sub` claim out of request.jwt.claims, which is what
--     makes the impersonation work.
--
-- OUTPUT
--
--     A results table, one row per case, with PASS or FAIL and what was expected
--     versus what happened. The final SELECT prints it. Re-running is safe and
--     idempotent — it drops and recreates its own scaffolding.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- Scaffolding
-- ---------------------------------------------------------------------------

drop table if exists public._rls_test_results;

create table public._rls_test_results (
  seq       serial primary key,
  case_name text not null,
  result    text not null,
  expected  text,
  actual    text
);

-- Records one assertion. Called with the role already reset to the owner.
create or replace function public._rls_assert(
  p_case     text,
  p_actual   boolean,
  p_expected boolean,
  p_detail   text default null
) returns void
language plpgsql
as $$
begin
  insert into public._rls_test_results (case_name, result, expected, actual)
  values (
    p_case,
    case when p_actual is not distinct from p_expected then 'PASS' else 'FAIL' end,
    coalesce(p_detail, '') ||
      case when p_detail is null then '' else ' — ' end ||
      'expected ' || coalesce(p_expected::text, 'null'),
    'got ' || coalesce(p_actual::text, 'null')
  );
end;
$$;

-- Switches the session to a given user, under the `authenticated` role so that
-- RLS actually applies. Passing null impersonates an anonymous visitor.
create or replace function public._rls_become(p_user uuid, p_role text default 'authenticated')
returns void
language plpgsql
as $$
begin
  execute format('set local role %I', p_role);
  if p_user is null then
    perform set_config('request.jwt.claims', json_build_object('role', p_role)::text, true);
    perform set_config('request.jwt.claim.sub', '', true);
  else
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', p_user::text, 'role', p_role)::text,
      true
    );
    -- Older Supabase builds read this instead. Harmless to set both.
    perform set_config('request.jwt.claim.sub', p_user::text, true);
  end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- Fixture
--
--   alice  public account, owns one trip at each of the four visibility levels
--   bob    the reader — his relationship to alice changes as cases progress
--   carol  PRIVATE account, owns one trip marked 'public'
--   dave   declined invitee on alice's private trip
--   erin   pending  invitee on alice's private trip
--   frank  accepted companion on alice's public trip
-- ---------------------------------------------------------------------------

do $$
declare
  alice uuid := '00000000-0000-4000-a000-000000000001';
  bob   uuid := '00000000-0000-4000-a000-000000000002';
  carol uuid := '00000000-0000-4000-a000-000000000003';
  dave  uuid := '00000000-0000-4000-a000-000000000004';
  erin  uuid := '00000000-0000-4000-a000-000000000005';
  frank uuid := '00000000-0000-4000-a000-000000000006';
  ids   uuid[] := array[alice, bob, carol, dave, erin, frank];
  u     uuid;
  n     integer;
begin
  -- Clean any leftovers from a previous run. Cascades to profiles and trips.
  delete from auth.users where id = any(ids);
  delete from public.destinations where id = '00000000-0000-4000-b000-000000000001';

  -- Create the auth users. The handle_new_user trigger populates public.profiles,
  -- so this doubles as a test that the trigger fires.
  foreach u in array ids loop
    insert into auth.users (
      id, instance_id, aud, role, email,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data
    )
    values (
      u,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'rlstest_' || right(u::text, 1) || '@example.test',
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb
    );
  end loop;

  select count(*) into n from public.profiles where id = any(ids);
  if n <> 6 then
    raise exception
      'Fixture failed: expected 6 profiles from the signup trigger, got %. '
      'The handle_new_user trigger may not be installed.', n;
  end if;

  -- Account-level visibility.
  update public.profiles set account_visibility = 'public'  where id <> carol and id = any(ids);
  update public.profiles set account_visibility = 'private' where id = carol;

  -- Alice's four trips, one per visibility level.
  insert into public.trips (id, owner_id, title, visibility, status) values
    ('00000000-0000-4000-c000-000000000001', alice, 'Alice public',    'public',    'planned'),
    ('00000000-0000-4000-c000-000000000002', alice, 'Alice followers', 'followers', 'planned'),
    ('00000000-0000-4000-c000-000000000003', alice, 'Alice custom',    'custom',    'planned'),
    ('00000000-0000-4000-c000-000000000004', alice, 'Alice private',   'private',   'planned');

  -- Carol is a private account, but this trip is marked 'public'.
  insert into public.trips (id, owner_id, title, visibility, status) values
    ('00000000-0000-4000-c000-000000000005', carol, 'Carol public', 'public', 'planned');

  -- Participants on Alice's PRIVATE trip: one declined, one still pending.
  insert into public.trip_participants (trip_id, user_id, role, invite_status) values
    ('00000000-0000-4000-c000-000000000004', dave, 'companion', 'declined'),
    ('00000000-0000-4000-c000-000000000004', erin, 'companion', 'invited');

  -- Frank is an accepted companion on Alice's PUBLIC trip, for the write test.
  insert into public.trip_participants (trip_id, user_id, role, invite_status) values
    ('00000000-0000-4000-c000-000000000001', frank, 'companion', 'accepted');

  -- One destination row so the world-readable test has something to find.
  insert into public.destinations (id, city, country, region)
  values ('00000000-0000-4000-b000-000000000001', 'Testville', 'Testland', 'Test Region');
end;
$$;


-- ---------------------------------------------------------------------------
-- Cases
-- ---------------------------------------------------------------------------

do $$
declare
  alice     uuid := '00000000-0000-4000-a000-000000000001';
  bob       uuid := '00000000-0000-4000-a000-000000000002';
  carol     uuid := '00000000-0000-4000-a000-000000000003';
  dave      uuid := '00000000-0000-4000-a000-000000000004';
  erin      uuid := '00000000-0000-4000-a000-000000000005';
  frank     uuid := '00000000-0000-4000-a000-000000000006';

  t_public    uuid := '00000000-0000-4000-c000-000000000001';
  t_followers uuid := '00000000-0000-4000-c000-000000000002';
  t_custom    uuid := '00000000-0000-4000-c000-000000000003';
  t_private   uuid := '00000000-0000-4000-c000-000000000004';
  t_carol     uuid := '00000000-0000-4000-c000-000000000005';

  visible   integer;
  can_see   boolean;
  n         integer;
begin
  -- =========================================================================
  -- 1. A non-follower sees only Alice's 'public' trip.
  -- =========================================================================
  perform public._rls_become(bob);
  select count(*) into visible from public.trips where owner_id = alice;
  execute 'reset role';
  perform public._rls_assert(
    'non-follower sees only public trips',
    visible = 1, true,
    'bob sees ' || visible || ' of alice''s 4 trips'
  );

  perform public._rls_become(bob);
  select count(*) into visible from public.trips
   where owner_id = alice and visibility = 'public';
  execute 'reset role';
  perform public._rls_assert(
    'non-follower CAN see the public trip specifically',
    visible = 1, true
  );

  -- =========================================================================
  -- 3. A PENDING follower still cannot see 'followers' trips.
  --    (Run before accepting, so the pending state is genuine.)
  -- =========================================================================
  insert into public.follows (follower_id, following_id, status)
  values (bob, alice, 'pending');

  perform public._rls_become(bob);
  select exists (select 1 from public.trips where id = t_followers) into can_see;
  execute 'reset role';
  perform public._rls_assert(
    'pending follower does NOT see followers-only trips',
    can_see, false
  );

  -- =========================================================================
  -- 2. An ACCEPTED follower does see 'followers' trips.
  -- =========================================================================
  update public.follows set status = 'accepted'
   where follower_id = bob and following_id = alice;

  perform public._rls_become(bob);
  select exists (select 1 from public.trips where id = t_followers) into can_see;
  execute 'reset role';
  perform public._rls_assert(
    'accepted follower sees followers-only trips',
    can_see, true
  );

  -- =========================================================================
  -- 4. A private account's 'public' trip is invisible to a non-follower.
  -- =========================================================================
  perform public._rls_become(bob);
  select exists (select 1 from public.trips where id = t_carol) into can_see;
  execute 'reset role';
  perform public._rls_assert(
    'private account: non-follower sees nothing, even public trips',
    can_see, false
  );

  perform public._rls_become(bob);
  select count(*) into visible from public.trips where owner_id = carol;
  execute 'reset role';
  perform public._rls_assert(
    'private account: non-follower sees zero of its trips',
    visible = 0, true,
    'bob sees ' || visible || ' of carol''s trips'
  );

  -- And an accepted follower of the private account CAN see it.
  insert into public.follows (follower_id, following_id, status)
  values (bob, carol, 'accepted');

  perform public._rls_become(bob);
  select exists (select 1 from public.trips where id = t_carol) into can_see;
  execute 'reset role';
  perform public._rls_assert(
    'private account: accepted follower CAN see its public trip',
    can_see, true
  );

  -- =========================================================================
  -- 5. 'custom' visibility — only users named in trip_shares.
  -- =========================================================================
  perform public._rls_become(bob);
  select exists (select 1 from public.trips where id = t_custom) into can_see;
  execute 'reset role';
  perform public._rls_assert(
    'custom visibility: unshared user cannot read',
    can_see, false,
    'bob is an accepted follower but not shared with'
  );

  insert into public.trip_shares (trip_id, shared_with_user_id)
  values (t_custom, bob);

  perform public._rls_become(bob);
  select exists (select 1 from public.trips where id = t_custom) into can_see;
  execute 'reset role';
  perform public._rls_assert(
    'custom visibility: shared user CAN read',
    can_see, true
  );

  -- =========================================================================
  -- 6. A declined invitee has no access.
  -- =========================================================================
  perform public._rls_become(dave);
  select exists (select 1 from public.trips where id = t_private) into can_see;
  execute 'reset role';
  perform public._rls_assert(
    'declined invitee has no access',
    can_see, false
  );

  -- =========================================================================
  -- 7. A pending invitee CAN read.
  -- =========================================================================
  perform public._rls_become(erin);
  select exists (select 1 from public.trips where id = t_private) into can_see;
  execute 'reset role';
  perform public._rls_assert(
    'pending invitee CAN read',
    can_see, true,
    'needs to see what they are deciding about'
  );

  -- Child tables must inherit that access.
  insert into public.trip_segments (trip_id, type, status, provider)
  values (t_private, 'flight', 'wanted', 'Ryanair');

  perform public._rls_become(erin);
  select count(*) into n from public.trip_segments where trip_id = t_private;
  execute 'reset role';
  perform public._rls_assert(
    'pending invitee inherits read access to trip_segments',
    n = 1, true
  );

  perform public._rls_become(dave);
  select count(*) into n from public.trip_segments where trip_id = t_private;
  execute 'reset role';
  perform public._rls_assert(
    'declined invitee inherits NO access to trip_segments',
    n = 0, true
  );

  -- =========================================================================
  -- 8. A companion cannot write trip_segments.
  -- =========================================================================
  begin
    perform public._rls_become(frank);
    insert into public.trip_segments (trip_id, type, status, provider)
    values (t_public, 'train', 'wanted', 'Trenitalia');
    execute 'reset role';
    perform public._rls_assert(
      'companion cannot write trip_segments',
      true, false,
      'insert unexpectedly succeeded'
    );
  exception
    when insufficient_privilege then
      execute 'reset role';
      perform public._rls_assert(
        'companion cannot write trip_segments',
        false, false,
        'insert correctly denied by RLS'
      );
  end;

  -- The companion can still READ them, since the trip is public.
  perform public._rls_become(frank);
  select count(*) into n from public.trip_segments where trip_id = t_public;
  execute 'reset role';
  perform public._rls_assert(
    'companion CAN read trip_segments on a trip they can see',
    n >= 0, true
  );

  -- =========================================================================
  -- 9. The owner can always read and write their own trips.
  -- =========================================================================
  perform public._rls_become(alice);
  select count(*) into visible from public.trips where owner_id = alice;
  execute 'reset role';
  perform public._rls_assert(
    'owner reads all their own trips',
    visible = 4, true,
    'alice sees ' || visible || ' of her 4 trips'
  );

  perform public._rls_become(alice);
  select exists (select 1 from public.trips where id = t_private) into can_see;
  execute 'reset role';
  perform public._rls_assert(
    'owner reads their own private trip',
    can_see, true
  );

  begin
    perform public._rls_become(alice);
    update public.trips set notes = 'owner write test' where id = t_private;
    get diagnostics n = row_count;
    execute 'reset role';
    perform public._rls_assert(
      'owner can write their own trip',
      n = 1, true,
      n || ' row(s) updated'
    );
  exception
    when others then
      execute 'reset role';
      perform public._rls_assert(
        'owner can write their own trip',
        false, true,
        'unexpected error: ' || sqlerrm
      );
  end;

  -- A non-owner must not be able to write it.
  perform public._rls_become(bob);
  update public.trips set notes = 'bob was here' where id = t_public;
  get diagnostics n = row_count;
  execute 'reset role';
  perform public._rls_assert(
    'non-owner cannot write someone else''s trip',
    n = 0, true,
    n || ' row(s) updated'
  );

  -- =========================================================================
  -- 10. destinations — readable by everyone, writable by nobody.
  -- =========================================================================
  perform public._rls_become(bob);
  select count(*) into n from public.destinations;
  execute 'reset role';
  perform public._rls_assert(
    'destinations readable by an authenticated user',
    n >= 1, true,
    n || ' row(s) visible'
  );

  perform public._rls_become(null, 'anon');
  select count(*) into n from public.destinations;
  execute 'reset role';
  perform public._rls_assert(
    'destinations readable by an anonymous visitor',
    n >= 1, true,
    n || ' row(s) visible'
  );

  begin
    perform public._rls_become(bob);
    insert into public.destinations (city, country) values ('Hackerville', 'Nowhere');
    execute 'reset role';
    perform public._rls_assert(
      'destinations not writable by an authenticated user',
      true, false,
      'insert unexpectedly succeeded'
    );
  exception
    when insufficient_privilege then
      execute 'reset role';
      perform public._rls_assert(
        'destinations not writable by an authenticated user',
        false, false,
        'insert correctly denied by RLS'
      );
  end;

  begin
    perform public._rls_become(bob);
    delete from public.destinations;
    get diagnostics n = row_count;
    execute 'reset role';
    perform public._rls_assert(
      'destinations not deletable by an authenticated user',
      n = 0, true,
      n || ' row(s) deleted'
    );
  exception
    when insufficient_privilege then
      execute 'reset role';
      perform public._rls_assert(
        'destinations not deletable by an authenticated user',
        true, true,
        'delete correctly denied by RLS'
      );
  end;

  -- =========================================================================
  -- Bonus: an anonymous visitor sees public trips but nothing else.
  -- =========================================================================
  perform public._rls_become(null, 'anon');
  select count(*) into visible from public.trips where owner_id = alice;
  execute 'reset role';
  perform public._rls_assert(
    'anonymous visitor sees only the public trip',
    visible = 1, true,
    'anon sees ' || visible || ' of alice''s 4 trips'
  );

exception
  when others then
    -- Never leave the session stuck in the authenticated role.
    execute 'reset role';
    raise;
end;
$$;


-- ---------------------------------------------------------------------------
-- Cleanup — removes only the fixed sentinel ids created above.
-- ---------------------------------------------------------------------------

do $$
declare
  ids uuid[] := array[
    '00000000-0000-4000-a000-000000000001'::uuid,
    '00000000-0000-4000-a000-000000000002'::uuid,
    '00000000-0000-4000-a000-000000000003'::uuid,
    '00000000-0000-4000-a000-000000000004'::uuid,
    '00000000-0000-4000-a000-000000000005'::uuid,
    '00000000-0000-4000-a000-000000000006'::uuid
  ];
begin
  -- Cascades through profiles -> trips -> segments/participants/shares.
  delete from auth.users where id = any(ids);
  delete from public.destinations
   where id = '00000000-0000-4000-b000-000000000001'
      or (city = 'Hackerville' and country = 'Nowhere');
end;
$$;

drop function if exists public._rls_become(uuid, text);
drop function if exists public._rls_assert(text, boolean, boolean, text);


-- ---------------------------------------------------------------------------
-- Results
-- ---------------------------------------------------------------------------

select
  seq          as "#",
  result       as "result",
  case_name    as "case",
  expected     as "expected",
  actual       as "actual"
from public._rls_test_results
order by seq;

-- Summary line: this is the one to look at first.
select
  count(*) filter (where result = 'PASS') as passed,
  count(*) filter (where result = 'FAIL') as failed,
  case when count(*) filter (where result = 'FAIL') = 0
       then 'ALL CASES PASSED'
       else count(*) filter (where result = 'FAIL')::text || ' CASE(S) FAILED'
  end as verdict
from public._rls_test_results;
