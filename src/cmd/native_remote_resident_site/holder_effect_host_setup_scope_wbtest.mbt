///|
/// Arithmetic/lifecycle fixtures only. These quantities are not an adopted
/// Host layout profile and no physical Account/Source/Provider is opened.
fn host_setup_test_profile() -> HolderEffectHostSetupProfile {
  {
    read_ceiling: 32,
    setup_retained_bytes: 120L,
    current_retained_bytes: 30L,
    caller_retained_bytes: 30L,
    execution_bytes: 20L,
    string_bytes: 2L,
    utf16_unit_bytes: 2L,
    array_bytes: 2L,
    array_slot_bytes: 2L,
    tuple_bytes: 2L,
    retained_controls_bytes: 10L,
  }
}

///|
fn host_setup_test_site(max_operations : Int) -> @site.ExecutionSite {
  @site.create_site("test", 1, "runtime", max_operations, 1, 150L, 40L).unwrap()
}

///|
test "original control text arithmetic includes derived URL and retained binding values" {
  let profile = host_setup_test_profile()
  // Independent UTF-16 lengths: derived URL47 + Site key1 twice + authority1
  // + runtime1 = 51. Five string headers2 plus 51 units2 = 112.
  assert_eq(
    holder_effect_host_control_text_extent(
      profile, "https://x/outbound/observations", "s", "a", "r",
    ),
    Some(112L),
  )
  // A surrogate pair is two UTF-16 units; no NFC/value normalization is applied.
  assert_eq(
    holder_effect_host_control_text_extent(
      profile, "https://x/outbound/observations", "😀", "a", "r",
    ),
    Some(116L),
  )
  assert_true(
    holder_effect_host_control_text_extent(
      profile, "http://x/outbound/observations", "s", "a", "r",
    )
    is None,
  )
}

///|
test "original control text rejects insufficient setup budget" {
  let profile = host_setup_test_profile()
  // Controls10 + text112 + caller remainder30 exceeds reservation120.
  assert_true(
    holder_effect_host_control_representation_ready(
      profile, "https://x/outbound/observations", "s", "a", "r",
    )
    is None,
  )
  let exact = { ..profile, setup_retained_bytes: 152L, }
  assert_eq(
    holder_effect_host_control_representation_ready(
      exact, "https://x/outbound/observations", "s", "a", "r",
    ),
    Some(112L),
  )
  let one_under = { ..exact, setup_retained_bytes: 151L, }
  assert_true(
    holder_effect_host_control_representation_ready(
      one_under, "https://x/outbound/observations", "s", "a", "r",
    )
    is None,
  )
  let overflow = { ..profile, utf16_unit_bytes: 9223372036854775807L, }
  assert_true(
    holder_effect_host_control_text_extent(
      overflow, "https://x/outbound/observations", "s", "a", "r",
    )
    is None,
  )
  assert_true(
    holder_effect_host_snapshot_extent(
      profile,
      "r",
      [("n", "v")],
      control_text_bytes=-1L,
    )
    is None,
  )
}

///|
test "snapshot cannot consume the original caller remainder" {
  let profile = { ..host_setup_test_profile(), setup_retained_bytes: 144L, }
  let site = host_setup_test_site(2)
  let scope = begin_holder_effect_host_setup_scope(site, Some(profile), () => {
    true
  }).unwrap()
  let control_text_bytes = holder_effect_host_control_text_extent(
    profile, "https://x/outbound/observations", "s", "a", "r",
  ).unwrap()
  let snapshot = [("n", "v")]
  // The independent old snapshot28 plus original control text112 is 140.
  assert_eq(
    holder_effect_host_snapshot_extent(
      profile,
      "r",
      snapshot,
      control_text_bytes~,
    ),
    Some(140L),
  )
  assert_false(
    retain_holder_effect_host_snapshot(
      scope,
      "r",
      snapshot,
      control_text_bytes~,
    ),
  )
  assert_eq(@site.site_status(site)[6], 0L)
  assert_eq(@site.site_status(site)[7], 144L)
  assert_true(leave_holder_effect_host_read_scope(scope))
  assert_true(prepare_holder_effect_host_scope_retirement(scope))
  assert_eq(@site.site_status(site)[7], 144L)
  let operation = scope.caller_operation.unwrap()
  scope.caller_operation = None
  scope.current_binding = None
  assert_true(@site.settle_site_operation(operation))
  assert_eq(@site.site_status(site)[7], 0L)
}

///|
test "missing Host setup profile reserves nothing and never checks physical binding" {
  let site = host_setup_test_site(2)
  let checks = [0]
  assert_true(
    begin_holder_effect_host_setup_scope(site, None, () => {
      checks[0] += 1
      true
    })
    is None,
  )
  assert_eq(checks[0], 0)
  assert_eq(@site.site_status(site)[2], 0L)
  assert_eq(@site.site_status(site)[7], 0L)
}

///|
test "nested current check reuses original setup operation" {
  let site = host_setup_test_site(1)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => true,
  ).unwrap()
  let observed = [0L, 0L]
  assert_true(
    with_holder_effect_host_read_scope(scope, () => {
      observed[0] = @site.site_status(site)[2]
      observed[1] = @site.site_status(site)[7]
      true
    }),
  )
  assert_eq(observed, [1L, 120L])
  assert_eq(scope.depth, 1)
  assert_true(leave_holder_effect_host_read_scope(scope))
  assert_eq(@site.site_status(site)[2], 1L)
  assert_eq(@site.site_status(site)[7], 120L)
  assert_true(with_holder_effect_host_read_scope(scope, () => true))
  assert_eq(@site.site_status(site)[2], 1L)
  assert_eq(@site.site_status(site)[7], 120L)
}

///|
test "snapshot holding stays charged until actual caller retirement" {
  let site = host_setup_test_site(2)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => true,
  ).unwrap()
  let snapshot = [("n", "v")]
  // Independent arithmetic: controls10 + array2 + root(2+2) +
  // slot2 + tuple2 + two Strings each(2+2) = 28.
  assert_eq(
    holder_effect_host_snapshot_extent(scope.profile, "r", snapshot),
    Some(28L),
  )
  assert_true(retain_holder_effect_host_snapshot(scope, "r", snapshot))
  assert_true(leave_holder_effect_host_read_scope(scope))
  assert_eq(@site.site_status(site)[6], 28L)
  assert_eq(@site.site_status(site)[7], 92L)
  assert_true(prepare_holder_effect_host_scope_retirement(scope))
  assert_true(prepare_holder_effect_host_scope_retirement(scope))
  let holding = scope.holding.unwrap()
  scope.holding = None
  assert_true(@site.release_site_holding(holding))
  assert_eq(@site.site_status(site)[6], 0L)
  assert_eq(@site.site_status(site)[7], 92L)
  assert_eq(@site.site_status(site)[8], 20L)
  let operation = scope.caller_operation.unwrap()
  scope.caller_operation = None
  scope.current_binding = None
  assert_true(@site.settle_site_operation(operation))
  assert_false(@site.settle_site_operation(operation))
  assert_eq(@site.site_status(site)[7], 0L)
  assert_eq(@site.site_status(site)[8], 0L)
}

///|
test "setup and dispatch use unchanged Site ceiling and operation slots" {
  let site = host_setup_test_site(2)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => true,
  ).unwrap()
  assert_true(@site.start_site_operation(site, 31L, 1L) is None)
  let dispatch = @site.start_site_operation(site, 30L, 20L).unwrap()
  assert_true(enter_holder_effect_host_read_scope(scope))
  assert_eq(@site.site_status(site)[2], 2L)
  assert_true(leave_holder_effect_host_read_scope(scope))
  assert_true(leave_holder_effect_host_read_scope(scope))
  assert_true(@site.settle_site_operation(dispatch))
  assert_eq(@site.site_status(site)[7], 120L)
}

///|
test "binding revocation refuses current without retaining a cached Allow" {
  let site = host_setup_test_site(2)
  let current = Ref(true)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => current.val,
  ).unwrap()
  assert_true(leave_holder_effect_host_read_scope(scope))
  current.val = false
  let reads = [0]
  assert_false(
    with_holder_effect_host_read_scope(scope, () => {
      reads[0] += 1
      true
    }),
  )
  assert_eq(reads[0], 0)
  assert_eq(@site.site_status(site)[7], 120L)
}

///|
test "original failed read stays charged until same cleanup is observed" {
  let site = host_setup_test_site(2)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => true,
  ).unwrap()
  guard @bounded_files.read_bounded_text_file_with_custody(
      "unopened", "unread", 0L,
    )
    is Err(failure) else {
    fail("invalid limit admitted")
  }
  observe_holder_effect_host_read_failure(scope, failure)
  assert_false(leave_holder_effect_host_read_scope(scope))
  assert_false(enter_holder_effect_host_read_scope(scope))
  assert_eq(@site.site_status(site)[7], 120L)
  assert_eq(@site.site_status(site)[5], 1L)
  assert_true(prepare_holder_effect_host_scope_retirement(scope))
  assert_true(failure.issue() is @bounded_files.InvalidLimit)
  assert_eq(@site.site_status(site)[7], 120L)
  // Confirmed physical retirement does not itself return the cleanup token.
  assert_eq(@site.site_status(site)[5], 1L)
  let cleanup = scope.cleanup.unwrap()
  scope.cleanup = None
  assert_true(@site.release_site_cleanup(cleanup))
  assert_eq(@site.site_status(site)[5], 0L)
}

///|
test "one-pass retirement returns same pending scope without polling or duplicate cleanup" {
  let site = host_setup_test_site(2)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => true,
  ).unwrap()
  guard retire_holder_effect_host_scope(scope)
    is HostSetupScopePending(original) else {
    fail("active operation was retired")
  }
  assert_eq(original.depth, 1)
  assert_eq(@site.site_status(site)[2], 1L)
  assert_eq(@site.site_status(site)[5], 1L)
  assert_eq(@site.site_status(site)[7], 120L)
  assert_true(
    retire_holder_effect_host_scope(original) is HostSetupScopePending(_),
  )
  assert_eq(@site.site_status(site)[5], 1L)
  // A current scope cannot start another read after retirement was requested.
  assert_false(enter_holder_effect_host_read_scope(original))
  assert_false(leave_holder_effect_host_read_scope(original))
  assert_eq(scope.depth, 0)
  assert_true(
    retire_holder_effect_host_scope(original) is HostSetupReadyToDetach,
  )
  assert_eq(@site.site_status(site)[5], 1L)
  let cleanup = scope.cleanup.unwrap()
  scope.cleanup = None
  assert_true(@site.release_site_cleanup(cleanup))
}

///|
test "Site stop and revoke do not acknowledge setup cleanup or return its reservation" {
  let site = host_setup_test_site(2)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => true,
  ).unwrap()
  @site.begin_site_teardown(site)
  @site.revoke_site(site)
  assert_true(
    retire_holder_effect_host_scope(scope) is HostSetupScopePending(_),
  )
  assert_eq(@site.site_status(site)[2], 1L)
  assert_eq(@site.site_status(site)[5], 1L)
  assert_eq(@site.site_status(site)[7], 120L)
}

///|
test "setup binding retains the exact selection and rechecks each current verifier" {
  let site = host_setup_test_site(2)
  let calls = [0, 0]
  let runtime_current = Ref(true)
  let current = holder_effect_host_setup_binding(
    site,
    "test",
    1,
    "runtime",
    () => {
      calls[0] += 1
      true
    },
    () => {
      calls[1] += 1
      runtime_current.val
    },
  )
  assert_true(current())
  runtime_current.val = false
  assert_false(current())
  assert_eq(calls, [2, 2])
  @site.revoke_site(site)
  assert_false(current())
  assert_eq(calls, [3, 2])
}

///|
test "foreign setup key generation or runtime refuses before runtime verification" {
  let site = host_setup_test_site(2)
  let calls = [0]
  for
    (key, generation, runtime) in [
      ("foreign", 1, "runtime"),
      ("test", 2, "runtime"),
      ("test", 1, "foreign"),
    ] {
    let current = holder_effect_host_setup_binding(
      site,
      key,
      generation,
      runtime,
      () => true,
      () => {
        calls[0] += 1
        true
      },
    )
    assert_false(current())
  }
  assert_eq(calls[0], 0)
}

///|
test "lost current slot prevents the setup Site and runtime continuation" {
  let site = host_setup_test_site(2)
  let calls = [0]
  let current = holder_effect_host_setup_binding(
    site,
    "test",
    1,
    "runtime",
    () => false,
    () => {
      calls[0] += 1
      true
    },
  )
  assert_false(current())
  assert_eq(calls[0], 0)
  assert_eq(@site.site_status(site)[2], 0L)
}

///|
test "caller partition refuses insufficient current overlap before binding or I/O" {
  let site = host_setup_test_site(1)
  let checks = Ref(0)
  let profile = host_setup_test_profile()
  for
    candidate in [
      { ..profile, caller_retained_bytes: 29L, },
      { ..profile, caller_retained_bytes: 120L, },
    ] {
    assert_true(
      begin_holder_effect_host_setup_scope(site, Some(candidate), () => {
        checks.val += 1
        true
      })
      is None,
    )
  }
  assert_eq(checks.val, 0)
  assert_eq(@site.site_status(site)[2], 0L)
  assert_eq(@site.site_status(site)[7], 0L)
  assert_eq(@site.site_status(site)[8], 0L)
}

///|
test "partition keeps initial slot and workspace until caller aliases retire" {
  let site = host_setup_test_site(1)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => true,
  ).unwrap()
  let original = scope.caller_operation.unwrap()
  assert_true(retain_holder_effect_host_snapshot(scope, "r", [("n", "v")]))
  assert_true(leave_holder_effect_host_read_scope(scope))
  assert_true(with_holder_effect_host_read_scope(scope, () => true))
  assert_true(prepare_holder_effect_host_scope_retirement(scope))
  let snapshot = scope.holding.unwrap()
  scope.holding = None
  assert_true(@site.release_site_holding(snapshot))
  assert_eq(@site.site_status(site)[6], 0L)
  assert_eq(@site.site_status(site)[7], 92L)
  assert_eq(@site.site_status(site)[8], 20L)
  // Physical snapshot ACK is not the caller frame/alias boundary.
  assert_true(@site.start_site_operation(site, 1L, 1L) is None)
  scope.current_binding = None
  scope.caller_operation = None
  assert_true(@site.settle_site_operation(original))
  let next = @site.start_site_operation(site, 1L, 1L).unwrap()
  assert_true(@site.settle_site_operation(next))
}

///|
test "foreign read operation cannot consume the original caller reservation" {
  let site = host_setup_test_site(2)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => true,
  ).unwrap()
  let original = scope.caller_operation.unwrap()
  let foreign = @site.start_site_operation(site, 1L, 1L).unwrap()
  scope.operation = Some(foreign)
  let reads = Ref(0)
  assert_false(
    with_holder_effect_host_read_scope(scope, () => {
      reads.val += 1
      true
    }),
  )
  assert_eq(reads.val, 0)
  assert_eq(@site.site_status(site)[7], 121L)
  assert_true(@site.site_operation_available(original))
  assert_true(@site.settle_site_operation(foreign))
  // Only the original read borrow is restored; no reservation is reissued.
  scope.operation = Some(original)
  assert_true(leave_holder_effect_host_read_scope(scope))
  assert_eq(@site.site_status(site)[7], 120L)
}

///|
test "caller handoff clears scope aliases and never replaces the original operation" {
  let site = host_setup_test_site(1)
  let scope = begin_holder_effect_host_setup_scope(
    site,
    Some(host_setup_test_profile()),
    () => true,
  ).unwrap()
  let original = scope.caller_operation.unwrap()
  assert_true(leave_holder_effect_host_read_scope(scope))
  assert_true(prepare_holder_effect_host_scope_retirement(scope))
  let (operation, current) = take_holder_effect_host_caller_reservation(scope)
  assert_true(physical_equal(operation.unwrap(), original))
  assert_true(current.unwrap()())
  assert_true(scope.caller_operation is None)
  assert_true(scope.current_binding is None)
  assert_false(enter_holder_effect_host_read_scope(scope))
  let (duplicate, duplicate_current) = take_holder_effect_host_caller_reservation(
    scope,
  )
  assert_true(duplicate is None)
  assert_true(duplicate_current is None)
  assert_eq(@site.site_status(site)[7], 120L)
  // Clearing the private aliases, not a snapshot ACK, precedes the one return.
  assert_true(@site.settle_site_operation(operation.unwrap()))
  assert_eq(@site.site_status(site)[2], 0L)
  assert_eq(@site.site_status(site)[7], 0L)
  assert_eq(@site.site_status(site)[8], 0L)
}
