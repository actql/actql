///|
fn content_capture_test_string(
  value : @json.CanonicalValue,
  field : String,
) -> String {
  guard @json.object_field(value, field) is Some(@json.String(text)) else {
    abort("Missing Content fixture string")
  }
  text
}

///|
fn content_capture_test_generation(
  template : RunEvidenceValue,
  run : PublicationContract,
  live : Ref[Bool],
) -> BoundContentGeneration raise {
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(@contract.NumberType, nullable=false),
      ),
    ],
    max_fields=1,
    max_name_bytes=64,
  ).unwrap()
  let profile = prepare_content_serialization_profile(
    ContentJsonl,
    schema,
    ["id"],
    "{\"name\":\"empty.jsonl\"}",
    {
      max_fields: 1,
      max_name_bytes: 64,
      max_work: 1000,
      max_options_bytes: 4096,
      max_options_nodes: 100,
      max_options_depth: 8,
    },
  ).unwrap()
  let encoder = start_content_byte_encoder(
    profile,
    max_rows=10,
    max_bytes=4096,
    max_value_nodes=100,
    max_value_depth=8,
    max_frames=20,
  ).unwrap()
  assert_true(advance_content_bytes(encoder, 7) is ContentBytesReady("", ..))
  assert_eq(
    finish_content_bytes(encoder).unwrap().content_cid,
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  let limits : @admitted.ReferenceLimits = {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 8,
    max_text_units: 4096,
  }
  let binding : GeneratedContentBinding = {
    content_store_id: "fixture",
    content_store_cid: ordering_test_cid("1"),
    workspace_scope_cid: ordering_test_cid("2"),
    storage_scope: "workspace",
    retention_class: "fixture",
    expires_at: None,
    availability_evidence_cid: ordering_test_cid("3"),
    effective_data_policy_cid: ordering_test_cid("e"),
    data_classification: "internal",
    issuer_contract_cid: ordering_test_cid("5"),
    capture_authority_cid: ordering_test_cid("6"),
  }
  let candidate = prepare_generated_content_reference(encoder, binding, limits).unwrap()
  let issuer = @admitted.bind_reference_issuer(
    (_, wire) => live.val && wire == generated_content_reference_wire(candidate),
    _ => live.val,
  )
  let content = issue_generated_content_reference(candidate, issuer, limits).unwrap()
  let input = seal_run_evidence_value(
    "content_input_artifact",
    "{\"version\":\"actql-content-input-artifact/0.1\",\"program_definition_cid\":\"" +
    ordering_test_cid("8") +
    "\",\"parameter_values_cid\":\"" +
    ordering_test_cid("2") +
    "\",\"invocation_bindings_cid\":\"" +
    ordering_test_cid("3") +
    "\",\"task_ordinal\":0,\"step_ordinal\":1,\"input_fragment_cid\":\"" +
    ordering_test_cid("9") +
    "\",\"logical_relation_cid\":\"sha256:" +
    @sha.text_hex("{\"sort\":\"relation\",\"value\":[]}").unwrap() +
    "\",\"relation_schema_cid\":\"" +
    ordering_test_cid("a") +
    "\",\"ordered_rows_cid\":\"sha256:" +
    @sha.text_hex("[]").unwrap() +
    "\",\"row_count\":0,\"effective_data_policy_cid\":\"" +
    ordering_test_cid("e") +
    "\"}",
    65536,
    4096,
    32,
  ).unwrap()
  let input_body = @json.object_without_field(
    captured_test_value(run_evidence_value_json(input)),
    "input_artifact_cid",
  ).unwrap()
  let wrong_input = seal_run_evidence_value(
    "content_input_artifact",
    captured_test_wire(input_body).replace(
      old="\"effective_data_policy_cid\":\"" + ordering_test_cid("e") + "\"",
      new="\"effective_data_policy_cid\":\"" + ordering_test_cid("f") + "\"",
    ),
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    bind_generated_content_observation(
      template,
      publication_contract_identity(run),
      "content-1",
      ordering_test_cid("b"),
      wrong_input,
      candidate,
      content,
      65536,
      4096,
      32,
    )
    is Err(_),
  )
  bind_generated_content_observation(
    template,
    publication_contract_identity(run),
    "content-1",
    ordering_test_cid("b"),
    input,
    candidate,
    content,
    65536,
    4096,
    32,
  ).unwrap()
}

///|
fn content_capture_test_template() -> RunEvidenceValue {
  let template_body = @json.object_without_field(
    captured_test_value(
      run_evidence_value_json(receipt_test_template(ordering_test_cid("8"))),
    ),
    "bound_invocation_template_cid",
  ).unwrap()
  seal_run_evidence_value(
    "bound_invocation_template",
    captured_test_wire(template_body).replace(
      old="\"required_profile_contracts\":[]",
      new="\"required_profile_contracts\":[{\"profile_id\":\"actql-content/0.1\",\"contract_cid\":\"" +
        ordering_test_cid("c") +
        "\"}]",
    ),
    65536,
    4096,
    32,
  ).unwrap()
}

///|
fn content_capture_test_chain(
  live : Ref[Bool],
) -> (CapturedRunTestChain, BoundContentGeneration) raise {
  let original = captured_run_test_chain()
  let template = content_capture_test_template()
  let admission = receipt_test_admission(template, ordering_test_cid("8"))
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
  let generation = content_capture_test_generation(template, run, live)
  let observation_body = @json.object_without_field(
    captured_test_value(
      run_evidence_value_json(receipt_test_observation(template)),
    ),
    "observation_set_cid",
  ).unwrap()
  let observation_wire = captured_test_wire(observation_body)
    .replace(old="\"materialized\":false", new="\"materialized\":true")
    .replace(
      old="\"availability_evidence_cids\":[]",
      new="\"availability_evidence_cids\":[\"" + ordering_test_cid("3") + "\"]",
    )
  let observation = seal_run_evidence_value(
    "observation_set",
    "{\"content_generation_cids\":[\"" +
    run_evidence_value_identity(
      bound_content_generation_value(generation).unwrap(),
    ) +
    "\"]," +
    observation_wire[1:].to_owned(),
    65536,
    4096,
    32,
  ).unwrap()
  let invocation = issue_content_run_invocation(
    template,
    observation,
    [generation],
    65536,
    4096,
    32,
  ).unwrap()
  let evidence = issue_result_occurrence_evidence(
    original.definition,
    content_capture_test_string(
      captured_test_value(publication_contract_json(original.artifact)),
      "logical_result_cid",
    ),
    ordering_test_cid("9"),
    ordering_test_cid("a"),
    [],
    ordering_test_cid("b"),
    ordering_test_cid("e"),
    "actql-common-host",
    ordering_test_cid("c"),
    16384,
    128,
    8,
  ).unwrap()
  let artifact = issue_complete_result_artifact(
    original.definition,
    invocation,
    evidence,
    manifest_test_retention(ordering_test_cid("e")),
    1,
    32768,
    256,
    8,
  ).unwrap()
  let manifest = issue_result_manifest(
    run,
    invocation,
    [original.definition],
    [artifact],
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    issue_effect_free_run_receipt(
      admission,
      run,
      invocation,
      observation,
      [original.definition],
      [artifact],
      manifest,
      receipt_test_journal(),
      [],
      [],
      [],
      [],
      [],
      65536,
      4096,
      32,
    )
    is Err(ReceiptIssuanceInventoryMismatch("content_generation_cids")),
  )
  let receipt = issue_effect_free_run_receipt(
    admission,
    run,
    invocation,
    observation,
    [original.definition],
    [artifact],
    manifest,
    receipt_test_journal(),
    [],
    [],
    [],
    [],
    [],
    65536,
    4096,
    32,
    content_generations=[generation],
  ).unwrap()
  (
    { ..original, run, invocation, observation, artifact, manifest, receipt, },
    generation,
  )
}

///|
fn content_capture_test_start(
  chain : CapturedRunTestChain,
  generations : Array[BoundContentGeneration],
) -> CapturedRunIssuancePreparation {
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
    [],
    65536,
    4096,
    32,
    65536,
    content_generations=generations,
  )
}

///|
fn content_capture_test_finish(
  preparation : CapturedRunIssuancePreparation,
  quantum : Int,
) -> Result[(PublicationContract, Int), CapturedRunIssuanceIssue] raise {
  let mut total = 0
  for _ in 0..<100000 {
    match preparation.advance(quantum) {
      Err(issue) => return Err(issue)
      Ok((done, used)) => {
        assert_true(used <= quantum)
        total += used
        if done {
          return preparation.finish().map(value => (value, total))
        }
        assert_true(used > 0)
      }
    }
  }
  fail("Content capture did not finish")
}

///|
test "terminal Content observation cannot substitute its own policy" {
  let (chain, generation) = content_capture_test_chain(Ref(true))
  let body = @json.object_without_field(
    captured_test_value(run_evidence_value_json(chain.observation)),
    "observation_set_cid",
  ).unwrap()
  let observation = seal_run_evidence_value(
    "observation_set",
    captured_test_wire(body).replace(
      old="\"data_policy_cid\":\"" + ordering_test_cid("e") + "\"",
      new="\"data_policy_cid\":\"" + ordering_test_cid("f") + "\"",
    ),
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    issue_content_run_invocation(
      content_capture_test_template(),
      observation,
      [generation],
      65536,
      4096,
      32,
    )
    is Err(_),
  )
}

///|
test "Content receipt and capture retain the original proofs even without a Ref Result column" {
  let live = Ref(true)
  let (chain, generation) = content_capture_test_chain(live)
  let receipt = publication_contract_json(chain.receipt)
  assert_true(receipt.contains("\"kind\":\"content_generation\""))
  assert_true(!receipt.contains("\"kind\":\"model_invocation\""))
  let mut previous : (String, Int)? = None
  for quantum in [1, 7, 64] {
    let preparation = content_capture_test_start(chain, [generation])
    let (captured, work) = content_capture_test_finish(preparation, quantum).unwrap()
    if previous is Some((wire, used)) {
      assert_eq(publication_contract_json(captured), wire)
      assert_eq(work, used)
    }
    previous = Some((publication_contract_json(captured), work))
    let context = @json.object_field(
      captured_test_value(publication_contract_json(captured)),
      "effect_context",
    ).unwrap()
    let records = @json.object_field(context, "content_generations").unwrap()
    guard records is @json.Array(values) else { fail("No Content inventory") }
    assert_eq(@json.array_count(values), 1)
    let record = @json.array_at(values, 0).unwrap()
    for
      (name, evidence) in [
        (
          "content_evidence",
          bound_content_generation_derivation(generation).unwrap(),
        ),
        (
          "content_generation",
          bound_content_generation_value(generation).unwrap(),
        ),
        (
          "content_input_artifact",
          bound_content_generation_input_artifact(generation).unwrap(),
        ),
      ] {
      let saved = @json.object_field(record, name).unwrap()
      assert_eq(captured_test_wire(saved), run_evidence_value_json(evidence))
    }
    let reference = @json.object_field(record, "content_reference").unwrap()
    assert_eq(
      content_capture_test_string(reference, "content_ref_cid"),
      bound_content_generation_reference(generation).unwrap(),
    )
    let metadata = @json.object_field(reference, "metadata").unwrap()
    assert_eq(
      content_capture_test_string(metadata, "content_cid"),
      "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    )
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
    assert_eq(captured_content_generation_count(captured), Some(1))
    let storage = captured_content_generation_storage(
      captured,
      chain.run,
      ordering_test_cid("1"),
      0,
    ).unwrap()
    assert_eq(
      storage.0,
      content_generation_private_holding_cid(
        chain.run,
        ordering_test_cid("1"),
        "content-1",
        "content_bytes",
      ).unwrap(),
    )
    assert_eq(
      storage.1,
      bound_content_generation_reference(generation).unwrap(),
    )
    assert_eq(
      storage.2,
      "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    )
    assert_eq(storage.3, 0L)
    assert_eq(storage.4.length(), 3)
    assert_eq(storage.4[0].0, "content_input_artifact")
    assert_eq(
      storage.4[0].2,
      run_evidence_value_json(
        bound_content_generation_input_artifact(generation).unwrap(),
      ),
    )
    assert_true(
      captured_content_generation_storage(
        captured,
        chain.run,
        ordering_test_cid("9"),
        0,
      )
      is None,
    )
    assert_true(
      captured_content_generation_storage(
        captured,
        chain.run,
        ordering_test_cid("1"),
        1,
      )
      is None,
    )
  }
  let missing = content_capture_test_start(chain, [])
  assert_true(content_capture_test_finish(missing, 7) is Err(_))
  // Cancellation retires this preparation, not the original issued reference.
  let cancelled = content_capture_test_start(chain, [generation])
  assert_true(cancelled.advance(7) is Ok((false, 7)))
  cancelled.cancel()
  cancelled.cancel()
  assert_true(bound_content_generation_value(generation) is Some(_))
  let revoked = content_capture_test_start(chain, [generation])
  live.val = false
  assert_true(content_capture_test_finish(revoked, 7) is Err(_))
}

///|
test "Saved Content proof tampering cannot be hidden by resealing the outer capture" {
  let (chain, generation) = content_capture_test_chain(Ref(true))
  let (captured, _) = content_capture_test_finish(
    content_capture_test_start(chain, [generation]),
    7,
  ).unwrap()
  let body = @json.object_without_field(
    captured_test_value(publication_contract_json(captured)),
    "captured_run_cid",
  ).unwrap()
  let context = @json.object_field(body, "effect_context").unwrap()
  let context_body = @json.object_without_field(context, "effect_context_cid").unwrap()
  for
    (old, replacement) in [
      ("\"row_count\":0", "\"row_count\":1"),
      (
        "\"issuer_kind\":\"content_derivation\"", "\"issuer_kind\":\"connector_capture\"",
      ),
      ("\"node_id\":\"content-1\"", "\"node_id\":\"content-2\""),
      (
        "\"parameter_values_cid\":\"" + ordering_test_cid("2") + "\"",
        "\"parameter_values_cid\":\"" + ordering_test_cid("9") + "\"",
      ),
    ] {
    let changed = captured_test_value(
      captured_test_wire(context_body).replace(old~, new=replacement),
    )
    let identity = @json.cid_value(changed, 65536, 4096, 32)
    let changed = @json.object_with_string_field(
      changed, "effect_context_cid", identity,
    ).unwrap()
    let changed_wire = captured_test_wire(body).replace(
      old=captured_test_wire(context),
      new=captured_test_wire(changed),
    )
    let changed = seal_publication_contract(
      "captured_run", changed_wire, 65536, 4096, 32,
    ).unwrap()
    assert_true(
      validate_effect_free_run_evidence_chain(
        chain.run,
        chain.invocation,
        [chain.definition],
        [chain.artifact],
        chain.manifest,
        chain.receipt,
        changed,
        65536,
        4096,
        32,
      )
      is Err(EvidenceReferenceMismatch("content_generations")),
    )
  }
}
