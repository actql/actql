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
  read_selection : LocalCommandReadStorageSelection
  platform_selection : LocalCommandPlatformStorageSelection
  // Full retained Runtime/configuration/Journal/Common managed graphs,
  // including copies, decoding, callbacks and escaped diagnostics.
  // Demand selection only; never a residual facility capacity.
  managed_read_execution_bytes : Int64?
  // Mapped images and loader/pthread/TLS/OS/stack holdings outside component heaps.
  // Numerical demand selection only. A selected OS service original has no
  // byte-credit equivalent and must not fill this field with zero or a scalar.
  loader_platform_execution_bytes : Int64?
  // Original Read-backed native buffers/receivers and cleanup-only carriers.
  // Includes inspection's five retained strings and transient path/IO overlap.
  native_read_execution_bytes : Int64?
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
// Neither branch issues the original. The same trusted initial entry remains
// mandatory; the OS facility is a closed operational lifetime, not a byte pool.
priv enum LocalCommandPlatformStorageSelection {
  CommandPlatformDemand
  CommandPlatformInitialOsFacility
}

///|
// Closed Native command preparation only. Facility bytes are a pre-acquisition
// candidate for the same physical Read's occupied-page ceiling, never residual
// managed/native demand or a general business Read allowance.
priv enum LocalCommandReadStorageSelection {
  CommandReadDemand
  CommandReadFiniteFacility(Int64)
}

///|
priv enum LocalCommandReadPayloadRequirement {
  CommandReadDemandPayload(Int64)
  CommandReadNecessaryPayload(Int64)
}

///|
// Both branches require the same actual backed heap before first SQLite use.
// Facility capacity may exhaust; it is not an all-input demand guarantee.
priv enum LocalCommandSqliteHeapSelection {
  SqliteDemandBound(Int64)
  SqliteFiniteFacility
}

///|
priv enum LocalCommandSqlitePayloadRequirement {
  SqliteDemandPayload(Int64)
  SqliteNecessaryPayload(Int64)
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
extern "C" fn native_inspection_layout_field(field : Int) -> Int64 = "actql_journal_inspection_layout_field"

///|
priv struct LocalCommandNativeStorageQuote {
  source : String
  snapshot_bytes : Int64
  records : Int
  wal_frames : Int64
  wal_regions : Int64
  sqlite_payload_requirement : LocalCommandSqlitePayloadRequirement
  sqlite_execution_bytes : Int64
  read_execution_bytes : Int64
  read_payload_requirement : LocalCommandReadPayloadRequirement
  read_facility_ceiling : Int64?
  platform_selection : LocalCommandPlatformStorageSelection
  platform_required_bytes : Int64?
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
  // Preserve the original demand branch's missing-term refusal order.
  let managed_demand = match bounds.read_selection {
    CommandReadDemand => {
      guard bounds.managed_read_execution_bytes is Some(managed) && managed > 0L else {
        return Err(NativeStorageManagedMissing)
      }
      Some(managed)
    }
    CommandReadFiniteFacility(_) => None
  }
  let platform = match bounds.platform_selection {
    CommandPlatformDemand => {
      guard bounds.loader_platform_execution_bytes is Some(bytes) && bytes > 0L else {
        return Err(NativeStoragePlatformMissing)
      }
      Some(bytes)
    }
    CommandPlatformInitialOsFacility => {
      if bounds.loader_platform_execution_bytes is Some(_) {
        return Err(NativeStorageInvalidInput)
      }
      None
    }
  }
  let read_demand = match bounds.read_selection {
    CommandReadDemand => {
      guard bounds.native_read_execution_bytes is Some(native) && native > 0L else {
        return Err(NativeStorageReadMissing)
      }
      Some((managed_demand.unwrap(), native))
    }
    CommandReadFiniteFacility(_) => None
  }
  guard bounds.sqlite_heap_selection is Some(selection) else {
    return Err(NativeStorageSqliteHeapMissing)
  }
  // The original Journal admits 131072-byte bodies and 512-byte scan keys.
  // sqlite_stub.c allocates BOTH retained result copies before finalizing the
  // same statement. They use this same MEMSYS5 heap, not Read or a new credit.
  // In the demand branch these are a subset of the derived other-heap bound.
  // In the facility branch they remain necessary simultaneous payload only;
  // VM/cache/schema/fragmentation can still exhaust the same finite heap.
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
  let other = match selection {
    SqliteDemandBound(bytes) => {
      if bytes <= 0L {
        return Err(NativeStorageSqliteHeapMissing)
      }
      if bytes < result_copies {
        return Err(NativeStorageInsufficient)
      }
      bytes
    }
    SqliteFiniteFacility => result_copies
  }
  guard bounds.sqlite_external_execution_bytes is Some(external) &&
    external > 0L else {
    return Err(NativeStorageSqliteExternalMissing)
  }
  guard bounds.shared_control_bytes is Some(control) && control > 0L else {
    return Err(NativeStorageControlMissing)
  }
  let inspection = match
    native_storage_inspection_minimum(native_storage_page_bytes()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if read_demand is Some((_, native)) && native < inspection {
    return Err(NativeStorageInsufficient)
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
  // The facility branch checks only mandatory coexistence here. It neither
  // subtracts WAL from H nor fills an unknown demand with residual capacity.
  // Descriptor/VM/cache/result allocations must remain in the same heap with
  // no allocator fallback, enlargement or fresh reopen on exhaustion.
  // Inspection FDs remain separate Read children with their own cleanup ACKs.
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
  let sqlite_extent = match
    native_storage_page_round(
      profile.sqlite_heap_bytes,
      native_storage_page_bytes(),
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let crypto_extent = match
    native_storage_page_round(
      profile.crypto_heap_bytes,
      native_storage_page_bytes(),
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let sqlite = match native_storage_sum([sqlite_extent, external]) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // The one Crypto heap serves both original Libraries, all hooked OpenSSL
  // allocations, realloc overlap and cleanup. Native buffers remain separate.
  let (read, read_requirement, read_ceiling) = match bounds.read_selection {
    CommandReadDemand => {
      guard read_demand is Some((managed, native)) else {
        return Err(NativeStorageReadMissing)
      }
      let bytes = match native_storage_sum([crypto_extent, managed, native]) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      (bytes, CommandReadDemandPayload(bytes), None)
    }
    CommandReadFiniteFacility(bytes) => {
      let page = native_storage_page_bytes()
      if bytes <= 0L || page <= 0L || bytes % page != 0L {
        return Err(NativeStorageInvalidInput)
      }
      let minimum = match native_storage_sum([crypto_extent, inspection]) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      // This is necessary coexistence, not a complete managed/native demand
      // estimate. Crypto's contained heap is not charged a second time.
      if bytes < minimum || bytes > profile.read_budget.read_execution {
        return Err(NativeStorageInsufficient)
      }
      // Generic original bootstrap/workspace/read reservations remain separate.
      // No claim is enlarged or weakened to make the facility selection fit.
      let reserved = match
        native_storage_sum([
          profile.read_budget.bootstrap_execution,
          profile.read_budget.workspace_execution,
          profile.read_budget.read_execution,
        ]) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      if reserved > profile.read_domain_limits.execution_bytes {
        return Err(NativeStorageInsufficient)
      }
      (bytes, CommandReadNecessaryPayload(minimum), Some(bytes))
    }
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
    sqlite_payload_requirement: match selection {
      SqliteDemandBound(_) => SqliteDemandPayload(payload)
      SqliteFiniteFacility => SqliteNecessaryPayload(payload)
    },
    sqlite_execution_bytes: sqlite,
    read_execution_bytes: read,
    read_payload_requirement: read_requirement,
    read_facility_ceiling: read_ceiling,
    platform_selection: bounds.platform_selection,
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
