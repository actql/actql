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
  wasm_capacity : @resources.SharedCapacity
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
  materials : Map[Int, StoredMaterial]
  restorations : Map[Int, StoredRestoration]
  physical_starts : Map[Int, StoredPhysicalStart]
  native_sources : Map[Int, StoredNativeSourceConfiguration]
  native_attempts : Map[Int, StoredNativeAttempt]
  native_commands : Map[Int, StoredNativeCommand]
  computes : Map[Int, StoredNativeCompute]
  source_publications : Map[Int, StoredSourcePublication]
  publications : Map[Int, StoredPublication]
  tasks : Map[Int, StoredManagedTask]
  result_exports : Map[Int, StoredResultExport]
  result_chunks : Map[Int, StoredResultChunk]
  mut next_handle : Int
}

///|
let instance : Ref[Instance?] = Ref(None)

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
) -> Int {
  if nonce <= 0L || instance.val is Some(_) || max_wire_bytes > 1048576 {
    return -3
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
  match
    @buffers.open_pool_on_ledger(root, total_bytes, max_slots, max_wire_bytes) {
    Err(issue) => issue_code(issue)
    Ok(pool) => {
      instance.val = Some({
        nonce,
        pool,
        root,
        wasm_capacity,
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
        materials: {},
        restorations: {},
        physical_starts: {},
        native_sources: {},
        native_attempts: {},
        native_commands: {},
        computes: {},
        source_publications: {},
        publications: {},
        tasks: {},
        result_exports: {},
        result_chunks: {},
        next_handle: 1,
      })
      0
    }
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
  // Pending Native work and its downstream consumers must retire through
  // their existing stop/cleanup boundary before the Root can be closed.
  if !value.native_attempts.is_empty() ||
    !value.computes.is_empty() ||
    !value.source_publications.is_empty() ||
    !value.publications.is_empty() ||
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
    match @resources.close_shared_capacity(value.wasm_capacity) {
      Err(_) => return -10
      Ok(_) => value.runtime_closing = true
    }
  }
  if result == 0 {
    value.copies.clear()
    value.readers.clear()
    value.environments.clear()
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
    value.source_publications.clear()
    value.publications.clear()
    value.tasks.clear()
    value.result_exports.clear()
    value.result_chunks.clear()
  }
  result
}
