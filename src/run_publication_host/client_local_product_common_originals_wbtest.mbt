///|
fn product_common_test_bytes(value : Bytes) -> String {
  @utf8.decode(value) catch {
    _ => abort("invalid UTF-8 original")
  }
}

///|
fn product_common_test_originals(
  root? : String = "/Users/operator/.actql-local",
  at? : String = "2026-10-12T00:00:00.000Z",
) -> ClientLocalProductCommonOriginals {
  client_local_product_common_originals(root, at, product_test_assets()).unwrap()
}

///|
test "common originals require no Native library or CLI configuration" {
  let common = product_common_test_originals()
  // Literal preimages from the finite Account and existing Store domains.
  assert_eq(
    product_common_test_bytes(common.account),
    "{\"account_id\":\"local-cli\",\"entries\":[{\"connection\":{\"any_of\":[\"local\"]},\"entry_id\":\"local-result-read\",\"exclusions\":[],\"operation\":{\"any_of\":[\"read\"]},\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"local-cli\"]},\"resource\":{\"any_of\":[\"result/answer\"]}},{\"connection\":{\"any_of\":[\"local\"]},\"entry_id\":\"local-run-control\",\"exclusions\":[],\"operation\":{\"any_of\":[\"cancel\",\"publish\",\"read\",\"submit\"]},\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"local-cli\"]},\"resource\":{\"any_of\":[\"run\"]}}],\"version\":\"actql-execution-account-config/0.1\"}",
  )
  assert_eq(
    product_common_test_bytes(common.store),
    "{\"version\":\"actql-local-store-owner/0.1\",\"root\":\"/Users/operator/.actql-local/results\",\"principalId\":\"local-cli\"}",
  )
  assert_eq(
    product_cid(product_common_test_bytes(common.result_policy)),
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
  )
  for
    bytes in [
      common.account,
      common.retention_dependencies,
      common.retention_policy,
      common.store,
      common.result_policy,
    ] {
    assert_true(bytes.length() > 0 && bytes.length() <= 65536)
    let body = product_common_test_bytes(bytes)
    for
      forbidden in [
        "\"native\"", "sqlite_library", "signature_library", "cli-read",
      ] {
      assert_false(body.contains(forbidden))
    }
  }
}

///|
test "Native and common assemblers retain identical original bytes" {
  let common = product_common_test_originals()
  let native = product_test_originals()
  for
    (bytes, name) in [
      (common.account, "account.json"),
      (common.retention_dependencies, "retention.json"),
      (common.store, "store.json"),
    ] {
    assert_eq(bytes, @utf8.encode(product_test_original(native, name)))
  }
  let run = product_asset_value(product_test_original(native, "run.json")).unwrap()
  for
    (bytes, path) in [
      (common.retention_policy, ["native", "run", "retention_policy_wire"]),
      (
        common.result_policy,
        ["native", "run", "source_free", "result_policy_wire"],
      ),
    ] {
    assert_eq(
      bytes,
      @utf8.encode(product_test_text(product_test_field(run, path))),
    )
  }
  // Finite authority remains bound to the original principal and target.
  let account = @authorization.admit_account_configuration_json(
    product_common_test_bytes(common.account),
  ).unwrap()
  for
    (resource, operation) in [
      ("run", "resolve"),
      ("result/other", "read"),
      ("source/table", "read"),
    ] {
    assert_true(
      @authorization.evaluate_account(account, {
        principal: "local-cli",
        connection: "local",
        resource,
        operation,
      })
      is @authorization.Deny(_),
    )
  }
}

///|
test "common Store preimages preserve Unicode and each line ending" {
  // Independent vectors over the literal existing Store domain, not returned CIDs.
  for
    (root, expected) in [
      (
        "/Users/e\u{0301}/.actql-local", "sha256:76f202e5029b1252e537805c853e1185057b603c02fd742b4bd1095516264a05",
      ),
      (
        "/Users/é/.actql-local", "sha256:5e5d4e8b8e5242582bbb90992d43cd4a57ddf90782f486fbf2d948f6a384f099",
      ),
      (
        "/Users/cr\r/.actql-local", "sha256:24c98d743472a8808e83970b4f6e845a7b83e3b43dd28958c32b940966ef2783",
      ),
      (
        "/Users/lf\n/.actql-local", "sha256:610f1e701eb046b3c9a50547ef1e0691926d01327bba9df38cd93cf8b30b6c3f",
      ),
      (
        "/Users/crlf\r\n/.actql-local", "sha256:b058f367a63a8b31a6c8210ae2f3b10f88009cdc402652954f5f83281059d577",
      ),
    ] {
    let common = product_common_test_originals(root~)
    assert_eq(product_cid(product_common_test_bytes(common.store)), expected)
    assert_eq(
      common.store,
      @utf8.encode(
        product_test_original(product_test_originals(root~), "store.json"),
      ),
    )
  }
}

///|
test "common assembly refuses invalid originals instead of replacing them" {
  let original = product_test_assets()
  for
    (assets, expected) in [
      ({ ..original, environment: "{}", }, InvalidEnvironment),
      ({ ..original, registry: "{}", }, UnsupportedAsset),
      ({ ..original, values: "{}", }, UnsupportedAsset),
      ({ ..original, fragment: "{}", }, UnsupportedAsset),
      ({ ..original, ordered: Some("{}"), }, UnsupportedAsset),
      ({ ..original, result_policy: "{}", }, InvalidResultPolicy),
      (
        {
          ..original,
          result_policy: original.result_policy.replace(
            old="unknown",
            new="public",
          ),
        },
        InvalidResultPolicy,
      ),
    ] {
    assert_eq(
      client_local_product_common_originals(
        "/Users/operator/.actql-local", "2026-10-12T00:00:00.000Z", assets,
      ).map(_ => 1),
      Err(expected),
    )
  }
  for
    root in [
      "relative",
      "/",
      "/home/../user",
      "/home/\u{0000}user",
      "/" + "x".repeat(4096),
    ] {
    assert_eq(
      client_local_product_common_originals(
        root, "2026-10-12T00:00:00.000Z", original,
      ).map(_ => 1),
      Err(InvalidLocation),
    )
  }
  for at in ["2026-10-12", "2026-10-12T00:00:00Z", "9999-12-31T23:59:59.999Z"] {
    assert_eq(
      client_local_product_common_originals(
        "/Users/operator/.actql-local", at, original,
      ).map(_ => 1),
      Err(InvalidObservationTime),
    )
  }
}

///|
test "common retention uses the original finite observation time" {
  let first = product_common_test_originals()
  let second = product_common_test_originals(at="2026-10-12T00:00:01.000Z")
  assert_eq(first.account, second.account)
  assert_eq(first.retention_dependencies, second.retention_dependencies)
  assert_eq(first.store, second.store)
  assert_eq(first.result_policy, second.result_policy)
  assert_true(first.retention_policy != second.retention_policy)
  let retention = product_asset_value(
    product_common_test_bytes(first.retention_policy),
  ).unwrap()
  for
    (field, expected) in [
      ("available_until", "2026-10-13T00:00:00.000Z"),
      ("delete_by", "2026-10-14T00:00:00.000Z"),
      ("metadata_delete_by", "2026-10-19T00:00:00.000Z"),
      (
        "retention_contract_cid", "sha256:a8fb82bdb39b1eb3e6871a55d63f3cb554dcc1953e06501bb686fd8ca8f9646a",
      ),
      (
        "clock_contract_cid", "sha256:c2f7278baa9548283e904d1e8b9048efc0a206ecaca397527ec970776a2f2356",
      ),
    ] {
    assert_eq(
      product_test_text(product_test_field(retention, [field])),
      expected,
    )
  }
}
