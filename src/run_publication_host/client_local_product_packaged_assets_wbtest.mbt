///|
test "packaged Local originals enter the existing common factory without Native paths" {
  let assets = client_local_product_assets()
  let originals = client_local_product_common_originals(
    "/Users/operator/.actql-local", "2026-10-12T00:00:00.000Z", assets,
  ).unwrap()
  // Normative policy and Store preimages remain independent expectations.
  assert_eq(
    product_cid(product_common_test_bytes(originals.result_policy)),
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
  )
  assert_eq(
    product_common_test_bytes(originals.store),
    "{\"version\":\"actql-local-store-owner/0.1\",\"root\":\"/Users/operator/.actql-local/results\",\"principalId\":\"local-cli\"}",
  )
  let account = @authorization.admit_account_configuration_json(
    product_common_test_bytes(originals.account),
  ).unwrap()
  assert_true(
    @authorization.evaluate_account(account, {
      principal: "local-cli",
      connection: "local",
      resource: "run",
      operation: "publish",
    })
    is @authorization.Allow(_),
  )
  assert_true(
    @authorization.evaluate_account(account, {
      principal: "local-cli",
      connection: "local",
      resource: "source/private",
      operation: "read",
    })
    is @authorization.Deny(_),
  )
}
