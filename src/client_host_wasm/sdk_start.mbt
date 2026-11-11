///|
/// Original physical CAS projection and start Owner proof, never a Scheduler
/// or durable Run state. The same material/Plan/current/Store remain required.
priv struct StoredSDKStartStep {
  row : @host.ClientJournalPhysicalRow
  body : Bytes
  start : @local_run.LocalRunPhysicalStart?
  publication_material : Int
}

///|
/// Keep the live first-admission Owner distinct from an actual saved snapshot.
priv enum StoredSDKOriginalRows {
  Submitted(
    @local_run.LocalSubmittedRunRows,
    @preparation.LocalSubmittedPreparation
  )
  Saved(@host.ClientSavedSubmissionSnapshot)
}

///|
fn sdk_saved_original_snapshot(
  value : Instance,
  run : Int,
  plan : @local_run.LocalRunPlan,
) -> Result[
  (@host.ClientSavedSubmissionSnapshot, StoredSDKOriginalRows, Int),
  Int,
] {
  guard value.runs.get(run) is Some(record) &&
    value.run_configurations.get(record.configuration) is Some(current) &&
    current.sdk is Some(_) &&
    record.sdk_submission is Some(held) &&
    value.submissions.get(held) is Some(observation) else {
    return Err(-2)
  }
  if record.restoration is Some(restoration) {
    let snapshot = match sdk_restored_run_snapshot(value, run, plan) {
      Ok(snapshot) => snapshot
      Err(code) => return Err(code)
    }
    guard @host.client_saved_submission_run_row(snapshot) is Some(row) else {
      return Err(-35)
    }
    let submission = @host.client_saved_submission_row(snapshot)
    if @local_run.validate_local_saved_snapshot_rows(
        plan, snapshot, row, submission,
      )
      is Err(_) {
      return Err(-31)
    }
    return Ok((snapshot, Saved(snapshot), restoration))
  }
  guard value.preparations.get(record.preparation)
    is Some({ submitted: Some(preparation), .. }) else {
    return Err(-2)
  }
  let saved = match observe_submission_append(value, observation, current) {
    Ok(@host.Retained(saved)) => saved
    Ok(@host.Append(_)) => return Err(-35)
    Err(code) => return Err(code)
  }
  guard @host.client_saved_submission_run_row(saved) is Some(row) else {
    return Err(-35)
  }
  let submission = @host.client_saved_submission_row(saved)
  for (handle, material) in value.materials {
    if material.run == run &&
      material.kind == 6 &&
      material.produced &&
      material.submission is Some({ rows: Some(rows), .. }) {
      if @local_run.validate_local_saved_submitted_rows(
          rows,
          plan,
          preparation,
          row.key,
          row.revision,
          row.body,
          submission.key,
          submission.revision,
          submission.body,
        )
        is Err(_) {
        return Err(-31)
      }
      return Ok((saved, Submitted(rows, preparation), handle))
    }
  }
  Err(-2)
}

///|
// Project rows from the same completed observation without another journal
// audit. The snapshot remains local to this call, not retained current proof.
fn sdk_saved_original_rows(
  value : Instance,
  run : Int,
  plan : @local_run.LocalRunPlan,
) -> Result[
  (
    @host.ClientJournalPhysicalRow,
    @host.ClientJournalPhysicalRow,
    StoredSDKOriginalRows,
    Int,
  ),
  Int,
] {
  let (snapshot, original, handle) = match
    sdk_saved_original_snapshot(value, run, plan) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  guard @host.client_saved_submission_run_row(snapshot) is Some(row) else {
    return Err(-35)
  }
  Ok((row, @host.client_saved_submission_row(snapshot), original, handle))
}

///|
fn sdk_start_original_row(
  value : Instance,
  run : Int,
  plan : @local_run.LocalRunPlan,
) -> Result[
  (
    @host.ClientJournalPhysicalRow,
    @host.ClientRunJournalEncoding,
    String?,
    String?,
    Int,
  ),
  Int,
] {
  let (row, submission, rows, rows_material) = match
    sdk_saved_original_rows(value, run, plan) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  let (encoding, policy, observation_originals) = match
    @host.decode_client_run_journal_row_with_observation_originals(row.body) {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  if encoding.effect_material_originals is Some(_) ||
    encoding.checkpoint is Some(_) {
    return Err(-42)
  }
  // Saved strings alone cannot authorize start. Only the same Common Owner's
  // confirmed/retained nominal binding is accepted at this saved revision.
  for (handle, material) in value.materials {
    if material.run == run &&
      material.kind == 9 &&
      material.produced &&
      material.sdk_publication is Some({ original: Some(original), .. }) {
      match
        @local_run.validate_local_run_publication_binding_original(
          original, row, submission,
        ) {
        Ok(_) =>
          return Ok((row, encoding, policy, observation_originals, handle))
        Err(issue) => return Err(sdk_publication_binding_issue(issue))
      }
    }
  }
  match rows {
    Submitted(_, _) => Err(-42)
    Saved(snapshot) =>
      // A cold process has no live kind-9 handle. Retain only the already
      // saved binding through the same Common Owner and current Store checks.
      match
        sdk_saved_publication_binding(
          value, run, plan, snapshot, row, submission,
        ) {
        Ok(@local_run.Retained(original)) =>
          match
            @local_run.validate_local_run_publication_binding_original(
              original, row, submission,
            ) {
            Ok(_) =>
              Ok((row, encoding, policy, observation_originals, rows_material))
            Err(issue) => Err(sdk_publication_binding_issue(issue))
          }
        Ok(@local_run.Append(_)) => Err(-42)
        Err(code) => Err(code)
      }
  }
}

///|
fn prepare_sdk_start_step(
  value : Instance,
  material : StoredMaterial,
  record : StoredRun,
  plan : @local_run.LocalRunPlan,
) -> Result[StoredSDKStartStep, Int] {
  guard value.run_configurations.get(record.configuration) is Some(current) &&
    current.sdk is Some(_) else {
    return Err(-2)
  }
  let (row, encoding, policy, observation_originals, publication_material) = match
    sdk_start_original_row(value, material.run, plan) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  if row.revision < 0L || row.revision == 9223372036854775807L {
    return Err(-4)
  }
  if encoding.cancellation_requested || encoding.physical_start_claimed {
    return Err(-35)
  }
  let permit = match
    @authorization.bind_dispatch_authorization(
      current.account,
      current.tuple,
      @authorization.Activation,
      @host.prepared_client_identity(@local_run.local_run_prepared(plan)).program_definition_cid,
      current.context_cid,
    ) {
    Ok(value) => value
    Err(_) => return Err(-32)
  }
  let definition = @publication.publication_contract_identity(
    encoding.definition,
  )
  let start = match material.kind {
    7 => {
      match
        @local_run.prepare_local_run_start(
          plan,
          encoding.request,
          definition,
          encoding.dispatch_reserved,
          permit,
          current.account,
          current.tuple,
          current.context_cid,
        ) {
        Ok(@host.ReserveDispatch) => ()
        Ok(@host.ReconcileReservedDispatch) => return Err(-35)
        Err(_) => return Err(-32)
      }
      None
    }
    8 =>
      match
        @local_run.confirm_local_run_physical_start(
          plan,
          encoding.request,
          definition,
          encoding.dispatch_reserved,
          !encoding.physical_start_claimed,
          encoding.cancellation_requested,
          false,
          permit,
          current.account,
          current.tuple,
          current.context_cid,
        ) {
        Ok(start) => Some(start)
        Err(_) => return Err(-35)
      }
    _ => return Err(-3)
  }
  let changed = if material.kind == 7 {
    { ..encoding, dispatch_reserved: true, }
  } else {
    { ..encoding, physical_start_claimed: true, }
  }
  let body = match
    @host.client_run_journal_row_body(
      changed,
      local_run_policy_originals=policy,
      run_observation_originals=observation_originals,
    ) {
    Ok(body) => body
    Err(_) => return Err(-34)
  }
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return Err(code)
  }
  Ok({ row, body, start, publication_material, })
}

///|
fn sdk_start_material_wire(
  value : Instance,
  material : StoredMaterial,
  record : StoredRun,
  plan : @local_run.LocalRunPlan,
) -> Result[String, Int] {
  let step = match prepare_sdk_start_step(value, material, record, plan) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  try {
    let writer = @encode.writer(1048576, 6, 1)
    @encode.begin_object(writer)
    for
      (key, text) in [
        ("kind", if material.kind == 7 { "dispatch" } else { "claim" }),
        ("key", step.row.key),
        ("revision", step.row.revision.to_string()),
        ("body", @utf8.decode(step.body)),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, text)
    }
    @encode.end_object(writer)
    let wire = @encode.finish(writer)
    material.sdk_start = Some(step)
    Ok(wire)
  } catch {
    _ => Err(-34)
  }
}

///|
pub fn validate_sdk_start_material(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.materials.get(handle) is Some(material) &&
    !material.output_closed &&
    material.produced &&
    material.sdk_start is Some(original) &&
    value.runs.get(material.run) is Some(record) &&
    record.outcome is Some(Ok(plan)) else {
    return -2
  }
  let actual = match prepare_sdk_start_step(value, material, record, plan) {
    Ok(value) => value
    Err(code) => return code
  }
  if actual.row.key != original.row.key ||
    actual.row.body != original.row.body ||
    actual.row.revision != original.row.revision ||
    actual.body != original.body ||
    actual.publication_material != original.publication_material {
    return -35
  }
  0
}

///|
/// Adopt an observed original physical claim, never the earlier CAS candidate.
fn confirm_sdk_start_step(
  value : Instance,
  step_handle : Int,
  plan : @local_run.LocalRunPlan,
) -> Int {
  guard value.materials.get(step_handle) is Some(material) &&
    material.produced &&
    (material.kind == 7 || material.kind == 8) &&
    material.sdk_start is Some(step) &&
    value.runs.get(material.run) is Some(record) &&
    value.run_configurations.get(record.configuration) is Some(current) else {
    return -2
  }
  let (row, _, _, _, publication_material) = match
    sdk_start_original_row(value, material.run, plan) {
    Ok(value) => value
    Err(code) => return code
  }
  if publication_material != step.publication_material ||
    row.key != step.row.key ||
    row.revision != step.row.revision + 1L ||
    row.body != step.body {
    return -35
  }
  let permit = match
    @authorization.bind_dispatch_authorization(
      current.account,
      current.tuple,
      @authorization.Activation,
      @host.prepared_client_identity(@local_run.local_run_prepared(plan)).program_definition_cid,
      current.context_cid,
    ) {
    Ok(value) => value
    Err(_) => return -32
  }
  if @local_run.authorize_local_compute_configuration(
      plan,
      permit,
      current.account,
      current.tuple,
      current.context_cid,
    )
    is Err(_) {
    return -32
  }
  0
}

///|
fn validate_sdk_start_claim(
  value : Instance,
  step_handle : Int,
  plan : @local_run.LocalRunPlan,
) -> Int {
  guard value.materials.get(step_handle)
    is Some({ kind: 8, sdk_start: Some({ start: Some(_), .. }), .. }) else {
    return -2
  }
  confirm_sdk_start_step(value, step_handle, plan)
}

///|
pub fn confirm_sdk_start_material(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.materials.get(handle) is Some(material) &&
    value.runs.get(material.run) is Some({ outcome: Some(Ok(plan)), .. }) else {
    return -2
  }
  confirm_sdk_start_step(value, handle, plan)
}

///|
pub fn reserve_sdk_physical_start(
  nonce : Int64,
  run : Int,
  step_handle : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.runs.get(run) is Some(record) &&
    !record.physical_start_reserved &&
    record.outcome is Some(Ok(plan)) &&
    value.materials.get(step_handle) is Some(material) &&
    material.run == run &&
    material.sdk_start is Some({ start: Some(start), .. }) else {
    return -2
  }
  let code = validate_sdk_start_claim(value, step_handle, plan)
  if code != 0 {
    return code
  }
  if value.next_handle == 2147483647 {
    return -4
  }
  let handle = value.next_handle
  // Borrow the original Run input, not the consumed transport output. Its
  // nominal proof remains under material/Run custody after output retirement.
  let borrow = match
    @buffers.borrow_buffer(value.pool, record.slot, () => {
      physical_reader_stop(record.input_physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  value.physical_starts[handle] = {
    run,
    current_configuration: record.configuration,
    borrow,
    invoked: true,
    outcome: Some(Ok(start)),
    sdk_step: Some(step_handle),
  }
  record.physical_start_reserved = true
  value.next_handle += 1
  handle
}
