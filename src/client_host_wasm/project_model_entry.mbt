///|
priv enum PortableModelHttpWorker {
  Unclaimed
  Active
  ClosedAwaitingRaw(Int, Int)
  ClosedUnknown
  RawReady(@model.ModelPhysicalCallPoll)
}

///|
// Install one deferred physical port for the admitted original. Registering
// custody under the consumed Entry does not acquire a worker or open HTTPS.
fn queue_portable_model_transport(
  selected_task : StoredPortableModelMember,
  prepared : @model.ModelPreparedCallSet,
  original : @model.PreparedModelHttpChatRequest,
  entry : @model.ModelCallEntry,
) -> @model.ModelPhysicalCall? {
  guard selected_task.transport is None &&
    selected_task.entry is Some(pending) &&
    physical_equal(pending, entry) &&
    selected_task.capture is Some(capture) &&
    selected_task.dispatch is Some(admission) &&
    @model.prepared_model_scope(prepared) is Some(scope) &&
    @host.client_model_raw_capture_matches(capture, admission, scope) &&
    @host.check_client_model_raw_capture_current(capture) is Ok(_) &&
    @model.model_call_entry_originals(entry) is Some((slot, _, _, _)) &&
    @model.prepared_model_request(prepared, slot) is Some(request) &&
    @model.prepared_model_http_chat_material(
      original,
      request,
      selected_task.provider,
    )
    is Some(_) else {
    return None
  }
  guard @model.register_model_physical_call_for_request(
      entry,
      request,
      () => {
        let usage : @model.ModelPhysicalUsage = {
          input_tokens: None,
          output_tokens: None,
        }
        match selected_task.transport_worker {
          Unclaimed if selected_task.transport_stop =>
            @model.PhysicalRejected(@model.Cancelled, usage)
          ClosedAwaitingRaw(_, _) if selected_task.transport_stop =>
            @model.PhysicalUnknown(usage)
          ClosedUnknown => @model.PhysicalUnknown(usage)
          RawReady(response) => response
          Unclaimed | Active | ClosedAwaitingRaw(_, _) => @model.PhysicalPending
        }
      },
      () => selected_task.transport_stop = true,
      _ => {
        match selected_task.transport_worker {
          Unclaimed => selected_task.transport_stop
          Active => false
          ClosedAwaitingRaw(_, _) | ClosedUnknown | RawReady(_) => true
        }
      },
    )
    is Some(call) else {
    return None
  }
  selected_task.transport = Some(call)
  Some(call)
}

///|
/// Cross the Core's original Entry registration boundary once for this
/// already authorized task. The retained persistence operation awaits its
/// physical Store successor. The caller's clock ends with this bounded step.
pub fn stage_portable_model_entry(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    !record.pending &&
    !record.closing &&
    record.issue is None &&
    record.progress is Some({ waiting: true, .. }) &&
    value.copies.get(clock_input) is Some((slot, _)) else {
    return -2
  }
  guard portable_model_task_original(value, record)
    is Ok(Some((run, selected_task, current))) &&
    selected_task.active is Some(active) &&
    @infer.prepared_call_set(active) is Some(prepared) &&
    @model.prepared_model_scope(prepared) is Some(scope) &&
    selected_task.dispatch is Some(admission) &&
    selected_task.dispatch_clock.val is None &&
    selected_task.entry is None &&
    selected_task.transport is None else {
    return -32
  }
  guard input_cursor(value, slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["observed_at"]) is Ok(fields) &&
    required_text(fields, "observed_at") is Some(at) &&
    at.length() <= 64 else {
    return -31
  }
  let clock = selected_task.dispatch_clock
  clock.val = Some(at)
  defer {
    clock.val = None
  }
  match @host.check_client_infer_dispatch_current(admission) {
    Err(@host.Expired) => return -36
    Err(_) => return -32
    Ok(_) => ()
  }
  // Require the real Raw policy before the durable Entry or deferred port.
  let capture = match
    register_portable_model_capture(
      value, record, run, selected_task, current, admission, scope, at,
    ) {
    Ok(capture) => capture
    Err(code) => return code
  }
  selected_task.capture = Some(capture)
  guard @model.bind_prepared_model_http_chat_transport(
      prepared,
      selected_task.provider,
      (original, entry) => {
        queue_portable_model_transport(selected_task, prepared, original, entry)
      },
    )
    is Ok(_) else {
    return -32
  }
  guard @infer.bind_model_entry_persistence(active, prepared, admission, entry => {
      guard selected_task.entry is None else { return None }
      guard @model.model_call_entry_persistence(entry, prepared, () => {
          portable_entry_persistence(
            selected_task,
            record.closing,
            entry,
            prepared,
          )
        })
        is Some(operation) else {
        return None
      }
      selected_task.entry = Some(entry)
      Some(operation)
    })
    is Ok(_) else {
    return -32
  }
  let code = advance_managed_task(nonce, handle, 1)
  if code != 0 {
    return code
  }
  guard selected_task.entry is Some(_) else { return -33 }
  0
}

///|
priv enum PortableModelEntryState {
  Prepared
  Offered
  Observed
  Confirmed
  Uncertain
}

///|
/// Owns one pending Entry's exported material and actual Store observation.
priv struct PortableModelEntryJournal {
  output : Int
  mut projection : @model.ModelCallEntryJournalProjection?
  mut attempt_cid : String?
  mut entry_digest : String?
  mut entry_extent : Int
  mut scope_slot : (String, String)?
  mut workspace : @buffers.WorkspaceLoan?
  mut state : PortableModelEntryState
}

///|
fn portable_entry_persistence(
  selected_task : StoredPortableModelMember,
  closing : Bool,
  entry : @model.ModelCallEntry,
  prepared : @model.ModelPreparedCallSet,
) -> @model.ModelEntryPersistenceObservation {
  match selected_task.entry_journal {
    Some({ state: Confirmed, .. }) =>
      match @model.acknowledge_saved_model_call_entry(entry, prepared) {
        Some(ack) => @model.Saved(ack)
        None => @model.Unknown
      }
    Some({ state: Uncertain, .. }) => @model.Unknown
    Some({ state: Offered | Observed, .. }) => @model.Pending
    _ => if closing { @model.NotRecorded } else { @model.Pending }
  }
}

///|
fn portable_entry_original(
  value : Instance,
  record : StoredManagedTask,
) -> (
  StoredPortableModelRun,
  StoredPortableModelMember,
  StoredRunConfiguration,
  @model.ModelPreparedCallSet,
  @host.ClientInferDispatchAdmission,
  @model.ModelCallEntry,
)? {
  guard !record.pending &&
    !record.closing &&
    record.issue is None &&
    portable_model_task_original(value, record)
    is Ok(Some((run, selected_task, configuration))) &&
    selected_task.active is Some(active) &&
    @infer.prepared_call_set(active) is Some(prepared) &&
    selected_task.dispatch is Some(admission) &&
    selected_task.entry is Some(entry) else {
    return None
  }
  Some((run, selected_task, configuration, prepared, admission, entry))
}

///|
fn portable_entry_dimensions(
  run : StoredPortableModelRun,
  prepared : @model.ModelPreparedCallSet,
  admission : @host.ClientInferDispatchAdmission,
  entry : @model.ModelCallEntry,
) -> (Int, Int)? {
  guard @model.model_call_entry_persistence_originals(
      entry, prepared, admission,
    )
    is Some((_, _, call, attempt, authority, scope)) &&
    @model.model_call_entry_journal_bound(
      run.request,
      run.definition,
      call,
      attempt,
      authority,
      65536L,
    )
    is Some(body) else {
    return None
  }
  // The original ASCII locators and admission coordinates are transport
  // only. The stored Entry body and its semantic identity stay unchanged.
  let trust_bytes = match run.tls_ca {
    Some((name, digest)) => name.length() + digest.length()
    None => 0
  }
  let wire = body +
    @publication.model_invocation_scope_cid(scope).length() +
    @publication.run_evidence_value_identity(attempt).length() +
    26 + trust_bytes
  Some((body, wire))
}

///|
pub fn portable_model_entry_bound(
  nonce : Int64,
  handle : Int,
  compute : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    record.compute == compute &&
    portable_entry_original(value, record)
    is Some((run, selected_task, _, prepared, admission, entry)) &&
    selected_task.entry_journal is None &&
    portable_entry_dimensions(run, prepared, admission, entry)
    is Some((_, wire)) else {
    return -32
  }
  wire
}

///|
pub fn reserve_portable_model_entry(
  nonce : Int64,
  handle : Int,
  compute : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    record.compute == compute &&
    value.computes.get(record.compute)
    is Some({ origin: SourceFree(run_handle, _), .. }) &&
    portable_entry_original(value, record)
    is Some((run, selected_task, _, prepared, admission, entry)) &&
    selected_task.entry_journal is None &&
    portable_entry_dimensions(run, prepared, admission, entry)
    is Some((body, wire)) &&
    physical_copy_bytes >= 2L * wire.to_int64() else {
    return -32
  }
  // The exported wire, original body and actual readback can overlap.
  // All three belong to this one output loan even after it is consumed.
  let output = reserve_material_record(
    value,
    run_handle,
    10,
    physical_ticket,
    physical_copy_bytes,
    wire_limit=wire + 2 * body,
  )
  if output > 0 {
    selected_task.entry_journal = Some({
      output,
      projection: None,
      attempt_cid: None,
      entry_digest: None,
      entry_extent: 0,
      scope_slot: None,
      workspace: None,
      state: Prepared,
    })
  }
  output
}

///|
fn portable_entry_clock(value : Instance, clock_input : Int) -> String? {
  guard value.copies.get(clock_input) is Some((slot, _)) &&
    input_cursor(value, slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["observed_at"]) is Ok(fields) &&
    required_text(fields, "observed_at") is Some(at) &&
    at.length() <= 64 else {
    return None
  }
  Some(at)
}

///|
pub fn produce_portable_model_entry(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
  material : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    value.materials.get(material) is Some(output) &&
    output.kind == 10 &&
    !output.invoked &&
    !output.closing &&
    portable_entry_original(value, record)
    is Some((run, selected_task, _, prepared, admission, entry)) &&
    selected_task.entry_journal is Some(journal) &&
    journal.output == material &&
    selected_task.dispatch_clock.val is None &&
    portable_entry_clock(value, clock_input) is Some(at) &&
    portable_entry_dimensions(run, prepared, admission, entry)
    is Some((body, wire)) &&
    @buffers.buffer_output_limit(value.pool, output.slot) ==
    Some(wire + 2 * body) &&
    @encode.text_writer_construction_inventory(body, 16, 2) is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers + 16L,
      reference_slots: writer.reference_slots + 20L,
      scalar_words: writer.scalar_words + 16L,
      owned_utf16_units: writer.owned_utf16_units +
      2L * (wire - body).to_int64(),
      owned_wire_bytes: body.to_int64() + (wire - body).to_int64(),
    })
    is Some(scratch) else {
    return -32
  }
  let workspace = match
    @buffers.reserve_workspace(value.root, scratch, () => true, () => true) {
    Ok(workspace) => workspace
    Err(issue) => return issue_code(issue)
  }
  journal.workspace = Some(workspace)
  let code = build_portable_model_entry(
    value, selected_task, output, journal, run, prepared, admission, entry, body,
    at,
  )
  // Only the bounded synchronous writer used this workspace. Its finished
  // body and Store readback stay covered by the separate output loan.
  if retire_portable_entry_workspace(journal) {
    code
  } else if code == 0 {
    -9
  } else {
    code
  }
}

///|
fn retire_portable_entry_workspace(journal : PortableModelEntryJournal) -> Bool {
  match journal.workspace {
    None => true
    Some(workspace) =>
      match @buffers.close_workspace(workspace) {
        Ok(_) => {
          journal.workspace = None
          true
        }
        Err(_) => false
      }
  }
}

///|
fn build_portable_model_entry(
  value : Instance,
  selected_task : StoredPortableModelMember,
  output : StoredMaterial,
  journal : PortableModelEntryJournal,
  run : StoredPortableModelRun,
  prepared : @model.ModelPreparedCallSet,
  admission : @host.ClientInferDispatchAdmission,
  entry : @model.ModelCallEntry,
  body : Int,
  at : String,
) -> Int {
  selected_task.dispatch_clock.val = Some(at)
  defer {
    selected_task.dispatch_clock.val = None
  }
  guard @model.model_call_entry_current(entry, prepared) &&
    @model.model_call_entry_persistence_originals(entry, prepared, admission)
    is Some((count, slot, _, attempt, _, scope)) &&
    @publication.model_invocation_scope_slot(scope, slot) is Some((slot_cid, _, _)) else {
    return -32
  }
  output.invoked = true
  let projection = match
    @model.project_model_call_entry_journal(
      entry,
      prepared,
      admission,
      run.request,
      run.definition,
      body,
    ) {
    Ok(value) => value
    Err(_) => return -34
  }
  let scope_cid = @publication.model_invocation_scope_cid(scope)
  let key = @publication.run_evidence_value_identity(attempt)
  let (trust_name, trust_digest) = run.tls_ca.unwrap_or(("", ""))
  let header = @utf8.encode(
    "\{scope_cid}\n\{key}\n\{slot}\n\{count}\n\{trust_name}\n\{trust_digest}\n",
  )
  let wire = header + projection.body
  let result = status(
    @buffers.supply_buffer_output(value.pool, output.slot, wire),
  )
  if result == 0 {
    // Reserve retains the full bounded original body separately from the
    // exported copy through re-observation.
    journal.projection = Some(projection)
    journal.attempt_cid = Some(key)
    journal.scope_slot = Some((scope_cid, slot_cid))
    output.produced = true
  }
  result
}

///|
/// Validate the write or read back its actual SQLite row in that reader.
pub fn inspect_portable_model_entry(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
  material : Int,
  kind : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    value.materials.get(material)
    is Some({ kind: 10, produced: true, closing: false, .. }) &&
    portable_entry_original(value, record)
    is Some((_, selected_task, configuration, prepared, admission, entry)) &&
    selected_task.entry_journal is Some(journal) &&
    journal.output == material &&
    journal.projection is Some(projection) &&
    selected_task.dispatch_clock.val is None &&
    portable_entry_clock(value, clock_input) is Some(at) else {
    return -32
  }
  selected_task.dispatch_clock.val = Some(at)
  defer {
    selected_task.dispatch_clock.val = None
  }
  if kind == 0 && journal.state is Prepared {
    guard @model.model_call_entry_current(entry, prepared) else { return -32 }
    journal.state = Offered
    return 0
  }
  guard kind == 1 &&
    journal.state is Offered &&
    @model.model_call_entry_persistence_originals(entry, prepared, admission)
    is Some((_, _, _, attempt, _, _)) else {
    return -32
  }
  let key = @publication.run_evidence_value_identity(attempt)
  match
    sdk_run_journal_port(
      value,
      configuration,
      1,
      "client_model_call_originals",
      key,
      expected_body_length=Some(projection.body.length()),
    ) {
    Ok(Some(row)) if @model.model_call_entry_journal_matches_saved(
        projection, entry, prepared, row,
      ) => {
      // Save only the digest of the exact observed Entry. The full
      // projection can return its buffer before the settlement is built.
      journal.entry_digest = Some("sha256:" + @sha.hex(row.body))
      journal.entry_extent = row.body.length()
      journal.state = Observed
      0
    }
    Err(code) => code
    _ => -35
  }
}

///|
/// The physical Host invokes this only after leaving the original Store
/// operation. A failed confirmation cannot publish a Saved acknowledgement.
pub fn finish_portable_model_entry(
  nonce : Int64,
  handle : Int,
  material : Int,
  kind : Int,
) -> Int {
  // Closing does not lose the original pending operation. No new authority
  // is evaluated here, and the Core still owns the check before dispatch.
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    value.materials.get(material)
    is Some({ kind: 10, produced: true, closing: false, .. }) &&
    value.computes.get(record.compute) is Some(compute) &&
    stored_compute_original_run(value, compute) is Some(original) &&
    value.preparations.get(original.preparation)
    is Some({ project_request: Some({ model_run: Some(run), .. }), .. }) else {
    return -32
  }
  for selected_task in run.members {
    if selected_task.entry_journal is Some(journal) &&
      journal.output == material {
      let (task_index, _, _) = @host.client_infer_occurrence_coordinates(
        selected_task.graph.occurrence,
      )
      guard task_index == record.task else { return -32 }
      match (kind, journal.state) {
        (1, Observed) => journal.state = Confirmed
        (0, Offered | Observed) => journal.state = Uncertain
        (0, Prepared) => ()
        _ => return -32
      }
      journal.projection = None
      return 0
    }
  }
  -32
}
