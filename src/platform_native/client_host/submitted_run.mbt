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
fn NativeClientRunJournal::validate_submitted_run_admission(
  self : NativeClientRunJournal,
  record : NativeClientSubmittedIntentRecord,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard record.run_admission is Some(admission) else { return Ok(()) }
  let reference = match
    @host.admit_client_submission_reference_record(record.reference.wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  match self.retained(admission.request) {
    Ok(Some(run)) =>
      @host.validate_client_submitted_retained_run(
        reference,
        (admission.request, admission.run_definition_cid, admission.revision),
        run.request,
        run.definition,
        run.revision,
      ).map_err(_ => CustodyLost)
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
  match
    self.authorize_submitted_run(
      authority, reference, request, authority_scope_cid, current_authorization,
      now,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard preparation.preparation is Computation(prepared) else {
    return Err(UnsupportedPreparation)
  }
  match
    validate_native_client_run_binding(request, prepared, compiled, definition) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.accept_original_submitted_run(
    authority,
    reference,
    preparation.intent_cid,
    request,
    definition,
    authority_scope_cid,
    current_authorization,
  )
}

///|
/// Admit the original Effect preparation through its existing checked owner.
/// No Effect-free compilation, second Run, dispatch reservation or mutation
/// permit is created. Both execution families commit acceptance in the same
/// original request-journal transaction and retain the same immutable fact.
pub fn NativeClientRunJournal::accept_submitted_effect_run(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  authority_scope_cid : String,
  current_authorization : Bool,
  now : Double,
) -> Result[NativeClientSubmittedIntentRecord, NativeClientRunJournalIssue] {
  match
    self.authorize_submitted_run(
      authority, reference, request, authority_scope_cid, current_authorization,
      now,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard preparation.preparation is EffectComputation(prepared) else {
    return Err(UnsupportedPreparation)
  }
  let identity = @host.prepared_client_effect_identity(prepared)
  if @host.client_request_program_cid(request) !=
    identity.program_definition_cid ||
    @host.client_request_parameters_cid(request) !=
    identity.parameter_values_cid {
    return Err(ChangedIntent)
  }
  match @host.bind_client_effect_compiled_run(prepared, allowed, definition) {
    Ok(_) => ()
    Err(@host.ForeignCompilation) => return Err(ChangedIntent)
    Err(_) => return Err(ForeignRun)
  }
  self.accept_original_submitted_run(
    authority,
    reference,
    preparation.intent_cid,
    request,
    definition,
    authority_scope_cid,
    current_authorization,
  )
}

///|
fn NativeClientRunJournal::authorize_submitted_run(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  authority_scope_cid : String,
  current_authorization : Bool,
  now : Double,
) -> Result[Unit, NativeClientRunJournalIssue] {
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
  Ok(())
}

///|
/// Both public family-specific callers have validated their exact opaque
/// preparation and definition. This private transaction cannot be used to
/// substitute a merely equal CID for the checked owner or retained intent.
fn NativeClientRunJournal::accept_original_submitted_run(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  intent_cid : String,
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  authority_scope_cid : String,
  current_authorization : Bool,
  effect_material_originals? : String? = None,
  current_fence? : (() -> Bool)? = None,
) -> Result[NativeClientSubmittedIntentRecord, NativeClientRunJournalIssue] {
  self.transaction(() => {
    if current_fence is Some(current) && !current() {
      return Err(AuthorizationDenied)
    }
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
    if @host.client_submitted_intent_cid(original.intent) != intent_cid {
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
    // An original packet must enter with first admission, not as backfill of
    // an accepted or merely pre-existing Run after custody was lost.
    if effect_material_originals is Some(_) && original.run_admission is None {
      match self.retained(request) {
        Ok(None) => ()
        Ok(Some(_)) => return Err(MissingEffectMaterialOriginal)
        Err(issue) => return Err(issue)
      }
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
      if effect_material_originals is Some(packet) {
        match run.effect_material_originals {
          None => return Err(MissingEffectMaterialOriginal)
          Some(existing) if existing != packet =>
            return Err(ChangedEffectMaterialOriginal)
          Some(_) => ()
        }
      }
      if current_fence is Some(current) && !current() {
        return Err(AuthorizationDenied)
      }
      return Ok(original)
    }
    let run = match effect_material_originals {
      None => run
      Some(packet) => {
        if current_fence is Some(current) && !current() {
          return Err(AuthorizationDenied)
        }
        match self.save({ ..run, effect_material_originals: Some(packet), }) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
      }
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
    if current_fence is Some(current) && !current() {
      return Err(AuthorizationDenied)
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
