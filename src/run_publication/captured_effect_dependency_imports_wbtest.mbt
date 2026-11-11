///|
fn import_binding_test_body(
  kind : String,
  preimage : String,
) -> CapturedEffectDependencyBody raise {
  admit_local_effect_dependency_body(
    kind,
    dependency_test_local_wire(preimage),
    10000,
    1000,
    32,
  ).unwrap()
}

///|
test "saved local Model correspondence rejects foreign Unit and duplicate INFER realization" {
  // Isolate correspondence over admitted bodies. Body/graph completeness
  // and actual Model issuance have their own distinct tests.
  let leaf = relation_fixture_cid("1")
  fn unit(name : String) -> CapturedEffectDependencyBody raise {
    import_binding_test_body(
      "local_dependencies",
      "{\"version\":\"actql-local-unit-dependencies/0.1\",\"local_body_cid\":\"" +
      leaf +
      "\",\"used_parameter_declarations_cid\":\"" +
      leaf +
      "\",\"local_contract_closure_cid\":\"" +
      leaf +
      "\",\"import_interface_cids\":[],\"incoming_gate_contract_cids\":[],\"unit_namespace\":{\"program_id\":\"p\",\"node_id\":\"" +
      name +
      "\"}}",
    )
  }
  fn observation(
    unit : String,
    outcomes : String,
  ) -> CapturedEffectDependencyBody raise {
    import_binding_test_body(
      "local_model_observation",
      "{\"version\":\"actql-local-model-observation/0.1\",\"unit_definition_cid\":\"" +
      unit +
      "\",\"source_ordinal\":2,\"input_logical_relation_cid\":\"" +
      leaf +
      "\",\"input_relation_schema_cid\":\"" +
      leaf +
      "\",\"outcome_logical_relation_cid\":\"" +
      outcomes +
      "\",\"outcome_relation_schema_cid\":\"" +
      leaf +
      "\"}",
    )
  }
  fn invocation(
    unit : String,
    observations : Array[String],
  ) -> CapturedEffectDependencyBody raise {
    let list = "[" + observations.map(cid => "\"" + cid + "\"").join(",") + "]"
    import_binding_test_body(
      "local_computation",
      "{\"version\":\"actql-local-computation-semantics/0.1\",\"unit_definition_cid\":\"" +
      unit +
      "\",\"used_values_cid\":\"" +
      leaf +
      "\",\"local_contracts_cid\":\"" +
      leaf +
      "\",\"policy_cid\":\"" +
      leaf +
      "\",\"observation_cids\":" +
      list +
      "}",
    )
  }
  let original = unit("original")
  let foreign = unit("foreign")
  let observed = observation(original.node.identity, relation_fixture_cid("2"))
  let other = observation(original.node.identity, relation_fixture_cid("3"))
  let foreign_observed = observation(
    foreign.node.identity,
    relation_fixture_cid("2"),
  )
  assert_eq(
    validate_effect_dependency_import_bindings([
      original,
      observed,
      invocation(original.node.identity, [observed.node.identity]),
    ]),
    Ok(()),
  )
  assert_eq(
    validate_effect_dependency_import_bindings([
      original,
      foreign,
      foreign_observed,
      invocation(original.node.identity, [foreign_observed.node.identity]),
    ]),
    Err(InvalidBody),
  )
  assert_eq(
    validate_effect_dependency_import_bindings([
      original,
      observed,
      other,
      invocation(original.node.identity, [
        observed.node.identity,
        other.node.identity,
      ]),
    ]),
    Err(InvalidBody),
  )
}

///|
test "recovery import correspondence rejects independently valid substitutions" {
  // These are admitted bodies, not caller-authored graph edges. This test
  // isolates cross-body correspondence; closure/bounds are tested separately.
  let leaf = relation_fixture_cid("1")
  fn unit(
    name : String,
    imports : String,
  ) -> CapturedEffectDependencyBody raise {
    import_binding_test_body(
      "local_dependencies",
      "{\"version\":\"actql-local-unit-dependencies/0.1\",\"local_body_cid\":\"" +
      leaf +
      "\",\"used_parameter_declarations_cid\":\"" +
      leaf +
      "\",\"local_contract_closure_cid\":\"" +
      leaf +
      "\",\"import_interface_cids\":" +
      imports +
      ",\"incoming_gate_contract_cids\":[],\"unit_namespace\":{\"program_id\":\"p\",\"node_id\":\"" +
      name +
      "\"}}",
    )
  }
  fn invocation(
    unit : String,
    observations : String,
  ) -> CapturedEffectDependencyBody raise {
    import_binding_test_body(
      "local_computation",
      "{\"version\":\"actql-local-computation-semantics/0.1\",\"unit_definition_cid\":\"" +
      unit +
      "\",\"used_values_cid\":\"" +
      leaf +
      "\",\"local_contracts_cid\":\"" +
      leaf +
      "\",\"policy_cid\":\"" +
      leaf +
      "\",\"observation_cids\":" +
      observations +
      "}",
    )
  }
  let producer = unit("source", "[]")
  let run = invocation(producer.node.identity, "[]")
  fn result(
    name : String,
    table : Bool,
  ) -> (CapturedEffectDependencyBody, CapturedEffectDependencyBody) raise {
    let definition = import_binding_test_body(
      if table {
        "local_table_input_definition"
      } else {
        "local_result_definition"
      },
      "{\"version\":\"" +
      (if table {
        "actql-local-table-input-definition/0.1"
      } else {
        "actql-local-result-definition/0.1"
      }) +
      "\",\"unit_definition_cid\":\"" +
      producer.node.identity +
      "\"," +
      (if table { "\"table_input_name\"" } else { "\"result_name\"" }) +
      ":\"" +
      name +
      "\"}",
    )
    let evidence = issue_local_result_occurrence_evidence(
      definition.node.identity,
      relation_fixture_cid(if name == "rows" { "2" } else { "3" }),
      leaf,
      leaf,
      [],
      leaf,
      leaf,
      "owner",
      leaf,
      10000,
      1000,
      32,
    ).unwrap()
    let artifact = issue_complete_local_result_artifact(
      definition.node.identity,
      run.node.identity,
      evidence,
      relation_fixture_retention(leaf),
      1,
      10000,
      1000,
      32,
    ).unwrap()
    (
      definition,
      admit_publication_effect_dependency_body(
        if table {
          "table_input_artifact"
        } else {
          "result_artifact"
        },
        artifact.wire,
        10000,
        1000,
        32,
      ).unwrap(),
    )
  }
  let (definition, artifact) = result("rows", false)
  let (other_definition, other_artifact) = result("other", false)
  let (private_definition, private_artifact) = result("rows", true)
  let mixed_manifest = (private_cid : String, public_cid : String) => {
    import_binding_test_body(
      "local_manifest",
      "{\"version\":\"actql-local-result-manifest/0.1\",\"unit_definition_cid\":\"" +
      producer.node.identity +
      "\",\"local_invocation_cid\":\"" +
      run.node.identity +
      "\",\"results\":{\"rows\":\"" +
      public_cid +
      "\"},\"table_inputs\":{\"rows\":\"" +
      private_cid +
      "\"}}",
    )
  }
  let shared = [
    producer, run, definition, artifact, private_definition, private_artifact,
  ]
  let mixed = shared.copy()
  mixed.push(
    mixed_manifest(private_artifact.node.identity, artifact.node.identity),
  )
  assert_eq(validate_effect_dependency_import_bindings(mixed), Ok(()))
  for
    (private_cid, public_cid) in [
      (artifact.node.identity, artifact.node.identity),
      (private_artifact.node.identity, private_artifact.node.identity),
      (other_artifact.node.identity, artifact.node.identity),
    ] {
    let invalid = shared.copy()
    invalid.push(mixed_manifest(private_cid, public_cid))
    assert_eq(
      validate_effect_dependency_import_bindings(invalid),
      Err(InvalidBody),
    )
  }
  let manifest = import_binding_test_body(
    "local_manifest",
    "{\"version\":\"actql-local-result-manifest/0.1\",\"unit_definition_cid\":\"" +
    producer.node.identity +
    "\",\"local_invocation_cid\":\"" +
    run.node.identity +
    "\",\"results\":{\"rows\":\"" +
    artifact.node.identity +
    "\",\"other\":\"" +
    other_artifact.node.identity +
    "\"}}",
  )
  let interface = import_binding_test_body(
    "result_import_interface",
    "{\"version\":\"actql-result-import-interface/0.1\",\"input_name\":\"input\",\"producer_namespace\":{\"program_id\":\"p\",\"node_id\":\"source\"},\"producer_unit_definition_cid\":\"" +
    producer.node.identity +
    "\",\"producer_result\":\"rows\",\"value_contract_cid\":\"" +
    leaf +
    "\",\"availability\":\"stage_success\"}",
  )
  let consumer = unit("consumer", "[\"" + interface.node.identity + "\"]")
  fn observation(
    name : String,
    selected : String,
  ) -> CapturedEffectDependencyBody raise {
    import_binding_test_body(
      "result_import_observation",
      "{\"version\":\"actql-result-import-observation/0.1\",\"consumer_unit_definition_cid\":\"" +
      consumer.node.identity +
      "\",\"input_name\":\"" +
      name +
      "\",\"import_interface_cid\":\"" +
      interface.node.identity +
      "\",\"producer_local_manifest_cid\":\"" +
      manifest.node.identity +
      "\",\"result_artifact_cid\":\"" +
      selected +
      "\"}",
    )
  }
  let observed = observation("input", artifact.node.identity)
  let consumed = invocation(
    consumer.node.identity,
    "[\"" + observed.node.identity + "\"]",
  )
  let base = [
    producer, run, definition, artifact, other_definition, other_artifact, manifest,
    interface, consumer,
  ]
  let valid = base.copy()
  valid.push(observed)
  valid.push(consumed)
  assert_eq(validate_effect_dependency_import_bindings(valid), Ok(()))
  // Same schema, different exact Result: both Artifacts are valid and in
  // the same Manifest, but only rows belongs to the selected import.
  for
    invalid in [
      observation("input", other_artifact.node.identity),
      observation("other", artifact.node.identity),
    ] {
    let bodies = base.copy()
    bodies.push(invalid)
    assert_eq(
      validate_effect_dependency_import_bindings(bodies),
      Err(InvalidBody),
    )
  }
  let foreign = base.copy()
  foreign.push(observed)
  foreign.push(
    invocation(producer.node.identity, "[\"" + observed.node.identity + "\"]"),
  )
  assert_eq(
    validate_effect_dependency_import_bindings(foreign),
    Err(InvalidBody),
  )
  let incomplete = base.copy()
  incomplete.push(invocation(consumer.node.identity, "[]"))
  assert_eq(
    validate_effect_dependency_import_bindings(incomplete),
    Err(InvalidBody),
  )
  let missing = valid.filter(body => body.node.kind != "local_manifest")
  assert_eq(
    validate_effect_dependency_import_bindings(missing),
    Err(InvalidBody),
  )
  let mismatched = import_binding_test_body(
    "local_manifest",
    "{\"version\":\"actql-local-result-manifest/0.1\",\"unit_definition_cid\":\"" +
    producer.node.identity +
    "\",\"local_invocation_cid\":\"" +
    run.node.identity +
    "\",\"results\":{\"rows\":\"" +
    other_artifact.node.identity +
    "\"}}",
  )
  let bodies = base.copy()
  bodies.push(mismatched)
  assert_eq(
    validate_effect_dependency_import_bindings(bodies),
    Err(InvalidBody),
  )
}
