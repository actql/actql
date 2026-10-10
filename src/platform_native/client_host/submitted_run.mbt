///|
/// A durable acceptance fact for this original Submission, not a start permit,
/// current control revision, execution success or published Result.
struct NativeClientSubmittedRunAdmission {
  request : @host.ClientRequestIdentity
  run_definition_cid : String
  revision : Int64
}

///|
pub fn native_client_submitted_run_admission(
  record : NativeClientSubmittedIntentRecord,
) -> NativeClientSubmittedRunAdmission? {
  record.run_admission
}

///|
pub fn native_client_submitted_run_request(
  admission : NativeClientSubmittedRunAdmission,
) -> @host.ClientRequestIdentity {
  admission.request
}

///|
pub fn native_client_submitted_run_definition_cid(
  admission : NativeClientSubmittedRunAdmission,
) -> String {
  admission.run_definition_cid
}

///|
pub fn native_client_submitted_run_admission_revision(
  admission : NativeClientSubmittedRunAdmission,
) -> Int64 {
  admission.revision
}

///|
fn submitted_run_admission_body(
  admission : NativeClientSubmittedRunAdmission,
) -> Result[String, NativeClientRunJournalIssue] {
  let request = match
    @host.client_request_identity_record_wire(admission.request) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  try {
    let writer = @encode.writer(8192, 8, 2)
    @encode.begin_object(writer)
    @encode.key(writer, "admitted_revision")
    // The existing exact Int64 decoder accepts decimal text, not a JSON
    // number routed through a floating-point value.
    @encode.string_value(writer, admission.revision.to_string())
    @encode.key(writer, "request")
    @encode.string_value(writer, request)
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(writer, admission.run_definition_cid)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Encoding)
  }
}

///|
fn read_submitted_run_admission(
  wire : String,
) -> Result[NativeClientSubmittedRunAdmission, NativeClientRunJournalIssue] {
  let source = @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 8192,
    max_nodes: 8,
    max_depth: 2,
  }).to_option()
  guard source is Some(source) &&
    @decode.admit(source, {
      max_nodes: 8,
      max_depth: 2,
      max_string_bytes: 8192,
      max_total_string_bytes: 8192,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, [
      "admitted_revision", "request", "run_definition_cid",
    ])
    is Ok(object) &&
    epoch_text(object, "request") is Some(request_wire) &&
    epoch_text(object, "run_definition_cid") is Some(run_definition_cid) &&
    @decode.lookup(object, "admitted_revision") is Some(revision) &&
    @decode.decimal_int64(revision) is Ok(revision) &&
    revision >= 0L else {
    return Err(CustodyLost)
  }
  let request = match
    @host.admit_client_request_identity_record_wire(request_wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let admission : NativeClientSubmittedRunAdmission = {
    request,
    run_definition_cid,
    revision,
  }
  match submitted_run_admission_body(admission) {
    Ok(original) if original == wire => Ok(admission)
    _ => Err(CustodyLost)
  }
}

///|
fn NativeClientRunJournal::validate_submitted_run_admission(
  self : NativeClientRunJournal,
  record : NativeClientSubmittedIntentRecord,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard record.run_admission is Some(admission) else { return Ok(()) }
  guard epoch_cursor(@scope.submission_epoch_wire(record.reference.epoch.body))
    is Some(cursor) &&
    @decode.open_object(cursor) is Ok(epoch) &&
    epoch_text(epoch, "authority_scope_cid") ==
    Some(@host.client_request_authority_scope_cid(admission.request)) &&
    @host.client_request_caller_id(admission.request) ==
    record.reference.request_id else {
    return Err(CustodyLost)
  }
  match self.retained(admission.request) {
    Ok(Some(run)) if @publication.publication_contract_identity(run.definition) ==
      admission.run_definition_cid &&
      run.revision >= admission.revision => Ok(())
    Err(Physical(issue)) => Err(Physical(issue))
    _ => Err(CustodyLost)
  }
}

///|
/// Bind the original unchecked intent, its opaque ordinary preparation and the
/// existing owner-issued Run in one request-journal transaction. Admission does
/// not reserve dispatch or claim physical start. Lookup cannot call this method.
/// The caller supplies current Host authority and the original selected context;
/// no configured grants, providers or restored kernel are manufactured here.
pub fn NativeClientRunJournal::accept_submitted_run(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  authority_scope_cid : String,
  current_authorization : Bool,
  now : Double,
) -> Result[NativeClientSubmittedIntentRecord, NativeClientRunJournalIssue] {
  if !current_authorization {
    return Err(AuthorizationDenied)
  }
  if !physical_equal(self.database, authority.database) ||
    @host.client_request_authority_scope_cid(request) != authority_scope_cid ||
    @host.client_request_caller_id(request) != reference.request_id {
    return Err(InvalidSubmission)
  }
  match
    authority.verify_epoch(
      reference.epoch,
      authority_scope_cid,
      current_authorization,
      now,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Epoch(issue))
  }
  guard preparation.preparation is Computation(prepared) else {
    return Err(UnsupportedPreparation)
  }
  match
    validate_native_client_run_binding(request, prepared, compiled, definition) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.transaction(() => {
    match
      self.verify_submission_locked(
        authority, reference, authority_scope_cid, current_authorization,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match self.submitted_intent_custody() {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let original = match self.retained_submission(reference) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    if @host.client_submitted_intent_cid(original.intent) !=
      preparation.intent_cid {
      return Err(ChangedIntent)
    }
    let before = if original.run_admission is Some(_) {
      "ready"
    } else {
      "preparing"
    }
    if !@host.client_submitted_intent_transition(before, "ready") {
      return Err(CustodyLost)
    }
    let run = match self.bind_run_locked(request, definition) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if original.run_admission is Some(admission) {
      if @host.client_request_identity_relation(admission.request, request) !=
        @host.SameRequest ||
        admission.run_definition_cid !=
        @publication.publication_contract_identity(definition) {
        return Err(ChangedIntent)
      }
      return Ok(original)
    }
    let run_admission : NativeClientSubmittedRunAdmission = {
      request,
      run_definition_cid: @publication.publication_contract_identity(definition),
      revision: run.revision,
    }
    let body = match
      submitted_intent_body(
        reference,
        original.intent,
        run_admission=Some(run_admission),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    self.database
    .compare_exchange(
      "client_submitted_intents",
      reference.request_id,
      original.revision,
      body,
    )
    .map(revision => {
      ..original,
      run_admission: Some(run_admission),
      revision,
    })
    .map_err(issue => Physical(issue))
  })
}
