///|
// Arithmetic-only operands, never an adopted profile or a physical supplier.
// In particular even this complete declaration cannot acquire a platform
// original, Host, domain, Library, permission or business Run.
fn native_storage_finite_arithmetic_profile() -> LocalCommandPreparationProfile {
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
      read_selection: CommandReadFiniteFacility(
        1048576L + 16L * native_storage_page_bytes(),
      ),
      platform_selection: CommandPlatformInitialOsFacility,
      sqlite_domain_selection: CommandSqliteDomainFiniteFacility(
        128L * 1048576L,
      ),
      loader_platform_execution_bytes: None,
      sqlite_heap_selection: Some(SqliteFiniteFacility),
      sqlite_external_execution_bytes: None,
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
test "finite Journal necessary payload retains both result copies and WAL overlap" {
  assert_eq(native_storage_journal_necessary_payload(1L).unwrap(), 295456L)
  let regions = 2L
  let copies = native_storage_mem5_block(131072L).unwrap() +
    native_storage_mem5_block(512L).unwrap()
  let array = native_storage_mem5_block(8L * regions).unwrap()
  let recovery = native_storage_mem5_block(65536L + 24L + 32768L).unwrap()
  assert_eq(
    native_storage_journal_necessary_payload(regions).unwrap(),
    regions * 32768L + array + array + recovery + copies,
  )
  assert_true(
    native_storage_journal_necessary_payload(0L)
    is Err(NativeStorageInvalidInput),
  )
}

///|
test "finite quote refuses missing originals without zero demand substitutes" {
  let profile = native_storage_finite_arithmetic_profile()
  for selected in [None, Some(0L)] {
    assert_true(
      quote_local_command_native_storage({
        ..profile,
        native_storage: {
          ..profile.native_storage,
          shared_control_bytes: selected,
        },
      })
      is Err(NativeStorageControlMissing),
    )
  }
  assert_true(
    quote_local_command_native_storage({
      ..profile,
      native_storage: { ..profile.native_storage, sqlite_heap_selection: None, },
    })
    is Err(NativeStorageSqliteHeapMissing),
  )
  assert_true(
    quote_local_command_native_storage({
      ..profile,
      native_storage: { ..profile.native_storage, source: "foreign", },
    })
    is Err(NativeStorageInvalidInput),
  )
}

///|
test "finite SQLite heap cannot place simultaneous Journal payload outside its original" {
  let profile = native_storage_finite_arithmetic_profile()
  assert_true(
    quote_local_command_native_storage({
      ..profile,
      sqlite_heap_bytes: 262144L,
    })
    is Err(NativeStorageInsufficient),
  )
  assert_true(
    native_storage_sum([9223372036854775807L, 1L]) is Err(NativeStorageOverflow),
  )
  assert_true(native_storage_sum([-1L]) is Err(NativeStorageOverflow))
}

///|
test "finite Read necessary bound counts one aligned crypto extent and physical inspection" {
  let profile = native_storage_finite_arithmetic_profile()
  let page = native_storage_page_bytes()
  let crypto = native_storage_page_round(profile.crypto_heap_bytes, page).unwrap()
  let inspection = native_storage_inspection_minimum(page).unwrap()
  let minimum = crypto + inspection
  let exact = {
    ..profile,
    native_storage: {
      ..profile.native_storage,
      read_selection: CommandReadFiniteFacility(minimum),
    },
  }
  assert_eq(
    native_storage_finite_read_bytes(exact, crypto, inspection).unwrap(),
    minimum,
  )
  assert_true(
    native_storage_finite_read_bytes(
      {
        ..exact,
        native_storage: {
          ..exact.native_storage,
          read_selection: CommandReadFiniteFacility(minimum - page),
        },
      },
      crypto,
      inspection,
    )
    is Err(NativeStorageInsufficient),
  )
  // This numeric necessity check creates no Read/domain/Host or complete-demand proof.
  assert_true(
    quote_local_command_native_storage(exact)
    is Err(NativeStorageSqliteDomainMissing),
  )
}

///|
test "finite Read retains independent original reservation ceilings" {
  let profile = native_storage_finite_arithmetic_profile()
  let page = native_storage_page_bytes()
  let crypto = native_storage_page_round(profile.crypto_heap_bytes, page).unwrap()
  let inspection = native_storage_inspection_minimum(page).unwrap()
  let minimum = crypto + inspection
  let exact = {
    ..profile,
    native_storage: {
      ..profile.native_storage,
      read_selection: CommandReadFiniteFacility(minimum),
    },
  }
  assert_true(
    native_storage_finite_read_bytes(
      {
        ..exact,
        read_budget: { ..exact.read_budget, read_execution: minimum - 1L, },
      },
      crypto,
      inspection,
    )
    is Err(NativeStorageInsufficient),
  )
  let reserved = exact.read_budget.bootstrap_execution +
    exact.read_budget.workspace_execution +
    exact.read_budget.read_execution
  assert_true(
    native_storage_finite_read_bytes(
      {
        ..exact,
        read_domain_limits: {
          ..exact.read_domain_limits,
          execution_bytes: reserved - 1L,
        },
      },
      crypto,
      inspection,
    )
    is Err(NativeStorageInsufficient),
  )
  for invalid in [0L, -1L, minimum + 1L] {
    assert_true(
      native_storage_finite_read_bytes(
        {
          ..exact,
          native_storage: {
            ..exact.native_storage,
            read_selection: CommandReadFiniteFacility(invalid),
          },
        },
        crypto,
        inspection,
      )
      is Err(NativeStorageInvalidInput),
    )
  }
}

///|
test "finite platform OS selection cannot become a numerical reservation" {
  let profile = native_storage_finite_arithmetic_profile()
  for bytes in [0L, 19L] {
    assert_true(
      quote_local_command_native_storage({
        ..profile,
        native_storage: {
          ..profile.native_storage,
          loader_platform_execution_bytes: Some(bytes),
        },
      })
      is Err(NativeStorageInvalidInput),
    )
  }
  assert_true(
    quote_local_command_native_storage(profile)
    is Err(NativeStorageSqliteDomainMissing),
  )
}

///|
test "finite SQLite domain refuses fabricated external demand and absent physical provider" {
  let profile = native_storage_finite_arithmetic_profile()
  for bytes in [0L, 17L] {
    assert_true(
      quote_local_command_native_storage({
        ..profile,
        native_storage: {
          ..profile.native_storage,
          sqlite_external_execution_bytes: Some(bytes),
        },
      })
      is Err(NativeStorageInvalidInput),
    )
  }
  let page = native_storage_page_bytes()
  for invalid in [0L, -1L, page + 1L] {
    assert_true(
      quote_local_command_native_storage({
        ..profile,
        native_storage: {
          ..profile.native_storage,
          sqlite_domain_selection: CommandSqliteDomainFiniteFacility(invalid),
        },
      })
      is Err(NativeStorageInvalidInput),
    )
  }
  // The ordinary test binary has no selected physical layout provider. No fake
  // minimum or constructed demand selector can turn that into positive admission.
  assert_true(
    quote_local_command_native_storage(profile)
    is Err(NativeStorageSqliteDomainMissing),
  )
  assert_true(
    prepare_local_command_preparation_original(profile)
    is Err(CommandNativeStorage(NativeStorageSqliteDomainMissing)),
  )
}

///|
test "actual Journal policy has no unrelated physical count ceiling" {
  let original = "0000000000000000000000000000000000000001"
  for records in [1, 32, 1023, 1024, 1025, 2147483647] {
    assert_true(
      native_storage_journal_bounds_cover(original, 32L, original, records, 32L),
    )
    assert_false(
      native_storage_journal_bounds_cover(original, 32L, original, records, 33L),
    )
    assert_false(
      native_storage_journal_bounds_cover(
        original, 32L, "0000000000000000000000000000000000000002", records, 32L,
      ),
    )
  }
  for records in [0, -1] {
    assert_false(
      native_storage_journal_bounds_cover(original, 32L, original, records, 32L),
    )
  }
  assert_false(
    native_storage_journal_bounds_cover(original, 32L, original, 1, 0L),
  )
}

///|
test "finite numeric declarations cannot issue the absent actual platform original" {
  assert_true(
    require_native_command_platform_original()
    is Err(NativeStoragePlatformUnadmitted),
  )
  assert_true(command_preparation_invocation.val is None)
  assert_true(initial_crypto_invocation.val is None)
}

///|
test "finite necessary extents preserve page rounding without external demand additions" {
  let page = native_storage_page_bytes()
  assert_true(page > 0L)
  assert_eq(
    native_storage_page_round(1048576L + 1L, page).unwrap(),
    1048576L + page,
  )
  assert_eq(
    native_storage_page_round(134217728L + 1L, page).unwrap(),
    134217728L + page,
  )
}

///|
test "finite quote final ceilings reject every one-short original independently" {
  let profile = native_storage_finite_arithmetic_profile()
  let exact = {
    ..profile,
    consumer_execution_bytes: 4096L,
    read_domain_limits: {
      ..profile.read_domain_limits,
      execution_bytes: 4096L,
    },
    sqlite_domain_limits: {
      ..profile.sqlite_domain_limits,
      execution_bytes: 8192L,
    },
    sqlite_domain_bytes: 8192L,
    control_bytes: 128L,
  }
  assert_true(native_storage_finite_ceilings_cover(exact, 4096L, 8192L, 128L))
  assert_false(
    native_storage_finite_ceilings_cover(
      { ..exact, consumer_execution_bytes: 4095L, },
      4096L,
      8192L,
      128L,
    ),
  )
  assert_false(
    native_storage_finite_ceilings_cover(
      {
        ..exact,
        read_domain_limits: {
          ..exact.read_domain_limits,
          execution_bytes: 4095L,
        },
      },
      4096L,
      8192L,
      128L,
    ),
  )
  assert_false(
    native_storage_finite_ceilings_cover(
      {
        ..exact,
        sqlite_domain_limits: {
          ..exact.sqlite_domain_limits,
          execution_bytes: 8191L,
        },
      },
      4096L,
      8192L,
      128L,
    ),
  )
  assert_false(
    native_storage_finite_ceilings_cover(
      { ..exact, sqlite_domain_bytes: 8191L, },
      4096L,
      8192L,
      128L,
    ),
  )
  assert_false(
    native_storage_finite_ceilings_cover(
      { ..exact, control_bytes: 127L, },
      4096L,
      8192L,
      128L,
    ),
  )
}
