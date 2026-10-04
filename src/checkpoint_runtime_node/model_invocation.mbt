///|
priv suberror ModelBridgeFailure {
  ModelBridgeFailed(String)
}

///|
fn model_member(value : Json, name : String) -> String raise ModelBridgeFailure {
  match text_member(value, name) {
    Some(text) => text
    None => raise ModelBridgeFailed("MissingModelOriginal:" + name)
  }
}

///|
fn model_parse(text : String) -> Json raise ModelBridgeFailure {
  let bounds = limits()
  if @source.parse_json(text, {
      max_input_bytes: bounds.max_wire_bytes,
      max_nodes: bounds.max_nodes,
      max_depth: bounds.max_depth,
    })
    is Err(_) {
    raise ModelBridgeFailed("ModelOriginalLimits")
  }
  match parse(text) {
    Some(value) => value
    None => raise ModelBridgeFailed("InvalidModelOriginal")
  }
}

///|
fn model_evidence(
  name : String,
  wire : String,
) -> @publication.RunEvidenceValue raise ModelBridgeFailure {
  let bounds = limits()
  match
    @publication.admit_run_evidence_value(
      name,
      wire,
      bounds.max_wire_bytes,
      bounds.max_nodes,
      bounds.max_depth,
    ) {
    Ok(value) => {
      if @publication.run_evidence_value_json(value) != wire {
        raise ModelBridgeFailed("NoncanonicalModelOriginal:" + name)
      }
      value
    }
    Err(issue) => raise ModelBridgeFailed(@debug.to_string(issue))
  }
}

///|
fn model_contract(
  name : String,
  wire : String,
) -> @publication.PublicationContract raise ModelBridgeFailure {
  let bounds = limits()
  match
    @publication.admit_publication_contract(
      name,
      wire,
      bounds.max_wire_bytes,
      bounds.max_nodes,
      bounds.max_depth,
    ) {
    Ok(value) => {
      if @publication.publication_contract_json(value) != wire {
        raise ModelBridgeFailed("NoncanonicalModelOriginal:" + name)
      }
      value
    }
    Err(issue) => raise ModelBridgeFailed(@debug.to_string(issue))
  }
}

///|
fn model_original_run(
  text : String,
) -> (@publication.RunPublicationAdmission, @publication.PublicationContract) raise ModelBridgeFailure {
  let original = model_parse(text)
  let template = model_evidence(
    "bound_invocation_template",
    model_member(original, "boundInvocationTemplateWire"),
  )
  let prepared = model_evidence(
    "prepared_invocation",
    model_member(original, "preparedInvocationWire"),
  )
  let authorization = model_evidence(
    "run_authorization",
    model_member(original, "runAuthorizationWire"),
  )
  let plan = model_contract(
    "compiled_plan",
    model_member(original, "compiledPlanWire"),
  )
  let definition = model_contract(
    "run_definition",
    model_member(original, "runDefinitionWire"),
  )
  let admission = match
    @publication.admit_run_publication(template, prepared, authorization, plan) {
    Ok(value) => value
    Err(issue) => raise ModelBridgeFailed(@debug.to_string(issue))
  }
  if @publication.check_model_original_run_binding(admission, definition)
    is Err(_) {
    raise ModelBridgeFailed("ModelRunBindingMismatch")
  }
  (admission, definition)
}

///|
fn model_integer(value : Json, name : String) -> Int64 raise ModelBridgeFailure {
  guard number_member(value, name) is Some(number) &&
    safe_integer(number) is Some(integer) else {
    raise ModelBridgeFailed("InvalidModelInteger:" + name)
  }
  integer
}

///|
fn model_boundary(
  value : Json,
) -> @publication.ModelInvocationBoundary raise ModelBridgeFailure {
  {
    unit_id: model_member(value, "unit_id"),
    task_index: model_integer(value, "task_index"),
    strategy_revision: model_integer(value, "strategy_revision"),
    inference_barrier_cid: model_member(value, "inference_barrier_cid"),
    account_id: model_member(value, "account_id"),
    configuration_cid: model_member(value, "configuration_cid"),
    entry_id: model_member(value, "entry_id"),
    principal: model_member(value, "principal"),
    connection: model_member(value, "connection"),
    resource: model_member(value, "resource"),
    context_cid: model_member(value, "context_cid"),
    installation_revision_cid: model_member(value, "installation_revision_cid"),
    configuration_contract_cid: model_member(
      value, "configuration_contract_cid",
    ),
    provider_configuration_cid: model_member(
      value, "provider_configuration_cid",
    ),
  }
}

///|
fn model_field(value : Json, name : String) -> Json raise ModelBridgeFailure {
  guard value is Object(map) && map.get(name) is Some(item) else {
    raise ModelBridgeFailed("MissingModelOriginal:" + name)
  }
  item
}

///|
fn model_call_set(
  request_wire : String,
) -> (
  @publication.BoundModelInvocationScope,
  @checkpoint.ModelCheckpointBinding,
) raise ModelBridgeFailure {
  let request = model_parse(request_wire)
  let (admission, definition) = model_original_run(
    model_member(request, "originalRunWire"),
  )
  let prepared_wire = model_member(request, "preparedInvocationWire")
  if prepared_wire !=
    @publication.run_evidence_value_json(
      @publication.run_publication_prepared(admission),
    ) {
    raise ModelBridgeFailed("ModelPreparedInvocationMismatch")
  }
  let scope = model_evidence(
    "model_invocation_scope",
    model_member(request, "scopeWire"),
  )
  let provider = model_evidence(
    "model_provider_binding",
    model_member(request, "providerBindingWire"),
  )
  let input = model_evidence(
    "model_input_artifact",
    model_member(request, "inputArtifactWire"),
  )
  let review = model_evidence(
    "run_review_projection",
    model_member(request, "reviewWire"),
  )
  guard model_field(request, "slotWires") is Array(wires) else {
    raise ModelBridgeFailed("MissingModelInventory")
  }
  if wires.length() > limits().max_nodes {
    raise ModelBridgeFailed("ModelOriginalLimits")
  }
  let slots : Array[@publication.RunEvidenceValue] = []
  for wire in wires {
    guard wire is String(text) else {
      raise ModelBridgeFailed("InvalidModelInventory")
    }
    slots.push(model_evidence("model_call_slot", text))
  }
  let boundary = model_boundary(model_field(request, "expectedBoundary"))
  let bound = match
    @publication.bind_model_invocation_scope(
      admission, definition, scope, provider, input, slots, boundary,
    ) {
    Ok(value) => value
    Err(issue) => raise ModelBridgeFailed(@debug.to_string(issue))
  }
  let checkpoint = match
    @checkpoint.admit_checkpoint_wire(
      model_member(request, "checkpointWire"),
      limits(),
    ) {
    Ok(value) => value
    Err(issue) => raise ModelBridgeFailed(@debug.to_string(issue))
  }
  let binding = match
    @checkpoint.bind_model_checkpoint(checkpoint, bound, review) {
    Ok(value) => value
    Err(issue) => raise ModelBridgeFailed(@debug.to_string(issue))
  }
  (bound, binding)
}

///|
fn model_scope_fields(
  scope : @publication.BoundModelInvocationScope,
) -> Map[String, Json] {
  let (run_id, run_definition_cid, unit_id) = @publication.model_invocation_scope_run(
    scope,
  )
  let boundary = @publication.model_invocation_scope_boundary(scope)
  let ids = @publication.model_invocation_scope_slots(scope)
  let slots : Array[Json] = []
  for ordinal in 0..<ids.length() {
    let (slot_cid, model_task_cid, fixed_request_cid) = @publication.model_invocation_scope_slot(
      scope, ordinal,
    ).unwrap()
    slots.push(
      Json::object({
        "ordinal": Json::number(ordinal.to_double()),
        "slotCid": Json::string(slot_cid),
        "modelTaskCid": Json::string(model_task_cid),
        "fixedRequestCid": Json::string(fixed_request_cid),
      }),
    )
  }
  {
    "runId": Json::string(run_id),
    "runDefinitionCid": Json::string(run_definition_cid),
    "unitId": Json::string(unit_id),
    "preparedInvocationCid": Json::string(
      @publication.model_invocation_scope_prepared_cid(scope),
    ),
    "scopeCid": Json::string(@publication.model_invocation_scope_cid(scope)),
    "inputArtifactCid": Json::string(
      @publication.model_invocation_scope_input_cid(scope),
    ),
    "providerBindingCid": Json::string(
      @publication.model_invocation_scope_provider_cid(scope),
    ),
    "taskIndex": Json::number(boundary.task_index.to_double()),
    "strategyRevision": Json::number(boundary.strategy_revision.to_double()),
    "slots": Json::array(slots),
  }
}

///|
/// Pure canonical-original linkage; never a current authority or custody fact.
#export_name("modelOriginalRunAdmit")
pub fn model_original_run_admit(original_run_wire : String) -> String {
  try {
    let (admission, definition) = model_original_run(original_run_wire)
    let wire = model_parse(@publication.publication_contract_json(definition))
    ok({
      "runId": Json::string(model_member(wire, "run_id")),
      "runDefinitionCid": Json::string(
        @publication.publication_contract_identity(definition),
      ),
      "preparedInvocationCid": Json::string(
        @publication.run_evidence_value_identity(
          @publication.run_publication_prepared(admission),
        ),
      ),
    })
  } catch {
    ModelBridgeFailed(issue) => fail_detail("InvalidModelOriginal", issue)
  }
}

///|
/// Returns bounded checked identities only. The Host must combine these with
/// the execution owner's opaque complete-input/call custody and retry facts.
#export_name("modelCallSetAdmit")
pub fn model_call_set_admit(request_wire : String) -> String {
  try {
    let (scope, _) = model_call_set(request_wire)
    let fields = model_scope_fields(scope)
    let request = model_parse(request_wire)
    let checkpoint = @checkpoint.admit_checkpoint_wire(
      model_member(request, "checkpointWire"),
      limits(),
    ).unwrap()
    fields["checkpointCid"] = Json::string(checkpoint.checkpoint_cid)
    ok(fields)
  } catch {
    ModelBridgeFailed(issue) => fail_detail("InvalidModelCallSet", issue)
  }
}

///|
#export_name("modelCallAttemptAdmit")
pub fn model_call_attempt_admit(
  request_wire : String,
  ordinal : Int,
  attempt_wire : String,
  authority_wire : String,
  attempt_index : Double,
) -> String {
  try {
    let (scope, _) = model_call_set(request_wire)
    guard safe_integer(attempt_index) is Some(index) else {
      raise ModelBridgeFailed("InvalidModelAttemptIndex")
    }
    let attempt = model_evidence("model_call_attempt", attempt_wire)
    let authority = model_evidence("model_dispatch_authority", authority_wire)
    match
      @publication.check_model_invocation_attempt(
        scope, ordinal, attempt, authority, index,
      ) {
      Ok(_) =>
        ok({
          "attemptIndex": Json::number(index.to_double()),
          "attemptCid": Json::string(
            @publication.run_evidence_value_identity(attempt),
          ),
        })
      Err(issue) => fail_detail("InvalidModelAttempt", @debug.to_string(issue))
    }
  } catch {
    ModelBridgeFailed(issue) => fail_detail("InvalidModelAttempt", issue)
  }
}

///|
#export_name("modelResolutionAdmit")
pub fn model_resolution_admit(
  request_wire : String,
  checkpoint_wire : String,
  resolution_wire : String,
  evidence_wire : String,
  authentication_json : String,
  authorities_json : String,
  verified_at : String,
) -> String {
  try {
    let (_, binding) = model_call_set(request_wire)
    match
      admit_resolution(
        checkpoint_wire,
        resolution_wire,
        evidence_wire,
        authentication_json,
        authorities_json,
        verified_at,
        model_binding=binding,
      ) {
      Ok((_, admitted)) =>
        ok({
          "resolution_id": Json::string(admitted.resolution_id),
          "resolution_cid": Json::string(admitted.resolution_cid),
          "decision": Json::string(decision_token(admitted.decision)),
          "attestation_preimage": Json::string(admitted.attestation_preimage),
        })
      Err(issue) => fail_detail(issue.code, issue.detail)
    }
  } catch {
    ModelBridgeFailed(issue) => fail_detail("InvalidModelCallSet", issue)
  }
}

///|
#export_name("modelResolutionDecide")
pub fn model_resolution_decide(
  request_wire : String,
  checkpoint_wire : String,
  resolution_wire : String,
  evidence_wire : String,
  authentication_json : String,
  authorities_json : String,
  verified_at : String,
  host_key_id : String,
  signature : String,
  closure_state : String,
  closure_resolution_cid : String,
  unknown_effects_json : String,
) -> String {
  try {
    let (_, binding) = model_call_set(request_wire)
    let unknown = match text_list(unknown_effects_json) {
      Some(values) => values
      None => return fail("InvalidUnknownEffects")
    }
    let (checkpoint, admitted) = match
      admit_resolution(
        checkpoint_wire,
        resolution_wire,
        evidence_wire,
        authentication_json,
        authorities_json,
        verified_at,
        model_binding=binding,
      ) {
      Ok(value) => value
      Err(issue) => return fail_detail(issue.code, issue.detail)
    }
    let verified = match
      @checkpoint.seal_verified_resolution(
        admitted,
        host_key_id,
        signature,
        limits(),
      ) {
      Ok(value) => value
      Err(issue) => return fail_resolution(issue)
    }
    let current = match closure(closure_state, closure_resolution_cid) {
      Some(value) => value
      None => return fail("InvalidClosure")
    }
    let action = @checkpoint.decide_resolution_commit(
      checkpoint, current, verified,
    )
    let (effect, run_status) = match
      @checkpoint.resolution_effect(
        checkpoint,
        verified.decision,
        unknown_effects=unknown,
      ) {
      MoveRun(status) =>
        ("move_run", Json::string(@checkpoint.run_status_token(status)))
      ContinuePreparation => ("continue_preparation", Json::null())
      EndPreparation => ("end_preparation", Json::null())
    }
    ok({
      "action": Json::string(commit_action(action)),
      "decision": Json::string(decision_token(verified.decision)),
      "effect": Json::string(effect),
      "run_status": run_status,
      "resolution_id": Json::string(verified.resolution_id),
      "resolution_cid": Json::string(verified.resolution_cid),
      "verified_resolution_cid": Json::string(verified.verified_resolution_cid),
      "verified_resolution_wire": Json::string(verified.wire),
      "resume_intent_id": optional_text(verified.resume_intent_id),
    })
  } catch {
    ModelBridgeFailed(issue) => fail_detail("InvalidModelCallSet", issue)
  }
}

///|
#export_name("modelResolutionAdmitImmediate")
pub fn model_resolution_admit_immediate(
  request_wire : String,
  body_wire : String,
  resolution_wire : String,
  evidence_wire : String,
  authentication_json : String,
  authorities_json : String,
  verified_at : String,
) -> String {
  try {
    let (_, binding) = model_call_set(request_wire)
    match
      admit_immediate(
        body_wire,
        resolution_wire,
        evidence_wire,
        authentication_json,
        authorities_json,
        verified_at,
        model_binding=binding,
      ) {
      Ok(admitted) =>
        ok({
          "checkpoint_cid": Json::string(admitted.checkpoint_cid()),
          "resolution_cid": Json::string(admitted.resolution_cid()),
          "decision": Json::string(decision_token(admitted.decision())),
          "attestation_preimage": Json::string(admitted.attestation_preimage()),
        })
      Err(issue) => fail_detail(issue.code, issue.detail)
    }
  } catch {
    ModelBridgeFailed(issue) => fail_detail("InvalidModelCallSet", issue)
  }
}

///|
#export_name("modelResolutionSealImmediate")
pub fn model_resolution_seal_immediate(
  request_wire : String,
  body_wire : String,
  resolution_wire : String,
  evidence_wire : String,
  authentication_json : String,
  authorities_json : String,
  verified_at : String,
  host_key_id : String,
  signature : String,
) -> String {
  try {
    let (_, binding) = model_call_set(request_wire)
    let admitted = match
      admit_immediate(
        body_wire,
        resolution_wire,
        evidence_wire,
        authentication_json,
        authorities_json,
        verified_at,
        model_binding=binding,
      ) {
      Ok(value) => value
      Err(issue) => return fail_detail(issue.code, issue.detail)
    }
    match
      @checkpoint.seal_immediate_resolution(
        admitted,
        host_key_id,
        signature,
        limits(),
      ) {
      Ok(immediate) =>
        ok({
          "checkpoint_cid": Json::string(immediate.checkpoint_cid),
          "decision": Json::string(decision_token(immediate.decision)),
          "resolution_cid": Json::string(immediate.resolution_cid),
          "verified_resolution_cid": Json::string(
            immediate.verified_resolution_cid,
          ),
          "verified_resolution_wire": Json::string(immediate.wire),
        })
      Err(issue) => fail_resolution(issue)
    }
  } catch {
    ModelBridgeFailed(issue) => fail_detail("InvalidModelCallSet", issue)
  }
}

///|
fn model_invocation_grant_at_impl(
  request_wire : String,
  checkpoint_wire : String,
  verified_wire : String,
  at : String,
  immediate : Bool,
) -> String {
  try {
    let (_, binding) = model_call_set(request_wire)
    let request = model_parse(request_wire)
    if model_member(request, "checkpointWire") != checkpoint_wire {
      raise ModelBridgeFailed("ModelCheckpointReadbackMismatch")
    }
    let grant = if immediate {
      @checkpoint.confirm_immediate_model_invocation_grant_wire(
        binding,
        verified_wire,
        at,
        limits(),
      )
    } else {
      let checkpoint = match
        @checkpoint.admit_checkpoint_wire(checkpoint_wire, limits()) {
        Ok(value) => value
        Err(issue) => return fail_checkpoint(issue)
      }
      let persisted = match
        @checkpoint.confirm_checkpoint_persisted(checkpoint, checkpoint_wire) {
        Ok(value) => value
        Err(issue) => return fail_checkpoint(issue)
      }
      @checkpoint.confirm_model_invocation_grant_wire(
        binding,
        persisted,
        verified_wire,
        at,
        limits(),
      )
    }
    match grant {
      Ok(grant) => {
        let fields = model_scope_fields(
          @checkpoint.model_invocation_grant_scope(grant),
        )
        fields["checkpointCid"] = Json::string(
          @checkpoint.model_invocation_grant_checkpoint_cid(grant),
        )
        fields["resolutionCid"] = Json::string(
          @checkpoint.model_invocation_grant_resolution_cid(grant),
        )
        fields["verifiedResolutionCid"] = Json::string(
          @checkpoint.model_invocation_grant_verified_resolution_cid(grant),
        )
        fields["expiresAt"] = Json::string(
          @checkpoint.model_invocation_grant_expires_at(grant),
        )
        fields["current"] = Json::boolean(
          @checkpoint.model_invocation_grant_current(grant, at),
        )
        ok(fields)
      }
      Err(issue) => fail_resolution(issue)
    }
  } catch {
    ModelBridgeFailed(issue) => fail_detail("InvalidModelGrant", issue)
  }
}

///|
/// Reconstruct a typed grant inside the execution runtime from the journal's
/// exact retained originals and authenticated resolution readback. The Host
/// must still verify current authority and enter each call durably before I/O.
pub fn model_invocation_grant_handle(
  request_wire : String,
  checkpoint_wire : String,
  verified_wire : String,
  at : String,
  immediate : Bool,
) -> Result[@checkpoint.ModelInvocationGrant, String] {
  try {
    let (_, binding) = model_call_set(request_wire)
    let request = model_parse(request_wire)
    if model_member(request, "checkpointWire") != checkpoint_wire {
      raise ModelBridgeFailed("ModelCheckpointReadbackMismatch")
    }
    if immediate {
      @checkpoint.confirm_immediate_model_invocation_grant_wire(
        binding, verified_wire, at, limits(),
      ).map_err(@debug.to_string)
    } else {
      let checkpoint = match @checkpoint.admit_checkpoint_wire(
        checkpoint_wire, limits(),
      ) {
        Ok(value) => value
        Err(issue) => raise ModelBridgeFailed(@debug.to_string(issue))
      }
      let persisted = match @checkpoint.confirm_checkpoint_persisted(
        checkpoint, checkpoint_wire,
      ) {
        Ok(value) => value
        Err(issue) => raise ModelBridgeFailed(@debug.to_string(issue))
      }
      @checkpoint.confirm_model_invocation_grant_wire(
        binding, persisted, verified_wire, at, limits(),
      ).map_err(@debug.to_string)
    }
  } catch {
    ModelBridgeFailed(issue) => Err(issue)
  }
}

///|
/// Live approval-scope check at Host-trusted time. Inputs must be the journal's
/// exact originals and wrapper from its trusted authenticated atomic commit.
/// Canonical reconstruction is linkage validation, not signature verification.
/// Arbitrary imported or rewritten database bytes are outside that trust. Current
/// per-send authority, owner custody, retry policy and journal entry remain
/// separate requirements; this result is not a physical dispatch permit.
#export_name("modelInvocationGrantAt")
pub fn model_invocation_grant_at(
  request_wire : String,
  checkpoint_wire : String,
  committed_verified_wire : String,
  at : String,
) -> String {
  model_invocation_grant_at_impl(
    request_wire, checkpoint_wire, committed_verified_wire, at, false,
  )
}

///|
/// Same live binding for an authenticated immediate answer; creates no waiting
/// Checkpoint, committed Resolution or resume intent.
#export_name("modelImmediateInvocationGrantAt")
pub fn model_immediate_invocation_grant_at(
  request_wire : String,
  checkpoint_wire : String,
  sealed_verified_wire : String,
  at : String,
) -> String {
  model_invocation_grant_at_impl(
    request_wire, checkpoint_wire, sealed_verified_wire, at, true,
  )
}
