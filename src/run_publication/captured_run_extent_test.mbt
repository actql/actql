///|
test "original captured preparation completes full issued chain beyond prior snapshot node ceiling" {
  for count in [10001, 100000] {
    let wire = "[" + Array::make(count, "{\"value\":7}").join(",") + "]"
    let logical = "sha256:" +
      @sha.text_hex("{\"sort\":\"relation\",\"value\":" + wire + "}").unwrap()
    let chain = captured_run_test_chain(
      row_count=count,
      logical_cid=Some(logical),
    )
    let snapshot_owner = start_captured_result_snapshot(
      chain.definition,
      chain.artifact,
      wire,
      ["value"],
      wire.length() + 28,
      3 * count + 3,
      8,
      1000,
    ).unwrap()
    let mut done = false
    for _ in 0..<100000 {
      if snapshot_owner.advance(256).unwrap().0 {
        done = true
        break
      }
    }
    assert_true(done)
    let snapshot = snapshot_owner.finish().unwrap()
    let definitions = [chain.definition]
    let artifacts = [chain.artifact]
    let snapshots = [snapshot]
    let models : Array[RunEvidenceValue] = []
    let plan = prepare_original_effect_free_capture_plan(
      chain.run,
      chain.invocation,
      definitions,
      artifacts,
      chain.manifest,
      chain.receipt,
      snapshots,
      chain.authoring,
      models,
    ).unwrap()
    // All caller inventory aliases may change after preparation. The original
    // plan still owns exactly the inventories used to derive its extent.
    definitions.clear()
    artifacts.clear()
    snapshots.clear()
    models.push(chain.authoring)
    let facts = capture_construction_layout_facts(plan).unwrap()
    assert_eq(facts.4, 1)
    assert_eq(facts.5, 1)
    assert_eq(facts.6, 1)
    assert_eq(facts.7, 0)
    assert_true(facts.3 < facts.1)
    let cancelled = prepare_original_effect_free_capture_plan(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      [snapshot],
      chain.authoring,
      [],
    ).unwrap()
    cancel_capture_construction_plan(cancelled)
    cancel_capture_construction_plan(cancelled)
    assert_true(capture_construction_layout_facts(cancelled) is None)
    assert_true(start_planned_captured_run(cancelled) is None)
    let owner = start_planned_captured_run(plan).unwrap()
    assert_true(capture_construction_layout_facts(plan) is None)
    assert_true(start_planned_captured_run(plan) is None)
    let extent = captured_run_preparation_limits(owner).unwrap()
    assert_true(extent.0 > wire.length() && extent.1 > 1 + 2 * count)
    let mut done = false
    for _ in 0..<200000 {
      match owner.advance(256) {
        Ok((true, _)) => {
          done = true
          break
        }
        Ok((false, _)) => ()
        Err(_) => fail("capture failed")
      }
    }
    assert_true(done)
    let captured = owner.finish_retained().unwrap()
    assert_true(
      publication_contract_check_limits(captured, extent.0, extent.1, extent.2)
      is Ok(_),
    )
    assert_eq(captured_run_preparation_limits(owner), Some(extent))
    let validation = prepare_original_effect_free_chain_validation(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      captured,
      retained=Some(owner),
    ).unwrap()
    assert_eq(
      publication_validation_plan_reuses_capture(validation),
      Some(true),
    )
    let stale = prepare_original_effect_free_chain_validation(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      captured,
      retained=Some(owner),
    ).unwrap()
    let checked = start_planned_chain_validation(validation).unwrap()
    assert_true(checked.advance(1).unwrap().0)
    checked.finish().unwrap()
    let restored = admit_publication_contract(
      "captured_run",
      publication_contract_json(captured),
      extent.0,
      extent.1,
      extent.2,
    ).unwrap()
    let foreign = prepare_original_effect_free_chain_validation(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      restored,
      retained=Some(owner),
    ).unwrap()
    assert_eq(publication_validation_plan_reuses_capture(foreign), Some(false))
    cancel_publication_validation_plan(foreign)
    owner.cancel()
    assert_true(captured_run_preparation_limits(owner) is None)
    assert_true(publication_validation_plan_reuses_capture(stale) is None)
    assert_true(start_planned_chain_validation(stale) is None)
    cancel_publication_validation_plan(stale)
    // Current-version read/admission creates a distinct original. The same
    // typed validator derives its extent, without a retained issuer or reissue.
    let validation = prepare_original_effect_free_chain_validation(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      restored,
    ).unwrap()
    assert_eq(
      publication_validation_plan_reuses_capture(validation),
      Some(false),
    )
    let checked = start_planned_chain_validation(validation).unwrap()
    let mut done = false
    for _ in 0..<200000 {
      if checked.advance(256).unwrap().0 {
        done = true
        break
      }
    }
    assert_true(done)
    checked.finish().unwrap()
  }
}
