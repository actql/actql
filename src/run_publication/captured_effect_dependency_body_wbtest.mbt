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
