///|
/// Same-Run observation custody in the existing Submission projection. The
/// actual Run remains borrowed until this original metadata/readback closes.
priv struct StoredSDKUnpublishedState {
  run : Int
  original : @host.ClientSavedSubmissionSnapshot
  row : @host.ClientJournalPhysicalRow
  publication : StoredSDKPublicationObservation
  model_entry : PortableModelEntryJournal?
  mut update : @host.ClientSavedRunStateUpdate?
  mut confirmed : Bool
}

///|
fn sdk_unpublished_state_fields(
  value : Instance,
  record : StoredSubmissionProjection,
) -> Result[(Int, String), Int] {
  guard record.borrow is Ok(borrow) &&
    input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "namespaceId", "authorityScopeCid", "runDefinitionCid", "run", "observed_at",
    ])
    is Ok(fields) &&
    @decode.required(fields, "run") is Ok(run) &&
    @decode.safe_integer(run) is Ok(run) &&
    run > 0L &&
    run < 2147483648L &&
    required_text(fields, "observed_at") is Some(at) else {
    return Err(-31)
  }
  Ok((run.to_int(), at))
}

///|
// This is the original strategy Owner's complete stop/retirement inventory,
// not a missing process-local worker or task map. The Model Call must
// independently return its actual transport and execution stop.
fn sdk_unpublished_execution_retired(value : Instance, run : Int) -> Bool {
  let mut selected = None
  for compute in value.computes.values() {
    if compute.origin is SourceFree(original, _) && original == run {
      if selected is Some(_) {
        return false
      }
      selected = Some(compute)
    }
  }
  guard selected is Some({ host: Some(host), .. }) else { return false }
  let original = @local_run.local_compute_run(host)
  !@strategy.captured_task_retirement_pending(original) &&
  !@strategy.captured_task_boundary_cleanup_pending(original)
}

///|
// Keep just the original confirmed Entry that belongs to the stopped Call.
// A Run claim, a closed socket or the absence of Raw is insufficient alone.
fn sdk_unpublished_model_entry(
  value : Instance,
  run : Int,
  plan : @local_run.LocalRunPlan,
) -> PortableModelEntryJournal? {
  guard value.runs.get(run)
    is Some({ preparation, restoration: None, outcome: Some(Ok(original)), .. }) &&
    physical_equal(original, plan) &&
    value.preparations.get(preparation)
    is Some({ project_request: Some({ model_run: Some(model), .. }), .. }) &&
    model.adopted is Some(_) &&
    model.members.length() == 1 &&
    physical_equal(model.request, @local_run.local_run_request(plan)) &&
    physical_equal(model.compiled, @local_run.local_run_compiled(plan)) &&
    physical_equal(model.definition, @local_run.local_run_definition(plan)) else {
    return None
  }
  let task = model.members[0]
  guard task.issue is Some(@infer.Model(@model.UnknownCalls)) &&
    task.transport_worker is ClosedUnknown &&
    task.active is Some(active) &&
    @infer.execution_stopped(active) &&
    task.entry is Some(_) &&
    task.entry_journal is Some({ state: Confirmed, .. } as entry) &&
    task.transport is Some(_) &&
    task.raw_save is None &&
    task.raw_store is None &&
    task.settlement is None &&
    sdk_unpublished_execution_retired(value, run) else {
    return None
  }
  Some(entry)
}

///|
fn inspect_sdk_unpublished_model_entry(
  value : Instance,
  configuration : StoredRunConfiguration,
  retained : StoredSDKUnpublishedState,
  plan : @local_run.LocalRunPlan,
) -> Result[Unit, Int] {
  guard retained.model_entry is Some(original) else { return Ok(()) }
  guard sdk_unpublished_model_entry(value, retained.run, plan) is Some(entry) &&
    physical_equal(entry, original) &&
    entry.attempt_cid is Some(attempt) &&
    entry.entry_digest is Some(digest) &&
    entry.scope_slot is Some((scope, slot)) &&
    entry.entry_extent > 0 &&
    configuration.sdk is Some(sdk) &&
    @publication.model_scoped_private_holding_cid(
      retained.publication.run.definition,
      sdk.store_authority_cid,
      scope, slot, attempt, 1, "entered", "model_raw_response",
    ) is Some(raw) else {
    return Err(-35)
  }
  let read = (table, key, extent) => sdk_run_journal_port(
    value,
    configuration,
    1,
    table,
    key,
    expected_body_length=Some(extent),
  )
  match read("client_model_call_originals", attempt, entry.entry_extent) {
    Ok(Some(row)) if row.key == attempt &&
      row.revision == 0L &&
      "sha256:" + @sha.hex(row.body) == digest => ()
    Err(code) => return Err(code)
    _ => return Err(-35)
  }
  for (table, key) in [
    ("client_model_raw_responses", raw), ("client_model_call_settlements", attempt),
  ] {
    match read(table, key, 0) {
      Ok(None) => ()
      Err(code) => return Err(code)
      _ => return Err(-35)
    }
  }
  Ok(())
}

///|
fn sdk_unpublished_candidate_wire(
  value : Instance,
  retained : StoredSDKUnpublishedState,
  plan : @local_run.LocalRunPlan,
  at : String,
) -> Result[String, Int] {
  let encoding = retained.publication.run
  let prepared = @local_run.local_run_prepared(plan)
  let execution_unknown = retained.model_entry is Some(_)
  if @host.prepared_client_acquisition_count(prepared) != 0 ||
    @host.prepared_client_composed_infer_count(prepared) != Some(
      if execution_unknown { 1 } else { 0 },
    ) ||
    (execution_unknown &&
      !(encoding.dispatch_reserved && encoding.physical_start_claimed)) ||
    encoding.checkpoint is Some(_) ||
    encoding.effect_material_originals is Some(_) {
    return Err(-42)
  }
  if retained.row.revision < 0L || retained.row.revision > 2147483647L {
    return Err(-34)
  }
  guard retained.publication.terminal == Some(false) &&
    @publication.run_definition_run_id(encoding.definition) is Ok(run_id) else {
    return Err(-42)
  }
  let unstarted = !encoding.physical_start_claimed
  let retired = sdk_unpublished_execution_retired(value, retained.run)
  let cancelled = @host.confirm_client_run_cancellation({
    cancellation_requested: encoding.cancellation_requested(),
    model_fence_required: execution_unknown,
    model_fenced: false,
    unresolved_model_calls: execution_unknown,
    unresolved_effects: false,
    reconciliation_required: execution_unknown,
    publication_committed: false,
    physical_stop_confirmed: retired ||
    (unstarted && encoding.cancellation_requested()),
    cleanup_confirmed: retired || unstarted,
    revision_unchanged: true,
  })
  let names = @host.client_task_compilation_result_names(
    @local_run.local_run_compilation(plan),
  )
  let state = match
    @publication.issue_effect_free_unpublished_run_state_wire(
      run_id,
      at,
      names,
      encoding.dispatch_reserved,
      false,
      65536,
      8192,
      64,
      cancelled_before_start=cancelled && unstarted,
      observed_terminal_outcome=if cancelled && !unstarted {
        Some(@publication.Cancelled)
      } else {
        None
      },
      execution_unknown~,
    ) {
    Ok(state) => state
    Err(_) => return Err(-31)
  }
  let control = match
    @publication.issue_run_control_observation_wire(
      retained.row.revision.to_int(),
      encoding.cancellation_requested(),
      unstarted,
      false,
      retired,
    ) {
    Ok(control) => control
    Err(_) => return Err(-31)
  }
  // Both fragments are issued by the existing canonical Common writers, not
  // caller JSON. Common's observation owner validates the full joined schema
  // and assigns the actual durable revision before any public exposure.
  if !state.has_prefix("{") {
    return Err(-31)
  }
  Ok("{\"control\":" + control + "," + state[1:].to_owned())
}

///|
fn sdk_unpublished_state_current(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  committed : Bool,
) -> Int {
  guard !record.output_closed &&
    record.unpublished_state is Some(retained) &&
    retained.update is Some(update) &&
    value.runs.get(retained.run) is Some({ outcome: Some(Ok(plan)), .. }) else {
    return -33
  }
  let snapshot = match
    observe_submission_lookup(
      value,
      record,
      configuration,
      // Before-write validation keeps the exact old snapshot. Readback must
      // admit the actual successor through the complete reader instead of
      // asking the unchanged-original optimization to accept a changed row.
      original=if committed { None } else { Some(retained.original) },
    ) {
    Ok(Some(snapshot)) => snapshot
    Ok(None) => return -31
    Err(code) => return code
  }
  guard @host.client_saved_submission_run_row(snapshot) is Some(row) &&
    row.key == retained.row.key &&
    row.revision == retained.row.revision &&
    row.body == retained.row.body else {
    return -35
  }
  let code = validate_sdk_publication_observation(
    value,
    record,
    configuration,
    retained.publication,
  )
  if code != 0 {
    return code
  }
  match inspect_sdk_unpublished_model_entry(value, configuration, retained, plan) {
    Ok(_) => ()
    Err(code) => return code
  }
  if committed {
    if @host.confirm_client_saved_run_state_update(update, snapshot) is Err(_) {
      return -35
    }
    retained.confirmed = true
    record.saved_snapshot = Some(snapshot)
  } else if retained.confirmed ||
    @host.validate_client_saved_run_state_update_original(update, snapshot)
    is Err(_) {
    return -35
  }
  match submission_lookup_current(value, record, configuration) {
    Ok(_) => 0
    Err(code) => code
  }
}

///|
fn produce_sdk_unpublished_run_state(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  if record.produced {
    return sdk_unpublished_state_current(value, record, configuration, true)
  }
  if record.invoked || record.output_closed {
    return -33
  }
  record.invoked = true
  let (run, at) = match sdk_unpublished_state_fields(value, record) {
    Ok(value) => value
    Err(code) => return code
  }
  guard value.runs.get(run) is Some(original) &&
    original.configuration == record.configuration &&
    original.outcome is Some(Ok(plan)) &&
    original.sdk_submission is Some(_) else {
    return -2
  }
  let snapshot = match observe_submission_lookup(value, record, configuration) {
    Ok(Some(snapshot)) => snapshot
    Ok(None) => return -31
    Err(code) => return code
  }
  guard @host.client_saved_submission_run_row(snapshot) is Some(row) &&
    submission_run_row_original_with_identity(row, None) is Ok(encoding) &&
    @host.client_request_identity_relation(
      encoding.request,
      @local_run.local_run_request(plan),
    )
    is @host.SameRequest &&
    @publication.publication_contract_identity(encoding.definition) ==
    @local_run.local_run_definition_cid(plan) else {
    return -32
  }
  let retained : StoredSDKUnpublishedState = {
    run,
    original: snapshot,
    row,
    publication: sdk_publication_observation_original(encoding),
    model_entry: sdk_unpublished_model_entry(value, run, plan),
    update: None,
    confirmed: false,
  }
  record.unpublished_state = Some(retained)
  let committed = match
    sdk_publication_observation(
      value,
      record,
      configuration,
      retained.publication,
    ) {
    Ok(value) => value
    Err(code) => return code
  }
  if committed {
    return -42
  }
  match inspect_sdk_unpublished_model_entry(value, configuration, retained, plan) {
    Ok(_) => ()
    Err(code) => return code
  }
  let wire = match sdk_unpublished_candidate_wire(value, retained, plan, at) {
    Ok(value) => value
    Err(code) => return code
  }
  let update = match
    @host.prepare_client_unpublished_run_state_update(
      snapshot,
      encoding.request,
      encoding.definition,
      wire,
    ) {
    Ok(value) => value
    Err(_) => return -35
  }
  retained.update = Some(update)
  let (key, prior, revision, body) = @host.client_saved_run_state_update_row(
    update,
  )
  let writer = @encode.writer(1048576, 16, 1) catch { _ => return -34 }
  let packet = try {
    @encode.begin_object(writer)
    for
      (name, text) in [
        ("body", @utf8.decode(body)),
        ("key", key),
        ("kind", if prior == revision { "retained" } else { "replace" }),
        ("revision", prior.to_string()),
        ("state", @host.client_saved_run_state_update_candidate_wire(update)),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, text)
    }
    @encode.end_object(writer)
    @utf8.encode(@encode.finish(writer))
  } catch {
    _ => return -34
  }
  let code = status(
    @buffers.supply_buffer_output(value.pool, record.slot, packet),
  )
  if code != 0 {
    return code
  }
  record.produced = true
  sdk_unpublished_state_current(value, record, configuration, false)
}

///|
fn close_sdk_unpublished_run_state(record : StoredSubmissionProjection) -> Int {
  guard record.unpublished_state is Some(retained) else { return 0 }
  let code = close_sdk_publication_observation(retained.publication)
  if code != 0 {
    return code
  }
  record.unpublished_state = None
  0
}
