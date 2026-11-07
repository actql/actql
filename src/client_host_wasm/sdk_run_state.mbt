///|
/// Project only an already saved SDK observation from the original admitted
/// Submission/Run snapshot. Its observation counter/key remains independent of
/// the SQL and Run control revisions. This neither refreshes availability nor
/// issues a replacement observation, preparation, publication or start claim.
fn saved_sdk_run_state_wire(
  snapshot : @host.ClientSavedSubmissionSnapshot?,
) -> Result[Bytes, Int] {
  guard snapshot is Some(snapshot) &&
    @host.client_saved_submission_run_row(snapshot) is Some(row) &&
    @host.client_saved_submission_state_original(snapshot) is Some(state) else {
    return Err(-42)
  }
  let submitted = @host.client_saved_submission_record(snapshot)
  guard submitted.run_admission is Some(_) &&
    submitted.run_state_original == Some(state.wire()) &&
    submitted.run_state_observation is Some((revision, Some(key))) else {
    return Err(-42)
  }
  // A decoded row is not enough: the snapshot's existing nested validator has
  // already admitted these same originals. Require their SDK provenance too.
  guard @host.decode_client_run_journal_row_with_observation_originals(row.body)
    is Ok((run, Some(_), Some(_))) &&
    @publication.run_definition_run_id(run.definition) is Ok(run_id) else {
    return Err(-32)
  }
  saved_sdk_run_state_observation_wire(state, run_id, revision, key)
}

///|
// Match the existing Native saved-state reader's exact observation binding.
// Never infer a public revision or availability from a row/COMMIT scalar.
fn saved_sdk_run_state_observation_wire(
  state : @host.ClientRunStateOriginal,
  run_id : String,
  revision : Int64,
  key : String,
) -> Result[Bytes, Int] {
  let observation = match
    @publication.prepare_run_state_observation(
      state.state_wire(),
      run_id,
      revision,
      65536,
      8192,
      64,
    ) {
    Ok(value) => value
    Err(_) => return Err(-32)
  }
  if observation.key() != key ||
    observation.wire(revision).to_option() != Some(state.state_wire()) {
    return Err(-32)
  }
  Ok(@utf8.encode(state.state_wire()))
}

///|
fn sdk_run_state_snapshot(
  value : Instance,
  run : Int,
  current_configuration : Int,
) -> Result[(@local_run.LocalRunPlan, @host.ClientSavedSubmissionSnapshot), Int] {
  guard value.runs.get(run) is Some(record) &&
    record.outcome is Some(Ok(plan)) &&
    record.sdk_submission is Some(submission) &&
    value.submissions.get(submission) is Some(original) &&
    value.run_configurations.get(current_configuration) is Some(current) &&
    current.sdk is Some(_) else {
    return Err(-2)
  }
  if record.restoration is Some(_) {
    return sdk_restored_run_snapshot(value, run, plan).map(snapshot => {
      (plan, snapshot)
    })
  }
  // Keep the same checked preparation, saved initial rows and policy original.
  // The helper already completed the full original journal audit and current
  // fences. Consume that exact snapshot immediately, before another callback,
  // rather than repeating the audit through the same configuration and reader.
  let (snapshot, _, _) = match sdk_saved_original_snapshot(value, run, plan) {
    Err(code) => return Err(code)
    Ok(value) => value
  }
  if record.configuration == current_configuration {
    return Ok((plan, snapshot))
  }
  // A different selected configuration must still perform its own checks.
  match observe_submission_append(value, original, current) {
    Ok(@host.Retained(snapshot)) => Ok((plan, snapshot))
    Ok(@host.Append(_)) => Err(-35)
    Err(code) => Err(code)
  }
}

///|
fn sdk_run_state_current(
  value : Instance,
  output : StoredPublicationCommitExport,
  run : Int,
  current_configuration : Int,
) -> Result[
  (
    @publication.PublicationCommitPreparation,
    @publication.PublicationCommitReadView,
  ),
  Int,
] {
  guard value.publications.get(output.publication) is Some(parent) &&
    value.run_configurations.get(current_configuration) is Some(current) &&
    current.sdk is Some(_) &&
    value.publication_preflights.get(parent.preflight)
    is Some({ closing: false, preflight: Some(preflight), .. }) &&
    parent.observation_checked &&
    !parent.observation_failed &&
    parent.observation_index is Some(index) &&
    parent.observation_publisher is Some(publisher) else {
    return Err(-32)
  }
  if output.closing || output.output_closed {
    return Err(-5)
  }
  let code = validate_publication_run(
    value.nonce,
    output.publication,
    run,
    current_configuration,
  )
  if code != 0 {
    return Err(code)
  }
  match run_configuration_current(value, current) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  if @local_run.validate_local_preflight_run_read_current(
      preflight,
      current.account,
    )
    is Err(_) {
    return Err(-35)
  }
  let code = publication_observation_publisher(
    value,
    parent,
    publisher,
    current_configuration,
    Some(index),
  )
  if code != 0 {
    return Err(code)
  }
  match run_configuration_current(value, current) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  if @local_run.validate_local_preflight_run_read_current(
      preflight,
      current.account,
    )
    is Err(_) {
    return Err(-35)
  }
  publication_commit_export_view(value, parent, current.account)
}

///|
/// The actual original Sealed records and current physical reader frame, not
/// a Store write result or a caller availability flag, establish presence.
/// Retention is checked separately by its existing owner; no read grant issues.
fn sdk_run_state_candidate(
  value : Instance,
  output : StoredPublicationCommitExport,
  run : Int,
  input : @buffers.BufferSlot,
  current_configuration : Int,
) -> Result[(@publication.PublicationContract, String), Int] {
  let (owner, view) = match
    sdk_run_state_current(value, output, run, current_configuration) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  guard input_cursor(value, input) is Some(cursor) &&
    @decode.closed_object(cursor, ["observed_at", "payloads"]) is Ok(fields) &&
    required_text(fields, "observed_at") is Some(at) &&
    @decode.required(fields, "payloads") is Ok(payloads_cursor) &&
    @decode.elements(payloads_cursor) is Ok(payloads) &&
    value.publications.get(output.publication) is Some(parent) &&
    payloads.length() == parent.publications.length() &&
    payloads.length() <= 8 else {
    return Err(-30)
  }
  let selected : Array[(Int, Int, @publication.PublicationContract)] = []
  for payload in payloads {
    guard @decode.closed_object(payload, ["record", "result", "binding"])
      is Ok(fields) else {
      return Err(-30)
    }
    let integer = name => {
      @decode.lookup(fields, name).bind(value => {
        @decode.safe_integer(value).to_option()
      })
    }
    guard integer("record") is Some(record) &&
      record > 0L &&
      record < 2147483648L &&
      integer("result") is Some(result) &&
      result >= 0L &&
      result < 2147483648L &&
      integer("binding") is Some(binding) &&
      binding >= 0L &&
      binding < 2147483648L else {
      return Err(-30)
    }
    let record = record.to_int()
    let result = result.to_int()
    let binding = binding.to_int()
    if selected.any(item => item.0 == record || item.1 == result) {
      return Err(-30)
    }
    let code = validate_publication_commit_payload_binding(
      value.nonce,
      output.publication,
      record,
      current_configuration,
      result,
      binding,
    )
    if code != 0 {
      return Err(code)
    }
    let original = match owner.view_binding(view, binding) {
      Ok(value) => value
      Err(_) => return Err(-32)
    }
    selected.push((record, result, original))
  }
  let manifest = match owner.view_contract(view, 2) {
    Ok(value) if @publication.publication_contract_name(value) ==
      "result_manifest" => value
    _ => return Err(-32)
  }
  let names = match @publication.manifest_result_names(manifest) {
    Ok(value) => value
    Err(_) => return Err(-32)
  }
  let states : Array[String] = []
  let reasons : Array[String] = []
  for name in names {
    let materials = match owner.observed_result_read_materials(view, name, 8) {
      Ok(value) => value
      Err(_) => return Err(-32)
    }
    if !selected.any(item => {
        @publication.publication_contract_identity(item.2) ==
        materials.read.durable_result_binding_cid
      }) {
      return Err(-32)
    }
    match
      @publication.result_read_availability(
        manifest,
        name,
        materials.retention,
        at,
      ) {
      Ok("available") => {
        states.push("available")
        reasons.push("confirmed_present")
      }
      Ok("retention_expired" | "delete_due") => {
        states.push("unavailable")
        reasons.push("retention_expired")
      }
      _ => return Err(-32)
    }
  }
  let (plan, _) = match
    sdk_run_state_snapshot(value, run, current_configuration) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  let run_id = match
    @publication.run_definition_run_id(@local_run.local_run_definition(plan)) {
    Ok(value) => value
    Err(_) => return Err(-32)
  }
  let wire = match
    @publication.issue_succeeded_run_state_wire(
      run_id,
      at,
      names,
      names,
      states,
      reasons,
      names.map(_ => at),
      65536,
      8192,
      64,
    ) {
    Ok(value) => value
    Err(_) => return Err(-32)
  }
  match sdk_run_state_current(value, output, run, current_configuration) {
    Ok(_) => Ok((manifest, wire))
    Err(code) => Err(code)
  }
}

///|
/// Prepare the existing same-row metadata CAS. This output is not public state
/// until the physical Host confirms the exact committed original row.
pub fn produce_publication_sdk_run_state(
  nonce : Int64,
  handle : Int,
  run : Int,
  input : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(output) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  if output.invoked || output.pending || output.produced {
    return -33
  }
  match sdk_run_state_current(value, output, run, current_configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  output.invoked = true
  output.projection = Some(SDKRunState(input, run))
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(value) => value
    Err(issue) => return issue_code(issue)
  }
  output.state_borrow = Some(borrow)
  let (manifest, wire) = match
    sdk_run_state_candidate(value, output, run, slot, current_configuration) {
    Ok(value) => value
    Err(code) => return code
  }
  let (plan, snapshot) = match
    sdk_run_state_snapshot(value, run, current_configuration) {
    Ok(value) => value
    Err(code) => return code
  }
  let update = match
    @host.prepare_client_saved_run_state_update(
      snapshot,
      @local_run.local_run_request(plan),
      @local_run.local_run_definition(plan),
      manifest,
      wire,
    ) {
    Ok(value) => value
    Err(_) => return -35
  }
  output.sdk_run_state_update = Some(update)
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
    @encode.finish(writer)
  } catch {
    _ => return -34
  }
  let code = status(
    @buffers.supply_buffer_output(value.pool, output.slot, @utf8.encode(packet)),
  )
  if code != 0 {
    return code
  }
  output.produced = true
  validate_publication_sdk_run_state(nonce, handle, current_configuration)
}

///|
fn sdk_run_state_validate(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
  committed : Bool,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(output) &&
    output.produced &&
    output.projection is Some(SDKRunState(input, run)) &&
    output.sdk_run_state_update is Some(update) &&
    value.copies.get(input) is Some((slot, _)) else {
    return -2
  }
  match
    sdk_run_state_candidate(value, output, run, slot, current_configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  let (_, snapshot) = match
    sdk_run_state_snapshot(value, run, current_configuration) {
    Ok(value) => value
    Err(code) => return code
  }
  if committed {
    if @host.confirm_client_saved_run_state_update(update, snapshot) is Err(_) {
      return -35
    }
  } else if @host.validate_client_saved_run_state_update_original(
      update, snapshot,
    )
    is Err(_) {
    return -35
  }
  match sdk_run_state_current(value, output, run, current_configuration) {
    Err(code) => code
    Ok(_) => 0
  }
}

///|
pub fn validate_publication_sdk_run_state(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  sdk_run_state_validate(nonce, handle, current_configuration, false)
}

///|
pub fn confirm_publication_sdk_run_state(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  sdk_run_state_validate(nonce, handle, current_configuration, true)
}
