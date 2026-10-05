///|
fn model_evidence_of(name : String) -> @publication.RunEvidenceValue {
  let kind = if name == "slot0" || name == "slot1" {
    "model_call_slot"
  } else {
    name
  }
  @publication.admit_run_evidence_value(
    kind,
    model_fixture_wire(name),
    262144,
    4096,
    32,
  ).unwrap()
}

///|
fn model_boundary_fixture() -> @publication.ModelInvocationBoundary {
  let value = parse_wire(model_fixture_wire("expected_boundary"), limits()).unwrap()
  {
    unit_id: string_field(value, "unit_id").unwrap(),
    task_index: 1L,
    strategy_revision: 2L,
    inference_barrier_cid: string_field(value, "inference_barrier_cid").unwrap(),
    account_id: string_field(value, "account_id").unwrap(),
    configuration_cid: string_field(value, "configuration_cid").unwrap(),
    entry_id: string_field(value, "entry_id").unwrap(),
    principal: string_field(value, "principal").unwrap(),
    connection: string_field(value, "connection").unwrap(),
    resource: string_field(value, "resource").unwrap(),
    context_cid: string_field(value, "context_cid").unwrap(),
    installation_revision_cid: string_field(value, "installation_revision_cid").unwrap(),
    configuration_contract_cid: string_field(
      value, "configuration_contract_cid",
    ).unwrap(),
    provider_configuration_cid: string_field(
      value, "provider_configuration_cid",
    ).unwrap(),
  }
}

///|
fn model_bind_fixture(
  scope? : @publication.RunEvidenceValue = model_evidence_of(
    "model_invocation_scope",
  ),
  provider? : @publication.RunEvidenceValue = model_evidence_of(
    "model_provider_binding",
  ),
  input? : @publication.RunEvidenceValue = model_evidence_of(
    "model_input_artifact",
  ),
  slots? : Array[@publication.RunEvidenceValue] = [
    model_evidence_of("slot0"),
    model_evidence_of("slot1"),
  ],
  expected? : @publication.ModelInvocationBoundary = model_boundary_fixture(),
) -> Result[
  @publication.BoundModelInvocationScope,
  @publication.RunEvidenceValueIssue,
] {
  let plan = @publication.admit_publication_contract(
    "compiled_plan",
    model_fixture_wire("compiled_plan"),
    262144,
    4096,
    32,
  ).unwrap()
  let definition = @publication.admit_publication_contract(
    "run_definition",
    model_fixture_wire("run_definition"),
    262144,
    4096,
    32,
  ).unwrap()
  let admission = @publication.admit_run_publication(
    model_evidence_of("bound_invocation_template"),
    model_evidence_of("prepared_invocation"),
    model_evidence_of("run_authorization"),
    plan,
  ).unwrap()
  @publication.bind_model_invocation_scope(
    admission, definition, scope, provider, input, slots, expected,
  )
}

///|
fn model_changed(
  value : @publication.RunEvidenceValue,
  field : String,
  replacement : Json?,
) -> Result[@publication.RunEvidenceValue, @publication.RunEvidenceValueIssue] {
  let name = @publication.run_evidence_value_name(value)
  let identity = match name {
    "run_review_projection" => "review_projection_cid"
    "model_input_artifact" => "input_artifact_cid"
    "model_call_slot" => "model_call_slot_cid"
    _ => "self_cid"
  }
  let fields : Map[String, Json] = Map([])
  for
    (key, item) in @json.object_fields(
      parse_wire(@publication.run_evidence_value_json(value), limits()).unwrap(),
    ).unwrap() {
    if key != identity && key != field {
      fields[key] = to_json(item)
    }
  }
  if replacement is Some(item) {
    fields[field] = item
  }
  @publication.seal_run_evidence_value(
    name,
    Json::object(fields).stringify(),
    262144,
    4096,
    32,
  )
}

///|
fn model_checkpoint_fixture() -> SealedCheckpoint {
  admit_checkpoint_wire(model_fixture_wire("checkpoint"), limits()).unwrap()
}

///|
fn model_binding_fixture() -> ModelCheckpointBinding {
  bind_model_checkpoint(
    model_checkpoint_fixture(),
    model_bind_fixture().unwrap(),
    model_evidence_of("run_review_projection"),
  ).unwrap()
}

///|
fn model_approval_evidence(
  checkpoint : SealedCheckpoint,
  prepared_cid : String,
) -> String {
  let approval_wire = with_self_cid(
    {
      "version": Json::string("actql-run-scope-approval/0.1"),
      "prepared_invocation_cid": Json::string(prepared_cid),
      "review_projection_cid": Json::string(
        checkpoint.checkpoint.review_projection_cid,
      ),
      "claim": Json::string("invocation_scope_approved"),
      "approver": Json::string("alice"),
      "approved_at": Json::string("2026-09-25T11:00:00.000Z"),
      "expires_at": Json::string("2026-09-26T12:00:00.000Z"),
      "proof": proof("reviewer-key"),
    },
    "run_scope_approval_cid",
  )
  wire_of(
    canonical_of(
      Json::object({
        "version": Json::string("actql-checkpoint-approval-evidence/0.1"),
        "kind": Json::string("model_invocation"),
        "checkpoint_cid": Json::string(checkpoint.checkpoint_cid),
        "review_projection_cid": Json::string(
          checkpoint.checkpoint.review_projection_cid,
        ),
        "compatibility_approval": to_json(
          parse_wire(approval_wire, limits()).unwrap(),
        ),
      }),
      limits(),
    ).unwrap(),
    limits(),
  ).unwrap()
}

///|
test "Model Checkpoint admits only the exact closed table and waiting kind" {
  let checkpoint = model_checkpoint_fixture()
  assert_eq(checkpoint.checkpoint.kind, ModelInvocation)
  assert_eq(checkpoint_artifact_type(ModelInvocation), "model_invocation_scope")
  assert_true(
    checkpoint_combination_valid(
      checkpoint.checkpoint.subject,
      Preflight,
      ModelInvocation,
    ),
  )
  assert_true(
    !checkpoint_combination_valid(
      checkpoint.checkpoint.subject,
      Commit,
      ModelInvocation,
    ),
  )
  assert_true(
    !checkpoint_combination_valid(
      PrepareAttempt(prepare_attempt_id="p"),
      Preflight,
      ModelInvocation,
    ),
  )
  assert_eq(parse_checkpoint_kind("model_budget"), None)
  assert_true(
    !checkpoint_requirements_valid(ModelInvocation, [EffectScopeApproved]),
  )
  let persisted = confirm_checkpoint_persisted(checkpoint, checkpoint.wire).unwrap()
  let state = issue_waiting_run_state(
    persisted,
    checkpoint.checkpoint.created_at,
    ["result"],
    limits(),
  ).unwrap()
  assert_eq(
    admit_run_state_wire(state, limits()).unwrap().status,
    WaitingCheckpoint,
  )
  assert_true(
    admit_run_state_wire(
      state.replace(old="model_invocation", new="model_budget"),
      limits(),
    )
    is Err(_),
  )
}

///|
test "Model scope binds independent originals and keeps the real PreparedInvocation" {
  let bound = model_bind_fixture().unwrap()
  assert_eq(
    @publication.model_invocation_scope_cid(bound),
    "sha256:3cabfeb57f5e1b83d060f416630bf5c18026be8e23867c4b2ee7a33fcf7ba08b",
  )
  assert_eq(
    @publication.model_invocation_scope_prepared_cid(bound),
    @publication.run_evidence_value_identity(
      model_evidence_of("prepared_invocation"),
    ),
  )
  assert_true(
    @publication.model_invocation_scope_prepared_cid(bound) !=
    @publication.model_invocation_scope_cid(bound),
  )
  assert_eq(@publication.model_invocation_scope_slots(bound), [
    @publication.run_evidence_value_identity(model_evidence_of("slot0")),
    @publication.run_evidence_value_identity(model_evidence_of("slot1")),
  ])
  assert_true(
    bind_model_checkpoint(
      model_checkpoint_fixture(),
      bound,
      model_evidence_of("run_review_projection"),
    )
    is Ok(_),
  )
}

///|
test "Model scope rejects changed Run input provider barrier occurrence and inventory" {
  let scope = model_evidence_of("model_invocation_scope")
  for
    field in [
      "run_definition_cid", "input_artifact_cid", "provider_binding_cid", "inference_barrier_cid",
    ] {
    assert_true(
      model_bind_fixture(
        scope=model_changed(scope, field, Some(Json::string(cid("9")))).unwrap(),
      )
      is Err(_),
    )
  }
  for field in ["task_index", "strategy_revision"] {
    assert_true(
      model_bind_fixture(
        scope=model_changed(scope, field, Some(Json::number(7.0))).unwrap(),
      )
      is Err(_),
    )
  }
  assert_true(
    model_bind_fixture(slots=[
      model_evidence_of("slot1"),
      model_evidence_of("slot0"),
    ])
    is Err(_),
  )
  assert_true(model_bind_fixture(slots=[model_evidence_of("slot0")]) is Err(_))
  assert_true(model_changed(scope, "model_call_slot_cids", None) is Err(_))
  let duplicate = @publication.run_evidence_value_identity(
    model_evidence_of("slot0"),
  )
  assert_true(
    model_changed(
      scope,
      "model_call_slot_cids",
      Some(string_array_json([duplicate, duplicate])),
    )
    is Err(_),
  )
  let empty = model_changed(
    scope,
    "model_call_slot_cids",
    Some(Json::array([])),
  ).unwrap()
  assert_true(model_bind_fixture(scope=empty, slots=[]) is Ok(_))
  assert_true(model_bind_fixture(scope=empty) is Err(_))
}

///|
test "Model scope compares every trusted activation and provider binding field" {
  let scope = model_evidence_of("model_invocation_scope")
  let value = parse_wire(@publication.run_evidence_value_json(scope), limits()).unwrap()
  let context = @json.object_field(value, "authorization_context").unwrap()
  for
    changed in [
      "account_id", "configuration_cid", "entry_id", "principal", "connection", "resource",
      "context_cid",
    ] {
    let fields : Map[String, Json] = Map([])
    for (key, item) in @json.object_fields(context).unwrap() {
      fields[key] = if key == changed {
        Json::string(cid("9"))
      } else {
        to_json(item)
      }
    }
    let altered = model_changed(
      scope,
      "authorization_context",
      Some(Json::object(fields)),
    ).unwrap()
    assert_true(model_bind_fixture(scope=altered) is Err(_))
  }
  for
    changed in [
      "provider_id", "installation_revision_cid", "configuration_contract_cid", "configuration_cid",
    ] {
    let provider = model_changed(
      model_evidence_of("model_provider_binding"),
      changed,
      Some(Json::string(cid("9"))),
    ).unwrap()
    let altered = model_changed(
      scope,
      "provider_binding_cid",
      Some(Json::string(@publication.run_evidence_value_identity(provider))),
    ).unwrap()
    assert_true(model_bind_fixture(scope=altered, provider~) is Err(_))
  }
}

///|
test "Model review rejects scope aliases for PreparedInvocation and wrong review inventory" {
  let scope = model_bind_fixture().unwrap()
  let checkpoint = model_checkpoint_fixture()
  for
    changed in [
      "prepared_invocation_cid", "execution_context_cid", "host_policy_cid",
    ] {
    let review = model_changed(
      model_evidence_of("run_review_projection"),
      changed,
      Some(Json::string(@publication.model_invocation_scope_cid(scope))),
    ).unwrap()
    let reissued = sealed_of({
      ..checkpoint.checkpoint,
      review_projection_cid: @publication.run_evidence_value_identity(review),
    })
    assert_true(bind_model_checkpoint(reissued, scope, review) is Err(_))
  }
  let review = model_changed(
    model_evidence_of("run_review_projection"),
    "displayed_scope",
    Some(
      Json::object({
        "model_invocation_scope_cid": Json::string(
          @publication.model_invocation_scope_cid(scope),
        ),
        "model_call_slot_cids": string_array_json([]),
      }),
    ),
  ).unwrap()
  let reissued = sealed_of({
    ..checkpoint.checkpoint,
    review_projection_cid: @publication.run_evidence_value_identity(review),
  })
  assert_true(bind_model_checkpoint(reissued, scope, review) is Err(_))
}

///|
test "Model approval requires original binding and exact persisted grant readback" {
  let checkpoint = model_checkpoint_fixture()
  let binding = model_binding_fixture()
  let prepared = @publication.model_invocation_scope_prepared_cid(
    model_bind_fixture().unwrap(),
  )
  let evidence = model_approval_evidence(checkpoint, prepared)
  let resolution = with_self_cid(
    resolution_fields_for(checkpoint, "approved", Some(canonical_cid(evidence))),
    "resolution_cid",
  )
  assert_eq(
    issue_of(admit(checkpoint, resolution, Some(evidence))),
    Some(EvidenceMismatch("model_checkpoint_binding")),
  )
  let admitted = admit_checkpoint_resolution(
    checkpoint,
    resolution,
    Some(evidence),
    authentication(resolution),
    authorities(),
    "2026-09-25T12:00:01.000Z",
    limits(),
    model_binding=binding,
  ).unwrap()
  let verified = seal_verified_resolution(
    admitted,
    "host-key",
    "aG9zdA==",
    limits(),
  ).unwrap()
  let persisted = confirm_checkpoint_persisted(checkpoint, checkpoint.wire).unwrap()
  let grant = confirm_model_invocation_grant(
    binding,
    persisted,
    verified,
    verified.wire,
    "2026-09-25T12:00:01.000Z",
    limits(),
  ).unwrap()
  assert_eq(
    model_invocation_grant_checkpoint_cid(grant),
    checkpoint.checkpoint_cid,
  )
  assert_eq(
    model_invocation_grant_resolution_cid(grant),
    verified.resolution_cid,
  )
  assert_eq(
    model_invocation_grant_expires_at(grant),
    "2026-09-26T12:00:00.000Z",
  )
  assert_true(model_invocation_grant_current(grant, "2026-09-26T11:59:59.999Z"))
  assert_true(
    !model_invocation_grant_current(grant, "2026-09-26T12:00:00.000Z"),
  )
  assert_true(
    !model_invocation_grant_current(grant, "2026-09-25T12:00:00.000Z"),
  )
  assert_true(
    confirm_model_invocation_grant(
      binding,
      persisted,
      verified,
      verified.wire + " ",
      "2026-09-25T12:00:01.000Z",
      limits(),
    )
    is Err(_),
  )
  // A self-consistent outer CID does not bypass exact wrapper reconstruction.
  // These mutations are structural corruption tests, not signature validation.
  for
    (field, replacement) in [
      ("requirements", string_array_json(["effect_scope_approved"])),
      ("authorization_evidence_cid", Json::string(checkpoint.checkpoint_cid)),
      ("authorization_context_cid", Json::string(checkpoint.checkpoint_cid)),
      ("unexpected", Json::boolean(true)),
    ] {
    let fields : Map[String, Json] = Map([])
    for
      (key, value) in @json.object_fields(
        parse_wire(verified.wire, limits()).unwrap(),
      ).unwrap() {
      if key != "verified_resolution_cid" {
        fields[key] = to_json(value)
      }
    }
    fields[field] = replacement
    let corrupted = with_self_cid(fields, "verified_resolution_cid")
    assert_true(resumed_approval(corrupted, limits()) is Ok(_))
    assert_true(
      confirm_model_invocation_grant_wire(
        binding,
        persisted,
        corrupted,
        "2026-09-25T12:00:01.000Z",
        limits(),
      )
      is Err(_),
    )
    assert_true(
      confirm_immediate_model_invocation_grant_wire(
        binding,
        corrupted,
        "2026-09-25T12:00:01.000Z",
        limits(),
      )
      is Err(_),
    )
  }
  let wrong = model_approval_evidence(
    checkpoint,
    checkpoint.checkpoint.required_artifact_cid,
  )
  let wrong_resolution = with_self_cid(
    resolution_fields_for(checkpoint, "approved", Some(canonical_cid(wrong))),
    "resolution_cid",
  )
  assert_eq(
    issue_of(
      admit_checkpoint_resolution(
        checkpoint,
        wrong_resolution,
        Some(wrong),
        authentication(wrong_resolution),
        authorities(),
        "2026-09-25T12:00:01.000Z",
        limits(),
        model_binding=binding,
      ),
    ),
    Some(EvidenceMismatch("prepared_invocation_cid")),
  )
  let immediate = admit_immediate_resolution(
    checkpoint.checkpoint,
    resolution,
    Some(evidence),
    authentication(resolution),
    authorities(),
    "2026-09-25T12:00:01.000Z",
    limits(),
    model_binding=binding,
  ).unwrap()
  assert_eq(immediate.resolution_cid(), admitted.resolution_cid)
}

///|
test "Model scoped attempts bind original one-based index and refuse legacy send evidence" {
  let scope = model_bind_fixture().unwrap()
  let attempt = model_evidence_of("model_call_attempt")
  let authority = model_evidence_of("model_dispatch_authority")
  assert_true(
    @publication.check_model_invocation_attempt(
      scope, 0, attempt, authority, 1L,
    )
    is Ok(_),
  )
  for index in [0L, 2L] {
    assert_true(
      @publication.check_model_invocation_attempt(
        scope, 0, attempt, authority, index,
      )
      is Err(_),
    )
  }
  assert_true(
    @publication.check_model_invocation_attempt(
      scope, 1, attempt, authority, 1L,
    )
    is Err(_),
  )
  for
    field in [
      "slot_cid", "run_definition_cid", "model_task_cid", "fixed_request_cid", "authority_evidence_cid",
      "provider_id",
    ] {
    let altered = model_changed(attempt, field, Some(Json::string(cid("9")))).unwrap()
    assert_true(
      @publication.check_model_invocation_attempt(
        scope, 0, altered, authority, 1L,
      )
      is Err(_),
    )
  }
  let legacy = model_changed(authority, "model_invocation_scope_cid", None).unwrap()
  let legacy_attempt = model_changed(
    attempt,
    "authority_evidence_cid",
    Some(Json::string(@publication.run_evidence_value_identity(legacy))),
  ).unwrap()
  assert_true(
    @publication.check_model_invocation_attempt(
      scope, 0, legacy_attempt, legacy, 1L,
    )
    is Err(_),
  )
}

///|
test "Model input and call originals cannot be replaced by a self-consistent scope alone" {
  let scope = model_evidence_of("model_invocation_scope")
  for
    field in [
      "program_definition_cid", "unit_definition_cid", "effective_inputs_cid",
    ] {
    let input = model_changed(
      model_evidence_of("model_input_artifact"),
      field,
      Some(Json::string(cid("9"))),
    ).unwrap()
    let changed_scope = model_changed(
      scope,
      "input_artifact_cid",
      Some(Json::string(@publication.run_evidence_value_identity(input))),
    ).unwrap()
    assert_true(model_bind_fixture(scope=changed_scope, input~) is Err(_))
  }
  for
    field in [
      "input_artifact_cid", "model_task_cid", "program_definition_cid", "unit_definition_cid",
      "effective_inputs_cid",
    ] {
    let slot = model_changed(
      model_evidence_of("slot0"),
      field,
      Some(Json::string(cid("9"))),
    ).unwrap()
    let slots = [slot, model_evidence_of("slot1")]
    let changed_scope = model_changed(
      scope,
      "model_call_slot_cids",
      Some(
        string_array_json(slots.map(@publication.run_evidence_value_identity)),
      ),
    ).unwrap()
    assert_true(model_bind_fixture(scope=changed_scope, slots~) is Err(_))
  }
  let value = parse_wire(@publication.run_evidence_value_json(scope), limits()).unwrap()
  let context = @json.object_field(value, "authorization_context").unwrap()
  let fields : Map[String, Json] = Map([])
  for (key, item) in @json.object_fields(context).unwrap() {
    fields[key] = to_json(item)
  }
  fields["subject_cid"] = Json::string(
    @publication.run_evidence_value_identity(scope),
  )
  assert_true(
    model_changed(scope, "authorization_context", Some(Json::object(fields)))
    is Err(_),
  )
  assert_true(
    @publication.admit_run_evidence_value(
      "model_invocation_scope",
      model_fixture_wire("model_invocation_scope"),
      32,
      4096,
      32,
    )
    is Err(_),
  )
  assert_true(
    @publication.admit_run_evidence_value(
      "model_invocation_scope",
      model_fixture_wire("model_invocation_scope"),
      262144,
      4,
      32,
    )
    is Err(_),
  )
}
