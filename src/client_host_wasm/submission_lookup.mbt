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
    @decode.closed_object(cursor, ["reference"]) is Ok(object) &&
    required_text(object, "reference") is Some(wire) &&
    @host.admit_client_submission_reference_record(wire) is Ok(reference) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) else {
    return Err(-31)
  }
  if @host.client_submission_epoch_token_authority_scope_cid(
      @host.client_submission_reference_record_epoch(reference),
    ) !=
    configuration.authority_scope_cid {
    return Err(-32)
  }
  let check = () => submission_lookup_current(value, record, configuration)
  let observed = @host.inspect_client_saved_submission(
    reference,
    1024,
    (table, cursor) => {
      physical_journal_row(current.physical, check, 0, table, cursor)
    },
    (table, key) => physical_journal_row(current.physical, check, 1, table, key),
    submission_append_run_inspection,
    () => {
      @host.inspect_client_empty_cancellation_inventory(
        1024,
        (table, cursor) => {
          physical_journal_row(current.physical, check, 0, table, cursor)
        },
        (table, key) => {
          physical_journal_row(current.physical, check, 1, table, key)
        },
        -31,
        -42,
      )
    },
    -31,
  )
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
fn produce_submission_lookup(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  if record.output_closed {
    return -5
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
  let snapshot = match observe_submission_lookup(value, record, configuration) {
    Ok(value) => value
    Err(code) => return code
  }
  let wire = match submission_lookup_wire(snapshot) {
    Ok(value) => value
    Err(code) => return code
  }
  match submission_lookup_current(value, record, configuration) {
    Ok(_) => ()
    Err(code) => return code
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
    record.kind == 4 &&
    record.produced &&
    !record.output_closed &&
    value.run_configurations.get(record.configuration) is Some(configuration) &&
    configuration.host_current == Some(current) else {
    return -2
  }
  let snapshot = match observe_submission_lookup(value, record, configuration) {
    Ok(value) => value
    Err(code) => return code
  }
  let wire = match submission_lookup_wire(snapshot) {
    Ok(value) => value
    Err(code) => return code
  }
  match @buffers.buffer_wire(value.pool, record.slot) {
    Some(original) if original == wire => 0
    _ => -32
  }
}
