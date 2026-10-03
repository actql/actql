///|
fn relation_fixture_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn relation_fixture_retention(policy : String) -> PublicationContract {
  seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\",\"retention_contract_cid\":\"" +
    relation_fixture_cid("1") +
    "\",\"effective_data_policy_cid\":\"" +
    policy +
    "\",\"available_until\":\"2026-09-29T01:00:00.000Z\",\"delete_by\":\"2026-09-29T02:00:00.000Z\",\"extension_ceiling_at\":\"2026-09-29T03:00:00.000Z\",\"metadata_retention_policy_cid\":\"" +
    relation_fixture_cid("2") +
    "\",\"metadata_delete_by\":\"2026-09-29T04:00:00.000Z\",\"clock_contract_cid\":\"" +
    relation_fixture_cid("3") +
    "\"}",
    10000,
    1000,
    32,
  ).unwrap()
}

///|
test "acquisition scope preserves the checked static request identity" {
  let scope = issue_single_source_acquisition_scope(
    relation_fixture_cid("1"),
    relation_fixture_cid("2"),
    10000,
    1000,
    32,
  ).unwrap()
  // Independent canonical JSON + Node crypto, not the MoonBit emitter.
  assert_eq(
    scope.identity,
    "sha256:d0a87caff4a0a962b64be466199c6c3d9dc2de5cc6696bab85e907b9fa1ba920",
  )
  assert_true(
    admit_publication_contract("acquisition_scope", scope.wire, 10000, 1000, 32)
    is Ok(_),
  )
  assert_true(
    admit_publication_contract(
      "acquisition_scope",
      " " + scope.wire,
      10000,
      1000,
      32,
    )
    is Err(InvalidWire),
  )
  assert_true(
    issue_single_source_acquisition_scope(
      relation_fixture_cid("1"),
      "invalid",
      10000,
      1000,
      32,
    )
    is Err(Contract(_)),
  )
  assert_true(
    issue_single_source_acquisition_scope(
      relation_fixture_cid("1"),
      relation_fixture_cid("2"),
      1,
      1000,
      32,
    )
    is Err(Encoding),
  )
  let sources = @json.object_field(scope.value, "sources").unwrap()
  guard sources is @json.Array(entries) else { fail("scope sources") }
  let entry = @json.array_values(entries)[0]
  let entry_wire = @json.stringify_value(entry, 10000, 1000, 32)
  let duplicated = parse_contract_wire(
    "[" + entry_wire + "," + entry_wire + "]",
    10000,
    1000,
    32,
  ).unwrap()
  assert_false(validate_scope_sources(duplicated))
}

///|
test "derived input Relation preserves Artifact witnesses and completeness" {
  let scope = seal_publication_contract(
    "acquisition_scope", "{\"sources\":[],\"version\":\"actql-acquisition-scope/0.1\"}",
    10000, 1000, 32,
  ).unwrap()
  let policy = relation_fixture_cid("7")
  let evidence = issue_local_result_occurrence_evidence(
    relation_fixture_cid("1"),
    relation_fixture_cid("2"),
    relation_fixture_cid("3"),
    relation_fixture_cid("4"),
    [],
    scope.identity,
    policy,
    "fixture-owner",
    relation_fixture_cid("6"),
    10000,
    1000,
    32,
  ).unwrap()
  let retention = relation_fixture_retention(policy)
  let artifact = issue_complete_local_result_artifact(
    relation_fixture_cid("1"),
    relation_fixture_cid("5"),
    evidence,
    retention,
    2,
    10000,
    1000,
    32,
  ).unwrap()
  let relation = issue_derived_input_relation(
    artifact, evidence, scope, retention, 10000, 1000, 32,
  ).unwrap()
  assert_eq(
    contract_string(relation, "logical_value_cid"),
    Some(relation_fixture_cid("2")),
  )
  assert_eq(
    contract_string(relation, "ordering_evidence_cid"),
    Some(evidence.ordering.identity),
  )
  assert_eq(
    contract_string(relation, "observation_scope_cid"),
    Some(scope.identity),
  )
  assert_eq(contract_string(relation, "actual_completeness"), Some("complete"))
  assert_eq(contract_count(relation, "actual_row_count"), Some(2L))
  assert_true(
    admit_publication_contract(
      "acquisition_relation",
      relation.wire,
      10000,
      1000,
      32,
    )
    is Ok(_),
  )
  assert_true(
    admit_publication_contract(
      "acquisition_relation",
      relation.wire + "\n",
      10000,
      1000,
      32,
    )
    is Err(InvalidWire),
  )
  let partial = @json.object_without_field(
    artifact.value,
    "actual_completeness",
  ).unwrap()
  let partial = @json.object_with_string_field(
    partial, "actual_completeness", "partial",
  ).unwrap()
  let partial = @json.object_without_field(partial, artifact.identity_field).unwrap()
  let partial = seal_publication_contract(
    "result_artifact",
    @json.stringify_value(partial, 10000, 1000, 32),
    10000,
    1000,
    32,
  ).unwrap()
  let partial_relation = issue_derived_input_relation(
    partial, evidence, scope, retention, 10000, 1000, 32,
  ).unwrap()
  assert_eq(
    contract_string(partial_relation, "actual_completeness"),
    Some("partial"),
  )
  let other_scope = issue_single_source_acquisition_scope(
    relation_fixture_cid("1"),
    relation_fixture_cid("2"),
    10000,
    1000,
    32,
  ).unwrap()
  assert_true(
    issue_derived_input_relation(
      artifact, evidence, other_scope, retention, 10000, 1000, 32,
    )
    is Err(WrongScope),
  )
  assert_true(
    issue_derived_input_relation(
      artifact,
      evidence,
      scope,
      relation_fixture_retention(relation_fixture_cid("8")),
      10000,
      1000,
      32,
    )
    is Err(WrongRetention),
  )
  assert_true(
    issue_derived_input_relation(
      scope, evidence, scope, retention, 10000, 1000, 32,
    )
    is Err(WrongEvidence),
  )
}

///|
test "input Relation provenance rejects wrong kinds and repeated references" {
  let cid = relation_fixture_cid("1")
  for
    text in [
      "[{\"kind\":\"artifact\",\"cid\":\"" + cid + "\"}]",
      "[{\"kind\":\"source\",\"cid\":\"invalid\"}]",
      "[{\"kind\":\"source\",\"cid\":\"" +
      cid +
      "\"},{\"kind\":\"source\",\"cid\":\"" +
      cid +
      "\"}]",
      "[{\"kind\":\"source\",\"cid\":\"" +
      cid +
      "\"},{\"kind\":\"derivation\",\"cid\":\"" +
      cid +
      "\"}]",
    ] {
    if validate_relation_provenance(
        parse_contract_wire(text, 10000, 1000, 32).unwrap(),
      ) {
      fail("accepted invalid provenance: " + text)
    }
  }
  assert_true(
    validate_relation_provenance(
      parse_contract_wire(
        "[{\"kind\":\"derivation\",\"cid\":\"" +
        cid +
        "\"},{\"kind\":\"source\",\"cid\":\"" +
        cid +
        "\"}]",
        10000,
        1000,
        32,
      ).unwrap(),
    ),
  )
}

///|
test "combined acquisition scope retains both requests without widening permissions" {
  let left = issue_single_source_acquisition_scope(
    relation_fixture_cid("1"),
    relation_fixture_cid("2"),
    10000,
    1000,
    32,
  ).unwrap()
  let right = issue_single_source_acquisition_scope(
    relation_fixture_cid("3"),
    relation_fixture_cid("4"),
    10000,
    1000,
    32,
  ).unwrap()
  let joined = issue_combined_acquisition_scope(
    [right, left, right],
    10000,
    1000,
    32,
  ).unwrap()
  // Independent Node SHA-256 of the authored two-entry canonical scope body.
  assert_eq(
    joined.identity,
    "sha256:8d9592c5289d76efed38c6f47bedbaa1cc1827818d12e2ae3fafda7ead71995b",
  )
  assert_eq(
    issue_combined_acquisition_scope([left, right], 10000, 1000, 32).unwrap().identity,
    joined.identity,
  )
  assert_eq(
    issue_combined_acquisition_scope([left, left], 10000, 1000, 32).unwrap().identity,
    left.identity,
  )
  assert_true(
    issue_combined_acquisition_scope([], 10000, 1000, 32) is Err(WrongScope),
  )
  assert_true(
    issue_combined_acquisition_scope(
      [relation_fixture_retention(relation_fixture_cid("5"))],
      10000,
      1000,
      32,
    )
    is Err(WrongScope),
  )
  // Repeated entries consume the input budget even when they deduplicate.
  assert_true(
    issue_combined_acquisition_scope([left, left], 10000, 3, 32)
    is Err(Encoding),
  )
  assert_true(
    issue_combined_acquisition_scope([left, right], 1, 1000, 32)
    is Err(Encoding),
  )
}

///|
test "separate Source and publication policies preserve retention custody bounds" {
  let source = relation_fixture_retention(relation_fixture_cid("5"))
  let publication = relation_fixture_retention(relation_fixture_cid("6"))
  assert_true(result_retention_bounds_equal(source, publication))
  assert_true(result_retention_bounds_equal(source, source))
  let scope = issue_single_source_acquisition_scope(
    relation_fixture_cid("1"),
    relation_fixture_cid("2"),
    10000,
    1000,
    32,
  ).unwrap()
  assert_false(result_retention_bounds_equal(scope, publication))
  assert_false(result_retention_bounds_equal(source, scope))
  let body =
    #|{"version":"actql-result-retention-policy/0.1","retention_contract_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","effective_data_policy_cid":"sha256:6666666666666666666666666666666666666666666666666666666666666666","available_until":"2026-09-29T01:00:00.000Z","delete_by":"2026-09-29T02:00:00.000Z","extension_ceiling_at":"2026-09-29T03:00:00.000Z","metadata_retention_policy_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222","metadata_delete_by":"2026-09-29T04:00:00.000Z","clock_contract_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333"}
  for
    (old, replacement) in [
      (relation_fixture_cid("1"), relation_fixture_cid("7")),
      (relation_fixture_cid("2"), relation_fixture_cid("7")),
      (relation_fixture_cid("3"), relation_fixture_cid("7")),
      ("2026-09-29T01:00:00.000Z", "2026-09-29T01:30:00.000Z"),
      ("2026-09-29T02:00:00.000Z", "2026-09-29T02:30:00.000Z"),
      ("2026-09-29T03:00:00.000Z", "2026-09-29T03:30:00.000Z"),
      ("2026-09-29T04:00:00.000Z", "2026-09-29T04:30:00.000Z"),
    ] {
    let changed = seal_publication_contract(
      "result_retention_policy",
      body.replace(old~, new=replacement),
      10000,
      1000,
      32,
    ).unwrap()
    assert_false(result_retention_bounds_equal(source, changed))
  }
}
