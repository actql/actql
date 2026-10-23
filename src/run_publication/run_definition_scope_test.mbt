///|
fn scope_projection_body(scope : String) -> String {
  "{\"version\":\"actql-run-definition/0.1\"," +
  "\"scope_id\":" +
  scope +
  ",\"run_id\":\"run\",\"compiled_plan_cid\":\"" +
  contract_cid("1") +
  "\",\"invocation_template_cid\":\"" +
  contract_cid("2") +
  "\",\"authorization_context_cid\":\"" +
  contract_cid("3") +
  "\",\"input_artifact_set_cid\":\"" +
  contract_cid("4") +
  "\",\"created_at\":\"2026-09-18T00:00:00.000Z\"," +
  "\"valid_until\":\"2026-09-18T01:00:00.000Z\"}"
}

///|
test "Run scope projection preserves the fixed admitted definition and wire" {
  let definition = seal_publication_contract(
    "run_definition",
    scope_projection_body("\"scope\""),
    8192,
    64,
    4,
  ).unwrap()
  let identity = publication_contract_identity(definition)
  let wire = publication_contract_json(definition)
  assert_eq(
    identity, "sha256:4a288ff6406340fbcf51438ee9f493b1cb32c8d804be16cab0774cdbdfe3484f",
  )
  assert_eq(
    publication_contract_run_definition_scope(definition),
    Some("scope"),
  )
  assert_eq(
    publication_contract_run_definition_scope(definition),
    Some("scope"),
  )
  assert_eq(publication_contract_identity(definition), identity)
  assert_eq(publication_contract_json(definition), wire)
  let restored = admit_publication_contract("run_definition", wire, 8192, 64, 4).unwrap()
  assert_eq(publication_contract_run_definition_scope(restored), Some("scope"))
}

///|
test "Run scope projection refuses another contract kind and keeps external field admission" {
  let invocation = seal_publication_contract(
    "run_invocation",
    "{\"version\":\"actql-run-invocation/0.1\",\"invocation_template_cid\":\"" +
    contract_cid("1") +
    "\",\"observation_set_cid\":\"" +
    contract_cid("2") +
    "\"}",
    4096,
    32,
    4,
  ).unwrap()
  assert_eq(publication_contract_run_definition_scope(invocation), None)
  for invalid in ["null", "7", "\"\""] {
    assert_true(
      seal_publication_contract(
        "run_definition",
        scope_projection_body(invalid),
        8192,
        64,
        4,
      )
      is Err(InvalidField("scope_id")),
    )
  }
  let missing = scope_projection_body("\"scope\"").replace(
    old="\"scope_id\":\"scope\",",
    new="",
  )
  assert_true(
    seal_publication_contract("run_definition", missing, 8192, 64, 4)
    is Err(MissingField("scope_id")),
  )
}

///|
test "Run scope projection does not interpret native scope syntax" {
  let definition = seal_publication_contract(
    "run_definition",
    scope_projection_body("\"tenant/../scope\""),
    8192,
    64,
    4,
  ).unwrap()
  assert_eq(
    publication_contract_run_definition_scope(definition),
    Some("tenant/../scope"),
  )
}
