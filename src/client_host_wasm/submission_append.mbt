///|
/// The same original typed Host/Account fence, never a submitted Bool grant.
fn submission_append_current(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[Unit, Int] {
  if value.closing || value.runtime_closing {
    return Err(-5)
  }
  if record.borrow is Err(issue) {
    return Err(issue_code(issue))
  }
  if configuration.host_current is None {
    return Err(-32)
  }
  match run_configuration_current(value, configuration) {
    Ok(_) => ()
    Err(code) => return Err(code)
  }
  if @authorization.evaluate_account(configuration.account, configuration.tuple)
    is @authorization.Allow(_) {
    Ok(())
  } else {
    Err(-32)
  }
}

///|
fn submission_append_run_inspection(
  row : @host.ClientJournalPhysicalRow,
) -> Result[@host.ClientRunJournalInspection, Int] {
  submission_run_inspection_with_identity(row, None)
}

///|
fn submission_run_inspection_with_identity(
  row : @host.ClientJournalPhysicalRow,
  retained_identity : (
    @host.ClientRequestIdentity,
    @publication.PublicationContract,
  )?,
) -> Result[@host.ClientRunJournalInspection, Int] {
  let decoded = match retained_identity {
    None =>
      @host.decode_client_run_journal_row_with_observation_originals(row.body)
    Some((request, definition)) =>
      @host.decode_client_run_journal_row_with_retained_identity(
        row.body,
        request,
        definition,
      )
  }
  let (record, local_policy, observation_originals) = match decoded {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  if local_policy is Some(wire) &&
    @host.validate_client_local_run_policy_original_run(
      @utf8.encode(wire),
      record.request,
      record.definition,
    )
    is Err(_) {
    return Err(-31)
  }
  if record.checkpoint is Some(_) || record.effect_material_originals is Some(_) {
    return Err(-42)
  }
  if observation_originals is Some(wire) &&
    @host.restore_client_run_observation_originals_wire(
      record.definition,
      wire,
      131072,
      8192,
      64,
    )
    is Err(_) {
    return Err(-31)
  }
  if record.publication_policy_originals is Some(wire) &&
    @host.read_client_run_policy_originals(wire) is Err(_) {
    return Err(-31)
  }
  Ok({
    request: record.request,
    definition: record.definition,
    checkpoint: None,
    task_materials_cid: record.task_materials_cid,
  })
}

///|
/// Observe original namespaces through the existing same-transaction callback.
/// The Host authenticates the exact epoch before this call. Core retains its
/// own reference/intent, checks scope/validity and selects the write candidate.
/// Producing this output performs no write, admission, start or COMMIT ACK.
fn observe_submission_append(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[@host.ClientSubmittedJournalAppendPlan, Int] {
  match submission_append_current(value, record, configuration) {
    Ok(_) => ()
    Err(code) => return Err(code)
  }
  let borrow = match record.borrow {
    Ok(value) => value
    Err(issue) => return Err(issue_code(issue))
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["reference", "intent", "now"]) is Ok(object) &&
    required_text(object, "reference") is Some(reference_wire) &&
    @host.admit_client_submission_reference_record(reference_wire)
    is Ok(reference) &&
    required_text(object, "intent") is Some(intent_wire) &&
    @host.prepare_client_submitted_intent(intent_wire, 65536, 8192, 64)
    is Ok(intent) &&
    required_number(object, "now") is Some(now) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) else {
    return Err(-31)
  }
  let epoch = @host.client_submission_reference_record_epoch(reference)
  if @host.client_submission_epoch_token_authority_scope_cid(epoch) !=
    configuration.authority_scope_cid {
    return Err(-32)
  }
  let validity = match
    @host.submission_epoch_validity(
      @host.client_submission_epoch_token_body(epoch),
      now,
    ) {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  let check = () => submission_append_current(value, record, configuration)
  let scan = (table, cursor) => {
    physical_journal_row(current.physical, check, 0, table, cursor)
  }
  let read = (table, key) => {
    physical_journal_row(current.physical, check, 1, table, key)
  }
  // Keep the original complete inventory and unsupported Effect distinction.
  // No missing row, partial scan or outer count substitutes for these checks.
  match
    @host.inspect_client_run_journal_inventory(
      1024,
      scan,
      read,
      submission_append_run_inspection,
      () => {
        @host.inspect_client_empty_cancellation_inventory(
          1024, scan, read, -31, -42,
        )
      },
      -31,
    ) {
    Ok(_) => ()
    Err(code) => return Err(code)
  }
  let plan = match
    @host.prepare_client_submitted_journal_append(
      reference,
      intent,
      validity,
      1024,
      scan,
      read,
      row => {
        let original = match
          @host.decode_client_submitted_journal_row(row.body) {
          Ok(value) => value
          Err(_) => return Err(-31)
        }
        let observed = @host.read_client_saved_submission(
          original.reference,
          read,
          submission_append_run_inspection,
          -31,
        )
        match observed {
          Ok(Some(snapshot)) if @host.client_saved_submission_row(snapshot).body ==
            row.body &&
            @host.client_saved_submission_row(snapshot).revision == row.revision =>
            Ok(@host.client_saved_submission_record(snapshot))
          Err(code) => Err(code)
          _ => Err(-31)
        }
      },
      submission_append_run_inspection,
      -31,
    ) {
    Ok(value) => value
    Err(@host.Observation(code)) => return Err(code)
    Err(@host.ChangedIntent) => return Err(-45)
    Err(@host.EpochRejected(_)) => return Err(-46)
    Err(@host.CapacityExceeded) => return Err(-4)
    Err(@host.Encoding(_)) => return Err(-34)
  }
  match check() {
    Ok(_) => ()
    Err(code) => return Err(code)
  }
  Ok(plan)
}

///|
fn produce_submission_append(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  if record.output_closed {
    return -5
  }
  match submission_append_current(value, record, configuration) {
    Ok(_) => ()
    Err(code) => return code
  }
  if record.produced {
    return 0
  }
  if record.invoked {
    return -33
  }
  record.invoked = true
  let plan = match observe_submission_append(value, record, configuration) {
    Ok(value) => value
    Err(code) => return code
  }
  let check = () => submission_append_current(value, record, configuration)
  let writer = @encode.writer(1048576, 16, 2) catch { _ => return -34 }
  let wire = try {
    @encode.begin_object(writer)
    match plan {
      @host.Append(candidate) => {
        let (key, body, revision, issued) = @host.client_submitted_journal_append_rows(
          candidate,
        )
        @encode.key(writer, "kind")
        @encode.string_value(writer, "append")
        @encode.key(writer, "key")
        @encode.string_value(writer, key)
        @encode.key(writer, "body")
        @encode.string_value(writer, @utf8.decode(body))
        @encode.key(writer, "issued_revision")
        @encode.string_value(writer, revision.to_string())
        @encode.key(writer, "issued_body")
        @encode.string_value(writer, @utf8.decode(issued))
      }
      @host.Retained(snapshot) => {
        let row = @host.client_saved_submission_row(snapshot)
        @encode.key(writer, "kind")
        @encode.string_value(writer, "retained")
        @encode.key(writer, "key")
        @encode.string_value(writer, row.key)
        @encode.key(writer, "body")
        @encode.string_value(writer, @utf8.decode(row.body))
        @encode.key(writer, "revision")
        @encode.string_value(writer, row.revision.to_string())
      }
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return -34
  }
  match check() {
    Ok(_) => ()
    Err(code) => return code
  }
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(wire)),
  )
  if result == 0 {
    record.append_plan = Some(plan)
    record.produced = true
  }
  result
}

///|
pub fn validate_submission_append(
  nonce : Int64,
  handle : Int,
  current : Int,
) -> Int {
  if selected(nonce) is Some(value) &&
    value.submissions.get(handle) is Some(record) &&
    record.kind == 9 &&
    value.run_configurations.get(record.configuration) is Some(configuration) &&
    configuration.host_current == Some(current) {
    return validate_submission_preparation_failure(value, record, configuration)
  }
  if selected(nonce).bind(value => value.submissions.get(handle))
    is Some({ kind: 4 | 5 | 6 | 7 | 8, .. }) {
    return validate_submission_lookup(nonce, handle, current)
  }
  guard selected(nonce) is Some(value) &&
    value.submissions.get(handle) is Some(record) &&
    record.kind == 3 &&
    record.produced &&
    record.append_plan is Some(_) &&
    value.run_configurations.get(record.configuration) is Some(configuration) &&
    configuration.host_current == Some(current) else {
    return -2
  }
  let observed = match observe_submission_append(value, record, configuration) {
    Ok(value) => value
    Err(code) => return code
  }
  match (record.append_plan, observed) {
    (Some(@host.Append(original)), @host.Append(actual)) =>
      if @host.client_submitted_journal_append_rows(original) ==
        @host.client_submitted_journal_append_rows(actual) {
        0
      } else {
        -32
      }
    (Some(@host.Retained(original)), @host.Retained(actual)) => {
      let before = @host.client_saved_submission_row(original)
      let after = @host.client_saved_submission_row(actual)
      if before.key == after.key &&
        before.body == after.body &&
        before.revision == after.revision {
        0
      } else {
        -32
      }
    }
    _ => -32
  }
}

///|
/// Attach the actual failed preparation before producing a terminal candidate.
/// The existing output/loan Owner retains both inputs through CAS and cleanup.
pub fn reserve_submission_preparation_failure(
  nonce : Int64,
  configuration : Int,
  preparation : Int,
  input : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.preparations.get(preparation) is Some(original) &&
    original.kind == 3 &&
    original.started &&
    original.restoration is None &&
    original.outcome is Some(Err(_)) else {
    return -2
  }
  let handle = reserve_submission_projection(
    nonce, configuration, input, 9, physical_ticket, physical_copy_bytes,
  )
  if handle > 0 {
    value.submissions[handle].failure_preparation = Some(preparation)
  }
  handle
}

///|
fn observe_submission_preparation_failure(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[(@host.ClientJournalPhysicalRow, Bytes), Int] {
  match submission_append_current(value, record, configuration) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  guard record.kind == 9 &&
    record.failure_preparation is Some(handle) &&
    value.preparations.get(handle) is Some(original) &&
    original.kind == 3 &&
    original.started &&
    original.restoration is None &&
    preparation_failure_problem(original) is Some(problem) &&
    @buffers.buffer_wire(value.pool, original.slot) is Some(wire) else {
    return Err(-2)
  }
  let text = @utf8.decode(wire) catch { _ => return Err(-12) }
  let intent = match
    @host.prepare_client_submitted_intent(text, 65536, 8192, 64) {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  let saved = match observe_submission_lookup(value, record, configuration) {
    Ok(Some(value)) => value
    Ok(None) => return Err(-42)
    Err(code) => return Err(code)
  }
  let body = match
    @host.client_saved_submission_preparation_failure_body(
      saved, intent, problem,
    ) {
    Ok(value) => value
    Err(_) => return Err(-32)
  }
  match submission_append_current(value, record, configuration) {
    Err(code) => Err(code)
    Ok(_) => Ok((@host.client_saved_submission_row(saved), body))
  }
}

///|
fn produce_submission_preparation_failure(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  if record.output_closed {
    return -5
  }
  if record.produced {
    return 0
  }
  if record.invoked {
    return -33
  }
  record.invoked = true
  let (before, body) = match
    observe_submission_preparation_failure(value, record, configuration) {
    Ok(value) => value
    Err(code) => return code
  }
  let writer = @encode.writer(1048576, 8, 1) catch { _ => return -34 }
  let wire = try {
    @encode.begin_object(writer)
    @encode.key(writer, "key")
    @encode.string_value(writer, before.key)
    @encode.key(writer, "revision")
    @encode.string_value(writer, before.revision.to_string())
    @encode.key(writer, "before")
    @encode.string_value(writer, @utf8.decode(before.body))
    @encode.key(writer, "body")
    @encode.string_value(writer, @utf8.decode(body))
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return -34
  }
  match submission_append_current(value, record, configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(wire)),
  )
  if result == 0 {
    record.failure_plan = Some((before, body))
    record.produced = true
  }
  result
}

///|
fn validate_submission_preparation_failure(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard record.produced &&
    !record.output_closed &&
    record.failure_plan is Some((before, body)) else {
    return -2
  }
  match observe_submission_preparation_failure(value, record, configuration) {
    Ok((actual, after)) if before.key == actual.key &&
      before.revision == actual.revision &&
      before.body == actual.body &&
      body == after => 0
    Ok(_) => -32
    Err(code) => code
  }
}
