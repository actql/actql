///|
priv struct CapturedRunTestChain {
  run : PublicationContract
  invocation : PublicationContract
  observation : RunEvidenceValue
  definition : PublicationContract
  artifact : PublicationContract
  evidence : ResultOrderingEvidence
  retention : PublicationContract
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
fn captured_run_test_chain(
  with_model? : Bool = false,
  logical_cid? : String? = None,
  schema_cid? : String = ordering_test_cid("9"),
) -> CapturedRunTestChain {
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
    logical_cid.unwrap_or(logical),
    schema_cid,
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
    evidence,
    retention,
    manifest,
    receipt,
    authoring,
    models,
  }
}

///|
test "publication evidence defaults reserve fixed streams without changing node limits" {
  assert_eq(publication_evidence_workspace(-1), 0)
  assert_eq(publication_evidence_workspace(0), 0)
  assert_eq(publication_evidence_workspace(128), 5120)
  assert_eq(publication_evidence_workspace(256), 6144)
  assert_eq(publication_evidence_workspace(2147483647), 2147483647)
  let chain = captured_run_test_chain()
  let snapshot = admit_captured_result_snapshot(
    chain.definition,
    chain.artifact,
    "[{\"value\":7}]",
    ["value"],
    65536,
    256,
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
    256,
    32,
  ).unwrap()
  validate_effect_free_run_evidence_chain(
    chain.run,
    chain.invocation,
    [chain.definition],
    [chain.artifact],
    chain.manifest,
    chain.receipt,
    captured,
    65536,
    256,
    32,
  ).unwrap()
  let explicit = captured_validation_test_start(chain, captured, workspace=2048)
  let mut refused = false
  for _ in 0..<10000 {
    match explicit.advance(1) {
      Err(EvidenceInventoryMismatch("result_artifacts")) => {
        refused = true
        break
      }
      Err(_) => abort("unrelated evidence refusal")
      Ok((true, _)) => abort("fixed stream buffers require explicit capacity")
      Ok((false, _)) => ()
    }
  }
  assert_true(refused)
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
fn captured_preparation_test_start(
  with_model? : Bool = false,
) -> CapturedRunIssuancePreparation {
  let chain = captured_run_test_chain(with_model~)
  let snapshot = admit_captured_result_snapshot(
    chain.definition,
    chain.artifact,
    "[{\"value\":7}]",
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  start_effect_free_captured_run(
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
    32768,
  )
}

///|
fn captured_validation_test_start(
  chain : CapturedRunTestChain,
  captured : PublicationContract,
  workspace? : Int = 32768,
) -> ComputationEvidenceCheck {
  start_effect_free_run_evidence_check(
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
    workspace,
  )
}

///|
test "captured evidence validation preserves quantum-independent work and exact rows" {
  let chain = captured_run_test_chain()
  let issuer = captured_preparation_test_start()
  while !issuer.advance(256).unwrap().0 {
    ()
  }
  let captured = issuer.finish().unwrap()
  let mut expected_work = None
  for quantum in [1, 7, 64] {
    let check = captured_validation_test_start(chain, captured)
    let mut work = 0
    let mut polls = 0
    while true {
      let (done, used) = check.advance(quantum).unwrap()
      assert_true(used > 0 && used <= quantum)
      work += used
      polls += 1
      assert_true(polls < 100000)
      if done {
        break
      }
    }
    check.finish().unwrap()
    assert_true(check.finish() is Err(EvidenceEncoding))
    match expected_work {
      None => expected_work = Some(work)
      Some(expected) => assert_eq(work, expected)
    }
  }
  let altered = final_test_reseal_captured_context(
    captured, "\"value\":7", "\"value\":8",
  )
  let check = captured_validation_test_start(chain, altered)
  let mut failure = None
  for _ in 0..<100000 {
    match check.advance(1) {
      Err(issue) => {
        failure = Some(issue)
        break
      }
      Ok((done, _)) => assert_true(!done)
    }
  }
  assert_eq(failure, Some(EvidenceReferenceMismatch("captured_result_values")))
}

///|
test "captured evidence cancellation retires private checks without retiring inputs" {
  let chain = captured_run_test_chain()
  let issuer = captured_preparation_test_start()
  while !issuer.advance(256).unwrap().0 {
    ()
  }
  let captured = issuer.finish().unwrap()
  let original = publication_contract_json(captured)
  for
    phase in [
      "root-check", "receipt-check", "context-check", "capture-inventory", "result-lookup",
      "rows-check", "suffix-check",
    ] {
    let check = captured_validation_test_start(chain, captured)
    let mut reached = false
    for _ in 0..<100000 {
      let (done, work) = check.advance(1).unwrap()
      assert_eq(work, 1)
      assert_true(!done)
      if computation_evidence_check_fixture_phase(check) == phase {
        reached = true
        break
      }
    }
    assert_true(reached)
    check.cancel()
    check.cancel()
    assert_eq(computation_evidence_check_fixture_phase(check), "closed")
    assert_true(check.advance(1) is Err(EvidenceEncoding))
    assert_true(check.finish() is Err(EvidenceEncoding))
    assert_eq(publication_contract_json(captured), original)
  }
  let too_small = captured_validation_test_start(chain, captured, workspace=11)
  assert_true(too_small.advance(1) is Err(EvidenceEncoding))
  assert_eq(computation_evidence_check_fixture_phase(too_small), "closed")
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
  ).unwrap()
}

///|
test "captured receipt checking yields before context with admitted Model evidence" {
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
  let original = publication_contract_json(captured)
  let check = captured_validation_test_start(chain, captured)
  let mut receipt_polls = 0
  for _ in 0..<10000 {
    let (done, used) = check.advance(1).unwrap()
    assert_eq(used, 1)
    assert_true(!done)
    let phase = computation_evidence_check_fixture_phase(check)
    assert_true(phase != "context-check")
    if phase == "receipt-check" {
      receipt_polls += 1
      if receipt_polls > 64 {
        break
      }
    }
  }
  assert_eq(receipt_polls, 65)
  check.cancel()
  assert_eq(computation_evidence_check_fixture_phase(check), "closed")
  assert_eq(publication_contract_json(captured), original)
  let replay = captured_validation_test_start(chain, captured)
  while !replay.advance(7).unwrap().0 {
    ()
  }
  replay.finish().unwrap()
}

///|
test "publication commit preparation preserves dependency refusal before binding checks" {
  let chain = captured_run_test_chain()
  let issuer = captured_preparation_test_start()
  while !issuer.advance(256).unwrap().0 {
    ()
  }
  let captured = issuer.finish().unwrap()
  // Root contracts cannot substitute for Result dependencies. Invalid request
  // and index arguments must not mask the earlier typed inventory refusal.
  let check = start_effect_free_publication_commit_check(
    chain.run,
    chain.invocation,
    [chain.definition],
    [chain.artifact],
    [],
    [],
    [],
    [],
    chain.manifest,
    chain.receipt,
    captured,
    chain.run,
    chain.run,
    chain.run,
    65536,
    4096,
    32,
    32768,
  )
  assert_eq(check.advance(1), Err(CommitResultEvidence(ResultEvidenceCount)))
  assert_eq(publication_commit_preparation_fixture_phase(check), "closed")
  assert_true(check.finish() is Err(CommitEncoding))
  check.cancel()
  assert_eq(
    validate_effect_free_publication_commit_with_result_evidence(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      [],
      [],
      [],
      [],
      chain.manifest,
      chain.receipt,
      captured,
      chain.run,
      chain.run,
      chain.run,
      65536,
      4096,
      32,
    ),
    Err(CommitResultEvidence(ResultEvidenceCount)),
  )
}

///|
test "Captured Run preparation keeps final evidence checking and quantum-independent identity" {
  let mut identity = None
  let mut total = None
  for quantum in [1, 7, 64] {
    let preparation = captured_preparation_test_start(with_model=true)
    let mut work = 0
    let mut saw_context_check = false
    let mut saw_rows_check = false
    let mut finished = false
    for _ in 0..<500000 {
      let (done, used) = preparation.advance(quantum).unwrap()
      assert_true(used <= quantum)
      work += used
      let phase = captured_run_preparation_fixture_phase(preparation)
      if phase == "context-check" {
        saw_context_check = true
      }
      if phase == "rows-check" {
        saw_rows_check = true
      }
      if done {
        finished = true
        break
      }
      assert_true(used > 0)
    }
    assert_true(finished)
    if quantum == 1 {
      assert_true(saw_context_check && saw_rows_check)
    }
    let contract = preparation.finish().unwrap()
    let wire = publication_contract_json(contract)
    assert_true(wire.contains("\"result_values\":{\"answer\":[{\"value\":7}]}"))
    assert_true(wire.contains("\"result_fields\":{\"answer\":[\"value\"]}"))
    if identity is Some(previous) {
      assert_eq(publication_contract_identity(contract), previous)
    }
    identity = Some(publication_contract_identity(contract))
    if total is Some(previous) {
      assert_eq(work, previous)
    }
    total = Some(work)
    assert_true(preparation.finish() is Err(CaptureIssuanceEncoding))
    assert_eq(captured_run_preparation_fixture_phase(preparation), "closed")
  }
}

///|
test "Captured Run preparation cancels after real progress at every aggregate boundary" {
  for
    wanted in [
      "source-advances", "snapshot-inventory", "model-inventory", "context", "envelope",
      "seal", "context-check", "rows-check", "done",
    ] {
    let preparation = captured_preparation_test_start(with_model=true)
    let mut progress = 0
    let mut reached = false
    for _ in 0..<500000 {
      let (_, used) = preparation.advance(1).unwrap()
      progress += used
      if captured_run_preparation_fixture_phase(preparation) == wanted {
        reached = true
        break
      }
    }
    assert_true(reached && progress > 0)
    preparation.cancel()
    preparation.cancel()
    assert_eq(captured_run_preparation_fixture_phase(preparation), "closed")
    assert_true(preparation.advance(1) is Err(CaptureIssuanceEncoding))
    assert_true(preparation.finish() is Err(CaptureIssuanceEncoding))
  }
}

///|
test "capture input reference reservations survive context emission and cancel once" {
  for cancel in [false, true] {
    let preparation = captured_preparation_test_start(with_model=true)
    let mut reached = false
    for _ in 0..<500000 {
      let (done, _) = preparation.advance(1).unwrap()
      assert_true(!done)
      if captured_run_preparation_fixture_phase(preparation) == "context" {
        let (_, slots, snapshots, models) = captured_run_preparation_fixture_inventory(
          preparation,
        )
        assert_eq(slots, 2)
        assert_true(snapshots && models)
        reached = true
        break
      }
    }
    assert_true(reached)
    if !cancel {
      let mut retired = false
      for _ in 0..<500000 {
        let (done, _) = preparation.advance(1).unwrap()
        assert_true(!done)
        let (_, slots, snapshots, models) = captured_run_preparation_fixture_inventory(
          preparation,
        )
        if captured_run_preparation_fixture_phase(preparation) == "envelope" {
          assert_eq(slots, 0)
          assert_true(!snapshots && !models)
          retired = true
          break
        }
        assert_eq(slots, 2)
      }
      assert_true(retired)
    }
    preparation.cancel()
    preparation.cancel()
    assert_eq(
      captured_run_preparation_fixture_inventory(preparation),
      (0, 0, false, false),
    )
  }
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

///|
test "Captured Run sealing and restoration retain typed JSON data keys" {
  // Independent SHA-256 of {"sort":"relation","value":[{"value":{"$json":{"é":null}}}]}.
  let chain = captured_run_test_chain(
    logical_cid=Some(
      "sha256:2c63c45bcaf4b24b8b71f57c6a44d361f580b88b647b3c764b0e174691fbc43d",
    ),
  )
  let snapshot = admit_captured_result_snapshot(
    chain.definition,
    chain.artifact,
    "[{\"value\":{\"$json\":{\"é\":null}}}]",
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
    [],
    65536,
    4096,
    32,
  ).unwrap()
  let restored = admit_publication_contract(
    "captured_run",
    publication_contract_json(captured),
    65536,
    4096,
    32,
  ).unwrap()
  assert_eq(
    publication_contract_identity(restored),
    publication_contract_identity(captured),
  )
  let source = @source.parse_json_bytes_preserving(
    @utf8.encode(publication_contract_json(restored)),
    { max_input_bytes: 65536, max_nodes: 4096, max_depth: 32, },
  ).unwrap()
  let value = @json.from_source(source, 4096, 32, 65536, data_keys=true) catch {
    _ => abort("Invalid retained JSON value")
  }
  let context = @json.object_field(value, "effect_context").unwrap()
  let values = @json.object_field(context, "result_values").unwrap()
  guard @json.object_field(values, "answer") is Some(@json.Array(rows)) else {
    fail("Missing retained Result")
  }
  let row = @json.array_at(rows, 0).unwrap()
  let cell = @json.object_field(row, "value").unwrap()
  let payload = @json.object_field(cell, "$json").unwrap()
  assert_true(@json.object_field(payload, "é") is Some(@json.Null))
  assert_true(@json.object_field(payload, "é") is None)
}

///|
test "Captured Run issuance checks its unchanged publication root once" {
  let preparation = captured_preparation_test_start()
  let mut root_checks = 0
  let mut in_root = false
  let mut finished = false
  for _ in 0..<500000 {
    let (done, _) = preparation.advance(1).unwrap()
    let root = captured_run_preparation_fixture_phase(preparation) ==
      "root-check"
    if root && !in_root {
      root_checks += 1
    }
    in_root = root
    if done {
      finished = true
      break
    }
  }
  assert_true(finished)
  let captured = preparation.finish().unwrap()
  assert_eq(root_checks, 1)
  let chain = captured_run_test_chain()
  let independent = captured_validation_test_start(chain, captured)
  let mut independent_roots = 0
  in_root = false
  finished = false
  for _ in 0..<500000 {
    let (done, _) = independent.advance(1).unwrap()
    let root = computation_evidence_check_fixture_phase(independent) ==
      "root-check"
    if root && !in_root {
      independent_roots += 1
    }
    in_root = root
    if done {
      finished = true
      break
    }
  }
  assert_true(finished)
  independent.finish().unwrap()
  assert_eq(independent_roots, 1)
}
