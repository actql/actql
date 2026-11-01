///|
/// Current installed Read purpose, independent of submission permission.
fn submission_lookup_current(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[Unit, Int] {
  if value.closing || value.runtime_closing || record.output_closed {
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
  let tuple : @authorization.AccessTuple = {
    principal: configuration.tuple.principal,
    connection: configuration.tuple.connection,
    resource: "run",
    operation: "read",
  }
  if @authorization.evaluate_account(configuration.account, tuple)
    is @authorization.Allow(_) {
    Ok(())
  } else {
    Err(-32)
  }
}

///|
/// A reference-only read of the original same-Store history. The physical
/// Host authenticates its retained epoch before entering this snapshot. No
/// intent, preparation, candidate row, clock issuance or write is accepted.
fn observe_submission_lookup(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  original? : @host.ClientSavedSubmissionSnapshot? = None,
) -> Result[@host.ClientSavedSubmissionSnapshot?, Int] {
  match submission_lookup_current(value, record, configuration) {
    Ok(_) => ()
    Err(code) => return Err(code)
  }
  let borrow = match record.borrow {
    Ok(value) => value
    Err(issue) => return Err(issue_code(issue))
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) else {
    return Err(-31)
  }
  let check = () => submission_lookup_current(value, record, configuration)
  let scan = (table, cursor) => {
    physical_journal_row(current.physical, check, 0, table, cursor)
  }
  let read = (table, key) => {
    physical_journal_row(current.physical, check, 1, table, key)
  }
  let cancellation = () => {
    @host.inspect_client_empty_cancellation_inventory(
      1024, scan, read, -31, -42,
    )
  }
  // The original physical reader observes its actual same-transaction schema.
  // This is only algorithm-selection DATA; every Account/current/epoch and
  // selected nested-original validator below still runs. Errors never mean
  // legacy absence or permission to prepare another Run.
  let physical_schema = physical_journal_schema(current.physical)
  if physical_schema != 0 && physical_schema != 1 {
    return Err(-41)
  }
  // Reuse only immutable request/Definition DATA from this already completed
  // saved source. Initial inventory rows and selected revalidation rows are
  // still physically read; foreign/changed identity takes full admission.
  // Nested policies/evidence and all current/cancellation checks remain fresh.
  let identity = record.saved_result.bind(saved => {
    if saved.complete {
      saved.source.map(@local_run.local_sdk_read_source_run_identity)
    } else {
      None
    }
  })
  let inspect_run = row => {
    submission_run_inspection_with_identity(row, identity)
  }
  if record.kind == 5 ||
    record.kind == 6 ||
    record.kind == 7 ||
    record.kind == 8 {
    guard @decode.closed_object(
        cursor,
        if record.kind == 6 {
          ["namespaceId", "authorityScopeCid", "runDefinitionCid", "resultName"]
        } else {
          ["namespaceId", "authorityScopeCid", "runDefinitionCid"]
        },
      )
      is Ok(object) &&
      required_text(object, "namespaceId") is Some(run_namespace) &&
      required_text(object, "authorityScopeCid") is Some(scope) &&
      required_text(object, "runDefinitionCid") is Some(definition) else {
      return Err(-31)
    }
    if run_namespace != configuration.run_namespace ||
      scope != configuration.authority_scope_cid {
      return Err(-32)
    }
    let observed = submission_run_reference_snapshot(
      run_namespace,
      scope,
      definition,
      original,
      scan,
      read,
      inspect_run,
      cancellation,
      original_identity=identity,
      physical_schema~,
    )
    return match check() {
      Ok(_) => observed
      Err(code) => Err(code)
    }
  }
  guard record.kind == 4 &&
    @decode.closed_object(cursor, ["reference"]) is Ok(object) &&
    required_text(object, "reference") is Some(wire) &&
    @host.admit_client_submission_reference_record(wire) is Ok(reference) else {
    return Err(-31)
  }
  if @host.client_submission_epoch_token_authority_scope_cid(
      @host.client_submission_reference_record_epoch(reference),
    ) !=
    configuration.authority_scope_cid {
    return Err(-32)
  }
  let observed = if physical_schema == 1 {
    match
      @host.read_client_saved_submission(reference, read, inspect_run, -31) {
      Err(code) => Err(code)
      Ok(snapshot) => cancellation().map(_ => snapshot)
    }
  } else {
    @host.inspect_client_saved_submission(
      reference, 1024, scan, read, inspect_run, cancellation, -31,
    )
  }
  if observed is Ok(Some(snapshot)) &&
    @host.client_saved_submission_run_row(snapshot) is Some(row) {
    guard @host.decode_client_run_journal_row_with_observation_originals(
        row.body,
      )
      is Ok((run, _, _)) &&
      @publication.run_definition_namespace(run.definition) ==
      Some(configuration.run_namespace) else {
      return Err(-32)
    }
  }
  match check() {
    Ok(_) => observed
    Err(code) => Err(code)
  }
}

///|
// Only a completed same-holder caller supplies original. It selects DATA;
// fresh target rows, nested admission and cancellation still come from the
// current physical snapshot. Initial/cold callers keep complete admission.
fn submission_run_reference_snapshot(
  namespace : String,
  scope : String,
  definition : String,
  original : @host.ClientSavedSubmissionSnapshot?,
  scan : (String, String) -> Result[@host.ClientJournalPhysicalRow?, Int],
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, Int],
  inspect_run : (@host.ClientJournalPhysicalRow) -> Result[
    @host.ClientRunJournalInspection,
    Int,
  ],
  cancellation : () -> Result[Unit, Int],
  original_identity? : (
    @host.ClientRequestIdentity,
    @publication.PublicationContract,
  )? = None,
  physical_schema? : Int = 0,
) -> Result[@host.ClientSavedSubmissionSnapshot?, Int] {
  if physical_schema != 0 && physical_schema != 1 {
    return Err(-41)
  }
  guard original is Some(before) else {
    if physical_schema == 1 {
      let selected = match
        @host.read_client_saved_run_reference(
          namespace, scope, definition, read, inspect_run, -31,
        ) {
        Ok(value) => value
        Err(code) => return Err(code)
      }
      return cancellation().map(_ => Some(selected))
    }
    return @host.inspect_client_saved_run_reference(
      namespace, scope, definition, 1024, scan, read, inspect_run, cancellation,
      -31,
    )
  }
  let reference = @host.client_saved_submission_record(before).reference
  // Only the actual completed saved source supplies this original identity.
  // A generic Snapshot does not certify this caller's full nested validator.
  // Reuse preserves that original result; it never certifies a new validator.
  let reobserved = match original_identity {
    Some((request, original_definition)) => {
      let record = @host.client_saved_submission_record(before)
      let run = @host.client_saved_submission_run_row(before)
      if @host.client_request_authority_scope_cid(request) == scope &&
        @publication.publication_contract_identity(original_definition) ==
        definition &&
        @publication.run_definition_namespace(original_definition) ==
        Some(namespace) &&
        @publication.publication_contract_check_limits(
          original_definition, 65536, 4096, 64,
        )
        is Ok(_) &&
        record.run_admission is Some(admission) &&
        run is Some(row) &&
        @host.validate_client_submitted_retained_run(
          reference,
          admission,
          request,
          original_definition,
          row.revision,
        )
        is Ok(_) {
        match @host.reobserve_client_saved_submission_original(before, read) {
          Ok(value) => value
          Err(code) => return Err(code)
        }
      } else {
        None
      }
    }
    None => None
  }
  let observation = if reobserved is Some(actual) {
    Ok(Some(actual))
  } else {
    @host.read_client_saved_submission(
      reference,
      read,
      row => {
        let run = match inspect_run(row) {
          Ok(value) => value
          Err(code) => return Err(code)
        }
        if @host.client_request_authority_scope_cid(run.request) != scope ||
          @publication.publication_contract_identity(run.definition) !=
          definition ||
          @publication.run_definition_namespace(run.definition) !=
          Some(namespace) {
          return Err(-32)
        }
        Ok(run)
      },
      -31,
    )
  }
  let observed = match observation {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  match cancellation() {
    Ok(_) => ()
    Err(code) => return Err(code)
  }
  guard observed is Some(actual) else { return Ok(None) }
  let before_submission = @host.client_saved_submission_row(before)
  let after_submission = @host.client_saved_submission_row(actual)
  if before_submission.key != after_submission.key ||
    before_submission.revision != after_submission.revision ||
    before_submission.body != after_submission.body {
    return Err(-32)
  }
  guard @host.client_saved_submission_run_row(before) is Some(before_run) &&
    @host.client_saved_submission_run_row(actual) is Some(after_run) &&
    before_run.key == after_run.key &&
    before_run.revision == after_run.revision &&
    before_run.body == after_run.body else {
    return Err(-32)
  }
  Ok(Some(actual))
}

///|
/// Private transport of existing Owner facts, not a new admission or state.
fn submission_lookup_wire(
  snapshot : @host.ClientSavedSubmissionSnapshot?,
) -> Result[Bytes, Int] {
  try {
    let writer = @encode.writer(1048576, 8, 1)
    @encode.begin_object(writer)
    @encode.key(writer, "kind")
    match snapshot {
      None => @encode.string_value(writer, "missing")
      Some(snapshot) => {
        let record = @host.client_saved_submission_record(snapshot)
        @encode.string_value(
          writer,
          if record.run_admission is Some(_) {
            "ready"
          } else {
            "preparing"
          },
        )
        @encode.key(writer, "intentCid")
        @encode.string_value(
          writer,
          @host.client_submitted_intent_cid(record.intent),
        )
        if record.run_admission is Some(_) {
          let admission = match
            @host.client_saved_submission_admission_wire(snapshot) {
            Ok(value) => value
            Err(_) => return Err(-31)
          }
          @encode.key(writer, "admission")
          @encode.string_value(writer, admission)
        }
      }
    }
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(-34)
  }
}

///|
/// Private bounded transport from the same admitted saved snapshot. These
/// original input/admission bytes are neither a prepared Program nor a grant.
fn saved_sdk_original_descriptor_wire(
  snapshot : @host.ClientSavedSubmissionSnapshot?,
) -> Result[Bytes, Int] {
  guard snapshot is Some(snapshot) else { return Err(-42) }
  let admission = match @host.client_saved_submission_admission_wire(snapshot) {
    Ok(value) => value
    Err(_) => return Err(-35)
  }
  let submitted = @host.client_saved_submission_record(snapshot)
  try {
    let writer = @encode.writer(1048576, 8, 1)
    @encode.begin_object(writer)
    @encode.key(writer, "intent")
    @encode.string_value(
      writer,
      @host.client_submitted_intent_wire(submitted.intent),
    )
    @encode.key(writer, "admission")
    @encode.string_value(writer, admission)
    // Routing DATA only. A positive observation cannot replace the complete
    // original material/Run/current binding performed by restore_sdk_material.
    @encode.key(writer, "materials_available")
    @encode.bool_value(
      writer,
      @host.client_saved_submission_task_materials_original(snapshot) is Some(_),
    )
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(-34)
  }
}

///|
fn produce_submission_lookup(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  if record.output_closed {
    return -5
  }
  if (record.kind == 7 || record.kind == 8) && configuration.sdk is None {
    return -32
  }
  match submission_lookup_current(value, record, configuration) {
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
  if record.kind == 6 {
    let wire = match prepare_saved_result_read(value, record, configuration) {
      Ok(value) => value
      Err(code) => return code
    }
    let result = status(
      @buffers.supply_buffer_output(value.pool, record.slot, wire),
    )
    if result == 0 {
      record.produced = true
    }
    return result
  }
  let snapshot = match observe_submission_lookup(value, record, configuration) {
    Ok(value) => value
    Err(code) => return code
  }
  let projected = if record.kind == 7 {
    saved_sdk_run_state_wire(snapshot)
  } else if record.kind == 8 {
    saved_sdk_original_descriptor_wire(snapshot)
  } else {
    submission_lookup_wire(snapshot)
  }
  let wire = match projected {
    Ok(value) => value
    Err(code) => return code
  }
  match submission_lookup_current(value, record, configuration) {
    Ok(_) => ()
    Err(code) => return code
  }
  if record.kind == 7 || record.kind == 8 {
    // Retain the actual admitted rows before transferring their saved facts.
    // Later validation must reobserve this exact original, not an equal reply.
    record.saved_snapshot = snapshot
  }
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, wire),
  )
  if result == 0 {
    record.produced = true
  }
  result
}

///|
fn validate_submission_lookup(
  nonce : Int64,
  handle : Int,
  current : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.submissions.get(handle) is Some(record) &&
    (record.kind >= 4 && record.kind <= 8) &&
    record.produced &&
    !record.output_closed &&
    value.run_configurations.get(record.configuration) is Some(configuration) &&
    configuration.host_current == Some(current) else {
    return -2
  }
  if record.kind == 6 {
    return match validate_saved_result_read(value, record, configuration) {
      Ok(_) => 0
      Err(code) => code
    }
  }
  if (record.kind == 7 || record.kind == 8) && record.saved_snapshot is None {
    return -42
  }
  let snapshot = match
    observe_submission_lookup(
      value,
      record,
      configuration,
      original=record.saved_snapshot,
    ) {
    Ok(value) => value
    Err(code) => return code
  }
  let projected = if record.kind == 7 {
    saved_sdk_run_state_wire(snapshot)
  } else if record.kind == 8 {
    saved_sdk_original_descriptor_wire(snapshot)
  } else {
    submission_lookup_wire(snapshot)
  }
  let wire = match projected {
    Ok(value) => value
    Err(code) => return code
  }
  match @buffers.buffer_wire(value.pool, record.slot) {
    Some(original) if original == wire => 0
    _ => -32
  }
}
