///|
test "Catalog policy dependency uses its self-excluding identity" {
  // Independent checked Catalog fixture, including its original fixed CID.
  let wire = "{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://crm/main/r#v\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"}"
  let body = admit_catalog_effect_dependency_body(
    "data_policy", wire, 10000, 1000, 32,
  ).unwrap()
  assert_eq(
    body.node.identity,
    "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf",
  )
  let limits : CapturedEffectDependencyLimits = {
    max_entries: 1,
    max_total_bytes: 10000,
    max_depth: 8,
    max_references: 1,
  }
  let inventory = issue_captured_effect_dependency_inventory(
    [body],
    [body],
    limits,
    1000,
    32,
  ).unwrap()
  assert_true(
    admit_captured_effect_dependency_inventory(
      inventory.wire,
      [body],
      limits,
      1000,
      32,
    )
    is Ok(_),
  )
  assert_true(
    admit_catalog_effect_dependency_body(
      "source_contract", wire, 10000, 1000, 32,
    )
    is Err(InvalidBody),
  )
  assert_true(
    admit_catalog_effect_dependency_body(
      "data_policy",
      wire + " ",
      10000,
      1000,
      32,
    )
    is Err(InvalidBody),
  )
  assert_true(
    admit_hashed_effect_dependency_body(
      "schema_evidence",
      body.node.identity,
      wire,
      10000,
      1000,
      32,
    )
    is Err(InvalidBody),
  )
}

///|
test "installed retention dependencies keep canonical bodies and fixed identities" {
  // Node crypto over literal canonical UTF-8 preimages, independently fixed.
  for
    (kind, name, cid) in [
      (
        "retention_contract", "local-result-retention", "sha256:a8fb82bdb39b1eb3e6871a55d63f3cb554dcc1953e06501bb686fd8ca8f9646a",
      ),
      (
        "metadata_retention_policy", "local-result-metadata", "sha256:dbf36e9f6f9b35881ac625290a1c93dbbe485ee8d954cdac3c55e345df4c3095",
      ),
      (
        "clock_contract", "local-clock", "sha256:c2f7278baa9548283e904d1e8b9048efc0a206ecaca397527ec970776a2f2356",
      ),
    ] {
    let wire = "{\"name\":\"" +
      name +
      "\",\"version\":\"actql-installed-local-policy/0.1\"}"
    let body = admit_hashed_effect_dependency_body(
      kind, cid, wire, 10000, 1000, 32,
    ).unwrap()
    assert_eq(body.wire, wire)
    let reordered = "{\"version\":\"actql-installed-local-policy/0.1\",\"name\":\"" +
      name +
      "\"}"
    assert_true(
      admit_hashed_effect_dependency_body(kind, cid, reordered, 10000, 1000, 32)
      is Err(InvalidBody),
    )
  }
}
