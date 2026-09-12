///|
fn stage_has_contract(
  inventory : CoreContractInventory,
  stage : Int,
  expected : CoreContractBody,
) -> Bool {
  for i in 0..<core_contract_stage_body_count(inventory, stage).unwrap() {
    if core_contract_stage_body_at(inventory, stage, i) == Some(expected) {
      return true
    }
  }
  false
}

///|
test "Stage contract selections retain transitive dependencies without borrowing consumer imports" {
  let (identity, _, _) = prepared_identity_fixture()
  let v = collect_core_contracts(identity, {
    max_work: 10000000,
    max_roots: 1000,
    max_bodies: 100,
    max_edges: 100,
  }).unwrap()
  assert_eq(core_contract_stage_count(v), 2)
  assert_eq(core_contract_stage_body_count(v, 0), Some(25))
  assert_eq(core_contract_stage_body_count(v, 1), Some(26))
  assert_false(
    stage_has_contract(v, 0, StageSemantics(@environment.ResultImportInterface)),
  )
  assert_true(
    stage_has_contract(v, 1, StageSemantics(@environment.ResultImportInterface)),
  )
  for stage in 0..<2 {
    assert_true(
      stage_has_contract(v, stage, ExpressionBody(Inherited(UnicodeData))),
    )
    assert_true(
      stage_has_contract(
        v,
        stage,
        CatalogGrammarBody(@environment.CapacityGrammarBody),
      ),
    )
    let seen : Array[String] = []
    for i in 0..<core_contract_stage_body_count(v, stage).unwrap() {
      let cid = core_contract_cid(
        core_contract_stage_body_at(v, stage, i).unwrap(),
      )
      assert_false(seen.contains(cid))
      seen.push(cid)
    }
    assert_true(core_contract_stage_body_at(v, stage, seen.length()) is None)
  }
  for invalid in [-2147483648, -1, 2, 2147483647] {
    assert_true(core_contract_stage_body_count(v, invalid) is None)
    assert_true(core_contract_stage_body_at(v, invalid, 0) is None)
  }
  for invalid in [-2147483648, -1, 2147483647] {
    assert_true(core_contract_stage_body_at(v, 0, invalid) is None)
  }
}
