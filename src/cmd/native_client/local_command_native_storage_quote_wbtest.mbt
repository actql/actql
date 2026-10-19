///|
// Arithmetic-only operands, never an adopted profile or a physical supplier.
// In particular even this complete declaration cannot acquire a platform
// original, Host, domain, Library, permission or business Run.
fn native_storage_arithmetic_profile() -> LocalCommandPreparationProfile {
  let limits : @initial_resources.LedgerLimits = {
    planning_work: 1,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: 1000L,
    execution_bytes: 900000000L,
  }
  let source = "0000000000000000000000000000000000000001"
  {
    source,
    recipe: Bytes::make(32, 0),
    arena_bytes: 2000000000L,
    control_bytes: 1000L,
    host_limits: { ..limits, execution_bytes: 2000000000L, },
    read_domain_bytes: 900000000L,
    read_domain_limits: limits,
    sqlite_domain_bytes: 900000000L,
    sqlite_domain_limits: limits,
    read_budget: {
      bootstrap_retained: 1L,
      bootstrap_execution: 1L,
      workspace_execution: 1L,
      read_retained: 1000L,
      read_execution: 800000000L,
    },
    consumer_retained_bytes: 1L,
    consumer_execution_bytes: 800000000L,
    sqlite_heap_bytes: 134217728L,
    crypto_heap_bytes: 1048576L,
    diagnostic_ceiling: 128,
    native_storage: {
      source,
      max_snapshot_bytes: 32L,
      max_records: 8,
      read_selection: CommandReadDemand,
      managed_read_execution_bytes: Some(11L),
      loader_platform_execution_bytes: Some(19L),
      native_read_execution_bytes: Some(131072L),
      sqlite_heap_selection: Some(SqliteDemandBound(131584L)),
      sqlite_external_execution_bytes: Some(17L),
      shared_control_bytes: Some(29L),
    },
  }
}

///|
test "Native storage WAL boundaries retain the first-region header difference" {
  for
    (frames, regions) in [
      (0L, 1L),
      (4062L, 1L),
      (4063L, 2L),
      (8158L, 2L),
      (8159L, 3L),
    ] {
    let result = native_storage_wal_regions(32L + frames * 536L).unwrap()
    assert_eq(result.0, frames)
    assert_eq(result.1, regions)
  }
  assert_true(native_storage_wal_regions(0L) is Err(NativeStorageInvalidInput))
}

///|
test "Native storage maximum copied WAL is not one index page" {
  let result = native_storage_wal_regions(536870912L).unwrap()
  assert_eq(result.0, 1001624L)
  assert_eq(result.1, 245L)
  assert_eq(result.1 * 32768L, 8028160L)
  assert_true(
    native_storage_wal_regions(536870913L) is Err(NativeStorageInvalidInput),
  )
}

///|
test "Native storage MEMSYS5 rounds actual blocks without a new heap credit" {
  for
    (requested, rounded) in [
      (1L, 16L),
      (24L, 32L),
      (1960L, 2048L),
      (32768L, 32768L),
      (98328L, 131072L),
    ] {
    assert_eq(native_storage_mem5_block(requested).unwrap(), rounded)
  }
  assert_true(native_storage_mem5_block(0L) is Err(NativeStorageInvalidInput))
  assert_true(
    native_storage_mem5_block(9223372036854775807L)
    is Err(NativeStorageOverflow),
  )
}

///|
test "Native storage missing originals are not replaced with zero" {
  let profile = native_storage_arithmetic_profile()
  let missing = {
    ..profile.native_storage,
    loader_platform_execution_bytes: None,
  }
  assert_true(
    quote_local_command_native_storage({ ..profile, native_storage: missing, })
    is Err(NativeStoragePlatformMissing),
  )
  let missing = {
    ..profile.native_storage,
    managed_read_execution_bytes: None,
  }
  assert_true(
    quote_local_command_native_storage({ ..profile, native_storage: missing, })
    is Err(NativeStorageManagedMissing),
  )
  let missing = { ..profile.native_storage, sqlite_heap_selection: None, }
  assert_true(
    quote_local_command_native_storage({ ..profile, native_storage: missing, })
    is Err(NativeStorageSqliteHeapMissing),
  )
}

///|
test "Native storage shared heaps count once and platform never charges Read" {
  let profile = native_storage_arithmetic_profile()
  let quote = quote_local_command_native_storage(profile).unwrap()
  assert_eq(quote.read_execution_bytes, profile.crypto_heap_bytes + 131083L)
  assert_true(quote.read_payload_requirement is CommandReadDemandPayload(_))
  assert_eq(quote.read_facility_ceiling, None)
  assert_eq(quote.platform_required_bytes, 19L)
  assert_eq(quote.sqlite_execution_bytes, profile.sqlite_heap_bytes + 17L)
  assert_true(quote.sqlite_payload_requirement is SqliteDemandPayload(295456L))
  assert_eq(quote.shared_control_bytes, 29L)
}

///|
test "Native storage exhaustion and arithmetic overflow refuse before acquisition" {
  let profile = native_storage_arithmetic_profile()
  assert_true(
    quote_local_command_native_storage({ ..profile, sqlite_heap_bytes: 4096L, })
    is Err(NativeStorageInsufficient),
  )
  assert_true(
    quote_local_command_native_storage({
      ..profile,
      consumer_execution_bytes: 1L,
    })
    is Err(NativeStorageInsufficient),
  )
  assert_true(
    native_storage_sum([9223372036854775807L, 1L]) is Err(NativeStorageOverflow),
  )
  assert_true(native_storage_sum([-1L]) is Err(NativeStorageOverflow))
}

///|
test "Native storage actual Journal options remain inside the captured envelope" {
  let profile = native_storage_arithmetic_profile()
  let quote = quote_local_command_native_storage(profile).unwrap()
  assert_true(quote.covers_journal(profile.source, 8, 32L))
  assert_false(quote.covers_journal(profile.source, 9, 32L))
  assert_false(quote.covers_journal(profile.source, 8, 33L))
  assert_false(
    quote.covers_journal("0000000000000000000000000000000000000002", 8, 32L),
  )
}

///|
test "Native storage positive DATA cannot issue the absent platform original" {
  assert_true(
    prepare_local_command_preparation_original(
      native_storage_arithmetic_profile(),
    )
    is Err(CommandNativeStorage(NativeStoragePlatformUnadmitted)),
  )
  assert_true(command_preparation_invocation.val is None)
  assert_true(initial_crypto_invocation.val is None)
}

///|
test "Native storage original page alignment is preserved for both heaps" {
  let profile = native_storage_arithmetic_profile()
  let page = native_storage_page_bytes()
  assert_true(page > 0L)
  let profile = {
    ..profile,
    sqlite_heap_bytes: profile.sqlite_heap_bytes + 1L,
    crypto_heap_bytes: profile.crypto_heap_bytes + 1L,
  }
  let quote = quote_local_command_native_storage(profile).unwrap()
  assert_eq(quote.sqlite_execution_bytes, 134217728L + page + 17L)
  assert_eq(quote.read_execution_bytes, 1048576L + page + 131083L)
  assert_eq(quote.platform_required_bytes, 19L)
}

///|
test "Native storage original page alignment rejects overflow and false page" {
  assert_true(
    native_storage_page_round(1L, 0L) is Err(NativeStorageInvalidInput),
  )
  assert_true(
    native_storage_page_round(9223372036854775807L, 16384L)
    is Err(NativeStorageOverflow),
  )
  assert_eq(native_storage_page_round(16384L, 16384L).unwrap(), 16384L)
  assert_eq(native_storage_page_round(16385L, 16384L).unwrap(), 32768L)
}

///|
test "Native storage inspection keeps separate file pages and receiver" {
  assert_true(native_inspection_layout_field(0) > 0L)
  assert_true(native_inspection_layout_field(1) > 0L)
  assert_true(
    native_inspection_layout_field(0) + native_inspection_layout_field(1) <
    4096L,
  )
  assert_eq(native_storage_inspection_minimum(4096L).unwrap(), 53248L)
  assert_eq(native_storage_inspection_minimum(16384L).unwrap(), 114688L)
  assert_true(
    native_storage_inspection_minimum(0L) is Err(NativeStorageInvalidInput),
  )
}

///|
test "Native storage inspection subset refuses a positive underquote" {
  let profile = native_storage_arithmetic_profile()
  let required = native_storage_inspection_minimum(native_storage_page_bytes()).unwrap()
  let below = {
    ..profile.native_storage,
    native_read_execution_bytes: Some(required - 1L),
  }
  assert_true(
    quote_local_command_native_storage({ ..profile, native_storage: below, })
    is Err(NativeStorageInsufficient),
  )
  let exact = {
    ..profile.native_storage,
    native_read_execution_bytes: Some(required),
  }
  let quote = quote_local_command_native_storage({
    ..profile,
    native_storage: exact,
  }).unwrap()
  assert_eq(
    quote.read_execution_bytes,
    profile.crypto_heap_bytes + 11L + required,
  )
  assert_true(
    prepare_local_command_preparation_original({
      ..profile,
      native_storage: exact,
    })
    is Err(CommandNativeStorage(NativeStoragePlatformUnadmitted)),
  )
}

///|
test "Native storage cannot place Journal scan result copies outside the same heap" {
  let profile = native_storage_arithmetic_profile()
  // Independent original caller dimensions: 131072 body + 512 key, each
  // already a MEMSYS5 power-of-two block. No VM/cache/DB adequacy is claimed.
  let too_small = {
    ..profile.native_storage,
    sqlite_heap_selection: Some(SqliteDemandBound(131583L)),
  }
  assert_true(
    quote_local_command_native_storage({ ..profile, native_storage: too_small, })
    is Err(NativeStorageInsufficient),
  )
  let exact = {
    ..profile.native_storage,
    sqlite_heap_selection: Some(SqliteDemandBound(131584L)),
  }
  let quote = quote_local_command_native_storage({
    ..profile,
    native_storage: exact,
  }).unwrap()
  assert_true(quote.sqlite_payload_requirement is SqliteDemandPayload(295456L))
  // A large separate Read or outer platform value cannot repair this deficit.
  assert_true(
    quote_local_command_native_storage({
      ..profile,
      native_storage: {
        ..too_small,
        managed_read_execution_bytes: Some(1000000L),
        loader_platform_execution_bytes: Some(1000000L),
      },
    })
    is Err(NativeStorageInsufficient),
  )
}

///|
test "Native SQLite finite capacity is distinct from derived demand" {
  let profile = native_storage_arithmetic_profile()
  let bounds = {
    ..profile.native_storage,
    sqlite_heap_selection: Some(SqliteFiniteFacility),
  }
  let facility = { ..profile, native_storage: bounds, }
  let quote = quote_local_command_native_storage(facility).unwrap()
  assert_true(
    quote.sqlite_payload_requirement is SqliteNecessaryPayload(295456L),
  )
  assert_eq(quote.sqlite_execution_bytes, profile.sqlite_heap_bytes + 17L)
  // Capacity selection cannot supply physical current/platform authority.
  assert_true(
    prepare_local_command_preparation_original(facility)
    is Err(CommandNativeStorage(NativeStoragePlatformUnadmitted)),
  )
  // Known mandatory same-heap coexistence remains required, even with large
  // separate Read/platform allowances. The heap is never all usable payload.
  assert_true(
    quote_local_command_native_storage({
      ..facility,
      sqlite_heap_bytes: 295456L,
    })
    is Err(NativeStorageInsufficient),
  )
  let missing_external = { ..bounds, sqlite_external_execution_bytes: None, }
  assert_true(
    quote_local_command_native_storage({
      ..profile,
      native_storage: missing_external,
    })
    is Err(NativeStorageSqliteExternalMissing),
  )
  // A genuine demand bound can require more than this finite facility.
  let excessive = {
    ..bounds,
    sqlite_heap_selection: Some(SqliteDemandBound(profile.sqlite_heap_bytes)),
  }
  assert_true(
    quote_local_command_native_storage({ ..profile, native_storage: excessive, })
    is Err(NativeStorageInsufficient),
  )
  let missing_platform = { ..bounds, loader_platform_execution_bytes: None, }
  assert_true(
    quote_local_command_native_storage({
      ..profile,
      native_storage: missing_platform,
    })
    is Err(NativeStoragePlatformMissing),
  )
}

///|
test "Native command Read facility separates capacity from complete demand" {
  let profile = native_storage_arithmetic_profile()
  let page = native_storage_page_bytes()
  let ceiling = profile.crypto_heap_bytes + 16L * page
  let bounds = {
    ..profile.native_storage,
    read_selection: CommandReadFiniteFacility(ceiling),
    managed_read_execution_bytes: None,
    native_read_execution_bytes: None,
  }
  let selected = { ..profile, native_storage: bounds, }
  let quote = quote_local_command_native_storage(selected).unwrap()
  assert_eq(quote.read_execution_bytes, ceiling)
  assert_eq(quote.read_facility_ceiling, Some(ceiling))
  assert_true(quote.read_payload_requirement is CommandReadNecessaryPayload(_))
  // Positive DATA still cannot supply the actual initial/platform original.
  assert_true(
    prepare_local_command_preparation_original(selected)
    is Err(CommandNativeStorage(NativeStoragePlatformUnadmitted)),
  )
  let demand = { ..bounds, read_selection: CommandReadDemand, }
  assert_true(
    quote_local_command_native_storage({ ..profile, native_storage: demand, })
    is Err(NativeStorageManagedMissing),
  )
}

///|
test "Native command Read facility retains minima and independent reservations" {
  let profile = native_storage_arithmetic_profile()
  let page = native_storage_page_bytes()
  let minimum = profile.crypto_heap_bytes +
    native_storage_inspection_minimum(page).unwrap()
  let bounds = {
    ..profile.native_storage,
    read_selection: CommandReadFiniteFacility(minimum - page),
    managed_read_execution_bytes: None,
    native_read_execution_bytes: None,
  }
  assert_true(
    quote_local_command_native_storage({ ..profile, native_storage: bounds, })
    is Err(NativeStorageInsufficient),
  )
  let exact = { ..bounds, read_selection: CommandReadFiniteFacility(minimum), }
  let quote = quote_local_command_native_storage({
    ..profile,
    native_storage: exact,
  }).unwrap()
  assert_true(quote.read_payload_requirement is CommandReadNecessaryPayload(_))
  assert_eq(quote.read_execution_bytes, minimum)
  assert_true(
    quote_local_command_native_storage({
      ..profile,
      native_storage: exact,
      read_budget: { ..profile.read_budget, read_execution: minimum - 1L, },
    })
    is Err(NativeStorageInsufficient),
  )
  assert_true(
    quote_local_command_native_storage({
      ..profile,
      native_storage: exact,
      read_budget: {
        ..profile.read_budget,
        bootstrap_execution: profile.read_domain_limits.execution_bytes,
      },
    })
    is Err(NativeStorageInsufficient),
  )
  let missing_external = { ..exact, loader_platform_execution_bytes: None, }
  assert_true(
    quote_local_command_native_storage({
      ..profile,
      native_storage: missing_external,
    })
    is Err(NativeStoragePlatformMissing),
  )
}
