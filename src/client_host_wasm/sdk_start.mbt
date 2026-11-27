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
  let saved = match
    observe_submission_append(value, observation, current, original_run=Some(run)) {
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
          row_original=sdk_run_row_codec_original(value, run),
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
    @host.decode_client_run_journal_row_with_observation_originals(
      row.body,
      original=sdk_run_row_codec_original(value, run),
    ) {
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
          original,
          row,
          submission,
          row_original=sdk_run_row_codec_original(value, run),
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
              original,
              row,
              submission,
              row_original=sdk_run_row_codec_original(value, run),
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
  if encoding.cancellation_requested() || encoding.physical_start_claimed {
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
          encoding.cancellation_requested(),
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
  sdk_start_step_wire(material.kind, step.row, step.body, 1048576).map(wire => {
    material.sdk_start = Some(step)
    wire
  })
}

///|
fn sdk_start_step_wire(
  kind : Int,
  row : @host.ClientJournalPhysicalRow,
  body : Bytes,
  limit : Int,
  source_count? : Int? = None,
) -> Result[String, Int] {
  try {
    let writer = @encode.writer(limit, 6, 1)
    @encode.begin_object(writer)
    for
      (key, text) in [
        ("kind", if kind == 7 { "dispatch" } else { "claim" }),
        ("key", row.key),
        ("revision", row.revision.to_string()),
        ("body", @utf8.decode(body)),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, text)
    }
    if source_count is Some(count) {
      @encode.key(writer, "source_count")
      @encode.number_value(writer, count.to_double())
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(-34)
  }
}

///|
pub fn validate_sdk_start_material(nonce : Int64, handle : Int) -> Int {
  if selected(nonce) is Some(value) &&
    value.materials.get(handle) is Some({ file_start: Some(start), .. }) {
    return observe_sdk_file_start(value, handle, start, false)
  }
  if selected(nonce) is Some(value) &&
    value.materials.get(handle) is Some({ mock_start: Some(start), .. }) {
    return observe_mock_effect_sdk_start(value, handle, start, false)
  }
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
  sdk_start_activation_current(current, plan)
}

///|
fn sdk_start_activation_current(
  current : StoredRunConfiguration,
  plan : @local_run.LocalRunPlan,
) -> Int {
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
// Fresh currentness of one already-confirmed live start, not namespace
// admission/recovery or a retained permission. Only exact point reads enter
// this boundary; missing originals never fall through to append or restart.
fn validate_live_sdk_started_run_current(
  value : Instance,
  step_handle : Int,
  plan : @local_run.LocalRunPlan,
) -> Int {
  guard value.materials.get(step_handle)
    is Some(
      {
        run,
        kind: 8,
        produced: true,
        closing: false,
        sdk_start: Some(step),
        ..
      }
    ) &&
    step.start is Some(_) &&
    value.runs.get(run) is Some(record) &&
    record.restoration is None &&
    record.outcome is Some(Ok(original_plan)) &&
    physical_equal(original_plan, plan) &&
    value.run_configurations.get(record.configuration) is Some(current) &&
    current.sdk is Some(_) &&
    current.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(scope) &&
    record.sdk_submission is Some(submitted_handle) &&
    value.submissions.get(submitted_handle) is Some(submitted) &&
    value.preparations.get(record.preparation)
    is Some({ submitted: Some(preparation), .. }) &&
    value.materials.get(step.publication_material)
    is Some(
      {
        run: publication_run,
        kind: 9,
        produced: true,
        closing: false,
        sdk_publication: Some(binding),
        ..
      }
    ) &&
    publication_run == run &&
    binding.original is Some(publication) &&
    value.materials.get(binding.rows_material)
    is Some(
      {
        run: rows_run,
        kind: 6,
        produced: true,
        closing: false,
        submission: Some({ rows: Some(rows), task_materials, .. }),
        ..
      }
    ) &&
    rows_run == run else {
    return -2
  }
  let task_original = match
    @local_run.local_submitted_run_task_materials(rows, plan, preparation) {
    Ok(original) => original
    Err(_) => return -35
  }
  match (task_original, task_materials) {
    (None, None) => ()
    (Some(original), Some(retained)) if physical_equal(original, retained) => ()
    _ => return -35
  }
  match submission_append_current(value, submitted, current) {
    Ok(_) => ()
    Err(code) => return code
  }
  let borrow = match submitted.borrow {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    submission_append_input(cursor) is Ok((object, _)) &&
    required_text(object, "reference") is Some(reference_wire) &&
    @host.admit_client_submission_reference_record(reference_wire)
    is Ok(reference) &&
    @host.client_submission_epoch_token_authority_scope_cid(
      @host.client_submission_reference_record_epoch(reference),
    ) ==
    current.authority_scope_cid else {
    return -31
  }
  let check = () => submission_append_current(value, submitted, current)
  let read = (table, key) => {
    physical_journal_row(scope.physical, check, 1, table, key)
  }
  let snapshot = match
    @host.read_client_saved_submission_with_task_original(
      reference,
      read,
      row => sdk_run_row_inspection(value, run, row),
      -31,
      task_original,
    ) {
    Ok(Some(snapshot)) => snapshot
    Ok(None) => return -35
    Err(code) => return code
  }
  guard @host.client_saved_submission_run_row(snapshot) is Some(row) else {
    return -35
  }
  let submission = @host.client_saved_submission_row(snapshot)
  match
    @local_run.validate_local_saved_submitted_rows(
      rows,
      plan,
      preparation,
      row.key,
      row.revision,
      row.body,
      submission.key,
      submission.revision,
      submission.body,
      row_original=sdk_run_row_codec_original(value, run),
    ) {
    Ok(_) => ()
    Err(_) => return -31
  }
  match
    @local_run.validate_local_run_publication_binding_original(
      publication,
      row,
      submission,
      row_original=sdk_run_row_codec_original(value, run),
    ) {
    Ok(_) => ()
    Err(issue) => return sdk_publication_binding_issue(issue)
  }
  if row.key != step.row.key ||
    row.revision != step.row.revision + 1L ||
    row.body != step.body {
    return -35
  }
  match check() {
    Ok(_) => ()
    Err(code) => return code
  }
  let code = sdk_start_activation_current(current, plan)
  if code != 0 {
    return code
  }
  match check() {
    Ok(_) => 0
    Err(code) => code
  }
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
  if selected(nonce) is Some(value) &&
    value.materials.get(handle) is Some({ file_start: Some(start), .. }) {
    return observe_sdk_file_start(value, handle, start, true)
  }
  if selected(nonce) is Some(value) &&
    value.materials.get(handle) is Some({ mock_start: Some(start), .. }) {
    return observe_mock_effect_sdk_start(value, handle, start, true)
  }
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
    value.materials.get(step_handle) is Some(material) &&
    material.run == run else {
    return -2
  }
  if material.file_start is Some(claim) {
    guard material.kind == 8 && material.produced && claim.observed is Some(_) else {
      return -35
    }
    let checked = observe_sdk_file_start(value, step_handle, claim, true)
    if checked != 0 {
      return checked
    }
    return retain_sdk_physical_start(value, run, record, step_handle, None)
  }
  if material.mock_start is Some(claim) {
    guard material.kind == 8 && claim.confirmed else { return -35 }
    let checked = observe_mock_effect_sdk_start(
      value,
      step_handle,
      claim,
      true,
      read_confirmed_claim=true,
    )
    if checked != 0 {
      return checked
    }
    return retain_sdk_physical_start(value, run, record, step_handle, None)
  }
  guard record.outcome is Some(Ok(plan)) &&
    material.sdk_start is Some({ start: Some(start), .. }) else {
    return -2
  }
  let code = validate_sdk_start_claim(value, step_handle, plan)
  if code != 0 {
    return code
  }
  retain_sdk_physical_start(value, run, record, step_handle, Some(Ok(start)))
}

///|
fn retain_sdk_physical_start(
  value : Instance,
  run : Int,
  record : StoredRun,
  step_handle : Int,
  outcome : Result[@local_run.LocalRunPhysicalStart, @local_run.LocalRunIssue]?,
) -> Int {
  if record.physical_start_reserved {
    return -35
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
    invoked: outcome is Some(_),
    outcome,
    sdk_step: Some(step_handle),
    file_managed: None,
    model_file: None,
    mock_managed: None,
    mock_effect_compute: None,
    mock_effect_compute_started: false,
  }
  record.physical_start_reserved = true
  value.next_handle += 1
  handle
}
