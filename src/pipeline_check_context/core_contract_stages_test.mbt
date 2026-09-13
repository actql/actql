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
test "publication retains primitive interpretation roots for a Stage without steps" {
  let (identity, _, _) = prepared_identity_fixture(third_stage=true)
  let inventory = collect_core_contracts(identity, {
    max_work: 10000000,
    max_roots: 1000,
    max_bodies: 100,
    max_edges: 100,
  }).unwrap()
  let mut publications = 0
  for i in 0..<core_contract_root_count(inventory) {
    let root = core_contract_root_at(inventory, i).unwrap()
    if root.site is StagePublicationRules(stage, index) {
      assert_eq(index, 0)
      assert_true(stage >= 0 && stage < 3)
      assert_eq(root.body, AdoptedBody(@pipeline.RelaPrimitive))
      publications += 1
    }
  }
  assert_eq(publications, 3)
  assert_true(
    stage_has_contract(inventory, 2, AdoptedBody(@pipeline.RelaPrimitive)),
  )
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
  assert_eq(core_contract_stage_body_count(v, 0), Some(33))
  assert_eq(core_contract_stage_body_count(v, 1), Some(32))
  assert_true(stage_has_contract(v, 0, LocalSnapshotRules))
  assert_true(stage_has_contract(v, 0, LocalSourceReferenceRules))
  assert_false(stage_has_contract(v, 1, LocalSnapshotRules))
  assert_false(stage_has_contract(v, 1, LocalSourceReferenceRules))
  assert_false(
    stage_has_contract(v, 0, StageSemantics(@environment.GateRequirement)),
  )
  assert_true(
    stage_has_contract(v, 1, StageSemantics(@environment.GateRequirement)),
  )
  assert_false(
    stage_has_contract(v, 0, StageSemantics(@environment.ResultImportInterface)),
  )
  assert_true(
    stage_has_contract(v, 1, StageSemantics(@environment.ResultImportInterface)),
  )
  for stage in 0..<2 {
    assert_false(stage_has_contract(v, stage, SourceResponsePolicyRules))
    assert_true(stage_has_contract(v, stage, CanonicalIdentityRules))
    for
      (body, cid) in [
        (
          @environment.LocalContracts,
          "sha256:a1dcd5bf20a7d6dceedd4a298b684f439101d391063ae13bb61359bd10d30621",
        ),
        (
          @environment.LocalDependencies,
          "sha256:22a2636742d270464988e350adc168af898987e83f620cba893efb091d9f49e8",
        ),
      ] {
      assert_true(stage_has_contract(v, stage, StageSemantics(body)))
      assert_eq(core_contract_cid(StageSemantics(body)), cid)
    }
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
  assert_eq(
    core_contract_cid(StageSemantics(@environment.GateRequirement)),
    "sha256:7556fa58d35f66d498511ef31800cddda05bacdb1f4eba7d654010ee9994351d",
  )
  for invalid in [-2147483648, -1, 2, 2147483647] {
    assert_true(core_contract_stage_body_count(v, invalid) is None)
    assert_true(core_contract_stage_body_at(v, invalid, 0) is None)
  }
  for invalid in [-2147483648, -1, 2147483647] {
    assert_true(core_contract_stage_body_at(v, 0, invalid) is None)
  }
}
