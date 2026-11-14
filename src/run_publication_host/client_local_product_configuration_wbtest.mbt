///|
fn product_test_assets() -> ClientLocalProductAssets {
  {
    environment: product_test_environment_wire(),
    registry: compiler_registered_body_wire(),
    values: compiler_registered_values_wire(),
    fragment: product_test_fragment_wire(),
    ordered: Some(compiler_registered_ordered_wire()),
    result_policy: "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
  }
}

///|
fn product_test_originals(
  assets? : ClientLocalProductAssets = product_test_assets(),
  root? : String = "/Users/operator/.actql-local",
) -> Array[(String, Bytes)] {
  client_local_product_originals(
    root, "/product/lib/sqlite.dylib", "/product/lib/crypto.dylib", "2026-10-12T00:00:00.000Z",
    assets,
  ).unwrap()
}

///|
fn product_test_original(
  originals : Array[(String, Bytes)],
  name : String,
) -> String {
  for (entry, bytes) in originals {
    if entry == name {
      return @utf8.decode(bytes) catch { _ => abort("invalid UTF-8 original") }
    }
  }
  abort("missing expected original")
}

///|
fn product_test_field(
  value : @canonical.CanonicalValue,
  path : Array[String],
) -> @canonical.CanonicalValue {
  let mut result = value
  for name in path {
    result = @canonical.object_field(result, name).unwrap()
  }
  result
}

///|
fn product_test_text(value : @canonical.CanonicalValue) -> String {
  match value {
    @canonical.String(value) => value
    _ => abort("expected text")
  }
}

///|
test "fresh finite product Journal shares retained count policy without enlarging byte storage or legacy history" {
  let finite = client_local_product_finite_originals(
    "/Users/operator/.actql-local",
    "/product/lib/sqlite.dylib",
    "/product/lib/crypto.dylib",
    "2026-10-12T00:00:00.000Z",
    product_test_assets(),
  ).unwrap()
  for (originals, records) in [(product_test_originals(), 8), (finite, 100000)] {
    let config = product_asset_value(
      product_test_original(originals, "config.json"),
    ).unwrap()
    let settings = product_test_field(config, ["native", "local"])
    assert_eq(
      @canonical.stringify_value(
        product_test_field(settings, ["journal_record_limit"]),
        32,
        2,
        2,
      ),
      records.to_string(),
    )
    assert_eq(
      @canonical.stringify_value(
        product_test_field(settings, ["journal_snapshot_bytes"]),
        32,
        2,
        2,
      ),
      "8388608",
    )
  }
  assert_eq(product_default_store_objects(true), 100000)
  assert_eq(product_default_store_objects(false), 8)
}

///|
test "product originals grant only the finite source-free Account operations" {
  let originals = product_test_originals()
  let account = @authorization.admit_account_configuration_json(
    product_test_original(originals, "account.json"),
  ).unwrap()
  for operation in ["cancel", "publish", "read", "submit"] {
    assert_true(
      @authorization.evaluate_account(account, {
        principal: "local-cli",
        connection: "local",
        resource: "run",
        operation,
      })
      is @authorization.Allow(_),
    )
  }
  assert_true(
    @authorization.evaluate_account(account, {
      principal: "local-cli",
      connection: "local",
      resource: "result/answer",
      operation: "read",
    })
    is @authorization.Allow(_),
  )
  for
    (principal, connection, resource, operation) in [
      ("foreign", "local", "run", "submit"),
      ("local-cli", "remote", "run", "submit"),
      ("local-cli", "local", "result/other", "read"),
      ("local-cli", "local", "source/table", "read"),
      ("local-cli", "local", "run", "resolve"),
      ("local-cli", "local", "model/fixture", "infer"),
      ("local-cli", "local", "credential/key", "issue"),
      ("local-cli", "local", "connector/fixture", "create"),
    ] {
    assert_true(
      @authorization.evaluate_account(account, {
        principal,
        connection,
        resource,
        operation,
      })
      is @authorization.Deny(_),
    )
  }
}

///|
test "product originals retain the actual paths and finite selected originals" {
  let originals = product_test_originals()
  assert_eq(originals.map(pair => pair.0), [
    "account.json", "config.json", "environment.json", "run.json", "read.json", "retention.json",
    "store.json",
  ])
  for (_, bytes) in originals {
    assert_true(bytes.length() > 0 && bytes.length() <= 65536)
  }
  assert_eq(
    product_test_original(originals, "environment.json"),
    product_test_environment_wire(),
  )
  let config = product_asset_value(
    product_test_original(originals, "config.json"),
  ).unwrap()
  let settings = product_test_field(config, ["native", "local"])
  for
    (field, expected) in [
      ("managed_root", "/Users/operator/.actql-local"),
      ("state_parent", "/Users/operator/.actql-local"),
      ("state_name", "host"),
      ("sqlite_library", "/product/lib/sqlite.dylib"),
      ("signature_library", "/product/lib/crypto.dylib"),
    ] {
    assert_eq(
      product_test_text(product_test_field(settings, [field])),
      expected,
    )
  }
  assert_eq(
    @canonical.stringify_value(
      product_test_field(settings, ["installation_files"]),
      65536,
      8192,
      64,
    ),
    "[\"read.json\",\"run.json\",\"retention.json\",\"store.json\"]",
  )
  assert_true(@canonical.object_field(settings, "source_file") is None)
  assert_true(@canonical.object_field(settings, "reviewer_file") is None)
}

///|
test "product Result Policy and retention dependencies have actual original bodies" {
  let originals = product_test_originals()
  let run = product_asset_value(product_test_original(originals, "run.json")).unwrap()
  let policy = product_test_text(
    product_test_field(run, [
      "native", "run", "source_free", "result_policy_cid",
    ]),
  )
  assert_eq(
    policy, "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
  )
  assert_eq(
    product_test_text(
      product_test_field(run, [
        "native", "run", "source_free", "result_policy_wire",
      ]),
    ),
    product_test_assets().result_policy,
  )
  let retention = product_asset_value(
    product_test_text(
      product_test_field(run, ["native", "run", "retention_policy_wire"]),
    ),
  ).unwrap()
  for
    (field, expected) in [
      (
        "retention_contract_cid", "sha256:a8fb82bdb39b1eb3e6871a55d63f3cb554dcc1953e06501bb686fd8ca8f9646a",
      ),
      (
        "metadata_retention_policy_cid", "sha256:dbf36e9f6f9b35881ac625290a1c93dbbe485ee8d954cdac3c55e345df4c3095",
      ),
      (
        "clock_contract_cid", "sha256:c2f7278baa9548283e904d1e8b9048efc0a206ecaca397527ec970776a2f2356",
      ),
      ("effective_data_policy_cid", policy),
      ("available_until", "2026-10-13T00:00:00.000Z"),
      ("delete_by", "2026-10-14T00:00:00.000Z"),
      ("extension_ceiling_at", "2026-10-14T00:00:00.000Z"),
      ("metadata_delete_by", "2026-10-19T00:00:00.000Z"),
    ] {
    assert_eq(
      product_test_text(product_test_field(retention, [field])),
      expected,
    )
  }
  let read = product_asset_value(product_test_original(originals, "read.json")).unwrap()
  assert_eq(
    product_test_text(
      product_test_field(read, ["native", "result_read", "expires_at"]),
    ),
    "2026-10-13T00:00:00.000Z",
  )
  assert_eq(
    @canonical.stringify_value(
      product_test_field(read, ["native", "result_read", "result_names"]),
      65536,
      8192,
      64,
    ),
    "[\"answer\"]",
  )
  assert_eq(
    @canonical.stringify_value(
      product_test_field(read, ["native", "result_read", "max_uses"]),
      65536,
      8192,
      64,
    ),
    "1",
  )
}

///|
test "product Store owner preimage retains exact Unicode and line ends" {
  // Independent Node crypto vectors over the existing Store preimage.
  for
    (root, expected_cid) in [
      (
        "/Users/operator/.actql-local", "sha256:00fa147b05cdc1369516e70bfc157703b8099bcb709fe5f6eab2ee8afa5f954d",
      ),
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
    let originals = product_test_originals(root~)
    let store_wire = product_test_original(originals, "store.json")
    let store = product_asset_value(store_wire).unwrap()
    assert_eq(
      product_test_text(product_test_field(store, ["root"])),
      root + "/results",
    )
    assert_eq(
      product_test_text(product_test_field(store, ["principalId"])),
      "local-cli",
    )
    let run = product_asset_value(product_test_original(originals, "run.json")).unwrap()
    assert_eq(
      product_test_text(
        product_test_field(run, ["native", "run", "store_authority_cid"]),
      ),
      expected_cid,
    )
  }
  let decomposed = product_test_original(
    product_test_originals(root="/Users/e\u{0301}/.actql-local"),
    "store.json",
  )
  let composed = product_test_original(
    product_test_originals(root="/Users/é/.actql-local"),
    "store.json",
  )
  assert_true(decomposed != composed)
  // Independent existing Store domain and literal path, not assembler output.
  assert_eq(
    product_test_original(product_test_originals(), "store.json"),
    "{\"version\":\"actql-local-store-owner/0.1\",\"root\":\"/Users/operator/.actql-local/results\",\"principalId\":\"local-cli\"}",
  )
}

///|
test "product assembly refuses changed environment evidence and privileged assets" {
  let original = product_test_assets()
  for
    environment in [
      original.environment.replace(
        old="42e2125d9fbac72912fd67d8f619769810d5d4c606a362a4e569a89f32be54e0",
        new="0000000000000000000000000000000000000000000000000000000000000000",
      ),
      original.environment.replace(
        old="\"source_views\":[]",
        new="\"source_views\":[{}]",
      ),
      original.environment.replace(
        old="\"model_task_contracts\":[]",
        new="\"model_task_contracts\":[{}]",
      ),
      "{}",
    ] {
    assert_true(environment != original.environment)
    assert_eq(
      client_local_product_originals(
        "/home/user/.actql-local",
        "/product/lib/sqlite",
        "/product/lib/crypto",
        "2026-10-12T00:00:00.000Z",
        { ..original, environment, },
      ).map(_ => 1),
      Err(InvalidEnvironment),
    )
  }
  for
    result_policy in [
      "{}",
      original.result_policy.replace(old="unknown", new="public"),
    ] {
    assert_eq(
      client_local_product_originals(
        "/home/user/.actql-local",
        "/product/lib/sqlite",
        "/product/lib/crypto",
        "2026-10-12T00:00:00.000Z",
        { ..original, result_policy, },
      ).map(_ => 1),
      Err(InvalidResultPolicy),
    )
  }
}

///|
test "product assembly refuses unsupported engine bodies and unbounded locations" {
  for
    assets in [
      { ..product_test_assets(), registry: "{}", },
      { ..product_test_assets(), values: "{}", },
      { ..product_test_assets(), fragment: "{}", },
      { ..product_test_assets(), ordered: Some("{}"), },
    ] {
    assert_eq(
      client_local_product_originals(
        "/home/user/.actql-local", "/product/lib/sqlite", "/product/lib/crypto",
        "2026-10-12T00:00:00.000Z", assets,
      ).map(_ => 1),
      Err(UnsupportedAsset),
    )
  }
  for
    root in [
      "relative",
      "/",
      "/home//user",
      "/home/../user",
      "/home/./user",
      "/home/user/",
      "/" + "x".repeat(4096),
      "/home/\u{0000}user",
    ] {
    assert_eq(
      client_local_product_originals(
        root,
        "/product/lib/sqlite",
        "/product/lib/crypto",
        "2026-10-12T00:00:00.000Z",
        product_test_assets(),
      ).map(_ => 1),
      Err(InvalidLocation),
    )
  }
  assert_eq(
    client_local_product_originals(
      "/home/user",
      "/product/lib/same",
      "/product/lib/same",
      "2026-10-12T00:00:00.000Z",
      product_test_assets(),
    ).map(_ => 1),
    Err(InvalidLocation),
  )
}

///|
test "product assembly requires a canonical finite original clock" {
  for
    at in [
      "2026-10-12", "2026-02-29T00:00:00.000Z", "2026-10-12T00:00:00Z", "9999-12-31T23:59:59.999Z",
    ] {
    assert_eq(
      client_local_product_originals(
        "/home/user/.actql-local",
        "/product/lib/sqlite",
        "/product/lib/crypto",
        at,
        product_test_assets(),
      ).map(_ => 1),
      Err(InvalidObservationTime),
    )
  }
}

///|
test "finite Mock product originals retain the closed selected Account and Result names" {
  let task = "sha256:" + "a".repeat(64)
  let subjects : @authorization.LocalMockAccountSubjects = {
    account_id: "local-cli",
    principal: "local-cli",
    control_connection: "local",
    sources: [
      ("salesforce", "Opportunity"),
      ("drive", "files"),
      ("drive", "contents"),
    ],
    model_tasks: [task],
    request_target: None,
    update_target: Some(("salesforce", "Opportunity")),
    signing_key_resource: None,
  }
  let make = fn(mock) {
    client_local_product_finite_originals(
      "/Users/operator/.actql-local",
      "/product/lib/sqlite.dylib",
      "/product/lib/crypto.dylib",
      "2026-10-12T00:00:00.000Z",
      product_test_assets(),
      mock~,
    )
  }
  let baseline = make(None).unwrap()
  let selected = make(Some(subjects)).unwrap()
  assert_eq(selected.length(), baseline.length())
  assert_eq(
    product_test_original(selected, "account.json"),
    @authorization.local_mock_account_configuration(subjects).unwrap(),
  )
  for name in ["read.json", "material-read.json", "file-read.json"] {
    let value = product_asset_value(product_test_original(selected, name)).unwrap()
    assert_true(
      product_test_field(value, ["native", "result_read", "accepted_run_policy"])
      is @canonical.Bool(true),
    )
    assert_true(
      @canonical.object_field(
        product_test_field(value, ["native", "result_read"]),
        "data_policy_cids",
      )
      is None,
    )
    let unchanged = product_asset_value(product_test_original(baseline, name)).unwrap()
    assert_true(
      @canonical.object_field(
        product_test_field(unchanged, ["native", "result_read"]),
        "accepted_run_policy",
      )
      is None,
    )
    guard product_test_field(value, ["native", "result_read", "result_names"])
      is @canonical.Array(names) else {
      fail("missing original Result selection")
    }
    assert_eq(@canonical.array_count(names), 3)
    for index, expected in ["answer", "main", "updates"] {
      assert_eq(
        product_test_text(@canonical.array_at(names, index).unwrap()),
        expected,
      )
    }
  }
  // A fresh Mock selection changes only these four initial originals. It
  // cannot rewrite a restored Account, deadline, Run policy or compiler asset.
  for (name, bytes) in baseline {
    if name != "account.json" &&
      name != "read.json" &&
      name != "material-read.json" &&
      name != "file-read.json" {
      assert_eq(
        product_common_test_bytes(bytes),
        product_test_original(selected, name),
      )
    }
  }
  assert_true(
    make(Some({ ..subjects, principal: "another-host", }))
    is Err(UnsupportedAsset),
  )
  assert_true(
    make(
      Some({ ..subjects, update_target: Some(("salesforce", "unselected")), }),
    )
    is Err(UnsupportedAsset),
  )
}
