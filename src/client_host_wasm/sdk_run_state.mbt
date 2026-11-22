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
// Prepare the same RunState observation once on its own original buffer loan.
fn prepare_sdk_run_state_update(
  nonce : Int64,
  handle : Int,
  run : Int,
  input : Int,
  current_configuration : Int,
  measured? : Bool = false,
) -> Result[
  (@host.ClientSavedRunStateUpdate, StoredPublicationCommitExport),
  Int,
] {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(output) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return Err(-2)
  }
  if output.invoked || output.pending || output.produced {
    return Err(-33)
  }
  output.pending = true
  let prepared = prepare_sdk_run_state_update_body(
    value, output, run, slot, physical, handle, input, current_configuration, measured,
  )
  output.pending = false
  prepared.map(update => (update, output))
}

///|
fn prepare_sdk_run_state_update_body(
  value : Instance,
  output : StoredPublicationCommitExport,
  run : Int,
  slot : @buffers.BufferSlot,
  physical : Int,
  handle : Int,
  input : Int,
  current_configuration : Int,
  measured : Bool,
) -> Result[@host.ClientSavedRunStateUpdate, Int] {
  match sdk_run_state_current(value, output, run, current_configuration) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  if output.closing {
    return Err(-5)
  }
  output.invoked = true
  output.projection = Some(SDKRunState(input, run))
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue_code(issue))
  }
  output.state_borrow = Some(borrow)
  if measured {
    guard sdk_run_state_update_construction_capacity() is Some((r, e)) else {
      return Err(-4)
    }
    match @resources.reserve_capacity(value.root, r, e) {
      Ok(capacity) => output.sdk_run_state_update_capacity = Some(capacity)
      Err(_) => return Err(-4)
    }
  }
  let (update, prior_bytes) = match
    build_sdk_run_state_update(value, output, run, slot, current_configuration) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  // Store the candidate before any reconciliation can fail. The constructor
  // frame has returned, so no parsed snapshot or wrapped-state alias escapes.
  output.sdk_run_state_update = Some(update)
  if measured {
    match
      reconcile_sdk_run_state_update_capacity(
        value, output, prior_bytes, update,
      ) {
      Ok(_) => ()
      Err(code) => return Err(code)
    }
  }
  if output.closing {
    Err(-5)
  } else {
    Ok(update)
  }
}

///|
fn build_sdk_run_state_update(
  value : Instance,
  output : StoredPublicationCommitExport,
  run : Int,
  slot : @buffers.BufferSlot,
  current_configuration : Int,
) -> Result[(@host.ClientSavedRunStateUpdate, Int), Int] {
  let (manifest, wire) = match
    sdk_run_state_candidate(value, output, run, slot, current_configuration) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  let (plan, snapshot) = match
    sdk_run_state_snapshot(value, run, current_configuration) {
    Ok(value) => value
    Err(code) => return Err(code)
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
    Err(_) => return Err(-35)
  }
  let prior_bytes = @host.client_saved_submission_row(snapshot).body.length()
  Ok((update, prior_bytes))
}

///|
fn write_sdk_run_state_transport(
  writer : @encode.Writer,
  update : @host.ClientSavedRunStateUpdate,
) -> Unit raise {
  let (key, prior, revision, body) = @host.client_saved_run_state_update_row(
    update,
  )
  write_sdk_run_state_fields(
    writer,
    key,
    prior,
    revision,
    body,
    @host.client_saved_run_state_update_candidate_wire(update),
  )
}

///|
fn write_sdk_run_state_fields(
  writer : @encode.Writer,
  key : String,
  prior : Int64,
  revision : Int64,
  body : Bytes,
  state : String,
) -> Unit raise {
  @encode.begin_object(writer)
  @encode.key(writer, "body")
  @encode.string_value(writer, @utf8.decode(body))
  @encode.key(writer, "key")
  @encode.string_value(writer, key)
  @encode.key(writer, "kind")
  @encode.string_value(
    writer,
    if prior == revision {
      "retained"
    } else {
      "replace"
    },
  )
  @encode.key(writer, "revision")
  @encode.string_value(writer, prior.to_string())
  @encode.key(writer, "state")
  @encode.string_value(writer, state)
  @encode.end_object(writer)
}

///|
// Scoped constructor capacity, apart from the output slot's Core wire and
// Python copies. The nested row has already been admitted by the original CAS
// owner. UTF8 decoding owns at most one UTF16 unit per original byte. The
// actual text writer's backing, trim and synchronous controls are separate.
fn sdk_run_state_transport_capacity(
  update : @host.ClientSavedRunStateUpdate,
  output_bytes : Int,
) -> Int64? {
  let (_, _, _, body) = @host.client_saved_run_state_update_row(update)
  guard @encode.text_writer_construction_inventory(output_bytes, 16, 1)
    is Some(writer) else {
    return None
  }
  @execution.preparation_representation_cost({
    // Extra decode result, tuple, writer/outcome and original size controls.
    record_headers: writer.record_headers + 12L,
    reference_slots: writer.reference_slots + 16L,
    scalar_words: writer.scalar_words + 16L,
    owned_utf16_units: writer.owned_utf16_units + body.length().to_int64(),
    owned_wire_bytes: 0L,
  })
}

///|
fn[T] with_sdk_run_state_transport_capacity(
  value : Instance,
  output : StoredPublicationCommitExport,
  update : @host.ClientSavedRunStateUpdate,
  bytes : Int,
  encode : () -> Result[T, Int],
) -> Result[T, Int] {
  guard output.sdk_run_state_transport is None &&
    sdk_run_state_transport_capacity(update, bytes) is Some(working) else {
    return Err(-4)
  }
  let capacity = match @resources.reserve_capacity(value.root, 0L, working) {
    Ok(capacity) => capacity
    Err(_) => return Err(-4)
  }
  output.sdk_run_state_transport = Some(capacity)
  let result = encode()
  match @resources.settle_capacity(value.root, capacity) {
    Ok(_) => output.sdk_run_state_transport = None
    Err(_) => if result is Ok(_) { return Err(-4) }
  }
  result
}

///|
fn emit_sdk_run_state_transport(
  value : Instance,
  output : StoredPublicationCommitExport,
  update : @host.ClientSavedRunStateUpdate,
  bytes : Int,
  exact? : Bool = false,
) -> Result[Unit, Int] {
  // No code after success in this frame retains the decoded/escaped Strings.
  let packet = try {
    let writer = @encode.writer(bytes, 16, 1)
    write_sdk_run_state_transport(writer, update)
    @encode.finish(writer)
  } catch {
    _ => return Err(-34)
  }
  let wire = @utf8.encode(packet)
  if exact && wire.length() != bytes {
    return Err(-34)
  }
  let result = status(
    @buffers.supply_buffer_output(value.pool, output.slot, wire),
  )
  if result == 0 {
    Ok(())
  } else {
    Err(result)
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
  guard selected(nonce) is Some(value) else { return -2 }
  let (update, output) = match
    prepare_sdk_run_state_update(
      nonce, handle, run, input, current_configuration,
    ) {
    Ok(prepared) => prepared
    Err(code) => return code
  }
  match emit_sdk_run_state_transport(value, output, update, 1048576) {
    Err(code) => return code
    Ok(_) => output.produced = true
  }
  validate_publication_sdk_run_state(nonce, handle, current_configuration)
}

///|
/// Prepare one actual update and measure its existing closed transport. The
/// small original holder is not a body output and cannot be confirmed alone.
pub fn measure_publication_sdk_run_state(
  nonce : Int64,
  handle : Int,
  run : Int,
  input : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(output) &&
    @buffers.buffer_output_limit(value.pool, output.slot) == Some(1) else {
    return -2
  }
  let (update, original) = match
    prepare_sdk_run_state_update(
      nonce,
      handle,
      run,
      input,
      current_configuration,
      measured=true,
    ) {
    Ok(prepared) => prepared
    Err(code) => return code
  }
  original.pending = true
  let extent = with_sdk_run_state_transport_capacity(
    value,
    original,
    update,
    0,
    () => {
      try {
        let writer = @encode.measuring_writer(1048576, 16, 1)
        write_sdk_run_state_transport(writer, update)
        Ok(@encode.finish_measurement(writer))
      } catch {
        _ => Err(-34)
      }
    },
  )
  original.pending = false
  let bytes = match extent {
    Ok(bytes) => bytes
    Err(code) => return code
  }
  if original.closing {
    return -5
  }
  original.projection = Some(SDKMeasuredRunState(input, run, bytes, false))
  bytes
}

///|
/// Emit the same prepared update into its independently funded body slot.
/// Original current and prior-row validation still govern the subsequent CAS.
pub fn emit_publication_sdk_run_state(
  nonce : Int64,
  handle : Int,
  first_handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(output) &&
    value.commit_exports.get(first_handle) is Some(original) &&
    output.publication == original.publication &&
    original.projection
    is Some(SDKMeasuredRunState(input, run, bytes, attempted)) &&
    original.sdk_run_state_update is Some(update) else {
    return -2
  }
  if output.closing || original.closing {
    return -5
  }
  if output.invoked ||
    output.pending ||
    attempted ||
    original.produced ||
    original.pending {
    return -33
  }
  guard @buffers.buffer_output_limit(value.pool, output.slot) == Some(bytes) else {
    return -4
  }
  // Retain this particular body before current callbacks or encoding can
  // fail. Even a partial write stays attached to the original update.
  output.invoked = true
  output.sdk_payload_parent = Some(first_handle)
  original.projection = Some(SDKMeasuredRunState(input, run, bytes, true))
  original.pending = true
  output.pending = true
  let result = match
    sdk_run_state_current(value, original, run, current_configuration) {
    Err(code) => Err(code)
    Ok(_) if output.closing || original.closing => Err(-5)
    Ok(_) =>
      with_sdk_run_state_transport_capacity(value, output, update, bytes, () => {
        emit_sdk_run_state_transport(value, output, update, bytes, exact=true)
      })
  }
  original.pending = false
  output.pending = false
  match result {
    Err(code) => return code
    Ok(_) => {
      output.produced = true
      original.produced = true
    }
  }
  validate_publication_sdk_run_state(nonce, first_handle, current_configuration)
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
    output.sdk_run_state_update is Some(update) else {
    return -2
  }
  let (input, run) = match output.projection {
    Some(SDKRunState(input, run))
    | Some(SDKMeasuredRunState(input, run, _, _)) => (input, run)
    _ => return -2
  }
  guard value.copies.get(input) is Some((slot, _)) else { return -2 }
  if output.pending {
    return -33
  }
  output.pending = true
  let code = sdk_run_state_validate_body(
    value, output, run, slot, current_configuration, update, committed,
  )
  output.pending = false
  code
}

///|
fn sdk_run_state_validate_body(
  value : Instance,
  output : StoredPublicationCommitExport,
  run : Int,
  slot : @buffers.BufferSlot,
  current_configuration : Int,
  update : @host.ClientSavedRunStateUpdate,
  committed : Bool,
) -> Int {
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
