///|
// Optional read-only metadata on the existing adopted Request. This is a
// borrower, not a new Run, Ledger, admission issuer or execution scheduler.
struct ClientLogicalObservation {
  cleanup : ClientOriginalExplanationCapture
  mut original : @publication_host.ClientStructuralExplanationOriginal?
  mut attached : @strategy.CapturedDAG?
  record_bytes : Int64
  bytes : Int
  nodes : Int
  depth : Int
  projection_nodes : Int
  mut pending : Int
  mut record_peak : Int
  mut reading : Bool
  mut closing : Bool
}

///|
// Only the existing queue/pending delivery holds this token. Clear its copied
// key before decreasing the SAME session's outstanding count. Return is not a
// physical-stop, application-retention or delivery acknowledgement.
struct ClientLogicalObservationRecord {
  mut original : (ClientLogicalObservation, String?)?
  mut captured : Bool
  phase : @strategy.CapturedTaskBoundaryPhase
}

///|
pub(all) enum ClientLogicalObservationIssue {
  LogicalObservationForeignOriginal
  LogicalObservationReturned
  LogicalObservationWorkActive
  LogicalObservationCleanupPending
  LogicalObservationConstructionUnavailable
  LogicalObservationCapture(ClientOriginalExplanationCaptureIssue)
  LogicalObservationCapacity(@resources.PreparationCapacityIssue)
  LogicalObservationBoundary(@strategy.CapturedTaskBoundaryIssue)
  LogicalObservationProjection(@publication_host.ClientLogicalTaskBoundaryIssue)
  LogicalObservationCleanup(
    ClientLogicalObservationIssue,
    ClientLogicalObservation
  )
}

///|
// Session(H1/R3/W9), original Some(H1/R1/W1), attached Some+pair(H2/R3/W1),
// retained-original cell and its Some(H2/R2/W1), and eight complete two-reference
// result/current/error shells across quotation, capture and cleanup(H8/R16/W8).
// The Node consumer adds its session/method/control records, ten fixed closure
// environments and bounded read DATA tuple (H24/R112/W32); no new normal root slot.
// Sequential alternatives are conservatively co-counted. Controls remain charged until the existing parent retires;
// returning a sibling borrow does not shrink that parent's running peak.
let logical_observation_control_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 38L,
    reference_slots: 137L,
    scalar_words: 52L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
fn logical_observation_original(
  value : ClientLogicalObservation,
  delivering? : Bool = false,
) -> (
  @publication_host.PreparedClientProgram,
  @publication_host.ClientCompiledRun,
)? {
  if (!delivering && value.closing) || value.original is None {
    return None
  }
  guard original_explanation_capture_body(value.cleanup) is Some(prepared) &&
    value.cleanup.original is Some((_, original, compiled)) &&
    physical_equal(original, prepared) else {
    return None
  }
  if (!delivering && value.closing) || value.original is None {
    return None
  }
  Some((prepared, compiled))
}

///|
// Immutable body correspondence alone is not physical currentness. After an
// Host authority or queued-delivery boundary, consume the existing admitted
// Run's actual Resource current callback, then recheck its SAME originals.
fn logical_observation_current(
  value : ClientLogicalObservation,
  delivering? : Bool = false,
) -> (
  @publication_host.PreparedClientProgram,
  @publication_host.ClientCompiledRun,
)? {
  guard logical_observation_original(value, delivering~) is Some(_) &&
    value.cleanup.original is Some((run, _, _)) &&
    require_installed_managed_run(run) is Ok(_) else {
    return None
  }
  logical_observation_original(value, delivering~)
}

///|
fn reserve_logical_observation(
  value : ClientLogicalObservation,
  records : Int,
) -> Result[Unit, ClientLogicalObservationIssue] {
  guard logical_observation_original(value) is Some((prepared, _)) else {
    return Err(LogicalObservationForeignOriginal)
  }
  if records < 0 {
    return Err(LogicalObservationConstructionUnavailable)
  }
  // Later Host/publication phases share this original reservation and may
  // have grown it. Add only a NEW simultaneous-record peak to its CURRENT
  // extent; a stale snapshot/max would overlap or erase that sibling quote.
  let (current_retained, current_execution) = match
    @resources.preparation_body_borrow_reserved_extents(value.cleanup.holder) {
    Err(issue) => return Err(LogicalObservationCapacity(issue))
    Ok(extents) => extents
  }
  let extra_records = Int::max(0, records - value.record_peak)
  let fixed = if value.record_peak == 0 {
    @strategy.captured_logical_observation_construction_bytes()
  } else {
    0L
  }
  guard @execution.checked_preparation_add_product(
      fixed,
      extra_records.to_int64(),
      value.record_bytes,
    )
    is Some(extra) &&
    @execution.checked_preparation_add_product(current_retained, extra, 1L)
    is Some(r) &&
    @execution.checked_preparation_add_product(current_execution, extra, 1L)
    is Some(e) else {
    return Err(LogicalObservationConstructionUnavailable)
  }
  match
    @resources.reserve_preparation_publication_phase(
      value.cleanup.holder,
      prepared,
      r,
      e,
    ) {
    Err(issue) => return Err(LogicalObservationCapacity(issue))
    Ok(_) => ()
  }
  guard logical_observation_original(value) is Some((current, _)) &&
    physical_equal(current, prepared) else {
    return Err(LogicalObservationForeignOriginal)
  }
  value.cleanup.held_retained = r
  value.cleanup.held_execution = e
  value.record_peak = Int::max(value.record_peak, records)
  Ok(())
}

///|
/// Explicit same-Request preparation before Source/work. The existing working
/// parent is grown before even the retention cell or quotation constructors.
/// This creates no observation/control permission or public capability.
pub fn prepare_installed_logical_observation(
  run : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[ClientLogicalObservation, ClientLogicalObservationIssue] {
  if run.source_free_opening {
    return Err(LogicalObservationWorkActive)
  }
  let holder = match managed_run_publication_body(run, prepared) {
    Err(_) => return Err(LogicalObservationForeignOriginal)
    Ok(value) => value
  }
  let (r, e) = match
    @resources.preparation_body_borrow_reserved_extents(holder) {
    Err(issue) => return Err(LogicalObservationCapacity(issue))
    Ok(value) => value
  }
  let entry = explanation_capture_entry_control_bytes +
    logical_observation_control_bytes
  guard @execution.checked_preparation_add_product(r, entry, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e, entry, 1L) is Some(e) else {
    return Err(LogicalObservationConstructionUnavailable)
  }
  run.source_free_opening = true
  let result = match
    @resources.reserve_preparation_publication_phase(holder, prepared, r, e) {
    Err(issue) => Err(LogicalObservationCapacity(issue))
    Ok(_) =>
      construct_installed_logical_observation(
        run, prepared, compiled, definition, bytes, nodes, depth,
      )
  }
  run.source_free_opening = false
  result
}

///|
fn construct_installed_logical_observation(
  run : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[ClientLogicalObservation, ClientLogicalObservationIssue] {
  // Original Plan/Facts use the existing admitted Plan read profile. The
  // small closed logical_step_key contains fixed names, two 71-byte CIDs and
  // bounded ordinals; its event emitter has a separate fixed envelope. Event
  // size never becomes a new parser/Plan limit or a grant of more resources.
  let key_bytes = 4096
  let key_nodes = 128
  let key_depth = 16
  guard compilation_canonical_emitter_layout(key_depth) is Some(emitter) &&
    @encode.text_writer_construction_inventory(key_bytes, key_nodes, key_depth)
    is Some(writer) else {
    return Err(LogicalObservationConstructionUnavailable)
  }
  // One emitted key and its record/control carrier. Canonical children are
  // borrowed from the same compiler original; there is no parser or new ID.
  guard @execution.preparation_representation_cost({
      // Record/original Some/pair, optional copied key, output Result, three
      // DATA getter alternatives and both original/current post-callback
      // tuple/Some/Result carriers are conservatively co-counted (H16/R26/W16).
      // Node queue custody: DATA detail/attributes/record/item; fixed delivery,
      // release/current closure environments; Promise/reaction/Set entry and
      // One immutable read/delivery DATA tuple and current helper. No policy
      // decision cache. Alternatives are co-counted (H33/R131/W49).
      record_headers: emitter.record_headers + writer.record_headers + 49L,
      reference_slots: emitter.reference_slots + writer.reference_slots + 157L,
      scalar_words: emitter.scalar_words + writer.scalar_words + 65L,
      // Original key, complete worst-case JSON escape expansion and retained
      // envelope coexist BEFORE stringify/SQLite operands/queue insertion.
      // No application-owned arbitrary callback retention is certified here.
      owned_utf16_units: emitter.owned_utf16_units +
      writer.owned_utf16_units +
      8L * key_bytes.to_int64() +
      4096L,
      owned_wire_bytes: emitter.owned_wire_bytes +
      6L * key_bytes.to_int64() +
      4096L,
    })
    is Some(record_bytes) else {
    return Err(LogicalObservationConstructionUnavailable)
  }
  let retained = Ref(None)
  let capture = match
    capture_installed_original_explanation(
      run,
      prepared,
      compiled,
      definition,
      bytes,
      nodes,
      depth,
      retain_original=Some(retained),
    ) {
    Err(issue) => return Err(LogicalObservationCapture(issue))
    Ok(value) => value
  }
  let value : ClientLogicalObservation = {
    cleanup: capture,
    original: retained.val,
    attached: None,
    record_bytes,
    bytes: key_bytes,
    nodes: key_nodes,
    depth: key_depth,
    projection_nodes: nodes,
    pending: 0,
    record_peak: 0,
    reading: false,
    closing: false,
  }
  match reserve_logical_observation(value, 1) {
    Ok(_) => Ok(value)
    Err(primary) => {
      // No lower hook or output record exists yet. Drop the new semantic
      // context before the original sibling can return its parent role.
      value.original = None
      match return_installed_original_explanation_capture(value.cleanup) {
        Ok(_) => Err(primary)
        Err(_) => Err(LogicalObservationCleanup(primary, value))
      }
    }
  }
}

///|
/// A failed constructor's original cleanup token, never a reconstructed loan.
pub fn failed_logical_observation_cleanup(
  issue : ClientLogicalObservationIssue,
) -> ClientLogicalObservation? {
  match issue {
    LogicalObservationCleanup(_, value) => Some(value)
    _ => None
  }
}

///|
/// Attach only the existing adopted Run's actual issued Compute. This cannot
/// import another bare DAG that happens to share SQL, a graph or a Ledger.
pub fn attach_installed_logical_observation(
  value : ClientLogicalObservation,
  captured : @strategy.CapturedDAG,
) -> Result[Unit, ClientLogicalObservationIssue] {
  if value.reading {
    return Err(LogicalObservationWorkActive)
  }
  value.reading = true
  let result = attach_logical_observation_original(value, captured)
  value.reading = false
  result
}

///|
fn attach_logical_observation_original(
  value : ClientLogicalObservation,
  captured : @strategy.CapturedDAG,
) -> Result[Unit, ClientLogicalObservationIssue] {
  guard logical_observation_current(value) is Some((prepared, _)) &&
    value.cleanup.original is Some((owner, _, _)) &&
    owner.ledger is Some(ledger) &&
    physical_equal(ledger, @strategy.captured_dag_ledger(captured)) &&
    owner.source_free_captured is Some(actual) &&
    physical_equal(actual, captured) &&
    physical_equal(
      @strategy.captured_dag_graph(captured),
      @publication_host.prepared_client_graph(prepared),
    ) else {
    return Err(LogicalObservationForeignOriginal)
  }
  if value.attached is Some(original) {
    return if physical_equal(original, captured) {
      Ok(())
    } else {
      Err(LogicalObservationForeignOriginal)
    }
  }
  // Retain the exact Run before its lower setup may leave pending cleanup.
  value.attached = Some(captured)
  match
    @strategy.prepare_captured_task_boundary_hooks(
      captured,
      @publication_host.prepared_client_graph(prepared),
      @strategy.captured_dag_strategy_revision(captured),
    ) {
    Err(issue) => Err(LogicalObservationBoundary(issue))
    Ok(_) =>
      if logical_observation_original(value) is Some(_) {
        Ok(())
      } else {
        Err(LogicalObservationForeignOriginal)
      }
  }
}

///|
pub fn read_installed_logical_observation(
  value : ClientLogicalObservation,
  phase : @strategy.CapturedTaskBoundaryPhase,
) -> Result[ClientLogicalObservationRecord, ClientLogicalObservationIssue] {
  let record = match begin_installed_logical_observation(value, phase) {
    Err(issue) => return Err(issue)
    Ok(record) => record
  }
  match capture_installed_logical_observation_record(record) {
    Ok(_) => Ok(record)
    Err(primary) => {
      return_logical_observation_record(record)
      Err(primary)
    }
  }
}

///|
/// Reserve the complete read/delivery overlap BEFORE the Host's Account and
/// egress callbacks. This creates no projected fact or observation permission.
pub fn begin_installed_logical_observation(
  value : ClientLogicalObservation,
  phase : @strategy.CapturedTaskBoundaryPhase,
) -> Result[ClientLogicalObservationRecord, ClientLogicalObservationIssue] {
  if value.reading {
    return Err(LogicalObservationWorkActive)
  }
  if value.pending == 2147483647 {
    return Err(LogicalObservationConstructionUnavailable)
  }
  guard logical_observation_original(value) is Some(_) &&
    value.attached is Some(_) else {
    return Err(LogicalObservationForeignOriginal)
  }
  if value.attached is Some(captured) &&
    @strategy.captured_task_boundary_cleanup_pending(captured) {
    // Do not create another lower fork while an earlier original return is
    // pending. The same lower Owner retries its bounded existing read/fork.
    return Err(LogicalObservationCleanupPending)
  }
  value.reading = true
  let result = match reserve_logical_observation(value, value.pending + 1) {
    Err(issue) => Err(issue)
    Ok(_) => {
      value.pending += 1
      Ok({ original: Some((value, None)), captured: false, phase, })
    }
  }
  value.reading = false
  result
}

///|
fn construct_logical_observation_key(
  value : ClientLogicalObservation,
  phase : @strategy.CapturedTaskBoundaryPhase,
) -> Result[String?, ClientLogicalObservationIssue] {
  guard logical_observation_current(value) is Some((prepared, compiled)) &&
    value.original is Some(original) &&
    value.attached is Some(captured) else {
    return Err(LogicalObservationForeignOriginal)
  }
  let projection = match
    @publication_host.read_client_logical_task_boundary(
      original,
      compiled,
      prepared,
      captured,
      phase,
      value.projection_nodes,
    ) {
    Err(issue) => return Err(LogicalObservationProjection(issue))
    Ok(value) => value
  }
  let wire = match projection {
    NotProjected(_) => None
    Projected(boundary) => {
      let output = @publication_host.client_logical_task_boundary_key_json(
        boundary,
        compiled,
        prepared,
        value.bytes,
        value.nodes,
        value.depth,
      )
      let returned = @publication_host.return_client_logical_task_boundary(
        boundary,
      )
      match (output, returned) {
        (Err(primary), _) => return Err(LogicalObservationProjection(primary))
        (_, Err(issue)) => return Err(LogicalObservationProjection(issue))
        (Ok(wire), Ok(_)) => Some(wire)
      }
    }
  }
  guard logical_observation_original(value) is Some((current, _)) &&
    physical_equal(current, prepared) else {
    return Err(LogicalObservationForeignOriginal)
  }
  Ok(wire)
}

///|
/// Invoke only after the SAME owned Host read has authorized disclosure. The
/// Host rechecks authority/current after this original Core projection too.
pub fn capture_installed_logical_observation_record(
  record : ClientLogicalObservationRecord,
) -> Result[Unit, ClientLogicalObservationIssue] {
  guard record.original is Some((value, _)) && !record.captured else {
    return Err(LogicalObservationReturned)
  }
  if value.reading {
    return Err(LogicalObservationWorkActive)
  }
  value.reading = true
  let result = construct_logical_observation_key(value, record.phase)
  value.reading = false
  match result {
    Err(issue) => Err(issue)
    Ok(wire) => {
      guard record.original is Some((same, _)) &&
        physical_equal(same, value) &&
        logical_observation_original(value) is Some(_) else {
        return Err(LogicalObservationReturned)
      }
      record.original = Some((value, wire))
      record.captured = true
      Ok(())
    }
  }
}

///|
// Keep the SAME loan's current callback fenced. A reentrant record return may
// revoke this read, but cannot let the parent refund while this frame still
// borrows its key/context. Recheck the original token after that callback.
fn read_logical_observation_record(
  value : ClientLogicalObservationRecord,
  field : Int,
) -> Result[String, ClientLogicalObservationIssue] {
  guard value.captured && value.original is Some((owner, _)) else {
    return Err(LogicalObservationReturned)
  }
  if owner.reading {
    return Err(LogicalObservationWorkActive)
  }
  owner.reading = true
  let current = logical_observation_current(owner, delivering=true) is Some(_)
  owner.reading = false
  guard current &&
    value.original is Some((same, wire)) &&
    physical_equal(same, owner) else {
    return Err(LogicalObservationReturned)
  }
  match field {
    0 => Ok(if wire is Some(_) { "projected" } else { "not_projected" })
    1 =>
      match wire {
        Some(original) => Ok(original)
        None => Err(LogicalObservationReturned)
      }
    _ =>
      Ok(
        match value.phase {
          Before => "before"
          Settled => "settled"
          OutputEmitted => "output_emitted"
        },
      )
  }
}

///|
pub fn logical_observation_record_state(
  value : ClientLogicalObservationRecord,
) -> Result[String, ClientLogicalObservationIssue] {
  read_logical_observation_record(value, 0)
}

///|
pub fn logical_observation_record_key(
  value : ClientLogicalObservationRecord,
) -> Result[String, ClientLogicalObservationIssue] {
  read_logical_observation_record(value, 1)
}

///|
pub fn logical_observation_record_phase(
  value : ClientLogicalObservationRecord,
) -> Result[String, ClientLogicalObservationIssue] {
  read_logical_observation_record(value, 2)
}

///|
pub fn return_logical_observation_record(
  value : ClientLogicalObservationRecord,
) -> Unit {
  guard value.original is Some((owner, _)) else { return }
  // Drop the copied wire/token context before changing the pending quantity.
  // Parent extents remain monotonic; this is not an individual byte refund.
  value.original = None
  owner.pending -= 1
}

///|
fn release_logical_observation_hook(
  value : ClientLogicalObservation,
) -> Result[Unit, ClientLogicalObservationIssue] {
  if value.attached is Some(captured) {
    match @strategy.release_captured_task_boundary_hooks(captured) {
      Err(_) => return Err(LogicalObservationCleanupPending)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
/// Pending delivery is an actual outstanding loan, not Sample/history state.
/// No parent is returned while an attached hook or delivery still has work.
pub fn return_installed_logical_observation(
  value : ClientLogicalObservation,
) -> Result[Bool, ClientLogicalObservationIssue] {
  value.closing = true
  if value.reading || value.pending != 0 {
    return Err(LogicalObservationCleanupPending)
  }
  // Queued deliveries retain their original under this same still-live loan.
  // Only after the last delivery drops it may lower return start/refund.
  value.original = None
  match release_logical_observation_hook(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // The helper frame containing captured/hook aliases has returned. Cut this
  // final Run link before the existing body borrower can acknowledge return.
  value.attached = None
  return_installed_original_explanation_capture(value.cleanup).map_err(issue => {
    LogicalObservationCapacity(issue)
  })
}
