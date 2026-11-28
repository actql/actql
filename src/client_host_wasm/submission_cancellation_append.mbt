///|
// The existing projection retains its same original rows, publication reader
// and candidate through physical COMMIT/Unknown and explicit readback. No new
// ledger, Run, stop owner or physical cleanup acknowledgment is introduced.
priv struct StoredCancellationAppend {
  original : @host.ClientSavedSubmissionSnapshot
  run : (@host.ClientJournalPhysicalRow, @host.ClientRunJournalEncoding)
  mut plan : @host.ClientCancellationJournalAppendPlan[
    (@host.ClientJournalPhysicalRow, @host.ClientRunJournalEncoding),
  ]?
  mut response : String?
  mut writes : Array[(String, String, Int64?, Bytes)]
  publication : StoredSDKPublicationObservation
  mut confirmed : Bool
}

///|
fn cancellation_request_fields(
  value : Instance,
  record : StoredSubmissionProjection,
) -> Result[(String, Int, String), Int] {
  guard record.borrow is Ok(borrow) &&
    input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "namespaceId", "authorityScopeCid", "runDefinitionCid", "cancelId", "expectedRevision",
      "attemptId",
    ])
    is Ok(object) &&
    required_text(object, "cancelId") is Some(cancel_id) &&
    required_text(object, "attemptId") is Some(attempt_id) &&
    @decode.required(object, "expectedRevision") is Ok(revision) &&
    @decode.safe_integer(revision) is Ok(revision) &&
    revision >= 0L &&
    revision <= 2147483647L else {
    return Err(-31)
  }
  Ok((cancel_id, revision.to_int(), attempt_id))
}

///|
fn cancellation_append_plan(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  original : (@host.ClientJournalPhysicalRow, @host.ClientRunJournalEncoding),
  terminal : () -> Result[Bool, Int],
) -> Result[
  @host.ClientCancellationJournalAppendPlan[
    (@host.ClientJournalPhysicalRow, @host.ClientRunJournalEncoding),
  ],
  @host.ClientCancellationJournalOperationIssue[Int],
] {
  let (cancel_id, revision, _) = match
    cancellation_request_fields(value, record) {
    Ok(value) => value
    Err(code) => return Err(@host.Observation(code))
  }
  guard configuration.host_current is Some(handle) &&
    value.host_currents.get(handle) is Some(current) else {
    return Err(@host.Observation(-32))
  }
  let check = () => submission_lookup_current(value, record, configuration)
  let scan = (table, cursor) => {
    physical_journal_row(current.physical, check, 0, table, cursor)
  }
  let read = (table, key) => {
    physical_journal_row(current.physical, check, 1, table, key)
  }
  let late_failure = Ref(0)
  let result = @host.prepare_client_cancellation_journal_append(
    original.1.request,
    configuration.run_namespace,
    cancel_id,
    revision,
    1024,
    original.1.publication_binding,
    () => {
      @host.inspect_client_cancellation_journal_inventory(
        1024, scan, read, submission_cancellation_run_inspection, -31,
      )
    },
    () => Ok(Some(original)),
    actual => {
      request: actual.1.request,
      definition: actual.1.definition,
      revision: actual.0.revision,
      cancellation_requested: actual.1.cancellation_requested(),
      publication_binding: actual.1.publication_binding,
    },
    key => {
      read("client_cancellations", key).bind(row => {
        match row {
          None => Ok(None)
          Some(row) =>
            @host.decode_client_cancellation_journal_row(row)
            .map(value => Some(value))
            .map_err(_ => -31)
        }
      })
    },
    _ => terminal(),
    () => {
      match check() {
        Ok(_) => true
        Err(code) => {
          late_failure.val = code
          false
        }
      }
    },
  )
  if late_failure.val != 0 {
    return Err(@host.Observation(late_failure.val))
  }
  result
}

///|
fn cancellation_candidate_writes(
  plan : @host.ClientCancellationJournalAppendPlan[
    (@host.ClientJournalPhysicalRow, @host.ClientRunJournalEncoding),
  ],
) -> Result[Array[(String, String, Int64?, Bytes)], Int] {
  guard plan is @host.AppendCancellation(plan) else { return Ok([]) }
  let original = @host.client_cancellation_append_original(plan)
  let writes : Array[(String, String, Int64?, Bytes)] = []
  if @host.client_cancellation_append_accepted_head(plan) is Some(head) {
    guard @host.decode_client_run_journal_row_with_observation_originals(
        original.0.body,
      )
      is Ok((_, policy, observations)) &&
      @host.client_run_journal_row_body(
        { ..original.1, cancellation_head: Some(head), },
        local_run_policy_originals=policy,
        run_observation_originals=observations,
      )
      is Ok(body) else {
      return Err(-31)
    }
    writes.push(
      ("client_runs", original.0.key, Some(original.0.revision), body),
    )
  }
  guard @host.client_cancellation_append_rows(plan)
    is Some((key, body, witness, issued_revision, issued_body)) else {
    return Err(-31)
  }
  writes.push(("client_cancellations", key, None, body))
  writes.push(("client_cancel_originals", key, None, witness))
  writes.push(
    ("client_cancel_custody", "issued", Some(issued_revision), issued_body),
  )
  Ok(writes)
}

///|
fn cancellation_append_packet(
  retained : StoredCancellationAppend,
) -> Result[Bytes, Int] {
  guard retained.response is Some(response) else { return Err(-33) }
  let writer = @encode.writer(1048576, 64, 5) catch { _ => return Err(-34) }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "response")
    @encode.string_value(writer, response)
    @encode.key(writer, "writes")
    @encode.begin_array(writer)
    for (table, key, revision, body) in retained.writes {
      @encode.begin_object(writer)
      @encode.key(writer, "namespace")
      @encode.string_value(writer, table)
      @encode.key(writer, "key")
      @encode.string_value(writer, key)
      @encode.key(writer, "revision")
      match revision {
        None => @encode.null_value(writer)
        Some(value) => @encode.string_value(writer, value.to_string())
      }
      @encode.key(writer, "body")
      @encode.string_value(
        writer,
        @utf8.decode(body) catch {
          _ => return Err(-31)
        },
      )
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(-34)
  }
}

///|
fn cancellation_append_original_record(
  plan : @host.ClientCancellationJournalAppendPlan[
    (@host.ClientJournalPhysicalRow, @host.ClientRunJournalEncoding),
  ],
) -> @host.ClientCancellationJournalEncoding {
  match plan {
    @host.AppendCancellation(value) =>
      @host.client_cancellation_append_record(value)
    @host.RetainedCancellation(value) => value
  }
}

///|
// A second produce is an original readback, never another prepare/write.
fn confirm_cancellation_append(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  retained : StoredCancellationAppend,
) -> Int {
  match submission_lookup_current(value, record, configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  guard retained.plan is Some(plan) else { return 0 }
  let (cancel_id, revision, _) = match
    cancellation_request_fields(value, record) {
    Ok(value) => value
    Err(code) => return code
  }
  let snapshot = match observe_submission_lookup(value, record, configuration) {
    Ok(snapshot) => snapshot
    Err(code) => return code
  }
  guard configuration.host_current is Some(handle) &&
    value.host_currents.get(handle) is Some(current) else {
    return -32
  }
  let check = () => submission_lookup_current(value, record, configuration)
  let failure = Ref(0)
  let observed = submission_cancellation_lookup_original(
    snapshot,
    configuration.run_namespace,
    cancel_id,
    revision,
    (table, cursor) => {
      physical_journal_row(current.physical, check, 0, table, cursor)
    },
    (table, key) => physical_journal_row(current.physical, check, 1, table, key),
    () => {
      match check() {
        Ok(_) => true
        Err(code) => {
          failure.val = code
          false
        }
      }
    },
  )
  if failure.val != 0 {
    return failure.val
  }
  match observed {
    Ok(@host.OriginalCancellation(actual)) => {
      let wanted = cancellation_append_original_record(plan)
      if @host.client_cancellation_journal_row_body(actual) !=
        @host.client_cancellation_journal_row_body(wanted) {
        return -32
      }
    }
    Ok(@host.UnresolvedCancellationHistory) => return -33
    Err(code) => return code
  }
  match check() {
    Err(code) => code
    Ok(_) => {
      retained.confirmed = true
      record.saved_snapshot = snapshot
      0
    }
  }
}

///|
// Pure relationship inside the existing cancellation Owner. The caller still
// owes current/target observations; this result grants no normal work or ACK.
fn cancellation_stop_record(
  retained : StoredCancellationAppend,
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
) -> Result[@host.ClientCancellationJournalEncoding?, Int] {
  if @host.client_request_identity_relation(retained.run.1.request, request) !=
    @host.SameRequest ||
    @publication.publication_contract_identity(retained.run.1.definition) !=
    @publication.publication_contract_identity(definition) {
    return Err(-35)
  }
  guard retained.plan is Some(plan) else { return Ok(None) }
  if !retained.confirmed {
    return Err(-33)
  }
  // A retained readback can be the same original accepted operation. Its
  // original action, rather than Append/Retained shape, determines interest.
  let original = cancellation_append_original_record(plan)
  if @host.client_request_identity_relation(original.request, request) !=
    @host.SameRequest ||
    @publication.publication_contract_identity(original.definition) !=
    @publication.publication_contract_identity(definition) {
    return Err(-35)
  }
  match original.action {
    @host.AcceptCancellation => Ok(Some(original))
    @host.AlreadyRequested | @host.AlreadyTerminal => Ok(None)
  }
}

///|
/// Observe stop interest from this SAME confirmed cancellation/Run only.
/// Zero is no request; one requests original physical retirement, never work,
/// cancellation completion or physical ACK. Negative refusals remain refusals.
pub fn observe_cancellation_stop_interest(
  nonce : Int64,
  handle : Int,
  run : Int,
  current : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.submissions.get(handle) is Some(record) &&
    record.kind == 10 &&
    record.produced &&
    !record.output_closed &&
    record.cancellation_append is Some(retained) &&
    value.run_configurations.get(record.configuration) is Some(configuration) &&
    configuration.host_current == Some(current) &&
    value.runs.get(run) is Some(original_run) &&
    original_run.configuration == record.configuration &&
    original_run.outcome is Some(Ok(plan)) &&
    value.host_currents.get(current) is Some(scope) else {
    return -2
  }
  let check = () => submission_lookup_current(value, record, configuration)
  match check() {
    Err(code) => return code
    Ok(_) => ()
  }
  let request = @local_run.local_run_request(plan)
  let definition = @local_run.local_run_definition(plan)
  let accepted = match cancellation_stop_record(retained, request, definition) {
    Ok(Some(original)) => original
    Ok(None) => return 0
    Err(code) => return code
  }
  if accepted.namespace_id != configuration.run_namespace {
    return -35
  }
  guard record.saved_snapshot is Some(snapshot) &&
    @host.client_saved_submission_run_row(snapshot) is Some(expected) &&
    expected.key == @host.client_request_scope_cid(request) else {
    return -33
  }
  // The control request boundary reobserves the original Run, receipt and
  // witness. No namespace census enters the normal task loop.
  let read = (table, key) => {
    physical_journal_row(scope.physical, check, 1, table, key)
  }
  let row = match read("client_runs", expected.key) {
    Ok(Some(row)) => row
    Ok(None) => return -33
    Err(code) => return code
  }
  if row.key != expected.key ||
    row.revision != expected.revision ||
    row.body != expected.body {
    return -35
  }
  let encoding = match sdk_run_row_original(value, run, row) {
    Ok(encoding) => encoding
    Err(code) => return code
  }
  guard encoding.cancellation_head is Some(head) else { return -35 }
  let observed = match
    @host.observe_client_accepted_cancellation_head(
      head,
      configuration.run_namespace,
      {
        request: encoding.request,
        definition: encoding.definition,
        revision: row.revision,
        cancellation_requested: true,
        publication_binding: encoding.publication_binding,
      },
      (table, key) => {
        match read(table, key) {
          Ok(Some(value)) if value.key == key => Ok(Some(value))
          Ok(Some(_)) => Err(-35)
          Ok(None) => Err(-33)
          Err(code) => Err(code)
        }
      },
      -31,
    ) {
    Ok(value) => value
    Err(code) => return code
  }
  if @host.client_cancellation_journal_row_body(observed) !=
    @host.client_cancellation_journal_row_body(accepted) {
    return -35
  }
  match check() {
    Ok(_) => 1
    Err(code) => code
  }
}

///|
fn produce_cancellation_append(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  if record.output_closed || value.closing || value.runtime_closing {
    return -5
  }
  match submission_lookup_current(value, record, configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  if record.produced {
    guard record.cancellation_append is Some(retained) else { return -33 }
    return confirm_cancellation_append(value, record, configuration, retained)
  }
  if record.invoked {
    return -33
  }
  record.invoked = true
  let (cancel_id, revision, attempt_id) = match
    cancellation_request_fields(value, record) {
    Ok(value) => value
    Err(code) => return code
  }
  let snapshot = match observe_submission_lookup(value, record, configuration) {
    Ok(Some(snapshot)) => snapshot
    Ok(None) => return -31
    Err(code) => return code
  }
  record.saved_snapshot = Some(snapshot)
  guard @host.client_saved_submission_run_row(snapshot) is Some(row) &&
    submission_run_row_original_with_identity(row, None) is Ok(run) else {
    return -31
  }
  let retained : StoredCancellationAppend = {
    original: snapshot,
    run: (row, run),
    plan: None,
    response: None,
    writes: [],
    publication: sdk_publication_observation_original(run),
    confirmed: false,
  }
  record.cancellation_append = Some(retained)
  let result = cancellation_append_plan(
    value,
    record,
    configuration,
    retained.run,
    () => {
      sdk_publication_observation(
        value,
        record,
        configuration,
        retained.publication,
      )
    },
  )
  match result {
    Ok(plan) => {
      retained.plan = Some(plan)
      retained.response = @host.client_cancellation_attempt_wire(
        cancellation_append_original_record(plan),
        attempt_id,
      )
      retained.writes = match cancellation_candidate_writes(plan) {
        Ok(value) => value
        Err(code) => return code
      }
    }
    Err(issue) => {
      guard @host.prepare_client_cancellation_identity(
          configuration.run_namespace,
          configuration.authority_scope_cid,
          cancel_id,
          run.definition,
          revision,
        )
        is Ok(identity) else {
        return -31
      }
      retained.response = @host.client_cancellation_rejection_wire(
        identity, attempt_id, issue,
      )
      if retained.response is None {
        return match issue {
          @host.Observation(code) => code
          _ => -31
        }
      }
    }
  }
  let wire = match cancellation_append_packet(retained) {
    Ok(value) => value
    Err(code) => return code
  }
  match submission_lookup_current(value, record, configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  let code = status(
    @buffers.supply_buffer_output(value.pool, record.slot, wire),
  )
  if code == 0 {
    record.produced = true
  }
  code
}

///|
fn validate_cancellation_append(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard record.produced &&
    !record.output_closed &&
    record.cancellation_append is Some(retained) else {
    return -33
  }
  match submission_lookup_current(value, record, configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  guard retained.plan is Some(wanted) else { return 0 }
  if retained.confirmed {
    return -33
  }
  let snapshot = match
    observe_submission_lookup(
      value,
      record,
      configuration,
      original=Some(retained.original),
    ) {
    Ok(Some(snapshot)) => snapshot
    Ok(None) => return -31
    Err(code) => return code
  }
  guard @host.client_saved_submission_run_row(snapshot) is Some(row) &&
    submission_run_row_original_with_identity(row, None) is Ok(run) else {
    return -31
  }
  let code = validate_sdk_publication_observation(
    value,
    record,
    configuration,
    retained.publication,
  )
  if code != 0 {
    return code
  }
  let actual = match
    cancellation_append_plan(value, record, configuration, (row, run), () => {
      match retained.publication.terminal {
        Some(value) => Ok(value)
        None => Err(-33)
      }
    }) {
    Ok(value) => value
    Err(@host.Observation(code)) => return code
    Err(_) => return -32
  }
  // Both before-write inventories and the exact original candidate must match.
  // A found original is observed via confirm instead, never written again.
  match (wanted, actual) {
    (@host.AppendCancellation(_), @host.AppendCancellation(_)) =>
      match cancellation_candidate_writes(actual) {
        Ok(writes) if writes == retained.writes => 0
        Err(code) => code
        _ => -32
      }
    (@host.RetainedCancellation(a), @host.RetainedCancellation(b)) =>
      if @host.client_cancellation_journal_row_body(a) ==
        @host.client_cancellation_journal_row_body(b) {
        0
      } else {
        -32
      }
    _ => -32
  }
}

///|
fn close_cancellation_append(record : StoredSubmissionProjection) -> Int {
  guard record.cancellation_append is Some(retained) else { return 0 }
  let code = close_sdk_publication_observation(retained.publication)
  if code != 0 {
    return code
  }
  record.cancellation_append = None
  0
}
