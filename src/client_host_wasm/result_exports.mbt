///|
/// Custody of existing checked Result preparation/export Owners. These
/// handles grant neither public Result access nor a terminal Run outcome.
priv struct StoredResultExport {
  task : Int
  result : Int
  mut invoked : Bool
  mut pending : Bool
  mut closing : Bool
  mut position : Int
  mut bridge : @execution.ManagedPublicationBridge[Int]?
  mut preparation : @host.CapturedClientResultTransformation?
  mut progress : (Bool, Int)?
  mut stream : @host.PublicationOutputExport?
  // Keep the original issued roots with the Result, independently of child
  // snapshot cancellation. Closing the Result releases this cache as well.
  mut publication : @local_run.LocalResultPublication?
  mut ended : Bool
  mut issue : StoredResultExportIssue?
}

///|
priv enum StoredResultExportIssue {
  Material
  Capacity
  Bridge(@execution.ManagedProducerBridgeIssue)
  Transform(@host.CapturedClientResultTransformationIssue)
  Export(@host.PublicationOutputExportIssue)
  Buffer(@buffers.BufferIssue)
}

///|
fn result_export_issue_code(issue : StoredResultExportIssue) -> Int {
  // Preserve typed Owner evidence. Only existing custody/capacity failures
  // have scalar projections; public reasons still require disclosure checks.
  match issue {
    Material => -32
    Capacity => -4
    Bridge(issue) => if issue is Closed { -5 } else { -32 }
    Transform(issue) => if issue is ForeignSelection { -2 } else { -32 }
    Export(issue) => if issue is InvalidState { -33 } else { -32 }
    Buffer(issue) => issue_code(issue)
  }
}

///|
pub fn reserve_result_export(nonce : Int64, task : Int, result : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(task) is Some(record) &&
    record.completed is Some(_) &&
    !record.closing &&
    !record.pending &&
    record.issue is None &&
    value.computes.get(record.compute)
    is Some({ host: Some(host), closing: false, .. }) &&
    @strategy.graph_result_task(
      @strategy.captured_dag_graph(@local_run.local_compute_run(host)),
      result,
    )
    is Some(selected_task) &&
    selected_task == record.task else {
    return -2
  }
  if value.closing || value.next_handle == 2147483647 {
    return -5
  }
  if value.result_exports.length() >= value.workspace_slots {
    return -4
  }
  let handle = value.next_handle
  value.result_exports[handle] = {
    task,
    result,
    invoked: false,
    pending: false,
    closing: false,
    position: 0,
    bridge: None,
    preparation: None,
    progress: None,
    stream: None,
    publication: None,
    ended: false,
    issue: None,
  }
  value.next_handle += 1
  handle
}

///|
/// One pre-reserved physical copy. A lost acknowledgement cannot advance the
/// exporter again: this issued chunk remains the only read invocation.
priv struct StoredResultChunk {
  result : Int
  physical_ticket : Int
  slot : @buffers.BufferSlot?
  reservation_issue : Int
  mut invoked : Bool
  mut pending : Bool
  mut produced : Bool
  mut final_chunk : Bool
  mut closing : Bool
}

///|
pub fn reserve_result_chunk(
  nonce : Int64,
  result : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.result_exports.get(result) is Some(record) &&
    record.stream is Some(_) else {
    return -2
  }
  if value.closing || record.closing || record.ended {
    return -5
  }
  if record.pending || record.issue is Some(_) {
    return -33
  }
  if physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.result_chunks
    .values()
    .any(chunk => {
      chunk.result == result || chunk.physical_ticket == physical_ticket
    }) ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.workspaces.values().any(pair => pair.0 == physical_ticket) ||
    value.native_commands
    .values()
    .any(command => command.physical_ticket == physical_ticket) {
    return -3
  }
  let handle = value.next_handle
  let (slot, reservation_issue) = match
    @buffers.reserve_output_buffer(value.pool, 65536, physical_copy_bytes, () => {
      physical_input_cleanup(physical_ticket) == 0
    }) {
    Ok(slot) => {
      value.copies[handle] = (slot, physical_ticket)
      (Some(slot), 0)
    }
    Err(issue) => (None, issue_code(issue))
  }
  value.result_chunks[handle] = {
    result,
    physical_ticket,
    slot,
    reservation_issue,
    invoked: false,
    pending: false,
    produced: false,
    final_chunk: false,
    closing: false,
  }
  value.next_handle += 1
  handle
}

///|
pub fn produce_result_chunk(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.result_chunks.get(handle) is Some(chunk) &&
    value.result_exports.get(chunk.result) is Some(record) &&
    record.stream is Some(stream) else {
    return -2
  }
  if value.closing || record.closing || chunk.closing {
    return -5
  }
  if chunk.produced {
    return 0
  }
  if chunk.reservation_issue != 0 {
    return chunk.reservation_issue
  }
  if chunk.invoked || record.pending {
    return -33
  }
  if record.issue is Some(issue) {
    return result_export_issue_code(issue)
  }
  guard chunk.slot is Some(slot) else { return -2 }
  chunk.invoked = true
  chunk.pending = true
  record.pending = true
  let next = match stream.next() {
    Err(issue) => Err(issue)
    Ok(Some(wire)) => Ok((wire, false))
    Ok(None) => stream.finish().map(wire => (wire, true))
  }
  match next {
    Err(issue) => record.issue = Some(Export(issue))
    Ok((wire, final_chunk)) =>
      match
        @buffers.supply_buffer_output(value.pool, slot, @utf8.encode(wire)) {
        Err(issue) => record.issue = Some(Buffer(issue))
        Ok(_) => {
          chunk.produced = true
          chunk.final_chunk = final_chunk
          record.ended = final_chunk
        }
      }
  }
  chunk.pending = false
  record.pending = false
  if record.issue is Some(issue) {
    result_export_issue_code(issue)
  } else {
    0
  }
}

///|
pub fn result_chunk_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.result_chunks.get(handle) is Some(chunk) &&
    chunk.produced &&
    chunk.slot is Some(slot) else {
    return -33
  }
  @buffers.buffer_length(value.pool, slot).unwrap_or(-33)
}

///|
/// Only the export Owner's successful finish produces the final marker. EOF
/// is not a publication receipt, Run success or permission to execute again.
pub fn result_chunk_final(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.result_chunks.get(handle) is Some(chunk) &&
    chunk.produced else {
    return -33
  }
  if chunk.final_chunk {
    1
  } else {
    0
  }
}

///|
pub fn close_result_chunk(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.result_chunks.get(handle) is Some(chunk) else {
    return -2
  }
  chunk.closing = true
  if chunk.pending {
    return -33
  }
  let retired = match chunk.slot {
    Some(slot) => status(@buffers.close_buffer(value.pool, slot))
    None =>
      if physical_input_cleanup(chunk.physical_ticket) == 0 {
        0
      } else {
        -9
      }
  }
  if retired == 0 {
    value.copies.remove(handle) |> ignore
    value.result_chunks.remove(handle) |> ignore
  }
  retired
}

///|
pub fn start_result_export(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.result_exports.get(handle) is Some(record) &&
    value.tasks.get(record.task)
    is Some(
      { completed: Some(completed), operations: Some(operations), compute, .. }
    ) &&
    value.computes.get(compute)
    is Some({ host: Some(host), closing: false, .. }) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if record.issue is Some(issue) {
    return result_export_issue_code(issue)
  }
  if record.bridge is Some(_) {
    return 0
  }
  if record.invoked {
    return -33
  }
  guard @local_run.local_compute_wasm_publication_limits(host) is Some(limits) else {
    record.issue = Some(Capacity)
    return -4
  }
  record.invoked = true
  record.pending = true
  match (operations.material)() {
    None => record.issue = Some(Material)
    Some(material) =>
      match
        @execution.prepare_managed_publication_bridge(
          completed,
          material,
          limits.max_rows,
          limits.values,
          100000,
          65536,
        ) {
        Ok(bridge) => record.bridge = Some(bridge)
        Err(issue) => record.issue = Some(Bridge(issue))
      }
  }
  record.pending = false
  if record.issue is Some(issue) {
    result_export_issue_code(issue)
  } else {
    0
  }
}

///|
/// Rows come from the exact retained producer; the existing bridge re-admits
/// them. The scalar position is a transfer cursor, not execution progress.
pub fn feed_result_export(nonce : Int64, handle : Int, quantum : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.result_exports.get(handle) is Some(record) &&
    record.bridge is Some(bridge) &&
    value.tasks.get(record.task) is Some(task) &&
    task.completed is Some(completed) &&
    task.operations is Some(operations) &&
    value.computes.get(task.compute) is Some({ host: Some(host), .. }) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if quantum <= 0 {
    return -3
  }
  if record.pending {
    return -33
  }
  if record.issue is Some(issue) {
    return result_export_issue_code(issue)
  }
  if record.preparation is Some(_) {
    return 0
  }
  guard @local_run.local_compute_wasm_publication_limits(host) is Some(limits) else {
    record.issue = Some(Capacity)
    return -4
  }
  let count = @execution.managed_completed_output_row_count(completed)
  for _ in 0..<quantum {
    record.pending = true
    if record.position == count {
      match @execution.finish_managed_publication_bridge(bridge) {
        Err(issue) => record.issue = Some(Bridge(issue))
        Ok(output) =>
          match
            @host.start_captured_managed_result_publication_export(
              @local_run.local_compute_run(host),
              record.result,
              completed,
              bridge,
              output,
              limits,
              max_pins=value.workspace_slots,
            ) {
            Ok(preparation) => record.preparation = Some(preparation)
            Err(issue) => record.issue = Some(Transform(issue))
          }
      }
    } else {
      match (operations.output_row)(record.position) {
        Err(_) => record.issue = Some(Material)
        Ok(row) =>
          match
            @execution.append_managed_publication_bridge_wire(bridge, row, {
              max_bytes: 65536,
              max_nodes: 10000,
              max_depth: 64,
              max_text_bytes: 65536,
            }) {
            Ok(_) => record.position += 1
            Err(issue) => record.issue = Some(Bridge(issue))
          }
      }
    }
    record.pending = false
    if record.issue is Some(issue) {
      return result_export_issue_code(issue)
    }
    if record.preparation is Some(_) {
      return 0
    }
  }
  0
}

///|
pub fn result_export_inputs_ready(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.result_exports.get(handle) is Some(record) else {
    return -2
  }
  if record.pending {
    return -33
  }
  if record.issue is Some(issue) {
    return result_export_issue_code(issue)
  }
  if record.preparation is Some(_) {
    0
  } else {
    -7
  }
}

///|
pub fn advance_result_export(nonce : Int64, handle : Int, quantum : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.result_exports.get(handle) is Some(record) &&
    record.preparation is Some(preparation) else {
    return -2
  }
  if value.closing || record.closing || record.stream is Some(_) {
    return -5
  }
  if quantum <= 0 {
    return -3
  }
  if record.pending {
    return -33
  }
  if record.issue is Some(issue) {
    return result_export_issue_code(issue)
  }
  record.pending = true
  match preparation.advance(quantum) {
    Ok(progress) => record.progress = Some(progress)
    Err(issue) => record.issue = Some(Transform(issue))
  }
  record.pending = false
  if record.issue is Some(issue) {
    result_export_issue_code(issue)
  } else {
    0
  }
}

///|
pub fn result_export_progress(nonce : Int64, handle : Int, field : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.result_exports.get(handle) is Some(record) &&
    !record.pending &&
    record.issue is None &&
    record.progress is Some((done, work)) else {
    return -33
  }
  match field {
    0 => if done { 1 } else { 0 }
    1 => work
    _ => -3
  }
}

///|
pub fn finish_result_export_preparation(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.result_exports.get(handle) is Some(record) &&
    record.preparation is Some(preparation) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if record.pending {
    return -33
  }
  if record.issue is Some(issue) {
    return result_export_issue_code(issue)
  }
  if record.stream is Some(_) {
    return 0
  }
  guard record.progress is Some((true, _)) else { return -7 }
  record.pending = true
  match preparation.finish() {
    Ok(stream) => record.stream = Some(stream)
    Err(issue) => record.issue = Some(Transform(issue))
  }
  record.pending = false
  if record.issue is Some(issue) {
    result_export_issue_code(issue)
  } else {
    0
  }
}

///|
pub fn close_result_export(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.result_exports.get(handle) is Some(record) else {
    return -2
  }
  record.closing = true
  if record.pending {
    return -33
  }
  if value.result_chunks.values().any(chunk => chunk.result == handle) {
    return -9
  }
  if value.publications
    .values()
    .any(publication => publication.results.contains(handle)) {
    return -9
  }
  record.pending = true
  if record.stream is Some(stream) {
    stream.cancel()
  }
  if record.preparation is Some(preparation) {
    preparation.cancel()
  }
  if record.bridge is Some(bridge) {
    @execution.close_managed_publication_bridge(bridge)
  }
  record.pending = false
  value.result_exports.remove(handle) |> ignore
  0
}

///|
/// Select the original Named Result's completed producer in Core. Python never
/// supplies a task number, copied completion flag or substitute Result mapping.
pub fn reserve_result_from_compute(
  nonce : Int64,
  compute : Int,
  result : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    !value.closing &&
    !value.runtime_closing &&
    value.computes.get(compute)
    is Some({ closing: false, host: Some(host), origin: SourceFree(_, _), .. }) &&
    value.run_configurations.get(current_configuration) is Some(current) &&
    compute_publication_preflight(value, compute) is Some((_, preflight)) else {
    return -2
  }
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return code
  }
  if !stored_preflight_current(value, preflight, current.account) {
    return -32
  }
  guard @strategy.graph_result_task(
      @strategy.captured_dag_graph(@local_run.local_compute_run(host)),
      result,
    )
    is Some(task) else {
    return -2
  }
  for handle, record in value.tasks {
    if record.compute == compute && record.task == task {
      return reserve_result_export(nonce, handle, result)
    }
  }
  -2
}
