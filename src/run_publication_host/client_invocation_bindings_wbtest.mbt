///|
test "empty Invocation Bindings require zero declarations" {
  assert_true(
    issue_empty_invocation_bindings(["target_file"], 10000, 1000, 32)
    is Err(BindingsDeclared),
  )
  let issued = issue_empty_invocation_bindings([], 10000, 1000, 32).unwrap()
  assert_eq(
    @publication.run_evidence_value_identity(issued),
    "sha256:5400e202cc7c63c3b757399f3a694b413f7b717ce58aa887cc156c6a39aab67f",
  )
  assert_eq(
    @publication.run_evidence_value_json(issued),
    "{\"bindings\":{},\"invocation_bindings_cid\":\"sha256:5400e202cc7c63c3b757399f3a694b413f7b717ce58aa887cc156c6a39aab67f\",\"version\":\"actql-invocation-bindings/0.1\"}",
  )
}
