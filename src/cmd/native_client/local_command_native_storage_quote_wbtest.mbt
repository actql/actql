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
      managed_read_execution_bytes: Some(11L),
      loader_platform_execution_bytes: Some(19L),
      native_read_execution_bytes: Some(13L),
      sqlite_other_heap_bytes: Some(32L),
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
  let missing = { ..profile.native_storage, sqlite_other_heap_bytes: None, }
  assert_true(
    quote_local_command_native_storage({ ..profile, native_storage: missing, })
    is Err(NativeStorageSqliteHeapMissing),
  )
}

///|
test "Native storage shared heaps count once and platform never charges Read" {
  let profile = native_storage_arithmetic_profile()
  let quote = quote_local_command_native_storage(profile).unwrap()
  assert_eq(quote.read_execution_bytes, profile.crypto_heap_bytes + 24L)
  assert_eq(quote.platform_required_bytes, 19L)
  assert_eq(quote.sqlite_execution_bytes, profile.sqlite_heap_bytes + 17L)
  assert_eq(quote.sqlite_heap_payload_bytes, 163904L)
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
