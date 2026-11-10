///|
test "dependency reader derives scope edges and rejects missing bodies" {
  let scope = issue_single_source_acquisition_scope(
    relation_fixture_cid("1"),
    relation_fixture_cid("2"),
    10000,
    1000,
    32,
  ).unwrap()
  let admitted = admit_publication_effect_dependency_body(
    "acquisition_scope",
    scope.wire,
    10000,
    1000,
    32,
  ).unwrap()
  assert_eq(admitted.node.identity, scope.identity)
  assert_eq(
    admitted.node.references.map(value => (value.kind, value.identity)),
    [
      ("source_contract", relation_fixture_cid("1")),
      ("request_values", relation_fixture_cid("2")),
    ],
  )
  let limits : CapturedEffectDependencyLimits = {
    max_entries: 10,
    max_total_bytes: 10000,
    max_depth: 8,
    max_references: 20,
  }
  assert_eq(
    validate_captured_effect_dependency_bodies(
      [admitted],
      [admitted],
      0,
      limits,
    ),
    Err(MissingDependency),
  )
  assert_true(
    admit_publication_effect_dependency_body(
      "acquisition_scope",
      " " + scope.wire,
      10000,
      1000,
      32,
    )
    is Err(_),
  )
  assert_true(
    admit_publication_effect_dependency_body(
      "caller_edges",
      scope.wire,
      10000,
      1000,
      32,
    )
    is Err(_),
  )
  let empty = seal_publication_contract(
    "acquisition_scope", "{\"sources\":[],\"version\":\"actql-acquisition-scope/0.1\"}",
    10000, 1000, 32,
  ).unwrap()
  let empty = admit_publication_effect_dependency_body(
    "acquisition_scope",
    empty.wire,
    10000,
    1000,
    32,
  ).unwrap()
  assert_eq(
    validate_captured_effect_dependency_bodies([empty], [empty], 0, limits),
    Ok(()),
  )
  assert_eq(
    validate_captured_effect_dependency_bodies(
      [empty, empty],
      [empty],
      0,
      limits,
    ),
    Err(DuplicateIdentity),
  )
}

///|
fn dependency_test_local_wire(preimage : String) -> String raise {
  let value = parse_contract_wire(preimage, 10000, 1000, 32).unwrap()
  let cid = @json.cid_value(value, 10000, 1000, 32)
  let value = @json.object_with_string_field(value, "self_cid", cid).unwrap()
  canonical_value_wire(value, 10000, 1000, 32).unwrap()
}

///|
test "local Model dependency admission derives all typed edges and refuses audit or missing bodies" {
  let preimage = "{\"input_logical_relation_cid\":\"" +
    relation_fixture_cid("b") +
    "\",\"input_relation_schema_cid\":\"" +
    relation_fixture_cid("c") +
    "\",\"outcome_logical_relation_cid\":\"" +
    relation_fixture_cid("d") +
    "\",\"outcome_relation_schema_cid\":\"" +
    relation_fixture_cid("e") +
    "\",\"source_ordinal\":2,\"unit_definition_cid\":\"" +
    relation_fixture_cid("a") +
    "\",\"version\":\"actql-local-model-observation/0.1\"}"
  let body = admit_local_effect_dependency_body(
    "local_model_observation",
    dependency_test_local_wire(preimage),
    10000,
    1000,
    32,
  ).unwrap()
  assert_eq(
    body.node.identity,
    "sha256:578782ff069b8920c4695df67bbf3b7fe2d3f2d2a39faa02bddc781964e985c5",
  )
  assert_eq(
    admit_captured_effect_dependency_body(
      "local_model_observation",
      Some(body.node.identity),
      body.wire,
      10000,
      1000,
      32,
    ).unwrap().node.identity,
    body.node.identity,
  )
  assert_eq(body.node.references.map(value => (value.kind, value.identity)), [
    ("local_dependencies", relation_fixture_cid("a")),
    ("relation_value", relation_fixture_cid("b")),
    ("relation_schema", relation_fixture_cid("c")),
    ("relation_value", relation_fixture_cid("d")),
    ("relation_schema", relation_fixture_cid("e")),
  ])
  assert_eq(
    validate_captured_effect_dependency_bodies([body], [body], 0, {
      max_entries: 10,
      max_total_bytes: 10000,
      max_depth: 8,
      max_references: 20,
    }),
    Err(MissingDependency),
  )
  for
    invalid in [
      preimage.replace(old="\"source_ordinal\":2", new="\"source_ordinal\":-1"),
      preimage.replace(old="\"source_ordinal\":2", new="\"source_ordinal\":1.5"),
      preimage.replace(
        old="\"source_ordinal\":2",
        new="\"source_ordinal\":2147483647",
      ),
      preimage.replace(
        old="\"source_ordinal\":2",
        new="\"source_ordinal\":\"2\"",
      ),
      preimage.replace(
        old="\"source_ordinal\":2",
        new="\"source_ordinal\":2,\"observation_set_cid\":\"" +
          relation_fixture_cid("f") +
          "\"",
      ),
    ] {
    assert_true(
      admit_local_effect_dependency_body(
        "local_model_observation",
        dependency_test_local_wire(invalid),
        10000,
        1000,
        32,
      )
      is Err(InvalidBody),
    )
  }
}

///|
test "static dependency reader rejects rehashed invalid namespace and availability" {
  let prefix = "{\"version\":\"actql-result-import-interface/0.1\",\"input_name\":\"rows\",\"producer_namespace\":{\"program_id\":\"p\",\"node_id\":\"source\"},\"producer_unit_definition_cid\":\"" +
    relation_fixture_cid("a") +
    "\",\"producer_result\":\"r\",\"value_contract_cid\":\"" +
    relation_fixture_cid("b") +
    "\",\"availability\":\"stage_success\"}"
  let valid = dependency_test_local_wire(prefix)
  let body = admit_local_effect_dependency_body(
    "result_import_interface", valid, 10000, 1000, 32,
  ).unwrap()
  assert_eq(body.node.references.map(value => (value.kind, value.identity)), [
    ("local_dependencies", relation_fixture_cid("a")),
    ("result_import_type", relation_fixture_cid("b")),
  ])
  for
    invalid in [
      prefix.replace(old="stage_success", new="always"),
      prefix.replace(old="\"node_id\":\"source\"", new="\"node_id\":7"),
      prefix.replace(old="\"program_id\":\"p\"", new="\"program_id\":\"\""),
      prefix.replace(
        old="\"node_id\":\"source\"",
        new="\"node_id\":\"source\",\"extra\":true",
      ),
    ] {
    assert_true(
      admit_local_effect_dependency_body(
        "result_import_interface",
        dependency_test_local_wire(invalid),
        10000,
        1000,
        32,
      )
      is Err(InvalidBody),
    )
  }
}

///|
test "Result import dependency reader preserves every bound input coordinate" {
  // Independent canonical preimage vector, shared with the contract corpus.
  let wire = "{\"consumer_unit_definition_cid\":\"" +
    relation_fixture_cid("a") +
    "\",\"import_interface_cid\":\"" +
    relation_fixture_cid("b") +
    "\",\"input_name\":\"rows\",\"producer_local_manifest_cid\":\"" +
    relation_fixture_cid("c") +
    "\",\"result_artifact_cid\":\"" +
    relation_fixture_cid("d") +
    "\",\"self_cid\":\"sha256:81e86ff46a75d01544f1a6bba0ec84731355fe7a0f777ddf6fd90ba110650fba\",\"version\":\"actql-result-import-observation/0.1\"}"
  let body = admit_local_effect_dependency_body(
    "result_import_observation", wire, 10000, 1000, 32,
  ).unwrap()
  assert_eq(captured_effect_dependency_body_json(body), wire)
  assert_eq(body.node.references.map(value => (value.kind, value.identity)), [
    ("local_dependencies", relation_fixture_cid("a")),
    ("result_import_interface", relation_fixture_cid("b")),
    ("local_manifest", relation_fixture_cid("c")),
    ("result_artifact", relation_fixture_cid("d")),
  ])
  for
    altered in [
      wire.replace(old="rows", new="other"),
      wire.replace(old=relation_fixture_cid("d"), new=relation_fixture_cid("e")),
      wire.replace(old="\"input_name\":\"rows\",", new=""),
      wire.replace(
        old="\"input_name\":\"rows\",",
        new="\"input_name\":\"rows\",\"edges\":[],",
      ),
    ] {
    assert_true(
      admit_local_effect_dependency_body(
        "result_import_observation", altered, 10000, 1000, 32,
      )
      is Err(InvalidBody),
    )
  }
  assert_true(
    admit_local_effect_dependency_body("local_manifest", wire, 10000, 1000, 32)
    is Err(InvalidBody),
  )
}

///|
test "private Table dependency roles preserve bodies and reject Result substitution" {
  // Independent Node SHA-256 over the three-field producer preimage.
  let definition_cid = "sha256:a1083fe142ab863bddb8c24d5187778d015278481a5e9f33c02a9590075e1f06"
  let definition_wire = "{\"self_cid\":\"" +
    definition_cid +
    "\",\"table_input_name\":\"rows\",\"unit_definition_cid\":\"" +
    relation_fixture_cid("1") +
    "\",\"version\":\"actql-local-table-input-definition/0.1\"}"
  let definition = admit_captured_effect_dependency_body(
    "local_table_input_definition",
    Some(definition_cid),
    definition_wire,
    10000,
    1000,
    32,
  ).unwrap()
  assert_eq(
    definition.node.references.map(dependency => {
      (dependency.kind, dependency.identity)
    }),
    [("local_dependencies", relation_fixture_cid("1"))],
  )
  assert_true(
    admit_captured_effect_dependency_body(
      "local_result_definition",
      None,
      definition_wire,
      10000,
      1000,
      32,
    )
    is Err(InvalidBody),
  )
  let evidence = issue_local_result_occurrence_evidence(
    definition_cid,
    relation_fixture_cid("2"),
    relation_fixture_cid("3"),
    relation_fixture_cid("1"),
    [],
    relation_fixture_cid("4"),
    relation_fixture_cid("5"),
    "owner",
    relation_fixture_cid("6"),
    10000,
    1000,
    32,
  ).unwrap()
  let derivation = result_ordering_derivation_contract(evidence)
  let ordering = result_ordering_evidence_contract(evidence)
  let artifact = issue_complete_local_result_artifact(
    definition_cid,
    relation_fixture_cid("7"),
    evidence,
    relation_fixture_retention(relation_fixture_cid("5")),
    1,
    10000,
    1000,
    32,
  ).unwrap()
  let private_artifact = admit_publication_effect_dependency_body(
    "table_input_artifact",
    artifact.wire,
    10000,
    1000,
    32,
  ).unwrap()
  let private_derivation = admit_publication_effect_dependency_body(
    "table_input_derivation",
    derivation.wire,
    10000,
    1000,
    32,
  ).unwrap()
  let private_ordering = admit_publication_effect_dependency_body(
    "table_input_ordering",
    ordering.wire,
    10000,
    1000,
    32,
  ).unwrap()
  assert_eq(private_artifact.wire, artifact.wire)
  assert_eq(private_derivation.wire, derivation.wire)
  assert_eq(private_ordering.wire, ordering.wire)
  assert_eq(private_artifact.node.identity, artifact.identity)
  assert_eq(
    private_artifact.node.references.map(dependency => {
      (dependency.kind, dependency.identity)
    }),
    [
      ("local_table_input_definition", definition_cid),
      ("local_computation", relation_fixture_cid("7")),
      ("relation_value", relation_fixture_cid("2")),
      ("relation_schema", relation_fixture_cid("3")),
      ("table_input_ordering", ordering.identity),
      ("data_policy", relation_fixture_cid("5")),
      (
        "result_retention_policy",
        contract_string(artifact, "effective_retention_policy_cid").unwrap(),
      ),
      ("table_input_derivation", derivation.identity),
    ],
  )
  assert_eq(
    private_derivation.node.references[0].kind,
    "local_table_input_definition",
  )
  assert_eq(
    private_ordering.node.references.map(dependency => {
      (dependency.kind, dependency.identity)
    }),
    [
      ("local_table_input_definition", definition_cid),
      ("table_input_derivation", derivation.identity),
    ],
  )
  let ordinary_artifact = admit_publication_effect_dependency_body(
    "result_artifact",
    artifact.wire,
    10000,
    1000,
    32,
  ).unwrap()
  let limits : CapturedEffectDependencyLimits = {
    max_entries: 10,
    max_total_bytes: 10000,
    max_depth: 8,
    max_references: 30,
  }
  // Same body/CID, wrong role: absence of ordinary producer must not fall back
  // to the private producer. A proper private role instead needs its real DAG.
  assert_eq(
    validate_captured_effect_dependency_bodies(
      [ordinary_artifact, definition],
      [ordinary_artifact],
      0,
      limits,
    ),
    Err(WrongDependencyKind),
  )
  assert_eq(
    validate_captured_effect_dependency_bodies(
      [private_artifact, definition],
      [private_artifact],
      0,
      limits,
    ),
    Err(MissingDependency),
  )
  let private_manifest = dependency_test_local_wire(
    "{\"version\":\"actql-local-result-manifest/0.1\",\"unit_definition_cid\":\"" +
    relation_fixture_cid("1") +
    "\",\"local_invocation_cid\":\"" +
    relation_fixture_cid("7") +
    "\",\"results\":{},\"table_inputs\":{\"rows\":\"" +
    artifact.identity +
    "\"}}",
  )
  let manifest = admit_local_effect_dependency_body(
    "local_manifest", private_manifest, 10000, 1000, 32,
  ).unwrap()
  assert_eq(manifest.node.references[2].kind, "table_input_artifact")
  let body = canonical_value_wire(
    @json.object_without_field(manifest.value, "self_cid").unwrap(),
    10000,
    1000,
    32,
  ).unwrap()
  assert_true(
    admit_local_effect_dependency_body(
      "local_manifest",
      dependency_test_local_wire(
        body.replace(
          old="\"table_inputs\":{\"rows\":\"" + artifact.identity + "\"}",
          new="\"table_inputs\":{}",
        ),
      ),
      10000,
      1000,
      32,
    )
    is Err(InvalidBody),
  )
}
