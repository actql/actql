///|
test "retained explanation reads exact compiler Facts and full original Run without recompilation" {
  for tasks in [false, true] {
    let (prepared, compiled, definition) = local_values_invocation_fixture(
      tasks,
    )
    let (original, view) = capture_client_structural_explanation_plan_original(
      compiled, prepared, 1000000, 100000, 100,
    ).unwrap()
    let facts = seal_client_structural_explanation_facts(
      original, compiled, prepared, 1000000, 100000, 100,
    ).unwrap()
    let identity = prepared_client_identity(prepared)
    let wire = retained_client_run_explanation_view(
      definition,
      Some(client_compiled_run_plan(compiled)),
      identity.program_definition_cid,
      identity.parameter_values_cid,
      Some(view),
      Some(@publication.run_evidence_value_json(facts)),
      "local-values",
      "sha256:" + "a".repeat(64),
      @publication.publication_contract_identity(definition),
      1000000,
      100000,
      100,
    ).unwrap()
    let read = @publication.parse_interactive_run_control_shape(
      "run_explanation_view", wire, 1000000, 100000, 100,
    ).unwrap()
    let explanation = @canonical.object_field(read, "explanation").unwrap()
    assert_eq(
      retained_explanation_text(explanation, "state"),
      Some("projected"),
    )
    let returned = @canonical.object_field(explanation, "facts").unwrap()
    assert_eq(
      @canonical.stringify_value(returned, 1000000, 100000, 100),
      @publication.run_evidence_value_json(facts),
    )
    let reference = @canonical.object_field(read, "run_ref").unwrap()
    assert_eq(
      retained_explanation_text(reference, "runDefinitionCid"),
      Some(@publication.publication_contract_identity(definition)),
    )
    assert_eq(
      retained_explanation_text(reference, "namespaceId"),
      Some("local-values"),
    )
  }
}

///|
test "retained explanation refuses foreign original bindings and never disguises encoding refusal as absence" {
  let (prepared, compiled, definition) = local_values_invocation_fixture(false)
  let (original, view) = capture_client_structural_explanation_plan_original(
    compiled, prepared, 1000000, 100000, 100,
  ).unwrap()
  let facts = seal_client_structural_explanation_facts(
    original, compiled, prepared, 1000000, 100000, 100,
  ).unwrap()
  let identity = prepared_client_identity(prepared)
  let definition_cid = @publication.publication_contract_identity(definition)
  let foreign = "sha256:" + "9".repeat(64)
  for selected in 0..<5 {
    assert_true(
      retained_client_run_explanation_view(
        definition,
        if selected == 4 {
          None
        } else {
          Some(client_compiled_run_plan(compiled))
        },
        if selected == 0 {
          foreign
        } else {
          identity.program_definition_cid
        },
        if selected == 1 {
          foreign
        } else {
          identity.parameter_values_cid
        },
        Some(view),
        Some(@publication.run_evidence_value_json(facts)),
        if selected == 2 {
          "foreign"
        } else {
          "local-values"
        },
        "sha256:" + "a".repeat(64),
        if selected == 3 {
          foreign
        } else {
          definition_cid
        },
        1000000,
        100000,
        100,
      )
      is Err(ForeignOriginal),
    )
  }
  assert_true(
    retained_client_run_explanation_view(
      definition,
      None,
      identity.program_definition_cid,
      identity.parameter_values_cid,
      None,
      None,
      "local-values",
      "sha256:" + "a".repeat(64),
      definition_cid,
      8,
      100000,
      100,
    )
    is Err(Encoding(_)),
  )
  let missing = retained_client_run_explanation_view(
    definition,
    None,
    identity.program_definition_cid,
    identity.parameter_values_cid,
    None,
    None,
    "local-values",
    "sha256:" + "a".repeat(64),
    definition_cid,
    65536,
    8192,
    64,
  ).unwrap()
  let read = @publication.parse_interactive_run_control_shape(
    "run_explanation_view", missing, 65536, 8192, 64,
  ).unwrap()
  let explanation = @canonical.object_field(read, "explanation").unwrap()
  assert_eq(
    retained_explanation_text(explanation, "reason"),
    Some("not_retained"),
  )
  assert_true(@canonical.object_field(explanation, "facts") is None)
}
