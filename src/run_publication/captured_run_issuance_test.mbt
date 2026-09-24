///|
priv struct CapturedRunTestChain {
  run : PublicationContract
  invocation : PublicationContract
  observation : RunEvidenceValue
  definition : PublicationContract
  artifact : PublicationContract
  manifest : PublicationContract
  receipt : PublicationContract
  authoring : RunEvidenceValue
  models : Array[RunEvidenceValue]
}

///|
fn captured_test_value(wire : String) -> @json.CanonicalValue {
  let parsed = @source.parse_json(wire, {
    max_input_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
  }).unwrap()
  @json.from_source(parsed, 4096, 32, 65536) catch {
    _ => abort("Invalid captured test value")
  }
}

///|
fn captured_test_wire(value : @json.CanonicalValue) -> String {
  @json.stringify_value(value, 65536, 4096, 32) catch {
    _ => abort("Invalid captured test encoding")
  }
}

///|
fn captured_run_test_chain(with_model? : Bool = false) -> CapturedRunTestChain {
  let program = ordering_test_cid("8")
  let template = receipt_test_template(program)
  let admission = receipt_test_admission(template, program)
  let run = issue_run_definition(
    admission,
    "scope",
    "run",
    ordering_test_cid("0"),
    "2026-09-18T00:00:00.000Z",
    "2026-09-18T04:00:00.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let observation = receipt_test_observation(template)
  let invocation = issue_run_invocation(template, observation, 65536, 4096, 32).unwrap()
  let relation_node = @source.parse_json(
    "{\"sort\":\"relation\",\"value\":[{\"value\":7}]}",
    { max_input_bytes: 65536, max_nodes: 4096, max_depth: 32, },
  ).unwrap()
  let relation = @json.from_source(relation_node, 4096, 32, 65536) catch {
    _ => abort("invalid Relation fixture")
  }
  let logical = @json.cid_value(relation, 65536, 4096, 32) catch {
    _ => abort("invalid Relation fixture identity")
  }
  let policy = ordering_test_cid("e")
  let retention = manifest_test_retention(policy)
  let definition = result_definition_contract(
    prepare_result_definition(ordering_test_cid("8"), "answer").unwrap(),
  )
  let evidence = issue_result_occurrence_evidence(
    definition,
    logical,
    ordering_test_cid("9"),
    ordering_test_cid("a"),
    [],
    ordering_test_cid("b"),
    policy,
    "actql-common-host",
    ordering_test_cid("c"),
    16384,
    128,
    8,
  ).unwrap()
  let artifact = issue_complete_result_artifact(
    definition, invocation, evidence, retention, 1, 32768, 256, 8,
  ).unwrap()
  let manifest = issue_result_manifest(
    run,
    invocation,
    [definition],
    [artifact],
    65536,
    4096,
    32,
  ).unwrap()
  let models = if with_model {
    [receipt_test_model_evidence(artifact)]
  } else {
    []
  }
  let receipt = issue_effect_free_run_receipt(
    admission,
    run,
    invocation,
    observation,
    [definition],
    [artifact],
    manifest,
    receipt_test_journal(),
    [],
    [],
    [],
    models,
    [],
    65536,
    4096,
    32,
  ).unwrap()
  let authoring = seal_run_evidence_value(
    "authoring_context",
    "{\"version\":\"actql-authoring-context/0.1\"," +
    "\"program_definition_cid\":\"" +
    program +
    "\",\"annotations\":[]}",
    65536,
    4096,
    32,
  ).unwrap()
  {
    run,
    invocation,
    observation,
    definition,
    artifact,
    manifest,
    receipt,
    authoring,
    models,
  }
}

///|
test "Captured Run issuer binds exact Result values and field order" {
  let chain = captured_run_test_chain()
  let snapshot = admit_captured_result_snapshot(
    chain.definition,
    chain.artifact,
    "[{\"value\":7}]",
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  let captured = issue_effect_free_captured_run(
    chain.run,
    chain.invocation,
    [chain.definition],
    [chain.artifact],
    chain.manifest,
    chain.receipt,
    [snapshot],
    [],
    chain.authoring,
    chain.models,
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    validate_effect_free_run_evidence_chain(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      captured,
      65536,
      4096,
      32,
    )
    is Ok(_),
  )
  assert_true(
    publication_contract_json(captured).contains(
      "\"result_values\":{\"answer\":[{\"value\":7}]}",
    ),
  )
}

///|
test "a self-identified Receipt cannot publish an unauthorized decision" {
  let chain = captured_run_test_chain()
  let snapshot = admit_captured_result_snapshot(
    chain.definition,
    chain.artifact,
    "[{\"value\":7}]",
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  let captured = issue_effect_free_captured_run(
    chain.run,
    chain.invocation,
    [chain.definition],
    [chain.artifact],
    chain.manifest,
    chain.receipt,
    [snapshot],
    [],
    chain.authoring,
    chain.models,
    65536,
    4096,
    32,
  ).unwrap()
  let authorization = @json.object_field(
    captured_test_value(publication_contract_json(chain.receipt)),
    "run_authorization",
  ).unwrap()
  let authorization_body = @json.object_without_field(
    authorization, "run_authorization_cid",
  ).unwrap()
  let authorization_body_wire = captured_test_wire(authorization_body)
  let unauthorized = seal_run_evidence_value(
    "run_authorization",
    authorization_body_wire.replace(
      old="\"decision\":\"allowed\"",
      new="\"decision\":\"approved\"",
    ),
    65536,
    4096,
    32,
  ).unwrap()
  let original_authorization_wire = captured_test_wire(authorization)
  let receipt_body = @json.object_without_field(
    captured_test_value(publication_contract_json(chain.receipt)),
    "receipt_identity_cid",
  ).unwrap()
  let forged_receipt = seal_publication_contract(
    "run_receipt",
    captured_test_wire(receipt_body).replace(
      old=original_authorization_wire,
      new=run_evidence_value_json(unauthorized),
    ),
    65536,
    4096,
    32,
  ).unwrap()
  let captured_body = @json.object_without_field(
    captured_test_value(publication_contract_json(captured)),
    "captured_run_cid",
  ).unwrap()
  let forged_capture = seal_publication_contract(
    "captured_run",
    captured_test_wire(captured_body).replace(
      old=publication_contract_json(chain.receipt),
      new=publication_contract_json(forged_receipt),
    ),
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    validate_effect_free_run_evidence_chain(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      forged_receipt,
      forged_capture,
      65536,
      4096,
      32,
    )
    is Err(EvidenceReferenceMismatch("run_authorization")),
  )
}

///|
test "Captured Result snapshot rejects substituted rows and fields" {
  let chain = captured_run_test_chain()
  assert_true(
    admit_captured_result_snapshot(
      chain.definition,
      chain.artifact,
      "[{\"value\":8}]",
      ["value"],
      65536,
      4096,
      32,
    )
    is Err(CaptureIssuanceReferenceMismatch("logical_result_cid")),
  )
  assert_true(
    admit_captured_result_snapshot(
      chain.definition,
      chain.artifact,
      "[{\"value\":7}]",
      ["other"],
      65536,
      4096,
      32,
    )
    is Err(CaptureIssuanceInvalidFields("answer")),
  )
  assert_true(
    admit_captured_result_snapshot(
      chain.definition,
      chain.artifact,
      "[ {\"value\":7}]",
      ["value"],
      65536,
      4096,
      32,
    )
    is Err(CaptureIssuanceInvalidRows("answer")),
  )
}

///|
test "Captured Run issuance rejects a foreign Receipt before exposure" {
  let chain = captured_run_test_chain()
  let snapshot = admit_captured_result_snapshot(
    chain.definition,
    chain.artifact,
    "[{\"value\":7}]",
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  let receipt_body = @json.object_without_field(
    captured_test_value(publication_contract_json(chain.receipt)),
    "receipt_identity_cid",
  ).unwrap()
  let forged = seal_publication_contract(
    "run_receipt",
    captured_test_wire(receipt_body).replace(
      old="\"result_manifest_cid\":\"" +
        publication_contract_identity(chain.manifest) +
        "\"",
      new="\"result_manifest_cid\":\"" + ordering_test_cid("f") + "\"",
    ),
    65536,
    4096,
    32,
  ).unwrap()
  let issue = issue_effect_free_captured_run(
    chain.run,
    chain.invocation,
    [chain.definition],
    [chain.artifact],
    chain.manifest,
    forged,
    [snapshot],
    [],
    chain.authoring,
    chain.models,
    65536,
    4096,
    32,
  ).unwrap_err()
  assert_eq(
    issue,
    CaptureIssuanceChain(EvidenceReferenceMismatch("result_manifest")),
  )
}

///|
test "Effect-free Captured Run rejects a final Effectful Receipt" {
  let chain = captured_run_test_chain()
  let snapshot = admit_captured_result_snapshot(
    chain.definition,
    chain.artifact,
    "[{\"value\":7}]",
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  let receipt_body = @json.object_without_field(
    captured_test_value(publication_contract_json(chain.receipt)),
    "receipt_identity_cid",
  ).unwrap()
  let final_body = captured_test_wire(receipt_body).replace(
    old="{\"aoa_ir_version\":",
    new="{\"effect_preview_cid\":\"" +
      ordering_test_cid("1") +
      "\",\"effect_set_apply_receipt_cid\":\"" +
      ordering_test_cid("2") +
      "\",\"captured_run_cid\":\"" +
      ordering_test_cid("3") +
      "\",\"aoa_ir_version\":",
  )
  let final_receipt = seal_publication_contract(
    "run_receipt", final_body, 65536, 4096, 32,
  ).unwrap()
  assert_eq(
    issue_effect_free_captured_run(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      final_receipt,
      [snapshot],
      [],
      chain.authoring,
      chain.models,
      65536,
      4096,
      32,
    ).unwrap_err(),
    CaptureIssuanceChain(EvidenceNotEffectFree),
  )
}

///|
test "pending source-state advance binds the captured ObservationSet" {
  let chain = captured_run_test_chain()
  let next_cid = "sha256:f743721c5679bdef371b58eaa6b2a0df9d869c2653301090ea92a75025881f8b"
  let wire = "{\"checkpoint_contract_cid\":\"" +
    ordering_test_cid("1") +
    "\",\"next_checkpoint_value\":{\"cursor\":7}," +
    "\"next_checkpoint_value_cid\":\"" +
    next_cid +
    "\",\"observation_set_cid\":\"" +
    run_evidence_value_identity(chain.observation) +
    "\",\"previous_generation\":0,\"requirement_cid\":\"" +
    ordering_test_cid("2") +
    "\"}"
  assert_true(
    admit_pending_source_state_advance(wire, chain.observation, 65536, 4096, 32)
    is Ok(_),
  )
  let foreign = wire.replace(
    old=run_evidence_value_identity(chain.observation),
    new=ordering_test_cid("f"),
  )
  assert_true(
    admit_pending_source_state_advance(
      foreign,
      chain.observation,
      65536,
      4096,
      32,
    )
    is Err(CaptureIssuanceReferenceMismatch("source_state_advance")),
  )
}

///|
test "Captured Run rejects an advance from another ObservationSet" {
  let chain = captured_run_test_chain()
  let foreign_template = receipt_test_template(ordering_test_cid("7"))
  let foreign_observation = receipt_test_observation(foreign_template)
  let next_cid = "sha256:f743721c5679bdef371b58eaa6b2a0df9d869c2653301090ea92a75025881f8b"
  let wire = "{\"checkpoint_contract_cid\":\"" +
    ordering_test_cid("1") +
    "\",\"next_checkpoint_value\":{\"cursor\":7}," +
    "\"next_checkpoint_value_cid\":\"" +
    next_cid +
    "\",\"observation_set_cid\":\"" +
    run_evidence_value_identity(foreign_observation) +
    "\",\"previous_generation\":0,\"requirement_cid\":\"" +
    ordering_test_cid("2") +
    "\"}"
  let advance = admit_pending_source_state_advance(
    wire, foreign_observation, 65536, 4096, 32,
  ).unwrap()
  let snapshot = admit_captured_result_snapshot(
    chain.definition,
    chain.artifact,
    "[{\"value\":7}]",
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    issue_effect_free_captured_run(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      [snapshot],
      [advance],
      chain.authoring,
      chain.models,
      65536,
      4096,
      32,
    )
    is Err(CaptureIssuanceReferenceMismatch("source_state_advance")),
  )
}

///|
test "Captured Run and Receipt bind the same model evidence set" {
  let chain = captured_run_test_chain(with_model=true)
  let snapshot = admit_captured_result_snapshot(
    chain.definition,
    chain.artifact,
    "[{\"value\":7}]",
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  let captured = issue_effect_free_captured_run(
    chain.run,
    chain.invocation,
    [chain.definition],
    [chain.artifact],
    chain.manifest,
    chain.receipt,
    [snapshot],
    [],
    chain.authoring,
    chain.models,
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    validate_effect_free_run_evidence_chain(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      captured,
      65536,
      4096,
      32,
    )
    is Ok(_),
  )
  assert_true(
    issue_effect_free_captured_run(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      [snapshot],
      [],
      chain.authoring,
      [],
      65536,
      4096,
      32,
    )
    is Err(CaptureIssuanceReferenceMismatch("model_evidence")),
  )
}
