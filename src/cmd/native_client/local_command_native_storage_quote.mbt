///|
// Installer-private input to the existing profile, never a resource issuer.
// Each optional term needs its original Native source/holding correspondence;
// absence remains incomplete. Node coefficients and observed fixture peaks
// cannot supply these terms. The actual Host/domain constructors still admit
// and retain the original backing independently.
priv struct LocalCommandNativeStorageBounds {
  source : String
  max_snapshot_bytes : Int64
  max_records : Int
  // Full retained Runtime/configuration/Journal/Common managed graphs,
  // including copies, decoding, callbacks and escaped diagnostics.
  managed_read_execution_bytes : Int64?
  // Mapped images and loader/pthread/TLS/OS/stack holdings outside component heaps.
  // One original shared term, retained through its own actual retirement.
  loader_platform_execution_bytes : Int64?
  // Original Read-backed native buffers/receivers and cleanup-only carriers.
  // Includes inspection's five retained strings and transient path/IO overlap.
  native_read_execution_bytes : Int64?
  // Same SQLite heap's DB/schema/cache/statement/lookaside/result/bindings,
  // including original FD nodes; excluding only the derived WAL index/recovery
  // terms below.
  sqlite_other_heap_bytes : Int64?
  // SQLite domain's original context, Library/DB receivers and managed aliases
  // outside the configured SQLite heap. No loader or heap duplicate here.
  sqlite_external_execution_bytes : Int64?
  // The shared outer registration/controller lifetime, counted once in the
  // existing actual control envelope, not once per Library or phase.
  shared_control_bytes : Int64?
}

///|
priv enum LocalCommandNativeStorageIssue {
  NativeStorageInvalidInput
  NativeStorageOverflow
  NativeStorageManagedMissing
  NativeStoragePlatformMissing
  NativeStoragePlatformUnadmitted
  NativeStorageReadMissing
  NativeStorageSqliteHeapMissing
  NativeStorageSqliteExternalMissing
  NativeStorageControlMissing
  NativeStorageInsufficient
}

///|
extern "C" fn native_storage_page_bytes() -> Int64 = "actql_native_command_storage_page_bytes"

///|
priv struct LocalCommandNativeStorageQuote {
  source : String
  snapshot_bytes : Int64
  records : Int
  wal_frames : Int64
  wal_regions : Int64
  sqlite_heap_payload_bytes : Int64
  sqlite_execution_bytes : Int64
  read_execution_bytes : Int64
  platform_required_bytes : Int64
  shared_control_bytes : Int64
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
  if bytes <= 0L || page <= 0L { return Err(NativeStorageInvalidInput) }
  let remainder = bytes % page
  if remainder == 0L { return Ok(bytes) }
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
fn quote_local_command_native_storage(
  profile : LocalCommandPreparationProfile,
) -> Result[LocalCommandNativeStorageQuote, LocalCommandNativeStorageIssue] {
  let bounds = profile.native_storage
  if bounds.source != profile.source ||
    bounds.source.length() != 40 ||
    bounds.max_records < 1 ||
    bounds.max_records > 1024 ||
    profile.crypto_heap_bytes <= 0L ||
    profile.crypto_heap_bytes > 2147483647L ||
    profile.sqlite_heap_bytes < 4096L ||
    profile.sqlite_heap_bytes > 2147483647L {
    return Err(NativeStorageInvalidInput)
  }
  let (frames, regions) = match
    native_storage_wal_regions(bounds.max_snapshot_bytes) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard bounds.managed_read_execution_bytes is Some(managed) && managed > 0L else {
    return Err(NativeStorageManagedMissing)
  }
  guard bounds.loader_platform_execution_bytes is Some(platform) &&
    platform > 0L else {
    return Err(NativeStoragePlatformMissing)
  }
  guard bounds.native_read_execution_bytes is Some(native) && native > 0L else {
    return Err(NativeStorageReadMissing)
  }
  guard bounds.sqlite_other_heap_bytes is Some(other) && other > 0L else {
    return Err(NativeStorageSqliteHeapMissing)
  }
  guard bounds.sqlite_external_execution_bytes is Some(external) &&
    external > 0L else {
    return Err(NativeStorageSqliteExternalMissing)
  }
  guard bounds.shared_control_bytes is Some(control) && control > 0L else {
    return Err(NativeStorageControlMissing)
  }
  let array = match native_storage_mem5_block(8L * regions) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // Recovery buffer uses the largest legal page. Both pointer-array copies
  // coexist during realloc; the old array is not an acknowledged free credit.
  let recovery = match native_storage_mem5_block(65536L + 24L + 32768L) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // Original descriptor carriers, statements, page/cache and bound/result
  // buffers are part of `other`, inside this same heap. Native inspection
  // source/output/index-creation FDs and their carriers stay separate Read
  // children. A DB close never acknowledges those siblings.
  let payload = match
    native_storage_sum([regions * 32768L, array, array, recovery, other]) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if payload > profile.sqlite_heap_bytes / 17L * 16L {
    return Err(NativeStorageInsufficient)
  }
  // Index/cache/statement/FD storage is already inside this configured heap.
  // Add the heap exactly once to the SQLite domain, never to both domains.
  let sqlite_extent = match native_storage_page_round(profile.sqlite_heap_bytes, native_storage_page_bytes()) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let crypto_extent = match native_storage_page_round(profile.crypto_heap_bytes, native_storage_page_bytes()) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let sqlite = match native_storage_sum([sqlite_extent, external]) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // The one Crypto heap serves both original Libraries, all hooked OpenSSL
  // allocations, realloc overlap and cleanup. Native buffers remain separate.
  let read = match
    native_storage_sum([crypto_extent, managed, native]) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if read > profile.consumer_execution_bytes ||
    read > profile.read_domain_limits.execution_bytes ||
    sqlite > profile.sqlite_domain_limits.execution_bytes ||
    sqlite > profile.sqlite_domain_bytes ||
    control > profile.control_bytes {
    return Err(NativeStorageInsufficient)
  }
  Ok({
    source: bounds.source,
    snapshot_bytes: bounds.max_snapshot_bytes,
    records: bounds.max_records,
    wal_frames: frames,
    wal_regions: regions,
    sqlite_heap_payload_bytes: payload,
    sqlite_execution_bytes: sqlite,
    read_execution_bytes: read,
    platform_required_bytes: platform,
    shared_control_bytes: control,
  })
}

///|
fn LocalCommandNativeStorageQuote::covers_journal(
  self : LocalCommandNativeStorageQuote,
  source : String,
  records : Int,
  snapshot_bytes : Int64,
) -> Bool {
  source == self.source &&
  records >= 1 &&
  records <= self.records &&
  snapshot_bytes > 0L &&
  snapshot_bytes <= self.snapshot_bytes
}


///|
// Exact pending supplier boundary: the selected SQLite dlopen and the later
// Crypto dlopen/OpenSSL pthread/TLS work are not backed by the Read arena.
// No current installed process/platform holding entrance covers them. A known
// byte requirement, selected source or successful component is not that
// original. Keep the existing unavailable outcome before the first backing
// acquisition until the same existing process/installer Owner supplies it.
fn require_native_command_platform_original(
) -> Result[Unit, LocalCommandNativeStorageIssue] {
  Err(NativeStoragePlatformUnadmitted)
}
