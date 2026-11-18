///|
// The existing Saved snapshot has already selected and admitted this Run in
// the same current transaction. Reuse its complete original row validator;
// neither a projected reference nor a cancellation row can replace that Owner.
fn submission_cancellation_lookup_original(
  snapshot : @host.ClientSavedSubmissionSnapshot?,
  run_namespace : String,
  cancel_id : String,
  expected_revision : Int,
  scan : (String, String) -> Result[@host.ClientJournalPhysicalRow?, Int],
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, Int],
  current : () -> Bool,
) -> Result[@host.ClientCancellationJournalLookup, Int] {
  guard snapshot is Some(snapshot) &&
    @host.client_saved_submission_run_row(snapshot) is Some(row) else {
    return Err(-31)
  }
  let run = match submission_run_row_original_with_identity(row, None) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  if @publication.run_definition_namespace(run.definition) !=
    Some(run_namespace) {
    return Err(-32)
  }
  let retained = (row, run)
  @host.lookup_client_cancellation_journal_original(
    run.request,
    run_namespace,
    cancel_id,
    expected_revision,
    () => {
      @host.inspect_client_cancellation_journal_inventory(
        1024, scan, read, submission_cancellation_run_inspection, -31,
      )
    },
    () => Ok(Some(retained)),
    original => {
      request: original.1.request,
      definition: original.1.definition,
      revision: original.0.revision,
      cancellation_requested: original.1.cancellation_requested,
      publication_binding: original.1.publication_binding,
    },
    key => {
      match read("client_cancellations", key) {
        Err(code) => Err(code)
        Ok(None) => Ok(None)
        Ok(Some(row)) =>
          @host.decode_client_cancellation_journal_row(row)
          .map(value => Some(value))
          .map_err(_ => -31)
      }
    },
    current,
  ).map_err(issue => {
    match issue {
      @host.Observation(code) => code
      @host.AuthorizationDenied => -32
      @host.Operation(_) => -32
      _ => -31
    }
  })
}

///|
// Closed public DATA encoding follows the existing cancellation_lookup wire.
// In particular, missing history says unknown and retains the original key;
// it cannot issue cancellation, claim physical stop or authorize another write.
fn submission_cancellation_lookup_view(
  run_namespace : String,
  scope : String,
  definition : String,
  cancel_id : String,
  expected_revision : Int,
  observed : @host.ClientCancellationJournalLookup,
) -> Result[Bytes, Int] {
  let writer = @encode.writer(8192, 40, 5) catch { _ => return Err(-34) }
  let run_ref = () => {
    @encode.key(writer, "namespaceId")
    @encode.string_value(writer, run_namespace)
    @encode.key(writer, "authorityScopeCid")
    @encode.string_value(writer, scope)
    @encode.key(writer, "runDefinitionCid")
    @encode.string_value(writer, definition)
  }
  let cancel_ref = () => {
    @encode.begin_object(writer)
    run_ref()
    @encode.key(writer, "cancelId")
    @encode.string_value(writer, cancel_id)
    @encode.key(writer, "expectedRevision")
    @encode.number_value(writer, expected_revision.to_double())
    @encode.end_object(writer)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "kind")
    match observed {
      @host.UnresolvedCancellationHistory => {
        @encode.string_value(writer, "unknown")
        @encode.key(writer, "cancelRef")
        cancel_ref()
      }
      @host.OriginalCancellation(original) => {
        @encode.string_value(writer, "found")
        @encode.key(writer, "cancellation")
        @encode.begin_object(writer)
        @encode.key(writer, "ref")
        @encode.begin_object(writer)
        run_ref()
        @encode.end_object(writer)
        @encode.key(writer, "cancelRef")
        cancel_ref()
        @encode.key(writer, "kind")
        @encode.string_value(
          writer,
          match original.action {
            @host.AcceptCancellation => "accepted"
            @host.AlreadyRequested => "already_requested"
            @host.AlreadyTerminal => "already_terminal"
          },
        )
        @encode.key(writer, "revision")
        @encode.number_value(writer, original.observed_revision.to_double())
        @encode.end_object(writer)
      }
    }
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(-34)
  }
}

///|
fn submission_cancellation_lookup_wire(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  snapshot : @host.ClientSavedSubmissionSnapshot?,
) -> Result[Bytes, Int] {
  guard record.borrow is Ok(borrow) &&
    input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "namespaceId", "authorityScopeCid", "runDefinitionCid", "cancelId", "expectedRevision",
    ])
    is Ok(object) &&
    required_text(object, "namespaceId") is Some(run_namespace) &&
    required_text(object, "authorityScopeCid") is Some(scope) &&
    required_text(object, "runDefinitionCid") is Some(definition) &&
    required_text(object, "cancelId") is Some(cancel_id) &&
    @decode.required(object, "expectedRevision") is Ok(revision_cursor) &&
    @decode.safe_integer(revision_cursor) is Ok(revision) &&
    revision >= 0L &&
    revision <= 2147483647L &&
    configuration.host_current is Some(handle) &&
    value.host_currents.get(handle) is Some(current) else {
    return Err(-31)
  }
  if run_namespace != configuration.run_namespace ||
    scope != configuration.authority_scope_cid {
    return Err(-32)
  }
  let check = () => submission_lookup_current(value, record, configuration)
  let late_failure = Ref(0)
  let observation = submission_cancellation_lookup_original(
    snapshot,
    run_namespace,
    cancel_id,
    revision.to_int(),
    (table, cursor) => {
      physical_journal_row(current.physical, check, 0, table, cursor)
    },
    (table, key) => physical_journal_row(current.physical, check, 1, table, key),
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
    return Err(late_failure.val)
  }
  let observed = match observation {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  match check() {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  submission_cancellation_lookup_view(
    run_namespace,
    scope,
    definition,
    cancel_id,
    revision.to_int(),
    observed,
  )
}
