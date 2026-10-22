///|
// Actual compiled layout queries only. No Host, backing, Read, Library or
// numerical funding is acquired by these profile assertions.
test "static profile preserves facilities and quotes its exact declared claims" {
  let mib = 1048576L
  let profile = local_command_installed_profile("a".repeat(40), "b".repeat(64))
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
  assert_eq(storage.records, 32)
}

///|
test "business profile recomputes the enclosing original control layout" {
  let profile = local_command_installed_profile("a".repeat(40), "b".repeat(64))
  let (combined, business) = local_command_source_free_business_profile(profile)
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
  assert_true(local_command_domain_bytes(0L) is None)
  assert_true(local_command_domain_bytes(9223372036854775807L) is None)
  assert_true(local_command_backing_layout(0L) is None)
  assert_true(local_command_backing_layout(9223372036854775807L) is None)
}
