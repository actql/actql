///|
test "installed platform matches only the actual compiled target" {
  for platform in ["", "linux-x64", "linux-arm64-gnu", "darwin-x64"] {
    assert_false(command_compiled_platform_matches(platform))
  }
  match command_compiled_platform_ffi() {
    1 => {
      assert_true(command_compiled_platform_matches("darwin-arm64"))
      assert_false(command_compiled_platform_matches("linux-x64-gnu"))
    }
    2 => {
      assert_true(command_compiled_platform_matches("linux-x64-gnu"))
      assert_false(command_compiled_platform_matches("darwin-arm64"))
    }
    _ => {
      assert_false(command_compiled_platform_matches("darwin-arm64"))
      assert_false(command_compiled_platform_matches("linux-x64-gnu"))
    }
  }
  assert_true(command_preparation_invocation.val is None)
}

///|
// These tests distinguish the actual compiled provider from ordinary Core's
// unselected profile. A failed arbitrary layout is never accepted as fallback;
// selected Native artifact acceptance remains independently mandatory.
fn local_command_test_selected_layout() -> Bool raise {
  // Leave room for the real control pages: a one-page domain is invalid
  // even when its provider is selected because control must be smaller.
  let necessary = @initial_bootstrap.execution_domain_necessary_bytes(
    native_storage_page_bytes() * 64L,
    1L,
  )
  if necessary <= 0L {
    assert_eq(necessary, -1L)
    assert_eq(local_command_domain_bytes(1L), None)
    false
  } else {
    true
  }
}

///|
fn local_command_test_unselected_profile_refusal() -> Unit raise {
  let failure = try {
    ignore(local_command_installed_profile("a".repeat(40), "b".repeat(64)))
    "unexpected installed profile"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(failure, "LocalCommandPreparationLayoutUnavailable")
}

///|
// Actual compiled layout queries only. No Host, backing, Read, Library or
// numerical funding is acquired by these profile assertions.
test "static profile uses its selected layout or refuses before backing" {
  if local_command_test_selected_layout() {
    let mib = 1048576L
    let profile = local_command_installed_profile(
      "a".repeat(40),
      "b".repeat(64),
    )
    assert_true(
      profile.native_storage.read_selection is CommandReadFiniteFacility(value) &&
      value == 96L * mib,
    )
    assert_true(
      profile.native_storage.sqlite_domain_selection
      is CommandSqliteDomainFiniteFacility(value) &&
      value == 48L * mib,
    )
    assert_eq(profile.sqlite_heap_bytes, 32L * mib)
    assert_eq(profile.read_budget.bootstrap_retained, mib)
    assert_eq(profile.read_budget.bootstrap_execution, mib)
    assert_eq(profile.read_budget.workspace_execution, 8L * mib)
    assert_eq(profile.read_budget.read_retained, 7L * mib)
    assert_eq(profile.read_budget.read_execution, 96L * mib)
    assert_eq(profile.read_domain_limits.retained_bytes, 8L * mib)
    assert_eq(profile.read_domain_limits.execution_bytes, 105L * mib)
    assert_eq(profile.sqlite_domain_limits.execution_bytes, 48L * mib)
    let payload = profile.read_domain_limits.retained_bytes +
      profile.read_domain_limits.execution_bytes
    assert_true(
      @initial_bootstrap.execution_domain_necessary_bytes(
        profile.read_domain_bytes,
        payload,
      ) <=
      profile.read_domain_bytes,
    )
    assert_true(
      @initial_bootstrap.execution_domain_necessary_bytes(
        profile.sqlite_domain_bytes,
        48L * mib,
      ) <=
      profile.sqlite_domain_bytes,
    )
    assert_true(
      @local_sqlite.command_domain_necessary_bytes(
        profile.sqlite_domain_bytes,
        profile.sqlite_heap_bytes,
      ).unwrap() <=
      48L * mib,
    )
    assert_true(
      profile.read_domain_bytes + profile.sqlite_domain_bytes < 192L * mib,
    )
    assert_true(
      profile.arena_bytes >=
      profile.read_domain_bytes +
      profile.sqlite_domain_bytes +
      profile.control_bytes,
    )
    assert_eq(
      @initial_bootstrap.command_backing_control_necessary_bytes(
        profile.arena_bytes,
      ),
      Some(profile.control_bytes),
    )
    let storage = quote_local_command_native_storage(profile).unwrap()
    assert_eq(storage.read_facility_ceiling, Some(96L * mib))
    assert_eq(storage.sqlite_domain_facility_ceiling, Some(48L * mib))
    assert_eq(storage.snapshot_bytes, 8L * mib)
    // Count is the later configured Journal policy, not a preallocated facility.
    assert_true(storage.covers_journal(profile.source, 1025, 8L * mib))
  } else {
    local_command_test_unselected_profile_refusal()
  }
  assert_true(command_preparation_invocation.val is None)
  assert_true(initial_crypto_invocation.val is None)
}

///|
test "business profile requires selected layout for enclosing original control" {
  if local_command_test_selected_layout() {
    let profile = local_command_installed_profile(
      "a".repeat(40),
      "b".repeat(64),
    )
    let (combined, business) = local_command_source_free_business_profile(
      profile,
    )
    assert_eq(business.limits.retained_bytes, 536870912L)
    assert_eq(business.limits.execution_bytes, 536870912L)
    assert_eq(
      [
        combined.read_budget.bootstrap_retained,
        combined.read_budget.bootstrap_execution,
        combined.read_budget.workspace_execution,
        combined.read_budget.read_retained,
        combined.read_budget.read_execution,
      ],
      [
        profile.read_budget.bootstrap_retained,
        profile.read_budget.bootstrap_execution,
        profile.read_budget.workspace_execution,
        profile.read_budget.read_retained,
        profile.read_budget.read_execution,
      ],
    )
    assert_true(
      combined.native_storage.read_selection is CommandReadFiniteFacility(value) &&
      value == 96L * 1048576L,
    )
    assert_true(
      combined.native_storage.sqlite_domain_selection
      is CommandSqliteDomainFiniteFacility(value) &&
      value == 48L * 1048576L,
    )
    assert_eq(combined.sqlite_heap_bytes, profile.sqlite_heap_bytes)
    let domains = combined.read_domain_bytes +
      combined.sqlite_domain_bytes +
      business.domain_bytes
    assert_true(combined.arena_bytes >= domains + combined.control_bytes)
    assert_eq(
      @initial_bootstrap.command_backing_control_necessary_bytes(
        combined.arena_bytes,
      ),
      Some(combined.control_bytes),
    )
    assert_eq(combined.host_limits.execution_bytes, combined.arena_bytes)
    quote_local_command_native_storage(combined).unwrap() |> ignore
  } else {
    local_command_test_unselected_profile_refusal()
  }
  assert_true(local_command_domain_bytes(0L) is None)
  assert_true(local_command_domain_bytes(9223372036854775807L) is None)
  assert_true(local_command_backing_layout(0L) is None)
  assert_true(local_command_backing_layout(9223372036854775807L) is None)
  assert_true(command_preparation_invocation.val is None)
  assert_true(initial_crypto_invocation.val is None)
}
