///|
fn physical_input_byte(input : Int, index : Int) -> Int = "actql_host" "input_byte"

///|
fn physical_input_cleanup(input : Int) -> Int = "actql_host" "input_cleanup"

///|
fn physical_reader_stop(input : Int, reader : Int) -> Int = "actql_host" "reader_stop"

///|
fn physical_native_settled(handle : Int) -> Int = "actql_host" "native_settled"

///|
fn physical_native_stopped(handle : Int) -> Int = "actql_host" "native_stopped"

///|
fn physical_native_cleaned(handle : Int) -> Int = "actql_host" "native_cleaned"

///|
/// Private instance handles are never Client wire refs or execution authority.
priv struct Instance {
  nonce : Int64
  pool : @buffers.BufferPool
  root : @resources.Ledger
  installed_sequences : InstalledSequenceContracts
  wasm_capacity : @resources.SharedCapacity
  host_capacity : @resources.SharedCapacity?
  workspaces : Map[Int, (Int, @buffers.WorkspaceLoan)]
  workspace_slots : Int
  mut runtime_closing : Bool
  mut closing : Bool
  copies : Map[Int, (@buffers.BufferSlot, Int)]
  readers : Map[Int, @buffers.BufferBorrow]
  environments : Map[Int, StoredEnvironment]
  preparations : Map[Int, StoredPreparation]
  run_configurations : Map[Int, StoredRunConfiguration]
  runs : Map[Int, StoredRun]
  submissions : Map[Int, StoredSubmissionProjection]
  bootstraps : Map[Int, StoredBootstrap]
  client_checks : Map[Int, StoredClientCheck]
  host_currents : Map[Int, StoredHostCurrent]
  original_metadata : Map[Int, StoredOriginalMetadata]
  journal_observations : Map[Int, StoredJournalObservation]
  materials : Map[Int, StoredMaterial]
  restorations : Map[Int, StoredRestoration]
  physical_starts : Map[Int, StoredPhysicalStart]
  native_sources : Map[Int, StoredNativeSourceConfiguration]
  native_attempts : Map[Int, StoredNativeAttempt]
  native_commands : Map[Int, StoredNativeCommand]
  computes : Map[Int, StoredNativeCompute]
  run_invocations : Map[Int, StoredRunInvocation]
  publication_preflights : Map[Int, StoredPublicationPreflight]
  publishers : Map[Int, StoredPublisher]
  publications : Map[Int, StoredPublication]
  result_bindings : Map[Int, StoredResultBinding]
  commit_exports : Map[Int, StoredPublicationCommitExport]
  payload_requests : Map[Int, StoredPayloadRequest]
  payload_chunks : Map[Int, StoredPayloadChunk]
  payload_records : Map[Int, StoredPayloadRecord]
  payload_reservations : Map[Int, StoredPayloadReservation]
  payload_writings : Map[Int, StoredPayloadWriting]
  payload_allocations : Map[Int, StoredPayloadAllocation]
  payload_bindings : Map[Int, StoredPayloadBinding]
  payload_names : Map[Int, StoredPayloadNames]
  tasks : Map[Int, StoredManagedTask]
  result_exports : Map[Int, StoredResultExport]
  result_chunks : Map[Int, StoredResultChunk]
  mut next_handle : Int
}

///|
/// Per-open immutable installed DATA. The original registry wire remains only
/// for the ABI selection check; every Run receives the same admitted token.
priv struct InstalledSequenceContracts {
  registry : String
  contracts : @local_host.ClientInstalledSequenceContracts
}

///|
fn prepare_product_sequence_contracts() -> InstalledSequenceContracts? {
  let assets = @host.client_local_product_assets()
  guard @local_host.prepare_installed_sequence_contracts(
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    )
    is Ok(contracts) else {
    return None
  }
  Some({ registry: assets.registry, contracts, })
}

///|
let instance : Ref[Instance?] = Ref(None)

///|
// Retain original initialization custody before the first Host admission.
// Failure never falls through to a scalar-created Root or repeats admission.
let live_initialization_attempt : Ref[Int64?] = Ref(None)

///|
let live_initialization : Ref[@resources.ImportedChildLedger?] = Ref(None)

///|
let live_initial_root : Ref[
  (@resources.Ledger, @resources.SharedCapacity, @resources.SharedCapacity)?,
] = Ref(None)

///|
let live_initial_issue : Ref[@resources.ImportedChildLedgerIssue?] = Ref(None)

///|
fn selected(nonce : Int64) -> Instance? {
  match instance.val {
    Some(value) if value.nonce == nonce => Some(value)
    _ => None
  }
}

///|
fn issue_code(issue : @buffers.BufferIssue) -> Int {
  match issue {
    ForeignOwner => -1
    InvalidLimits => -3
    Capacity | Resource(RetentionLimit | ExecutionLimit) => -4
    Closed => -5
    InvalidPosition => -6
    InvalidByte => -12
    Incomplete => -7
    Input({ issue: InputLimit | NodeLimit | DepthLimit, .. }) => -11
    Input(_) => -8
    CleanupPending => -9
    Resource(_) => -10
  }
}

///|
fn status(result : Result[Unit, @buffers.BufferIssue]) -> Int {
  match result {
    Ok(_) => 0
    Err(issue) => issue_code(issue)
  }
}

///|
/// Bind only the already issued original Root and its existing capacities.
/// Both raw diagnostics and the live-child constructor use this same state.
fn install_buffer_instance(
  nonce : Int64,
  root : @resources.Ledger,
  wasm_capacity : @resources.SharedCapacity,
  host_capacity : @resources.SharedCapacity?,
  pool : @buffers.BufferPool,
  max_slots : Int,
  installed_sequences : InstalledSequenceContracts,
) -> Int {
  instance.val = Some({
    nonce,
    pool,
    root,
    installed_sequences,
    wasm_capacity,
    host_capacity,
    workspaces: {},
    workspace_slots: max_slots,
    runtime_closing: false,
    closing: false,
    copies: {},
    readers: {},
    environments: {},
    preparations: {},
    run_configurations: {},
    runs: {},
    submissions: {},
    bootstraps: {},
    client_checks: {},
    host_currents: {},
    original_metadata: {},
    journal_observations: {},
    materials: {},
    restorations: {},
    physical_starts: {},
    native_sources: {},
    native_attempts: {},
    native_commands: {},
    computes: {},
    run_invocations: {},
    publication_preflights: {},
    publishers: {},
    publications: {},
    result_bindings: {},
    commit_exports: {},
    payload_requests: {},
    payload_chunks: {},
    payload_records: {},
    payload_reservations: {},
    payload_writings: {},
    payload_allocations: {},
    payload_bindings: {},
    payload_names: {},
    tasks: {},
    result_exports: {},
    result_chunks: {},
    next_handle: 1,
  })
  0
}

///|
fn imported_child_issue_code(
  issue : @resources.ImportedChildLedgerIssue,
) -> Int {
  match issue {
    Unavailable => -42
    Unknown => -41
    ForeignOriginal => -1
    AlreadyConsumed => -2
    InvalidOriginal => -3
    Resource(_) => -10
  }
}

///|
fn retain_live_issue(issue : @resources.ImportedChildLedgerIssue) -> Int {
  live_initial_issue.val = Some(issue)
  imported_child_issue_code(issue)
}

///|
/// Fixed Host imports provide the same original child allowance. No scalar
/// limits or new parent reservation enter this constructor. Partial state is
/// retained even if admission, pool setup or its response is lost.
#export_name("actql_buffer_open_live")
pub fn open_live(
  nonce : Int64,
  total_bytes : Int64,
  max_slots : Int,
  max_wire_bytes : Int,
) -> Int {
  if nonce <= 0L ||
    live_initialization_attempt.val is Some(_) ||
    instance.val is Some(_) ||
    total_bytes <= 0L ||
    max_slots < 1 ||
    max_slots > 1024 ||
    max_wire_bytes < 1 ||
    max_wire_bytes > 1048576 {
    return -3
  }
  guard prepare_product_sequence_contracts() is Some(installed_sequences) else {
    return -31
  }
  live_initialization_attempt.val = Some(nonce)
  let frame = match @resources.prepare_imported_child_ledger(nonce) {
    Err(issue) => return retain_live_issue(issue)
    Ok(value) => value
  }
  live_initialization.val = Some(frame)
  match @resources.start_imported_child_ledger(frame) {
    Err(issue) => return retain_live_issue(issue)
    Ok(_) => ()
  }
  let (root, wasm_capacity, host_capacity) = match
    @resources.take_imported_child_ledger(frame) {
    Err(issue) => return retain_live_issue(issue)
    Ok(value) => value
  }
  live_initial_root.val = Some((root, wasm_capacity, host_capacity))
  match
    @buffers.open_pool_on_imported_vm_capacity(
      frame, root, wasm_capacity, total_bytes, max_slots, max_wire_bytes,
    ) {
    Err(issue) => issue_code(issue)
    Ok(pool) =>
      install_buffer_instance(
        nonce,
        root,
        wasm_capacity,
        Some(host_capacity),
        pool,
        max_slots,
        installed_sequences,
      )
  }
}

///|
/// Explicit outer-operation flush, never an automatic RPC per byte getter.
/// The Resource Owner retains the original snapshot after a failed/lost ACK.
#export_name("actql_buffer_report_live")
pub fn report_live(nonce : Int64) -> Int {
  guard live_initialization_attempt.val is Some(original) && original == nonce else {
    return -1
  }
  guard live_initialization.val is Some(frame) else { return -42 }
  if live_initial_root.val is None && live_initial_issue.val is Some(issue) {
    return imported_child_issue_code(issue)
  }
  match @resources.report_imported_child_ledger(frame) {
    Err(issue) => retain_live_issue(issue)
    Ok(_) => 0
  }
}

///|
#export_name("actql_buffer_stop_live")
pub fn stop_live(nonce : Int64) -> Int {
  guard live_initialization_attempt.val is Some(original) && original == nonce else {
    return -1
  }
  guard live_initialization.val is Some(frame) else { return -42 }
  match @resources.stop_imported_child_ledger(frame) {
    Err(issue) => retain_live_issue(issue)
    Ok(_) => 0
  }
}

///|
/// Installed physical configuration binds one fresh instance. Reopening does
/// not replace its nonce, revive handles, or grow its admitted copy allowance.
#export_name("actql_buffer_open")
pub fn open(
  nonce : Int64,
  total_bytes : Int64,
  max_slots : Int,
  max_wire_bytes : Int,
  planning_work : Int,
  attempts : Int,
  holdings : Int,
  transfer_bytes : Int64,
  retained_bytes : Int64,
  execution_bytes : Int64,
  host_capacity_bytes : Int64,
) -> Int {
  if nonce <= 0L ||
    live_initialization_attempt.val is Some(_) ||
    instance.val is Some(_) ||
    max_wire_bytes > 1048576 ||
    host_capacity_bytes < 0L {
    return -3
  }
  guard prepare_product_sequence_contracts() is Some(installed_sequences) else {
    return -31
  }
  let root = match
    @resources.create_ledger({
      planning_work,
      attempts,
      holdings,
      transfer_bytes,
      retained_bytes,
      execution_bytes,
    }) {
    Err(_) => return -3
    Ok(root) => root
  }
  // Fixed instance memory is retained through physical Store destruction.
  // This reservation is not returned by logical Run or transfer-pool close.
  let wasm_capacity = match
    @resources.reserve_shared_capacity(root, 16777216L) {
    Err(_) => return -4
    Ok(capacity) => capacity
  }
  // An explicit backed Host may project its separately held lifetime onto
  // this Root. This reservation is allowance accounting, not an allocation
  // or evidence about earlier runtime initialization.
  let host_capacity = if host_capacity_bytes == 0L {
    // Ordinary platform-managed initialization owns no whole-runtime arena.
    // Real VM/transfer allowances remain above/below; an imported VM or native
    // holding still uses its distinct original-backed entrance.
    None
  } else {
    match @resources.reserve_shared_capacity(root, host_capacity_bytes) {
      Err(_) => return -4
      Ok(capacity) => Some(capacity)
    }
  }
  match
    @buffers.open_pool_on_ledger(root, total_bytes, max_slots, max_wire_bytes) {
    Err(issue) => issue_code(issue)
    Ok(pool) =>
      install_buffer_instance(
        nonce, root, wasm_capacity, host_capacity, pool, max_slots, installed_sequences,
      )
  }
}

///|
#export_name("actql_buffer_reserve")
pub fn reserve(
  nonce : Int64,
  physical_input : Int,
  wire_bytes : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  if value.closing {
    return -5
  }
  if physical_input <= 0 ||
    value.next_handle == 2147483647 ||
    value.copies.values().any(pair => pair.1 == physical_input) ||
    value.native_commands
    .values()
    .any(command => command.physical_ticket == physical_input) ||
    value.result_chunks
    .values()
    .any(chunk => chunk.physical_ticket == physical_input) ||
    value.workspaces.values().any(pair => pair.0 == physical_input) {
    return -3
  }
  match
    @buffers.reserve_buffer(value.pool, wire_bytes, physical_copy_bytes, () => {
      physical_input_cleanup(physical_input) == 0
    }) {
    Err(issue) => issue_code(issue)
    Ok(slot) => {
      let handle = value.next_handle
      value.next_handle += 1
      value.copies[handle] = (slot, physical_input)
      handle
    }
  }
}

///|
#export_name("actql_buffer_fill")
pub fn fill(nonce : Int64, handle : Int, start : Int, count : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.copies.get(handle) is Some((slot, physical_input)) else {
    return -2
  }
  status(
    @buffers.fill_buffer(value.pool, slot, start, count, index => {
      let byte = physical_input_byte(physical_input, index)
      if byte < 0 || byte > 255 {
        None
      } else {
        Some(byte.to_byte())
      }
    }),
  )
}

///|
#export_name("actql_buffer_seal")
pub fn seal(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.copies.get(handle) is Some((slot, _)) else { return -2 }
  status(@buffers.seal_buffer(value.pool, slot, 16384, 64))
}

///|
#export_name("actql_buffer_byte")
pub fn byte(nonce : Int64, handle : Int, index : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.copies.get(handle) is Some((slot, _)) else { return -2 }
  match @buffers.buffer_byte(value.pool, slot, index) {
    Some(value) => value.to_int()
    None => -5
  }
}

///|
#export_name("actql_buffer_borrow")
pub fn borrow(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.copies.get(handle) is Some((slot, physical_input)) else {
    return -2
  }
  if value.next_handle == 2147483647 {
    return -4
  }
  let reader = value.next_handle
  match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical_input, reader) == 0
    }) {
    Err(issue) => issue_code(issue)
    Ok(borrow) => {
      value.next_handle += 1
      value.readers[reader] = borrow
      reader
    }
  }
}

///|
#export_name("actql_buffer_return")
pub fn return_reader(nonce : Int64, reader : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.readers.get(reader) is Some(borrow) else { return -2 }
  let result = status(@buffers.return_buffer_borrow(value.pool, borrow))
  if result == 0 {
    value.readers.remove(reader) |> ignore
  }
  result
}

///|
#export_name("actql_buffer_close")
pub fn close(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.copies.get(handle) is Some((slot, _)) else { return -2 }
  if value.bootstraps.contains(handle) ||
    value.bootstraps.values().any(child => child.input == handle) ||
    value.host_currents.contains(handle) ||
    value.host_currents.values().any(child => child.input == handle) ||
    value.original_metadata.contains(handle) ||
    value.original_metadata.values().any(child => child.input == handle) ||
    value.journal_observations.contains(handle) ||
    value.journal_observations.values().any(child => child.material == handle) {
    return -9
  }
  let result = status(@buffers.close_buffer(value.pool, slot))
  if result == 0 {
    value.copies.remove(handle) |> ignore
  }
  result
}

///|
#export_name("actql_buffer_allocated")
pub fn allocated(nonce : Int64) -> Int64 {
  match selected(nonce) {
    Some(value) => @buffers.buffer_pool_usage(value.pool).allocated
    None => -1L
  }
}

///|
#export_name("actql_buffer_reserved")
pub fn reserved(nonce : Int64) -> Int64 {
  match selected(nonce) {
    Some(value) => @buffers.buffer_pool_reserved(value.pool)
    None => -1L
  }
}

///|
#export_name("actql_buffer_close_pool")
pub fn close_pool(nonce : Int64) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  value.closing = true
  if live_initialization.val is Some(_) {
    let stopped = stop_live(nonce)
    if stopped != 0 {
      return stopped
    }
  }
  // Pending Native work and its downstream consumers must retire through
  // their existing stop/cleanup boundary before the Root can be closed.
  if !value.client_checks.is_empty() ||
    !value.bootstraps.is_empty() ||
    !value.host_currents.is_empty() ||
    !value.original_metadata.is_empty() ||
    !value.journal_observations.is_empty() ||
    !value.native_attempts.is_empty() ||
    !value.computes.is_empty() ||
    !value.run_invocations.is_empty() ||
    !value.publication_preflights.is_empty() ||
    !value.publishers.is_empty() ||
    !value.publications.is_empty() ||
    !value.result_bindings.is_empty() ||
    !value.commit_exports.is_empty() ||
    !value.payload_requests.is_empty() ||
    !value.payload_chunks.is_empty() ||
    !value.payload_records.is_empty() ||
    !value.payload_reservations.is_empty() ||
    !value.payload_writings.is_empty() ||
    !value.payload_allocations.is_empty() ||
    !value.payload_bindings.is_empty() ||
    !value.payload_names.is_empty() ||
    !value.tasks.is_empty() ||
    !value.result_exports.is_empty() ||
    !value.result_chunks.is_empty() {
    return -9
  }
  let result = status(@buffers.close_pool(value.pool))
  if result != 0 {
    return result
  }
  if value.workspaces.length() != 0 {
    return -9
  }
  if !value.runtime_closing {
    if live_initial_root.val is None {
      if value.host_capacity is Some(capacity) {
        match @resources.close_shared_capacity(capacity) {
          Err(_) => return -10
          Ok(_) => ()
        }
      }
      match @resources.close_shared_capacity(value.wasm_capacity) {
        Err(_) => return -10
        Ok(_) => ()
      }
    }
    // A live child's fixed VM/Host tokens remain paid until the original
    // parent observes physical retirement. Logical close cannot return them.
    value.runtime_closing = true
  }
  if result == 0 {
    value.copies.clear()
    value.readers.clear()
    value.environments.clear()
    value.client_checks.clear()
    value.preparations.clear()
    value.run_configurations.clear()
    value.runs.clear()
    value.submissions.clear()
    value.materials.clear()
    value.restorations.clear()
    value.physical_starts.clear()
    value.native_sources.clear()
    value.native_attempts.clear()
    value.native_commands.clear()
    value.computes.clear()
    value.run_invocations.clear()
    value.publication_preflights.clear()
    value.publishers.clear()
    value.publications.clear()
    value.result_bindings.clear()
    value.commit_exports.clear()
    value.payload_requests.clear()
    value.payload_chunks.clear()
    value.payload_records.clear()
    value.payload_reservations.clear()
    value.payload_writings.clear()
    value.payload_allocations.clear()
    value.payload_bindings.clear()
    value.payload_names.clear()
    value.tasks.clear()
    value.result_exports.clear()
    value.result_chunks.clear()
  }
  result
}
