///|
// Literal protocol DATA and independent reference-role assertions only.
// This fixture neither captures Source bytes nor authenticates Store custody.
test "Lookup accounting dependency keeps original barrier batch and relation references" {
  let cid = (label : String) => "sha256:" + label.repeat(64)
  let contract = seal_publication_contract(
    "lookup_accounting",
    "{\"version\":\"actql-lookup-accounting-evidence/0.1\",\"barrier_cid\":\"" +
    cid("a") +
    "\",\"batch_plan_cid\":\"" +
    cid("b") +
    "\",\"input_relation_artifact_cid\":\"" +
    cid("c") +
    "\",\"previous_accounting_cid\":null,\"recorded_at\":\"2026-11-09T00:00:00.000Z\",\"elapsed_ms\":0,\"attempts\":[],\"totals\":{\"network_attempts\":0,\"request_bytes\":0,\"response_wire_bytes\":0,\"response_decoded_bytes\":0},\"issuer_id\":\"literal-fixture\",\"authority_scope_cid\":\"" +
    cid("d") +
    "\"}",
    10000,
    1000,
    20,
  ).unwrap()
  let body = admit_captured_effect_dependency_body(
    "lookup_accounting",
    Some(contract.identity),
    contract.wire,
    10000,
    1000,
    20,
  ).unwrap()
  assert_eq(body.node.references.map(value => (value.kind, value.identity)), [
    ("lookup_barrier", cid("a")),
    ("native_file_lookup_batch_plan", cid("b")),
    ("acquisition_relation", cid("c")),
  ])
  assert_true(
    admit_captured_effect_dependency_body(
      "lookup_accounting",
      Some(cid("0")),
      contract.wire,
      10000,
      1000,
      20,
    )
    is Err(InvalidBody),
  )
  assert_true(
    admit_captured_effect_dependency_body(
      "lookup_accounting",
      None,
      "{}",
      10000,
      1000,
      20,
    )
    is Err(InvalidBody),
  )
  // Body integrity alone does not close its dependency DAG.
  assert_true(
    validate_captured_effect_dependency_bodies([body], [body], 0, {
      max_entries: 10,
      max_total_bytes: 10000,
      max_depth: 10,
      max_references: 100,
    })
    is Err(MissingDependency),
  )
}
