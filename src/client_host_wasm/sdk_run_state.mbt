///|
const SAVED_SDK_RUN_STATE_MAX_BYTES : Int = 65536

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
    @host.client_saved_submission_retained_state_original(snapshot)
    is Some(retained) else {
    return Err(-42)
  }
  let submitted = @host.client_saved_submission_record(snapshot)
  guard submitted.run_admission is Some(_) &&
    submitted.run_state_original is Some(wire) &&
    submitted.run_state_observation is Some((revision, Some(key))) else {
    return Err(-42)
  }
  // A decoded row is not enough: the snapshot's existing nested validator has
  // already admitted these same originals. Require their SDK provenance too.
  guard @host.decode_client_run_journal_row_with_observation_originals(row.body)
    is Ok((run, Some(_), Some(_))) &&
    retained.matches(run.definition, wire, revision, key) &&
    retained.resolve() is Ok(state) else {
    return Err(-32)
  }
  Ok(@utf8.encode(state.state_wire()))
}

///|
fn ordinary_sdk_run_state_snapshot(
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
/// Borrow the live File snapshot only inside its actual adopted Journal Read.
/// The callback receives the same checked Request and Definition used by the
/// ordinary state codec. It cannot become a second source-free preparation.
fn[T] with_sdk_file_state_snapshot(
  value : Instance,
  parent : StoredPublication,
  file : StoredFilePublicationCapture,
  run : Int,
  current : StoredRunConfiguration,
  consume : (
    @host.ClientRequestIdentity,
    @publication.PublicationContract,
    @host.ClientSavedSubmissionSnapshot,
  ) -> Result[T, Int],
  saved_state_update? : @host.ClientSavedRunStateUpdate? = None,
  read_predecessor? : Bool = false,
) -> Result[T, Int] {
  guard sdk_file_publication_owns_run(value, parent, file, run) &&
    value.publication_preflights.get(parent.preflight)
    is Some({ origin: FilePublicationPreflight(active), closing: false, .. }) &&
    physical_equal(active, file.original) &&
    active.prepared is Some(preflight) else {
    return Err(-35)
  }
  with_file_publication_preflight_read(
    value,
    active,
    (_, _, _, _, original, snapshot, locator, read) => {
      @local_run.check_local_captured_task_publication_run_state(
        preflight,
        snapshot,
        locator,
        current.account,
        original.context_cid,
        read,
        saved_state_update~,
        read_predecessor~,
      )
      .map_err(file_preflight_issue)
      .bind(materials => consume(materials.0, materials.1, snapshot))
    },
    selected_file_projection=true,
  )
}

///|
fn[T] with_sdk_run_state_snapshot(
  value : Instance,
  output : StoredPublicationCommitExport,
  run : Int,
  current_configuration : Int,
  consume : (
    @host.ClientRequestIdentity,
    @publication.PublicationContract,
    @host.ClientSavedSubmissionSnapshot,
  ) -> Result[T, Int],
  saved_state_update? : @host.ClientSavedRunStateUpdate? = None,
) -> Result[T, Int] {
  guard value.publications.get(output.publication) is Some(parent) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return Err(-2)
  }
  if parent.file is Some(file) {
    return with_sdk_file_state_snapshot(
      value,
      parent,
      file,
      run,
      current,
      consume,
      saved_state_update~,
    )
  }
  ordinary_sdk_run_state_snapshot(value, run, current_configuration).bind(original => {
    let (plan, snapshot) = original
    consume(
      @local_run.local_run_request(plan),
      @local_run.local_run_definition(plan),
      snapshot,
    )
  })
}

///|
fn sdk_run_state_read_current(
  value : Instance,
  parent : StoredPublication,
  run : Int,
  current : StoredRunConfiguration,
  saved_state_update? : @host.ClientSavedRunStateUpdate? = None,
) -> Result[Unit, Int] {
  guard value.publication_preflights.get(parent.preflight)
    is Some({ closing: false, .. } as original) else {
    return Err(-32)
  }
  match original.origin {
    ComputePublicationPreflight({ prepared: Some(preflight), .. }) =>
      @local_run.validate_local_preflight_run_read_current(
        preflight,
        current.account,
      ).map_err(_ => -35)
    FilePublicationPreflight(_) =>
      match parent.file {
        Some(file) =>
          with_sdk_file_state_snapshot(
            value,
            parent,
            file,
            run,
            current,
            (_, _, _) => Ok(()),
            saved_state_update~,
          )
        None => Err(-35)
      }
    _ => Err(-32)
  }
}

///|
fn sdk_run_state_current(
  value : Instance,
  output : StoredPublicationCommitExport,
  run : Int,
  current_configuration : Int,
  saved_state_update? : @host.ClientSavedRunStateUpdate? = None,
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
  match
    sdk_run_state_read_current(value, parent, run, current, saved_state_update~) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  let code = publication_observation_publisher(
    value,
    parent,
    publisher,
    current_configuration,
    Some(index),
    file_state=saved_state_update.map(update => (output.publication, update)),
  )
  if code != 0 {
    return Err(code)
  }
  match run_configuration_current(value, current) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  match
    sdk_run_state_read_current(value, parent, run, current, saved_state_update~) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  match (parent.file, saved_state_update) {
    (Some(file), Some(update)) =>
      checked_publication_commit_view(value, parent, () => {
        sdk_file_live_state_read_current(
          value,
          output.publication,
          parent,
          file,
          run,
          current,
          confirm_update=Some(update),
        )
      })
    _ => publication_commit_export_view(value, parent, current.account)
  }
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
  saved_state_update? : @host.ClientSavedRunStateUpdate? = None,
) -> Result[(@publication.PublicationContract, String), Int] {
  let (owner, view) = match
    sdk_run_state_current(
      value,
      output,
      run,
      current_configuration,
      saved_state_update~,
    ) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  guard input_cursor(value, input) is Some(cursor) &&
    @decode.closed_object(cursor, ["observed_at", "payloads"]) is Ok(fields) &&
    required_text(fields, "observed_at") is Some(at) &&
    @decode.required(fields, "payloads") is Ok(payloads_cursor) &&
    @decode.elements(payloads_cursor) is Ok(payloads) &&
    value.publications.get(output.publication) is Some(parent) &&
    payloads.length() == publication_result_count(parent) &&
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
  let run_id = match
    with_sdk_run_state_snapshot(
      value,
      output,
      run,
      current_configuration,
      (_, definition, _) => {
        @publication.run_definition_run_id(definition).map_err(_ => -32)
      },
      saved_state_update~,
    ) {
    Ok(value) => value
    Err(code) => return Err(code)
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
  match
    sdk_run_state_current(
      value,
      output,
      run,
      current_configuration,
      saved_state_update~,
    ) {
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
    value, output, run, slot, physical, handle, input, current_configuration,
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
) -> Result[@host.ClientSavedRunStateUpdate, Int] {
  match sdk_run_state_current(value, output, run, current_configuration) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  if output.closing {
    return Err(-5)
  }
  output.invoked = true
  output.projection = Some(SDKMeasuredRunState(input, run, 0, false))
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue_code(issue))
  }
  output.state_borrow = Some(borrow)
  guard sdk_run_state_update_construction_capacity() is Some((r, e)) else {
    return Err(-4)
  }
  match @resources.reserve_capacity(value.root, r, e) {
    Ok(capacity) => output.sdk_run_state_update_capacity = Some(capacity)
    Err(_) => return Err(-4)
  }
  let (update, prior_bytes) = match
    build_sdk_run_state_update(value, output, run, slot, current_configuration) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  // Store the candidate before any reconciliation can fail. The constructor
  // frame has returned, so no parsed snapshot or wrapped-state alias escapes.
  output.sdk_run_state_update = Some(update)
  match
    reconcile_sdk_run_state_update_capacity(value, output, prior_bytes, update) {
    Ok(_) => ()
    Err(code) => return Err(code)
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
  with_sdk_run_state_snapshot(value, output, run, current_configuration, (
    request,
    definition,
    snapshot,
  ) => {
    @host.prepare_client_saved_run_state_update(
      snapshot, request, definition, manifest, wire,
    )
    .map_err(_ => -35)
    .map(update => {
      (update, @host.client_saved_submission_row(snapshot).body.length())
    })
  })
}

///|
const SDK_RUN_STATE_TRANSPORT_HEADER : Int = 84

///|
fn sdk_run_state_transport_extent(
  key : String,
  body : Bytes,
  state : String,
) -> Int? {
  guard @scalar.utf8_length_within(key, 71) == Some(71) &&
    body.length() > 0 &&
    body.length() < 1048576 - SDK_RUN_STATE_TRANSPORT_HEADER &&
    @scalar.utf8_length_within(
      state,
      1048576 - SDK_RUN_STATE_TRANSPORT_HEADER - body.length(),
    )
    is Some(state_bytes) &&
    state_bytes > 0 else {
    return None
  }
  Some(SDK_RUN_STATE_TRANSPORT_HEADER + body.length() + state_bytes)
}

///|
// The main output slot pays for the complete packet. The synchronous writer
// owns just the two UTF-8 temporaries and fixed output construction controls.
fn with_sdk_run_state_transport_capacity(
  value : Instance,
  output : StoredPublicationCommitExport,
  temporary_bytes : Int,
  encode : () -> Result[Unit, Int],
) -> Result[Unit, Int] {
  guard @execution.preparation_representation_cost({
      record_headers: 12L,
      reference_slots: 16L,
      scalar_words: 16L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 2L * temporary_bytes.to_int64(),
    })
    is Some(working) else {
    return Err(-4)
  }
  with_sdk_export_transport_capacity(value, output, working, encode)
}

///|
// Private binary image: prior revision, body extent, change flag, exact
// Submission key, original row bytes, then original public State UTF-8.
fn sdk_run_state_transport_packet(
  key : String,
  prior : Int64,
  revision : Int64,
  body : Bytes,
  state : String,
  bytes : Int,
) -> Bytes? {
  guard sdk_run_state_transport_extent(key, body, state) == Some(bytes) &&
    prior >= 0L &&
    (
      revision == prior ||
      (prior < 9223372036854775807L && revision == prior + 1L)
    ) else {
    return None
  }
  let key_bytes = @utf8.encode(key)
  let state_bytes = @utf8.encode(state)
  let body_end = SDK_RUN_STATE_TRANSPORT_HEADER + body.length()
  Some(
    Bytes::makei(bytes, index => {
      if index < 8 {
        (prior >> (index * 8)).to_byte()
      } else if index < 12 {
        (body.length() >> ((index - 8) * 8)).to_byte()
      } else if index == 12 {
        if revision == prior {
          b'\x00'
        } else {
          b'\x01'
        }
      } else if index < SDK_RUN_STATE_TRANSPORT_HEADER {
        key_bytes[index - 13]
      } else if index < body_end {
        body[index - SDK_RUN_STATE_TRANSPORT_HEADER]
      } else {
        state_bytes[index - body_end]
      }
    }),
  )
}

///|
fn emit_sdk_run_state_transport(
  value : Instance,
  output : StoredPublicationCommitExport,
  update : @host.ClientSavedRunStateUpdate,
  bytes : Int,
) -> Result[Unit, Int] {
  let (key, prior, revision, body) = @host.client_saved_run_state_update_row(
    update,
  )
  let state = @host.client_saved_run_state_update_candidate_wire(update)
  with_sdk_run_state_transport_capacity(value, output, bytes - body.length(), () => {
    guard sdk_run_state_transport_packet(
        key, prior, revision, body, state, bytes,
      )
      is Some(wire) else {
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
  })
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
      nonce, handle, run, input, current_configuration,
    ) {
    Ok(prepared) => prepared
    Err(code) => return code
  }
  let (key, _, _, body) = @host.client_saved_run_state_update_row(update)
  let state = @host.client_saved_run_state_update_candidate_wire(update)
  guard sdk_run_state_transport_extent(key, body, state) is Some(bytes) else {
    return -34
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
    bytes > 0 &&
    original.sdk_run_state_update is Some(update) else {
    return -2
  }
  if output.closing || original.closing {
    return -5
  }
  guard value.publications.get(original.publication) is Some(parent) else {
    return -2
  }
  if parent.file is Some(file) && file.state_export is Some(_) {
    return -33
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
    Ok(_) => emit_sdk_run_state_transport(value, output, update, bytes)
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
  let checked = validate_publication_sdk_run_state(
    nonce, first_handle, current_configuration,
  )
  if checked != 0 {
    return checked
  }
  if parent.file is Some(file) {
    guard !parent.closing &&
      !original.closing &&
      !output.closing &&
      value.publications.get(original.publication) is Some(active) &&
      physical_equal(active, parent) &&
      file.state_export is None else {
      return -35
    }
    // The existing export retains both the update and its capacity through
    // lost CAS return. This handle alone is never a confirmation.
    file.state_export = Some(first_handle)
  }
  0
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
    Some(SDKMeasuredRunState(input, run, _, _)) => (input, run)
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
  let saved_state_update = if committed &&
    value.publications.get(output.publication) is Some({ file: Some(_), .. }) {
    Some(update)
  } else {
    None
  }
  match
    sdk_run_state_candidate(
      value,
      output,
      run,
      slot,
      current_configuration,
      saved_state_update~,
    ) {
    Err(code) => return code
    Ok(_) => ()
  }
  let validated = with_sdk_run_state_snapshot(
    value,
    output,
    run,
    current_configuration,
    (_, _, snapshot) => {
      if committed {
        @host.confirm_client_saved_run_state_update(update, snapshot)
        .map(_ => ())
        .map_err(_ => -35)
      } else {
        @host.validate_client_saved_run_state_update_original(update, snapshot).map_err(_ => {
            -35
          },
        )
      }
    },
    saved_state_update~,
  )
  match validated {
    Err(code) => return code
    Ok(_) => ()
  }
  match
    sdk_run_state_current(
      value,
      output,
      run,
      current_configuration,
      saved_state_update~,
    ) {
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
