///|
test "imported validation visits do not become consumer Unit operation roots" {
  let (identity, wiring, _) = prepared_identity_fixture(unused_operation=true)
  let contracts = collect_core_contracts(identity, {
    max_work: 10000000,
    max_roots: 1000,
    max_bodies: 100,
    max_edges: 100,
  }).unwrap()
  let mut imported = 0
  let mut local_visits = 0
  for stage in 0..<2 {
    // Read the authored pipeline through source-bound Stage wiring, separately
    // from the collector's traversal and local-visit classification.
    let authored = @parameter_slots.pipeline(
      @stages.collection(
        @stage_results.stage_port_source(
          @stage_results.wiring_stage_at(wiring, stage).unwrap(),
        ),
      ),
    )
    for visit in 0..<program_identity_producer_count(identity, stage).unwrap() {
      let pipeline = program_identity_producer_at(identity, stage, visit).unwrap()
      let owned = physical_equal(pipeline, authored)
      assert_eq(
        program_identity_producer_is_local(identity, stage, visit),
        Some(owned),
      )
      if owned {
        local_visits += 1
      } else {
        imported += 1
      }
      let mut roots = 0
      for i in 0..<core_contract_root_count(contracts) {
        if core_contract_root_at(contracts, i).unwrap().site
          is OperationTransferRules(s, v, _) &&
          s == stage &&
          v == visit {
          roots += 1
        }
      }
      assert_eq(roots, if owned { @pipeline.step_count(authored) } else { 0 })
    }
  }
  assert_eq(local_visits, 2)
  assert_true(imported > 0)
  assert_true(program_identity_producer_is_local(identity, -1, 0) is None)
  assert_true(program_identity_producer_is_local(identity, 0, -1) is None)
  assert_true(program_identity_producer_is_local(identity, 2, 0) is None)
}
