///|
// Installer-private finite selections, never a resource issuer or a complete
// demand model. Actual Host/domain constructors still admit and retain the
// same physical backing independently; arithmetic cannot replace that original.
priv struct LocalCommandNativeStorageBounds {
  source : String
  max_snapshot_bytes : Int64
  read_selection : LocalCommandReadStorageSelection
  platform_selection : LocalCommandPlatformStorageSelection
  sqlite_domain_selection : LocalCommandSqliteDomainStorageSelection
  // The selected OS service original has no byte-credit equivalent. Reject
  // any numerical substitute, including zero, rather than infer demand.
  loader_platform_execution_bytes : Int64?
  // An explicit selection, never inferred from remaining heap capacity.
  sqlite_heap_selection : LocalCommandSqliteHeapSelection?
  // SQLite domain's original context, Library/DB receivers and managed aliases
  // outside the configured SQLite heap. No loader or heap duplicate here.
  sqlite_external_execution_bytes : Int64?
  // The shared outer registration/controller lifetime, counted once in the
  // existing actual control envelope, not once per Library or phase.
  shared_control_bytes : Int64?
}

///|
// This selection issues no original. The same trusted initial entry remains
// mandatory; the OS facility is a closed operational lifetime, not a byte pool.
priv enum LocalCommandPlatformStorageSelection {
  CommandPlatformInitialOsFacility
}

///|
// Closed Native command preparation only. Facility bytes are a pre-acquisition
// candidate for the same physical Read's occupied-page ceiling, never residual
// managed/native demand or a general business Read allowance.
priv enum LocalCommandReadStorageSelection {
  CommandReadFiniteFacility(Int64)
}

///|
// The same actual backed heap remains mandatory before first SQLite use.
// Facility capacity may exhaust; it is not an all-input demand guarantee.
priv enum LocalCommandSqliteDomainStorageSelection {
  CommandSqliteDomainFiniteFacility(Int64)
}

///|
priv enum LocalCommandSqliteHeapSelection {
  SqliteFiniteFacility
}

///|
priv enum LocalCommandNativeStorageIssue {
  NativeStorageInvalidInput
  NativeStorageOverflow
  NativeStoragePlatformUnadmitted
  NativeStorageSqliteHeapMissing
  NativeStorageControlMissing
  NativeStorageInsufficient
  NativeStorageSqliteDomainMissing
}

///|
extern "C" fn native_storage_page_bytes() -> Int64 = "actql_native_command_storage_page_bytes"

///|
extern "C" fn native_inspection_layout_field(field : Int) -> Int64 = "actql_journal_inspection_layout_field"

///|
priv struct LocalCommandNativeStorageQuote {
  source : String
  snapshot_bytes : Int64
  sqlite_domain_facility_ceiling : Int64?
  read_facility_ceiling : Int64?
}

///|
fn native_storage_sum(
  values : Array[Int64],
) -> Result[Int64, LocalCommandNativeStorageIssue] {
  let mut total = 0L
  for value in values {
    if value < 0L || value > 9223372036854775807L - total {
      return Err(NativeStorageOverflow)
    }
    total += value
  }
  Ok(total)
}

///|
fn native_storage_page_round(
  bytes : Int64,
  page : Int64,
) -> Result[Int64, LocalCommandNativeStorageIssue] {
  if bytes <= 0L || page <= 0L {
    return Err(NativeStorageInvalidInput)
  }
  let remainder = bytes % page
  if remainder == 0L {
    return Ok(bytes)
  }
  let padding = page - remainder
  native_storage_sum([bytes, padding])
}

///|
// MEMSYS5's configured minimum atom is 16. Payload rounds to a power-of-two
// block inside the SAME heap; its control byte per atom is not free capacity.
fn native_storage_mem5_block(
  bytes : Int64,
) -> Result[Int64, LocalCommandNativeStorageIssue] {
  if bytes <= 0L {
    return Err(NativeStorageInvalidInput)
  }
  let mut block = 16L
  while block < bytes {
    if block > 4611686018427387903L {
      return Err(NativeStorageOverflow)
    }
    block *= 2L
  }
  Ok(block)
}

///|
// Necessary simultaneous subset, not a complete Native holding quote. File
// buffers use the original generic page route; they cannot share a managed
// slab. Three source paths remain while either canonical-path temporaries or
// directory/copy/cleanup paths coexist. Count the receiver separately, even
// when a managed allocator could pack it beside another object. Complete
// caller graphs, context/allocator metadata and failed-retirement retention
// still belong to the caller's full Native/managed envelope.
fn native_storage_inspection_minimum(
  page : Int64,
) -> Result[Int64, LocalCommandNativeStorageIssue] {
  let payload = native_inspection_layout_field(0)
  let overhead = native_inspection_layout_field(1)
  let canonical = native_inspection_layout_field(2)
  if payload <= 0L || overhead <= 0L || canonical <= 0L {
    return Err(NativeStorageInvalidInput)
  }
  let receiver = match native_storage_sum([payload, overhead]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Literal suffixes in the same inspection Owner: /actql-journal-format-XXXXXX
  // is 28 bytes and /journal.sqlite3 is 16. Cleanup's longest suffix is -journal.
  let requests = [
    receiver,
    4096L + 1L,
    4096L + 4L + 1L,
    4096L + 8L + 1L,
    4096L + 1L,
    canonical,
    canonical,
    4096L + 28L + 1L,
    4096L + 28L + 16L + 1L,
    4096L + 28L + 16L + 8L + 1L,
  ]
  let rounded : Array[Int64] = []
  for bytes in requests {
    match native_storage_page_round(bytes, page) {
      Ok(value) => rounded.push(value)
      Err(issue) => return Err(issue)
    }
  }
  let resolving = match
    native_storage_sum([rounded[4], rounded[5], rounded[6]]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let copying = match native_storage_sum([rounded[7], rounded[8], rounded[9]]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  native_storage_sum([
    rounded[0],
    rounded[1],
    rounded[2],
    rounded[3],
    if resolving > copying {
      resolving
    } else {
      copying
    },
  ])
}

///|
// Pinned SQLite 3.51.0: first region 4062 frames, later regions 4096,
// WALINDEX_PGSZ 32768. A copied DB+WAL bound is an upper WAL byte bound,
// not a claim of one index region. The smallest legal page maximizes frames.
fn native_storage_wal_regions(
  snapshot_bytes : Int64,
) -> Result[(Int64, Int64), LocalCommandNativeStorageIssue] {
  if snapshot_bytes <= 0L || snapshot_bytes > 536870912L {
    return Err(NativeStorageInvalidInput)
  }
  let frames = if snapshot_bytes <= 32L {
    0L
  } else {
    (snapshot_bytes - 32L) / (512L + 24L)
  }
  let regions = if frames <= 4062L {
    1L
  } else {
    1L + (frames - 4062L + 4095L) / 4096L
  }
  Ok((frames, regions))
}

///|
// Necessary simultaneous Journal payload only, not complete SQLite demand.
// The actual finite quote uses these same MEMSYS5/WAL calculations before its
// physical domain provider can admit anything.
fn native_storage_journal_necessary_payload(
  regions : Int64,
) -> Result[Int64, LocalCommandNativeStorageIssue] {
  if regions <= 0L || regions > 9223372036854775807L / 32768L {
    return Err(NativeStorageInvalidInput)
  }
  let result_body = match native_storage_mem5_block(131072L) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let result_key = match native_storage_mem5_block(512L) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let result_copies = match native_storage_sum([result_body, result_key]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let array = match native_storage_mem5_block(8L * regions) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let recovery = match native_storage_mem5_block(65536L + 24L + 32768L) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  native_storage_sum([regions * 32768L, array, array, recovery, result_copies])
}

///|
// Check necessary finite Read coexistence and independent original reservations.
// A successful numeric check is not a physical Read, complete demand, or grant.
fn native_storage_finite_read_bytes(
  profile : LocalCommandPreparationProfile,
  crypto_extent : Int64,
  inspection : Int64,
) -> Result[Int64, LocalCommandNativeStorageIssue] {
  let CommandReadFiniteFacility(bytes) = profile.native_storage.read_selection
  let page = native_storage_page_bytes()
  if bytes <= 0L || page <= 0L || bytes % page != 0L {
    return Err(NativeStorageInvalidInput)
  }
  let minimum = match native_storage_sum([crypto_extent, inspection]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if bytes < minimum || bytes > profile.read_budget.read_execution {
    return Err(NativeStorageInsufficient)
  }
  let reserved = match
    native_storage_sum([
      profile.read_budget.bootstrap_execution,
      profile.read_budget.workspace_execution,
      profile.read_budget.read_execution,
    ]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if reserved > profile.read_domain_limits.execution_bytes {
    return Err(NativeStorageInsufficient)
  }
  Ok(bytes)
}

///|
fn quote_local_command_native_storage(
  profile : LocalCommandPreparationProfile,
) -> Result[LocalCommandNativeStorageQuote, LocalCommandNativeStorageIssue] {
  let bounds = profile.native_storage
  if bounds.source != profile.source ||
    bounds.source.length() != 40 ||
    profile.crypto_heap_bytes <= 0L ||
    profile.crypto_heap_bytes > 2147483647L ||
    profile.sqlite_heap_bytes < 4096L ||
    profile.sqlite_heap_bytes > 2147483647L {
    return Err(NativeStorageInvalidInput)
  }
  let (_, regions) = match
    native_storage_wal_regions(bounds.max_snapshot_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let CommandPlatformInitialOsFacility = bounds.platform_selection
  if bounds.loader_platform_execution_bytes is Some(_) {
    return Err(NativeStorageInvalidInput)
  }
  guard bounds.sqlite_heap_selection is Some(SqliteFiniteFacility) else {
    return Err(NativeStorageSqliteHeapMissing)
  }
  // Capacity cannot fill an external-demand field with residual bytes.
  if bounds.sqlite_external_execution_bytes is Some(_) {
    return Err(NativeStorageInvalidInput)
  }
  guard bounds.shared_control_bytes is Some(control) && control > 0L else {
    return Err(NativeStorageControlMissing)
  }
  let inspection = match
    native_storage_inspection_minimum(native_storage_page_bytes()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let payload = match native_storage_journal_necessary_payload(regions) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if payload > profile.sqlite_heap_bytes / 17L * 16L {
    return Err(NativeStorageInsufficient)
  }
  let crypto_extent = match
    native_storage_page_round(
      profile.crypto_heap_bytes,
      native_storage_page_bytes(),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let CommandSqliteDomainFiniteFacility(sqlite) = bounds.sqlite_domain_selection
  let page = native_storage_page_bytes()
  if sqlite <= 0L || page <= 0L || sqlite % page != 0L {
    return Err(NativeStorageInvalidInput)
  }
  // The original physical provider includes actual control/context/receiver
  // layouts. Never supply a dummy minimum for an unselected/unsupported binary.
  guard @local_sqlite.command_domain_necessary_bytes(
      profile.sqlite_domain_bytes,
      profile.sqlite_heap_bytes,
    )
    is Some(minimum) &&
    minimum > 0L else {
    return Err(NativeStorageSqliteDomainMissing)
  }
  if sqlite < minimum {
    return Err(NativeStorageInsufficient)
  }
  let read = match
    native_storage_finite_read_bytes(profile, crypto_extent, inspection) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !native_storage_finite_ceilings_cover(profile, read, sqlite, control) {
    return Err(NativeStorageInsufficient)
  }
  Ok({
    source: bounds.source,
    snapshot_bytes: bounds.max_snapshot_bytes,
    sqlite_domain_facility_ceiling: Some(sqlite),
    read_facility_ceiling: Some(read),
  })
}

///|
fn LocalCommandNativeStorageQuote::covers_journal(
  self : LocalCommandNativeStorageQuote,
  source : String,
  records : Int,
  snapshot_bytes : Int64,
) -> Bool {
  native_storage_journal_bounds_cover(
    self.source,
    self.snapshot_bytes,
    source,
    records,
    snapshot_bytes,
  )
}

///|
// Source and snapshot bounds belong to the captured physical quote. The actual
// positive record policy is selected later from the same checked configuration;
// future record count is not preallocated Read/SQLite demand. These scalars
// cannot manufacture a quote, physical original, or permission.
fn native_storage_journal_bounds_cover(
  original_source : String,
  original_snapshot_bytes : Int64,
  source : String,
  records : Int,
  snapshot_bytes : Int64,
) -> Bool {
  source == original_source &&
  records >= 1 &&
  snapshot_bytes > 0L &&
  snapshot_bytes <= original_snapshot_bytes
}

///|
// The C Owner retains its same actual entry original. This observation only
// rejects a missing supplier before backing acquisition; it creates no record,
// capacity or permission. Each selected load must still obtain that original
// and bind its same Runtime/member before dlopen, including initializers.
extern "C" fn native_command_platform_original_available() -> Bool = "actql_native_command_platform_available"

///|
fn require_native_command_platform_original() -> Result[
  Unit,
  LocalCommandNativeStorageIssue,
] {
  if native_command_platform_original_available() {
    Ok(())
  } else {
    Err(NativeStoragePlatformUnadmitted)
  }
}

///|
// The final numeric subset predicate used by the actual finite quote, after its
// real physical-provider guard. This does not issue or acknowledge an original.
fn native_storage_finite_ceilings_cover(
  profile : LocalCommandPreparationProfile,
  read : Int64,
  sqlite : Int64,
  control : Int64,
) -> Bool {
  read <= profile.consumer_execution_bytes &&
  read <= profile.read_domain_limits.execution_bytes &&
  sqlite <= profile.sqlite_domain_limits.execution_bytes &&
  sqlite <= profile.sqlite_domain_bytes &&
  control <= profile.control_bytes
}
