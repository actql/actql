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
  mut mock_start : StoredMockEffectSDKStart?
  mut sdk_publication : StoredSDKPublicationBinding?
  mut file_publication : StoredSDKFilePublication?
  mut file_start : StoredSDKFileStart?
}

///|
priv enum StoredSubmittedJournalCandidate {
  Retained(@host.ClientEffectRunJournalAppend, @resources.CapacityReservation)
  RetainedFile(
    @host.ClientCapturedTaskFirstRunRows,
    @resources.CapacityReservation,
    Int64
  )
  Closing(@resources.CapacityReservation)
}

///|
priv struct StoredSubmittedMaterial {
  current_configuration : Int
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  mut rows : @local_run.LocalSubmittedRunRows?
  mut sdk_wire : String?
  mut length_reader_serial : Int64
  mut task_materials : @local_run.LocalRunTaskMaterialsOriginal?
  effect : Bool
  portable_model : Bool
  mut journal_workspace : @resources.CapacityReservation?
  mut file_candidate_workspace : @resources.CapacityReservation?
  mut file_publication_material : Int?
  mut journal_candidate : StoredSubmittedJournalCandidate?
  mut first_journal_observed : Bool
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
  if (kind == 7 || kind == 8) &&
    selected(nonce) is Some(value) &&
    value.runs.get(run) is Some(record) &&
    sdk_whole_file_rows_handle(value, run, record.configuration) is Some(rows) {
    return reserve_sdk_file_start(
      value, run, rows, kind, physical_ticket, physical_copy_bytes,
    )
  }
  if kind == 9 &&
    selected(nonce) is Some(value) &&
    value.runs.get(run) is Some(record) &&
    sdk_whole_file_rows_handle(value, run, record.configuration) is Some(rows) {
    return reserve_sdk_file_publication(
      value,
      run,
      record.configuration,
      rows,
      physical_ticket,
      physical_copy_bytes,
    )
  }
  guard selected(nonce) is Some(value) &&
    value.runs.get(run) is Some(record) &&
    (
      record.outcome is Some(Ok(_)) ||
      ((kind == 7 || kind == 8) && mock_effect_start_run(value, record))
    ) else {
    return -2
  }
  if (kind < 1 || kind > 5) && kind != 7 && kind != 8 && kind != 9 {
    return -3
  }
  if (kind == 7 || kind == 8) && mock_effect_start_run(value, record) {
    if value.closing || value.runtime_closing {
      return -5
    }
    match mock_effect_start_dependencies(value, run, kind, None) {
      Err(code) => return code
      Ok(_) => ()
    }
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
  wire_limit? : Int = 1048576,
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
    @buffers.reserve_output_buffer(
      value.pool,
      wire_limit,
      physical_copy_bytes,
      () => physical_input_cleanup(physical_ticket) == 0,
    ) {
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
    mock_start: None,
    sdk_publication: None,
    file_publication: None,
    file_start: None,
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
    value.preparations.get(record.preparation) is Some(preparation) &&
    value.run_configurations.get(current_configuration) is Some(configuration) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  let selected_model = match configuration.sdk {
    Some({ portable_model: Some(_), .. }) => {
      guard record.configuration == current_configuration &&
        record.sdk_submission is Some(submission) &&
        retained_sdk_portable_request(
          value, preparation, current_configuration, configuration, submission,
        )
        is Some({ model_run_handle: Some(original), .. }) &&
        original == run &&
        !physical_equal(record.slot, slot) &&
        !physical_equal(preparation.slot, slot) else {
        return -35
      }
      true
    }
    _ => false
  }
  let (selected_effect, selected_file) = if preparation.kind ==
    RETAINED_MOCK_REQUEST_KIND &&
    !selected_model {
    guard record.configuration == current_configuration &&
      preparation.project_request is Some(held) else {
      return -2
    }
    match held.effect_plan {
      Some(plan) => {
        guard physical_equal(record.slot, slot) &&
          plan.sdk_run == Some(run) &&
          plan.journal is Some(journal) &&
          !journal.material_reserved else {
          return -2
        }
        (Some(journal), None)
      }
      None => {
        guard record.invoked &&
          record.restoration is None &&
          record.sdk_submission is Some(original) &&
          configuration.host_current is Some(_) &&
          held.whole_file_sdk_run == Some(run) &&
          !physical_equal(record.slot, slot) &&
          !physical_equal(preparation.slot, slot) &&
          sdk_whole_file_request(value, preparation, configuration) is Some(_) &&
          sdk_whole_file_preparing_submission(
            value, preparation, current_configuration, original,
          )
          is Some(_) else {
          return -2
        }
        match held.whole_file_sdk_phase {
          PlanReady => (None, Some(held))
          ReservingRows | RowsReserved(_) => return -33
          AwaitingPlan => return -2
        }
      }
    }
  } else {
    guard record.outcome is Some(Ok(_)) && preparation.submitted is Some(_) else {
      return -2
    }
    (None, None)
  }
  if selected_file is Some(held) {
    held.whole_file_sdk_phase = ReservingRows
  }
  let handle = reserve_material_record(
    value, run, 6, physical_ticket, physical_copy_bytes,
  )
  if handle <= 0 {
    // A refused output reservation did not expose a material handle. Only
    // this entry owns that pending File transition, including during cleanup.
    if selected_file is Some(held) {
      held.whole_file_sdk_phase = PlanReady
    }
    return handle
  }
  if selected_effect is Some(journal) {
    journal.material_reserved = true
  }
  let borrow = @buffers.borrow_buffer(value.pool, slot, () => {
    physical_reader_stop(physical, handle) == 0
  })
  value.materials[handle].submission = Some({
    current_configuration,
    borrow,
    rows: None,
    sdk_wire: None,
    length_reader_serial: 0L,
    task_materials: None,
    effect: selected_effect is Some(_),
    portable_model: selected_model,
    journal_workspace: None,
    file_candidate_workspace: None,
    file_publication_material: None,
    journal_candidate: None,
    first_journal_observed: false,
  })
  if selected_file is Some(held) {
    // Borrow refusal, if any, belongs to this already-issued material. Its
    // normal close retires the original output. Do not re-open first issuance.
    held.whole_file_sdk_phase = RowsReserved(handle)
  }
  handle
}

///|
fn read_submitted_rows_material_input(
  value : Instance,
  submission : StoredSubmittedMaterial,
) -> Result[(@host.ClientSubmissionReferenceRecord, String, Double), Int] {
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
  @host.admit_client_submission_reference_record(reference)
  .map(reference => (reference, preparing, now))
  .map_err(_ => -31)
}

///|
// The File caller uses its already-funded row-input workspace. This reads
// only the separate packet: the nominal snapshot, Account checks, and fresh
// physical journal observation belong to the caller's same Read.
fn check_sdk_whole_file_rows_input(
  value : Instance,
  submission : StoredSubmittedMaterial,
  preparing : @host.ClientSavedSubmissionSnapshot,
) -> Result[Double, Int] {
  let (reference, body, now) = match
    read_submitted_rows_material_input(value, submission) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let record = @host.client_saved_submission_record(preparing)
  let physical = @host.client_saved_submission_row(preparing)
  guard submission_snapshot_is_preparing(preparing) &&
    @host.client_submission_reference_record_wire(reference) ==
    @host.client_submission_reference_record_wire(record.reference) &&
    @utf8.encode(body) == physical.body else {
    return Err(-35)
  }
  guard @host.submission_epoch_validity(
      @host.client_submission_epoch_token_body(
        @host.client_submission_reference_record_epoch(record.reference),
      ),
      now,
    )
    is Ok(Admissible) else {
    return Err(-46)
  }
  Ok(now)
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
  let portable_parent = if submission.portable_model {
    guard value.runs.get(material.run) is Some(run) &&
      run.configuration == submission.current_configuration &&
      run.sdk_submission is Some(selected) &&
      retained_sdk_portable_request(
        value,
        preparation,
        run.configuration,
        current,
        selected,
      )
      is Some({ parent: Some(parent), model_run_handle: Some(original), .. }) &&
      original == material.run else {
      return Err(-35)
    }
    Some(parent)
  } else {
    None
  }
  let (reference, preparing, now) = match
    read_submitted_rows_material_input(value, submission) {
    Ok(value) => value
    Err(issue) => return Err(issue)
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
    let task_materials = match submission.task_materials {
      Some(original) => original
      None => {
        let captured = if portable_parent is Some(parent) {
          @local_run.capture_local_portable_run_task_materials_original(
            plan,
            parent,
            preparation.slot,
          )
        } else {
          guard value.environments.get(preparation.environment)
            is Some(environment) else {
            return Err(-2)
          }
          let bindings = match
            @preparation.local_submitted_preparation_parameters_wire(original) {
            Ok(value) => value
            Err(_) => return Err(-31)
          }
          @local_run.capture_local_run_task_materials_original(
            plan,
            environment.environment,
            environment.wire,
            bindings,
          )
        }
        match captured {
          Ok(original) => {
            submission.task_materials = Some(original)
            original
          }
          Err(_) => return Err(-34)
        }
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
  @host.client_submitted_run_candidate_wire(
    fields,
    issued~,
    reference_locator~,
    task_materials~,
    preparing_revision=0L,
  ).map_err(_ => -34)
}

///|
/// Re-observe in the original write transaction, never accept a cached candidate
/// from a previous snapshot/current generation. This performs no write or ACK.
pub fn validate_submitted_rows_material(nonce : Int64, handle : Int) -> Int {
  inspect_submitted_rows_material(nonce, handle, false)
}

///|
/// Observe the indexed owner only after the actual Run INSERT encountered its
/// Definition constraint and the Host finished rollback. This classifies the
/// original conflict; it does not admit the indexed row for execution.
pub fn inspect_submitted_run_definition_collision(
  nonce : Int64,
  handle : Int,
  current_handle : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.materials.get(handle) is Some(material) &&
    material.kind == 6 &&
    material.produced &&
    !material.closing &&
    !material.output_closed &&
    material.submission is Some(submission) &&
    value.runs.get(material.run) is Some(run) &&
    run.configuration == submission.current_configuration &&
    value.run_configurations.get(run.configuration) is Some(configuration) &&
    configuration.sdk is Some(_) &&
    configuration.host_current == Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(physical) else {
    return -2
  }
  if submission.journal_workspace is Some(_) {
    return -33
  }
  let base = 512L
  let workspace = match @resources.reserve_capacity(value.root, base, base) {
    Ok(token) => token
    Err(_) => return -4
  }
  submission.journal_workspace = Some(workspace)
  let observed = read_submitted_run_definition_collision(
    value, handle, run, submission, configuration, physical, workspace,
  )
  let closed = settle_sdk_submitted_journal_workspace(value, submission)
  match observed {
    Err(code) => code
    Ok(kind) => if closed == 0 { kind } else { closed }
  }
}

///|
fn read_submitted_run_definition_collision(
  value : Instance,
  handle : Int,
  run : StoredRun,
  submission : StoredSubmittedMaterial,
  configuration : StoredRunConfiguration,
  physical : StoredHostCurrent,
  workspace : @resources.CapacityReservation,
) -> Result[Int, Int] {
  fn current() -> Result[Unit, Int] {
    guard !value.closing &&
      !value.runtime_closing &&
      value.materials.get(handle) is Some(material) &&
      !material.closing &&
      !material.output_closed &&
      material.submission is Some(original) &&
      physical_equal(original, submission) &&
      submission.journal_workspace is Some(token) &&
      physical_equal(token, workspace) else {
      return Err(-9)
    }
    run_configuration_current(value, configuration).bind(_ => {
      if physical_journal_current(physical.physical) == 0 {
        Ok(())
      } else {
        Err(-41)
      }
    })
  }
  match current() {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  let (request, definition) = if submission.effect {
    let original = match
      mock_effect_journal_observation_original(value, handle, run.configuration) {
      Ok(value) => value
      Err(code) => return Err(code)
    }
    (original.effect.request, original.journal.materials.run_definition)
  } else if submission.journal_candidate is Some(RetainedFile(_, _, _)) {
    let original = match
      sdk_whole_file_journal_material_original(value, handle, run.configuration) {
      Ok(value) => value
      Err(code) => return Err(code)
    }
    let plan = original.candidate.task_materials.plan
    (plan.request, plan.definition)
  } else {
    guard run.outcome is Some(Ok(plan)) && submission.sdk_wire is Some(_) else {
      return Err(-2)
    }
    (@local_run.local_run_request(plan), @local_run.local_run_definition(plan))
  }
  if physical_journal_schema(physical.physical) != 1 {
    return Err(-41)
  }
  let cid = @publication.publication_contract_identity(definition)
  let row = match
    physical_journal_row(
      physical.physical,
      current,
      1,
      "client_sqlite_run_definition_owner",
      cid,
    ) {
    Ok(Some(row)) => row
    Ok(None) => return Err(-41)
    Err(code) => return Err(code)
  }
  guard journal_decode_row_capacity(row) is Some((retained, execution)) else {
    return Err(-31)
  }
  if @resources.grow_capacity_reservation(
      value.root,
      workspace,
      512L + retained,
      512L + retained + execution,
    )
    is Err(_) {
    return Err(-4)
  }
  guard @host.decode_client_run_journal_row_with_observation_originals(row.body)
    is Ok((owner, policy, _)) &&
    row.key == @host.client_request_scope_cid(owner.request) &&
    @publication.publication_contract_identity(owner.definition) == cid else {
    return Err(-31)
  }
  if policy is Some(wire) &&
    @host.validate_client_local_run_policy_original_run(
      @utf8.encode(wire),
      owner.request,
      owner.definition,
    )
    is Err(_) {
    return Err(-31)
  }
  let kind = match
    @host.client_request_identity_relation(request, owner.request) {
    @host.SameRequest => 1
    @host.DifferentRequest => 2
    @host.ChangedIntent => 3
  }
  current().map(_ => kind)
}

///|
fn inspect_submitted_rows_material(
  nonce : Int64,
  handle : Int,
  for_length : Bool,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.materials.get(handle) is Some(material) &&
    !material.output_closed &&
    !material.closing &&
    material.produced &&
    material.kind == 6 &&
    material.submission is Some(submission) &&
    value.runs.get(material.run) is Some(record) &&
    value.preparations.get(record.preparation) is Some(preparation) else {
    return -2
  }
  if submission.effect {
    return stage_sdk_mock_effect_journal(
      value, handle, material, submission, record, preparation,
    )
  }
  if submission.journal_candidate is Some(RetainedFile(_, _, _)) {
    return validate_sdk_whole_file_journal_rows(
      value, handle, material, submission,
    )
  }
  guard submission.sdk_wire is Some(expected) &&
    record.outcome is Some(Ok(plan)) &&
    value.run_configurations.get(submission.current_configuration)
    is Some(configuration) else {
    return -2
  }
  if for_length && submission.length_reader_serial > 0L {
    match sdk_journal_reader_serial(value, configuration) {
      Ok(serial) if serial == submission.length_reader_serial => {
        guard record.sdk_submission is Some(held) &&
          value.submissions.get(held) is Some(observation) else {
          return -31
        }
        return match
          submission_append_current(value, observation, configuration) {
          Ok(_) => 0
          Err(code) => code
        }
      }
      Ok(_) => ()
      Err(code) => return code
    }
  }
  submission.length_reader_serial = 0L
  let actual = match
    submitted_rows_material_wire(value, material, plan, preparation) {
    Ok(wire) => wire
    Err(code) => return code
  }
  if actual != expected {
    return -35
  }
  // Length only reuses a complete audit from the same still-live physical
  // Reader. The explicit validation at the Run writer always audits afresh.
  if !for_length && !submission.portable_model {
    match sdk_journal_reader_serial(value, configuration) {
      Ok(serial) => submission.length_reader_serial = serial
      Err(code) => return code
    }
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
    value.preparations.get(record.preparation) is Some(preparation) else {
    return -2
  }
  if material.kind == 6 &&
    material.submission is Some(submission) &&
    submission.effect {
    return stage_sdk_mock_effect_journal(
      value, handle, material, submission, record, preparation,
    )
  }
  if material.kind == 6 &&
    material.produced &&
    material.submission
    is Some({ journal_candidate: Some(RetainedFile(_, _, _)), .. }) {
    return validate_submitted_rows_material(nonce, handle)
  }
  if material.kind == 6 &&
    preparation.kind == RETAINED_MOCK_REQUEST_KIND &&
    material.submission is Some(submission) &&
    !submission.portable_model {
    return stage_sdk_whole_file_journal_rows(
      value, handle, material, submission, record, preparation,
    )
  }
  if (material.kind == 7 || material.kind == 8) &&
    mock_effect_start_run(value, record) {
    return produce_mock_effect_sdk_start(value, handle, material, record)
  }
  if material.file_publication is Some(binding) {
    return produce_sdk_file_publication(value, handle, material, binding)
  }
  if material.file_start is Some(start) {
    return produce_sdk_file_start(value, handle, material, start)
  }
  guard record.outcome is Some(Ok(plan)) &&
    preparation.outcome is Some(Ok(input)) else {
    return -2
  }
  let environment = value.environments.get(preparation.environment)
  if environment is None {
    // Portable Model owns a checked Project instead of a conventional
    // Environment buffer. All five projections borrow the same Run and
    // original Submission; Environment export still needs its real input.
    guard (
        material.kind == 5 ||
        material.kind == 6 ||
        material.kind == 7 ||
        material.kind == 8 ||
        material.kind == 9
      ) &&
      record.sdk_submission is Some(submission) &&
      value.run_configurations.get(record.configuration) is Some(current) &&
      retained_sdk_portable_request(
        value,
        preparation,
        record.configuration,
        current,
        submission,
      )
      is Some({ model_run_handle: Some(original), .. }) &&
      original == material.run else {
      return -2
    }
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
      guard environment is Some(environment) else { return -2 }
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
  if material.sdk_publication is Some(_) || material.file_publication is Some(_) {
    let code = validate_sdk_publication_material(nonce, handle)
    if code != 0 {
      return code
    }
  }
  if material.sdk_start is Some(_) ||
    material.mock_start is Some(_) ||
    material.file_start is Some(_) {
    let code = validate_sdk_start_material(nonce, handle)
    if code != 0 {
      return code
    }
  }
  if material.submission is Some(submission) &&
    (
      submission.sdk_wire is Some(_) ||
      (
        material.produced &&
        (
          submission.effect ||
          submission.journal_candidate is Some(RetainedFile(_, _, _))
        )
      )
    ) {
    let code = inspect_submitted_rows_material(nonce, handle, true)
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
  if material.kind == 11 &&
    portable_model_request_worker_active(value, material.run, handle) {
    return -9
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
        child.file_publication is Some({ rows_material, .. }) &&
        rows_material == handle
      ) ||
      (
        child.sdk_start is Some({ publication_material, .. }) &&
        publication_material == handle
      ) ||
      (
        child.file_start is Some(start) &&
        (
          start.publication_material == handle ||
          start.dispatch_material == Some(handle)
        )
      ) ||
      (
        child.mock_start is Some(start) &&
        (start.rows == handle || start.dispatch == Some(handle))
      )
    }) {
    return -9
  }
  // Transport retirement preserves the original rows/input borrow. Full
  // close does not: once its cleanup starts no new observation may borrow it.
  material.closing = true
  if material.file_start is Some(start) {
    let closed = close_sdk_file_start(value, start)
    if closed != 0 {
      return closed
    }
    material.file_start = None
  }
  if material.file_publication is Some(binding) {
    let closed = close_sdk_file_publication(value, binding)
    if closed != 0 {
      return closed
    }
    material.file_publication = None
  }
  if material.mock_start is Some(start) {
    start.step = None
    if @resources.settle_capacity(value.root, start.capacity) is Err(_) {
      return -4
    }
    material.mock_start = None
  }
  if material.submission is Some(submission) {
    let settled = settle_sdk_submitted_journal_workspace(value, submission)
    if settled != 0 {
      return settled
    }
    let settled = settle_sdk_whole_file_candidate_workspace(value, submission)
    if settled != 0 {
      return settled
    }
    let settled = close_sdk_submitted_journal_candidate(value, submission)
    if settled != 0 {
      return settled
    }
  }
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
