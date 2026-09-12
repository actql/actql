///|
test "Local snapshot roots retain source scope and exclude materialization" {
  let body = "{\"output_carrier\":\"relation\",\"schema\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"source_ref\":\"source:local/first/rows\",\"version\":\"actql-local-input-schema/0.1\"}"
  // Independent Node crypto digest and explicit JSON structural counts.
  let expected : CoreContractBody = LocalInputType(
    "sha256:ac3a6b9102dd5201e9a69b6a64f42066be6e64eef99cec7ee584e647bf5c9c1a",
  )
  let caps : CoreContractLimits = {
    max_work: 10000000,
    max_roots: 1000,
    max_bodies: 100,
    max_edges: 100,
  }
  let exact : @snapshot.Limits = {
    max_bytes: 234,
    max_nodes: 12,
    max_depth: 4,
  }
  for
    prefix in [
      "",
      "\"completeness\":\"partial\",\"input_cid\":\"sha256:" +
      "0".repeat(64) +
      "\",",
    ] {
    let (identity, _, _) = prepared_identity_fixture(
      schema_snapshots="[{" + prefix + body[1:].to_owned() + "]",
    )
    assert_true(
      collect_core_contracts(
        identity,
        caps,
        hash_limits=Some({ max_bytes: 0, max_nodes: 0, max_depth: 0, }),
      )
      is Err(BudgetExceeded),
    )
    let v = collect_core_contracts(identity, caps, hash_limits=Some(exact)).unwrap()
    assert_true(physical_equal(core_contract_identity(v), identity))
    assert_eq(core_contract_hash_usage(v), (234, 12))
    assert_true(stage_has_contract(v, 0, expected))
    assert_false(stage_has_contract(v, 1, expected))
    let mut roots = 0
    for i in 0..<core_contract_root_count(v) {
      let root = core_contract_root_at(v, i).unwrap()
      if root.site is StageLocalInputType(stage, index) {
        assert_eq((stage, index), (0, 0))
        assert_eq(root.body, expected)
        roots += 1
      }
    }
    assert_eq(roots, 1)
    for
      short in [
        { ..exact, max_bytes: 233, },
        { ..exact, max_nodes: 11, },
        { ..exact, max_depth: 3, },
      ] {
      assert_true(
        collect_core_contracts(identity, caps, hash_limits=Some(short))
        is Err(BudgetExceeded),
      )
    }
    let work = core_contract_usage(v).0
    assert_true(
      collect_core_contracts(
        identity,
        { ..caps, max_work: work, },
        hash_limits=Some(exact),
      )
      is Ok(_),
    )
    assert_true(
      collect_core_contracts(
        identity,
        { ..caps, max_work: work - 1, },
        hash_limits=Some(exact),
      )
      is Err(BudgetExceeded),
    )
  }
}
