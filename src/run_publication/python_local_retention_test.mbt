///|
// Independent fixed fixture inputs, never derived from a product response.
test "Python Local retention admits the exact frozen policy identity" {
  let wire = "{\"available_until\":\"2099-01-01T00:00:00.000Z\",\"clock_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"delete_by\":\"2099-01-02T00:00:00.000Z\",\"effective_data_policy_cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"effective_retention_policy_cid\":\"sha256:92241f901b8ffbd5d2b692e2619fb66c9cbe9c18fde9692ebe25d2746a17a82a\",\"extension_ceiling_at\":\"2099-01-03T00:00:00.000Z\",\"metadata_delete_by\":\"2099-01-04T00:00:00.000Z\",\"metadata_retention_policy_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"retention_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"version\":\"actql-result-retention-policy/0.1\"}"
  let contract = admit_publication_contract(
    "result_retention_policy", wire, 65536, 4096, 64,
  ).unwrap()
  assert_eq(
    publication_contract_identity(contract),
    "sha256:92241f901b8ffbd5d2b692e2619fb66c9cbe9c18fde9692ebe25d2746a17a82a",
  )
}

///|
test "Python Local retention rejects the mistaken fixture identity field" {
  let wire = "{\"available_until\":\"2099-01-01T00:00:00.000Z\",\"clock_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"delete_by\":\"2099-01-02T00:00:00.000Z\",\"effective_data_policy_cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"extension_ceiling_at\":\"2099-01-03T00:00:00.000Z\",\"metadata_delete_by\":\"2099-01-04T00:00:00.000Z\",\"metadata_retention_policy_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"retention_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"retention_policy_cid\":\"sha256:92241f901b8ffbd5d2b692e2619fb66c9cbe9c18fde9692ebe25d2746a17a82a\",\"version\":\"actql-result-retention-policy/0.1\"}"
  assert_true(
    admit_publication_contract("result_retention_policy", wire, 65536, 4096, 64)
    is Err(UnknownField("retention_policy_cid")),
  )
}
