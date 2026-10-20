///|
test "saved Content generation needs original identity and current issued reference" {
  let (chain, original) = content_capture_test_chain(Ref(true))
  let (captured, _) = content_capture_test_finish(
    content_capture_test_start(chain, [original]),
    7,
  ).unwrap()
  let context = @json.object_field(
    captured_test_value(publication_contract_json(captured)),
    "effect_context",
  ).unwrap()
  guard @json.object_field(context, "content_generations")
    is Some(@json.Array(records)) else {
    fail("No saved generation")
  }
  let record = @json.array_at(records, 0).unwrap()
  let wire = captured_test_wire(
    @json.object_field(record, "content_reference").unwrap(),
  )
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
  let limits : @admitted.ReferenceLimits = {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 8,
    max_text_units: 4096,
  }
  let candidate = prepare_stored_generated_content_reference(
    wire, binding, limits,
  ).unwrap()
  let live = Ref(true)
  let issuer = @admitted.bind_reference_issuer((_, value) => value == wire, _ => {
    live.val
  })
  let content = issue_stored_generated_content_reference(
    candidate, issuer, limits,
  ).unwrap()
  let template = content_capture_test_template()
  let input = admit_run_evidence_value(
    "content_input_artifact",
    captured_test_wire(
      @json.object_field(record, "content_input_artifact").unwrap(),
    ),
    65536,
    4096,
    32,
  ).unwrap()
  let derivation = admit_run_evidence_value(
    "content_evidence",
    captured_test_wire(@json.object_field(record, "content_evidence").unwrap()),
    65536,
    4096,
    32,
  ).unwrap()
  let evidence = admit_run_evidence_value(
    "content_generation",
    captured_test_wire(
      @json.object_field(record, "content_generation").unwrap(),
    ),
    65536,
    4096,
    32,
  ).unwrap()
  let expected = run_evidence_value_identity(
    bound_content_generation_value(original).unwrap(),
  )
  let run = publication_contract_identity(chain.run)
  let restored = readmit_generated_content_observation(
    template,
    run,
    "content-1",
    ordering_test_cid("b"),
    expected,
    input,
    derivation,
    evidence,
    candidate,
    content,
  ).unwrap()
  let from_capture = readmit_captured_generated_content_observation(
    captured,
    chain.run,
    template,
    "content-1",
    ordering_test_cid("b"),
    ordering_test_cid("1"),
    0,
    candidate,
    content,
  ).unwrap()
  assert_eq(
    bound_content_generation_reference(from_capture),
    bound_content_generation_reference(original),
  )
  for
    (store, index, node, barrier) in [
      (ordering_test_cid("f"), 0, "content-1", ordering_test_cid("b")),
      (ordering_test_cid("1"), -1, "content-1", ordering_test_cid("b")),
      (ordering_test_cid("1"), 1, "content-1", ordering_test_cid("b")),
      (ordering_test_cid("1"), 0, "content-2", ordering_test_cid("b")),
      (ordering_test_cid("1"), 0, "content-1", ordering_test_cid("c")),
    ] {
    assert_true(
      readmit_captured_generated_content_observation(
        captured,
        chain.run,
        template,
        node,
        barrier,
        store,
        index,
        candidate,
        content,
      )
      is Err(_),
    )
  }
  assert_eq(
    run_evidence_value_json(bound_content_generation_value(restored).unwrap()),
    run_evidence_value_json(bound_content_generation_value(original).unwrap()),
  )
  assert_eq(
    bound_content_generation_reference(restored),
    bound_content_generation_reference(original),
  )
  assert_eq(
    run_evidence_value_json(
      bound_content_generation_input_artifact(restored).unwrap(),
    ),
    run_evidence_value_json(input),
  )
  assert_true(
    issue_content_run_invocation(
      template,
      chain.observation,
      [restored],
      65536,
      4096,
      32,
    )
    is Ok(_),
  )
  for
    (changed_run, node, barrier, identity) in [
      (ordering_test_cid("f"), "content-1", ordering_test_cid("b"), expected),
      (run, "content-2", ordering_test_cid("b"), expected),
      (run, "content-1", ordering_test_cid("c"), expected),
      (run, "content-1", ordering_test_cid("b"), ordering_test_cid("f")),
    ] {
    assert_true(
      readmit_generated_content_observation(
        template, changed_run, node, barrier, identity, input, derivation, evidence,
        candidate, content,
      )
      is Err(_),
    )
  }
  // Even a valid new self CID does not replace the authenticated original
  // generation's committed input/derivation closure.
  let input_body = @json.object_without_field(
    captured_test_value(run_evidence_value_json(input)),
    "input_artifact_cid",
  ).unwrap()
  for
    (before, after) in [
      ("\"row_count\":0", "\"row_count\":1"),
      (
        "\"effective_data_policy_cid\":\"" + ordering_test_cid("e") + "\"",
        "\"effective_data_policy_cid\":\"" + ordering_test_cid("f") + "\"",
      ),
      (
        "\"parameter_values_cid\":\"" + ordering_test_cid("2") + "\"",
        "\"parameter_values_cid\":\"" + ordering_test_cid("f") + "\"",
      ),
      (
        "\"input_fragment_cid\":\"" + ordering_test_cid("9") + "\"",
        "\"input_fragment_cid\":\"" + ordering_test_cid("f") + "\"",
      ),
    ] {
    let substituted = seal_run_evidence_value(
      "content_input_artifact",
      captured_test_wire(input_body).replace(old=before, new=after),
      65536,
      4096,
      32,
    ).unwrap()
    assert_true(
      readmit_generated_content_observation(
        template,
        run,
        "content-1",
        ordering_test_cid("b"),
        expected,
        substituted,
        derivation,
        evidence,
        candidate,
        content,
      )
      is Err(_),
    )
  }
  live.val = false
  assert_true(bound_content_generation_value(restored) is None)
  assert_true(bound_content_generation_value(from_capture) is None)
  assert_true(
    readmit_captured_generated_content_observation(
      captured,
      chain.run,
      template,
      "content-1",
      ordering_test_cid("b"),
      ordering_test_cid("1"),
      0,
      candidate,
      content,
    )
    is Err(_),
  )
  assert_true(
    readmit_generated_content_observation(
      template,
      run,
      "content-1",
      ordering_test_cid("b"),
      expected,
      input,
      derivation,
      evidence,
      candidate,
      content,
    )
    is Err(_),
  )
}
