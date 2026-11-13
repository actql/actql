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
  reads? : NativeClientJournalReadAccess? = None,
  runs? : Map[String, NativeClientRunRecord]? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard record.run_admission is Some(admission) else { return Ok(()) }
  let reference = record.reference.original
  let retained = match runs {
    None => self.retained(admission.request, reads~)
    Some(originals) =>
      Ok(originals.get(@host.client_request_scope_cid(admission.request)))
  }
  match retained {
    Ok(Some(run)) => {
      if record.run_state_observation is Some(_) &&
        run.run_observation_originals is None {
        return Err(CustodyLost)
      }
      if record.run_state_original is Some(wire) {
        if run.run_observation_originals is None {
          return Err(CustodyLost)
        }
        match record.run_state_observation {
          None =>
            if @host.validate_client_historical_run_state_original(
                run.definition,
                wire,
              )
              is Err(_) {
              return Err(CustodyLost)
            }
          Some((revision, key)) => {
            let state = match
              @host.restore_client_run_state_original(run.definition, wire) {
              Ok(value) => value
              Err(_) => return Err(CustodyLost)
            }
            let observation = match
              native_saved_state_observation(run, state, revision) {
              Ok(value) => value
              Err(issue) => return Err(issue)
            }
            if key != Some(observation.key()) ||
              observation.wire(revision).to_option() != Some(state.state_wire()) {
              return Err(CustodyLost)
            }
          }
        }
      }
      @host.validate_client_submitted_retained_run(
        reference,
        (admission.request, admission.run_definition_cid, admission.revision),
        run.request,
        run.definition,
        run.revision,
      ).map_err(_ => CustodyLost)
    }
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
  self.accept_submitted_run_with_operations(
    authority, reference, preparation, request, compiled, definition, authority_scope_cid,
    current_authorization, now,
  )
}

///|
fn NativeClientRunJournal::accept_submitted_run_with_operations(
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
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[NativeClientSubmittedIntentRecord, NativeClientRunJournalIssue] {
  match
    self.authorize_submitted_run(
      authority,
      reference,
      request,
      authority_scope_cid,
      current_authorization,
      now,
      operations~,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard preparation.preparation is Computation(prepared) else {
    return Err(UnsupportedPreparation)
  }
  match
    self.validate_prepared_run_binding(request, prepared, compiled, definition) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let observation = match
    capture_native_run_observation_originals(compiled, definition) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let plan = match
    capture_native_run_plan_original(
      prepared,
      compiled,
      definition,
      before_construction=run_metadata_construction(
        self.database,
        operations.map(value => value.reads),
      ),
    ) {
    Ok(value) => value
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
    run_observation_originals=Some(observation),
    run_plan_original=Some(plan),
    operations~,
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
  let observation = match
    @host.capture_client_effect_run_observation_originals(
      prepared, allowed, definition,
    ) {
    Ok(value) => value
    Err(@host.Compilation(EffectBinding(ForeignCompilation))) =>
      return Err(ChangedIntent)
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
    run_observation_originals=Some(observation),
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
  operations? : NativeClientJournalOperationAccess? = None,
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
    authority.verify_epoch_with_operations(
      reference.epoch,
      authority_scope_cid,
      current_authorization,
      now,
      operations~,
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
  publication_policy_originals? : String? = None,
  local_run_policy_original? : @host.ClientLocalRunPolicyOriginal? = None,
  run_observation_originals? : @host.ClientRunObservationOriginals? = None,
  run_plan_original? : NativeClientCapturedRunPlan? = None,
  current_fence? : (() -> Bool)? = None,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[NativeClientSubmittedIntentRecord, NativeClientRunJournalIssue] {
  let reads = operations.map(value => value.reads)
  if publication_policy_originals is Some(wire) {
    if current_fence is None {
      return Err(AuthorizationDenied)
    }
    if read_run_policy_originals(wire) is Err(_) {
      return Err(CustodyLost)
    }
  }
  if run_plan_original is Some(_) && run_observation_originals is None {
    return Err(ForeignRun)
  }
  if run_plan_original is Some(plan) &&
    run_observation_originals is Some(observation) &&
    (
      plan.definition_cid !=
      @publication.publication_contract_identity(definition) ||
      plan.prepared !=
      @publication.run_evidence_value_json(observation.prepared()) ||
      plan.authorization !=
      @publication.run_evidence_value_json(observation.authorization())
    ) {
    return Err(ForeignRun)
  }
  let stored_observation = match run_observation_originals {
    None => None
    Some(value) => {
      let original = match run_plan_original {
        Some(captured) =>
          captured_native_run_stored_observation(
            captured,
            value,
            definition,
            @host.client_request_program_cid(request),
            before_construction=run_metadata_construction(self.database, reads),
          )
        None => {
          let wire = match
            native_run_observation_originals_wire(
              value,
              before_construction=run_metadata_construction(
                self.database,
                reads,
              ),
            ) {
            Ok(wire) => wire
            Err(issue) => return Err(issue)
          }
          read_native_stored_run_observation(
            wire,
            definition,
            Some(@host.client_request_program_cid(request)),
            before_construction=run_metadata_construction(self.database, reads),
          ).map_err(_ => ForeignRun)
        }
      }
      match original {
        Ok(original) => Some(original)
        Err(issue) => return Err(issue)
      }
    }
  }
  let observation_wire = stored_observation.map(original => original.wire)
  let local_run_policy_originals = match local_run_policy_original {
    None => None
    Some(original) => {
      if current_fence is None {
        return Err(AuthorizationDenied)
      }
      let bytes = @host.client_local_run_policy_original_body(original)
      if @host.validate_client_local_run_policy_original_run(
          bytes, request, definition,
        )
        is Err(_) {
        return Err(ForeignRun)
      }
      let wire = @utf8.decode(bytes) catch { _ => return Err(Encoding) }
      Some(wire)
    }
  }
  self.transaction_with_reads(
    () => {
      if current_fence is Some(current) && !current() {
        return Err(AuthorizationDenied)
      }
      match
        self.verify_submission_locked(
          authority,
          reference,
          authority_scope_cid,
          current_authorization,
          reads~,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      match
        client_journal_issuance_anchor(
          self.database,
          "client_submitted_intent_custody",
          self.max_records,
          reads~,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      let original = match self.retained_submission(reference, reads~) {
        Ok(Some(value)) => value
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      if @host.client_submitted_intent_cid(original.intent) != intent_cid {
        return Err(ChangedIntent)
      }
      if original.run_admission is None && local_run_policy_originals is None {
        match
          read_client_journal_value(
            self.database,
            "client_local_installation_originals",
            local_policy_upgrade_key,
            reads,
          ) {
          Ok(_) => return Err(CustodyLost)
          Err(@sqlite.NotFound) => ()
          Err(issue) => return Err(Physical(issue))
        }
      }
      let before = if original.run_admission is Some(_) {
        "ready"
      } else if original.preparation_problem is Some(_) {
        "preparation_failed"
      } else {
        "preparing"
      }
      if !@host.client_submitted_intent_transition(before, "ready") {
        return Err(CustodyLost)
      }
      // An original packet must enter with first admission, not as backfill of
      // an accepted or merely pre-existing Run after custody was lost.
      if (
          effect_material_originals is Some(_) ||
          publication_policy_originals is Some(_) ||
          local_run_policy_originals is Some(_) ||
          observation_wire is Some(_)
        ) &&
        original.run_admission is None {
        match self.retained(request, reads~) {
          Ok(None) => ()
          Ok(Some(_)) =>
            return Err(
              if local_run_policy_originals is Some(_) ||
                publication_policy_originals is Some(_) ||
                observation_wire is Some(_) {
                CustodyLost
              } else {
                MissingEffectMaterialOriginal
              },
            )
          Err(issue) => return Err(issue)
        }
      }
      let run = match
        self.bind_run_locked(
          request,
          definition,
          operations~,
          run_observation_originals=if original.run_admission is None {
            observation_wire
          } else {
            None
          },
          observation_original=if original.run_admission is None {
            stored_observation
          } else {
            None
          },
        ) {
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
        // Old accepted rows without originals remain accepted history, never
        // repaired by a newly supplied compilation. Status will be unavailable.
        if run.run_observation_originals is Some(saved) &&
          observation_wire is Some(candidate) &&
          saved != candidate {
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
        if local_run_policy_originals is Some(packet) &&
          run.local_run_policy_originals != Some(packet) {
          return Err(CustodyLost)
        }
        if publication_policy_originals is Some(packet) &&
          run.publication_policy_originals != Some(packet) {
          // Missing accepted custody is not an unstarted Run or permission to
          // add a policy selected from the current installation after the fact.
          return Err(CustodyLost)
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
          match
            self.save_with_operations(
              { ..run, effect_material_originals: Some(packet), },
              operations~,
            ) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
        }
      }
      let run = match local_run_policy_originals {
        None => run
        Some(packet) => {
          if current_fence is Some(current) && !current() {
            return Err(AuthorizationDenied)
          }
          match
            self.save_with_operations(
              { ..run, local_run_policy_originals: Some(packet), },
              operations~,
            ) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
        }
      }
      let run = match publication_policy_originals {
        None => run
        Some(packet) => {
          if current_fence is Some(current) && !current() {
            return Err(AuthorizationDenied)
          }
          match
            self.save_with_operations(
              { ..run, publication_policy_originals: Some(packet), },
              operations~,
            ) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
        }
      }
      let run_admission : NativeClientSubmittedRunAdmission = {
        request,
        run_definition_cid: @publication.publication_contract_identity(
          definition,
        ),
        revision: run.revision,
      }
      // Only this fresh acceptance has proved the original Run did not exist.
      // Old accepted rows take the retained branch above, without initialization.
      let run_state_observation = if observation_wire is Some(_) {
        Some((0L, None))
      } else {
        None
      }
      let body = match
        submitted_intent_body(
          before_construction=submitted_encode_construction(
            self.database,
            operations,
          ),
          reference,
          original.intent,
          run_admission=Some(run_admission),
          run_state_observation~,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if current_fence is Some(current) && !current() {
        return Err(AuthorizationDenied)
      }
      match self.index_run_id_locked(authority, reference, run, operations~) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      match
        self.index_saved_run_reference_locked(
          authority,
          reference,
          run,
          operations~,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      self.invalidate_operation_submission()
      compare_exchange_client_journal_value(
        self.database,
        "client_submitted_intents",
        reference.request_id,
        original.revision,
        body,
        operations,
      )
      .map(revision => {
        ..original,
        run_admission: Some(run_admission),
        run_state_observation,
        revision,
      })
      .map_err(issue => Physical(issue))
    },
    reads~,
  )
}
