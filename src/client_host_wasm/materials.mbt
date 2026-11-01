///|
/// Invocation custody and an existing Ledger reservation, never durable Run
/// state. A failed producer keeps this same handle until physical cleanup.
priv struct StoredMaterial {
  run : Int
  kind : Int
  slot : @buffers.BufferSlot
  mut invoked : Bool
  mut produced : Bool
  mut output_closed : Bool
  mut closing : Bool
  mut submission : StoredSubmittedMaterial?
  mut sdk_start : StoredSDKStartStep?
  mut sdk_publication : StoredSDKPublicationBinding?
}

///|
priv struct StoredSubmittedMaterial {
  current_configuration : Int
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  mut rows : @local_run.LocalSubmittedRunRows?
  mut sdk_wire : String?
  mut task_materials : @local_run.LocalRunTaskMaterialsOriginal?
}

///|
/// Reserve the complete wire allowance before encoding. The original Run
/// remains live until this output retires, including an interrupted export.
pub fn reserve_material(
  nonce : Int64,
  run : Int,
  kind : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.runs.get(run) is Some({ outcome: Some(Ok(_)), .. }) else {
    return -2
  }
  if (kind < 1 || kind > 5) && kind != 7 && kind != 8 && kind != 9 {
    return -3
  }
  reserve_material_record(
    value, run, kind, physical_ticket, physical_copy_bytes,
  )
}

///|
fn reserve_material_record(
  value : Instance,
  run : Int,
  kind : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  if physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.native_commands
    .values()
    .any(command => command.physical_ticket == physical_ticket) ||
    value.result_chunks
    .values()
    .any(chunk => chunk.physical_ticket == physical_ticket) ||
    value.workspaces.values().any(pair => pair.0 == physical_ticket) {
    return -3
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  let slot = match
    @buffers.reserve_output_buffer(value.pool, 1048576, physical_copy_bytes, () => {
      physical_input_cleanup(physical_ticket) == 0
    }) {
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  value.materials[handle] = {
    run,
    kind,
    slot,
    invoked: false,
    produced: false,
    output_closed: false,
    closing: false,
    submission: None,
    sdk_start: None,
    sdk_publication: None,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
/// Original row candidates only. Authentication and complete journal custody
/// must still be observed in the same physical admission transaction.
pub fn reserve_submitted_rows_material(
  nonce : Int64,
  run : Int,
  current_configuration : Int,
  input : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.runs.get(run) is Some(record) &&
    record.outcome is Some(Ok(_)) &&
    value.preparations.get(record.preparation) is Some(preparation) &&
    preparation.submitted is Some(_) &&
    value.run_configurations.contains(current_configuration) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  let handle = reserve_material_record(
    value, run, 6, physical_ticket, physical_copy_bytes,
  )
  if handle <= 0 {
    return handle
  }
  let borrow = @buffers.borrow_buffer(value.pool, slot, () => {
    physical_reader_stop(physical, handle) == 0
  })
  value.materials[handle].submission = Some({
    current_configuration,
    borrow,
    rows: None,
    sdk_wire: None,
    task_materials: None,
  })
  handle
}

///|
fn submitted_rows_material_wire(
  value : Instance,
  material : StoredMaterial,
  plan : @local_run.LocalRunPlan,
  preparation : StoredPreparation,
) -> Result[String, Int] {
  guard material.submission is Some(submission) &&
    preparation.submitted is Some(original) &&
    value.run_configurations.get(submission.current_configuration)
    is Some(current) else {
    return Err(-2)
  }
  let borrow = match submission.borrow {
    Ok(value) => value
    Err(issue) => return Err(issue_code(issue))
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["reference", "preparing", "now"])
    is Ok(object) &&
    required_text(object, "reference") is Some(reference) &&
    required_text(object, "preparing") is Some(preparing) &&
    required_number(object, "now") is Some(now) else {
    return Err(-31)
  }
  let reference = match
    @host.admit_client_submission_reference_record(reference) {
    Ok(value) => value
    Err(_) => return Err(-31)
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
  let rows_result = if current.sdk is Some(_) {
    guard value.runs[material.run].finite_policy is Some(finite) else {
      return Err(-32)
    }
    guard value.environments.get(preparation.environment) is Some(environment) else {
      return Err(-2)
    }
    let bindings = match
      @preparation.local_submitted_preparation_parameters_wire(original) {
      Ok(value) => value
      Err(_) => return Err(-31)
    }
    let task_materials = match submission.task_materials {
      Some(original) => original
      None =>
        match
          @local_run.capture_local_run_task_materials_original(
            plan,
            environment.environment,
            environment.wire,
            bindings,
          ) {
          Ok(original) => {
            submission.task_materials = Some(original)
            original
          }
          Err(_) => return Err(-34)
        }
    }
    @local_run.prepare_local_sdk_submitted_run_rows(
      plan,
      original,
      reference,
      @utf8.encode(preparing),
      permit,
      current.account,
      current.tuple,
      current.context_cid,
      now,
      finite,
      task_materials=Some(task_materials),
    )
  } else {
    @local_run.prepare_local_submitted_run_rows(
      plan,
      original,
      reference,
      @utf8.encode(preparing),
      permit,
      current.account,
      current.tuple,
      current.context_cid,
      now,
      local_policy_original=value.runs[material.run].finite_policy,
    )
  }
  let rows = match rows_result {
    Ok(value) => value
    Err(@local_run.AuthorizationMismatch) => return Err(-32)
    Err(_) => return Err(-31)
  }
  let fields = match @local_run.local_submitted_run_rows(rows, plan, original) {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  let task_materials = match
    @local_run.local_submitted_run_task_materials(rows, plan, original) {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  let issued = if current.sdk is Some(_) {
    guard value.runs[material.run].finite_policy is Some(packet) &&
      value.runs[material.run].sdk_submission is Some(held) &&
      value.submissions.get(held) is Some(observation) else {
      return Err(-31)
    }
    let saved = match observe_submission_append(value, observation, current) {
      Ok(@host.Retained(saved)) => @host.client_saved_submission_row(saved)
      Ok(@host.Append(_)) => return Err(-35)
      Err(code) => return Err(code)
    }
    if saved.key != fields.1 || saved.body != fields.2 || saved.revision != 0L {
      return Err(-35)
    }
    let candidate = match
      sdk_run_append_candidate(value, current, plan, packet, task_materials) {
      Ok(value) => value
      Err(code) => return Err(code)
    }
    let (key, body, revision, count) = @host.client_run_journal_append_rows(
      candidate,
    )
    if key != fields.0 || body != fields.3 {
      return Err(-31)
    }
    Some((revision, count))
  } else {
    None
  }
  // The same original tuple supplies subordinate locator DATA. It is saved
  // with these ready rows, not reconstructed by the physical Python caller.
  let reference_locator = if issued is Some(_) {
    match
      @host.client_saved_run_reference_locator(
        reference,
        @local_run.local_run_request(plan),
        @local_run.local_run_definition(plan),
      ) {
      Ok(value) => Some(value)
      Err(_) => return Err(-31)
    }
  } else {
    None
  }
  // Preserve any existing nominal row Owner held by an observation child.
  if submission.rows is None {
    submission.rows = Some(rows)
  }
  try {
    // At most three original chunks add one array and three closed objects.
    // The existing complete transport byte allowance remains unchanged.
    let writer = @encode.writer(1048576, 24, 3)
    @encode.begin_object(writer)
    for
      (key, text) in [
        ("run_key", fields.0),
        ("submission_key", fields.1),
        ("preparing", @utf8.decode(fields.2)),
        ("run", @utf8.decode(fields.3)),
        ("submitted", @utf8.decode(fields.4)),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, text)
    }
    if issued is Some((revision, count)) {
      @encode.key(writer, "issued_revision")
      @encode.string_value(writer, revision.to_string())
      @encode.key(writer, "issued_body")
      @encode.string_value(writer, @utf8.decode(count))
    }
    if reference_locator is Some((key, body)) {
      @encode.key(writer, "reference_locator")
      @encode.begin_object(writer)
      @encode.key(writer, "key")
      @encode.string_value(writer, key)
      @encode.key(writer, "body")
      @encode.string_value(writer, @utf8.decode(body))
      @encode.end_object(writer)
    }
    if task_materials is Some(original) {
      @encode.key(writer, "task_materials")
      @encode.begin_array(writer)
      for
        (key, body) in @local_run.local_run_task_materials_original_chunks(
          original,
        ) {
        @encode.begin_object(writer)
        @encode.key(writer, "key")
        @encode.string_value(writer, key)
        @encode.key(writer, "body")
        @encode.string_value(writer, body)
        @encode.end_object(writer)
      }
      @encode.end_array(writer)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(-34)
  }
}

///|
/// Re-observe in the original write transaction, never accept a cached candidate
/// from a previous snapshot/current generation. This performs no write or ACK.
pub fn validate_submitted_rows_material(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.materials.get(handle) is Some(material) &&
    !material.output_closed &&
    !material.closing &&
    material.produced &&
    material.kind == 6 &&
    material.submission is Some(submission) &&
    submission.sdk_wire is Some(expected) &&
    value.runs.get(material.run) is Some(record) &&
    record.outcome is Some(Ok(plan)) &&
    value.preparations.get(record.preparation) is Some(preparation) else {
    return -2
  }
  let actual = match
    submitted_rows_material_wire(value, material, plan, preparation) {
    Ok(wire) => wire
    Err(code) => return code
  }
  if actual != expected {
    return -35
  }
  0
}

///|
/// Project existing Owner records. Encoding is not admission, durable storage,
/// physical start or permission to retry. An interrupted handle is not reused.
pub fn produce_material(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.materials.get(handle) is Some(material) &&
    value.runs.get(material.run) is Some(record) &&
    record.outcome is Some(Ok(plan)) &&
    value.preparations.get(record.preparation) is Some(preparation) &&
    preparation.outcome is Some(Ok(input)) &&
    value.environments.get(preparation.environment) is Some(environment) else {
    return -2
  }
  if value.closing ||
    value.runtime_closing ||
    material.output_closed ||
    material.closing {
    return -5
  }
  if material.produced {
    if material.sdk_publication is Some(_) {
      return validate_sdk_publication_material(nonce, handle)
    }
    if material.sdk_start is Some(_) {
      return validate_sdk_start_material(nonce, handle)
    }
    if material.submission is Some({ sdk_wire: Some(_), .. }) {
      return validate_submitted_rows_material(nonce, handle)
    }
    return 0
  }
  if material.invoked {
    return -33
  }
  guard @buffers.buffer_output_limit(value.pool, material.slot) is Some(_) else {
    return -5
  }
  material.invoked = true
  let wire = match material.kind {
    1 => {
      let body = environment.wire
      match
        @local_run.export_local_run_materials(
          plan,
          environment.environment,
          body,
          None,
        ) {
        Ok(wire) => wire
        Err(_) => return -34
      }
    }
    2 =>
      match
        @host.client_request_identity_record_wire(
          @local_run.local_run_request(plan),
        ) {
        Ok(wire) => wire
        Err(_) => return -34
      }
    3 => @local_run.local_run_definition_cid(plan)
    4 =>
      match @preparation.local_prepared_original(input) {
        Program(wire) | Aql(wire) => wire
      }
    5 => {
      // Only the original checked audit can issue a completion-free journal.
      // The retained projection is not durable admission or execution permission.
      let normalization = match record.normalization {
        Some(original) => original
        None =>
          match @local_run.issue_local_run_normalization(plan) {
            Ok(original) => {
              record.normalization = Some(original)
              original
            }
            Err(_) => return -34
          }
      }
      match @local_run.local_run_normalization_evidence(plan, normalization) {
        Ok(evidence) => @publication.run_evidence_value_json(evidence)
        Err(_) => return -34
      }
    }
    6 =>
      match submitted_rows_material_wire(value, material, plan, preparation) {
        Ok(value) => value
        Err(issue) => return issue
      }
    7 | 8 =>
      match sdk_start_material_wire(value, material, record, plan) {
        Ok(wire) => wire
        Err(code) => return code
      }
    9 =>
      match sdk_publication_material_wire(value, material, plan) {
        Ok(wire) => wire
        Err(code) => return code
      }
    _ => return -3
  }
  let result = status(
    @buffers.supply_buffer_output(value.pool, material.slot, @utf8.encode(wire)),
  )
  if result == 0 {
    if material.submission is Some(submission) &&
      value.run_configurations[submission.current_configuration].sdk is Some(_) {
      submission.sdk_wire = Some(wire)
    }
    material.produced = true
  }
  result
}

///|
pub fn material_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.materials.get(handle) is Some(material) else {
    return -2
  }
  if material.sdk_publication is Some(_) {
    let code = validate_sdk_publication_material(nonce, handle)
    if code != 0 {
      return code
    }
  }
  if material.sdk_start is Some(_) {
    let code = validate_sdk_start_material(nonce, handle)
    if code != 0 {
      return code
    }
  }
  if material.submission is Some({ sdk_wire: Some(_), .. }) {
    let code = validate_submitted_rows_material(nonce, handle)
    if code != 0 {
      return code
    }
  }
  match @buffers.buffer_length(value.pool, material.slot) {
    Some(length) => length
    None => -33
  }
}

///|
pub fn close_material(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.materials.get(handle) is Some(material) else {
    return -2
  }
  if value.journal_observations.values().any(child => child.material == handle) {
    return -9
  }
  if value.physical_starts.values().any(child => child.sdk_step == Some(handle)) {
    return -9
  }
  if value.materials
    .values()
    .any(child => {
      (
        child.sdk_publication is Some({ rows_material, .. }) &&
        rows_material == handle
      ) ||
      (
        child.sdk_start is Some({ publication_material, .. }) &&
        publication_material == handle
      )
    }) {
    return -9
  }
  // Transport retirement preserves the original rows/input borrow. Full
  // close does not: once its cleanup starts no new observation may borrow it.
  material.closing = true
  if !material.output_closed {
    let result = status(@buffers.close_buffer(value.pool, material.slot))
    if result != 0 {
      return result
    }
    material.output_closed = true
  }
  let result = match material.submission {
    Some({ borrow: Ok(borrow), .. }) =>
      status(@buffers.return_buffer_borrow(value.pool, borrow))
    _ => 0
  }
  if result == 0 {
    value.materials.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}

///|
/// Retire only the consumed transport through the same Buffer Owner. Original
/// rows/step proof, Run/input borrow and child custody survive until full close.
pub fn retire_material_output(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.materials.get(handle) is Some(material) &&
    material.produced &&
    (
      material.kind == 6 ||
      material.kind == 7 ||
      material.kind == 8 ||
      material.kind == 9
    ) else {
    return -2
  }
  if material.closing {
    return -5
  }
  if material.output_closed {
    return 0
  }
  let code = status(@buffers.close_buffer(value.pool, material.slot))
  if code != 0 {
    return code
  }
  material.output_closed = true
  value.copies.remove(handle) |> ignore
  0
}
