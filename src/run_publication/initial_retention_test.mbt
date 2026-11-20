///|
// Independent canonical Node-selection preimage. It is not emitted by product
// code and deliberately differs from the separate 24-hour Wasm profile.
fn initial_retention_expected() -> String {
  (
    #|{"available_until":"2026-11-18T01:00:00.000Z","clock_contract_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","delete_by":"2026-11-18T02:00:00.000Z","effective_data_policy_cid":"sha256:5555555555555555555555555555555555555555555555555555555555555555","extension_ceiling_at":"2026-11-25T00:00:00.000Z","metadata_delete_by":"2026-11-25T00:00:00.000Z","metadata_retention_policy_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222","retention_contract_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","version":"actql-result-retention-policy/0.1"}
  )
}

///|
test "initial retention issues exactly the independently selected fields and canonical identity" {
  let value = issue_initial_result_retention(
    "sha256:" + "1".repeat(64),
    "sha256:" + "5".repeat(64),
    "2026-11-18T01:00:00.000Z",
    "2026-11-18T02:00:00.000Z",
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "2".repeat(64),
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "3".repeat(64),
    10000,
    1000,
    32,
  ).unwrap()
  let expected = initial_retention_expected()
  let cid = "sha256:" + @sha.hex(@utf8.encode(expected))
  assert_eq(publication_contract_identity(value), cid)
  assert_eq(
    publication_contract_json(value),
    expected.replace(
      old=",\"extension_ceiling_at\"",
      new=",\"effective_retention_policy_cid\":\"" +
        cid +
        "\",\"extension_ceiling_at\"",
    ),
  )
}

///|
test "initial retention measuring writer enforces exact wire limit before body construction" {
  let expected = initial_retention_expected()
  let geometry = initial_result_retention_construction_geometry(
    "sha256:" + "1".repeat(64),
    "sha256:" + "5".repeat(64),
    "2026-11-18T01:00:00.000Z",
    "2026-11-18T02:00:00.000Z",
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "2".repeat(64),
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "3".repeat(64),
    expected.length(),
    1000,
    32,
  ).unwrap()
  assert_eq(geometry.bytes, expected.length())
  assert_eq(geometry.fields, 9)
  assert_eq(geometry.nodes, 10)
  assert_eq(geometry.depth, 1)
  assert_true(
    initial_result_retention_construction_geometry(
      "sha256:" + "1".repeat(64),
      "sha256:" + "5".repeat(64),
      "2026-11-18T01:00:00.000Z",
      "2026-11-18T02:00:00.000Z",
      "2026-11-25T00:00:00.000Z",
      "sha256:" + "2".repeat(64),
      "2026-11-25T00:00:00.000Z",
      "sha256:" + "3".repeat(64),
      expected.length() - 1,
      1000,
      32,
    )
    is Err(Encoding),
  )
  assert_true(
    initial_result_retention_construction_geometry(
      "sha256:" + "1".repeat(64),
      "sha256:" + "5".repeat(64),
      "2026-11-18T01:00:00.000Z",
      "2026-11-18T02:00:00.000Z",
      "2026-11-25T00:00:00.000Z",
      "sha256:" + "2".repeat(64),
      "2026-11-25T00:00:00.000Z",
      "sha256:" + "3".repeat(64),
      10000,
      0,
      32,
    )
    is Err(InvalidLimits),
  )
  assert_true(
    issue_initial_result_retention(
      "foreign",
      "sha256:" + "5".repeat(64),
      "2026-11-18T01:00:00.000Z",
      "2026-11-18T02:00:00.000Z",
      "2026-11-25T00:00:00.000Z",
      "sha256:" + "2".repeat(64),
      "2026-11-25T00:00:00.000Z",
      "sha256:" + "3".repeat(64),
      10000,
      1000,
      32,
    )
    is Err(_),
  )
}
