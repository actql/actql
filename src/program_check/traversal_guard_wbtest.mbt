///|
test "current TRAIL guards bind producer Unit limits and imported execution gates" {
  for
    (value, expected_cid) in [
      (
        1, "sha256:34c394d702c1a36a33a2ae2d24bd311d0336fa960945fbeb899706002ceffa14",
      ),
      (
        1000, "sha256:1e22abf67915fd8fb8d01eb5030b6717199c57495e201a6c8dd2bbf1ac5cbd30",
      ),
      (
        2000, "sha256:80a00a3fab80bd5aa222c646c04b426786d1864db5674811dc351950f61d2d78",
      ),
    ] {
    for parameter in [false, true] {
      if parameter && value != 1 {
        continue
      }
      let programs : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        parameters=parameter,
        graph=true,
        graph_construction_limit=Some(1000),
        traversal_capacity=true,
        generated_rows=Some("[{\"id\":1},{\"id\":2}]"),
        producer_expression="id",
        producer_suffix=current_trail_resources_suffix(
          "out",
          "1",
          guard_text=",\"max_output_rows\":" +
            (if parameter { "{\"$param\":\"n\"}" } else { value.to_string() }),
        ),
        producer_result_from="projected",
        extra_step_budget=3,
      )
      let program = programs[0]
      let retained = unit_traversal_limit_at(program, 0, 0).unwrap()
      assert_eq(unit_traversal_limit_count(program, 1), Some(0))
      let selected = traversal_limit_selection(retained)
      let claim = traversal_limit_claim(retained, OutputRows)
      assert_eq(
        @derivation.minimum_value(@wire.limit_minimum(claim)),
        value.min(1000).to_int64(),
      )
      assert_eq(
        @derivation.minimum_candidate_count(@wire.limit_minimum(claim)),
        2,
      )
      let closure = @context.stage_requirement_operations(program.requirements)
      let mut gates = 0
      for i in 0..<@context.operation_closure_count(closure) {
        if @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(TraversalOutputGuard(check))) {
          gates += 1
          assert_true(
            physical_equal(
              @step_bounds.traversal_limit_pipeline(check.limits),
              @step_bounds.traversal_limit_pipeline(selected.limits),
            ),
          )
          assert_true(
            physical_equal(
              @step_bounds.traversal_limit_claim(check.limits, OutputRows),
              @step_bounds.traversal_limit_claim(selected.limits, OutputRows),
            ),
          )
          assert_eq(
            @step_bounds.traversal_limit_guard_value(check.limits),
            Some(value.to_int64()),
          )
          assert_eq(
            @context.operation_execution_phase(TraversalOutputGuard(check)),
            BeforeOperationOutput,
          )
          assert_eq(
            @context.operation_execution_failure(TraversalOutputGuard(check)),
            RejectOperationOutput,
          )
        }
      }
      assert_eq(gates, 3)
      let synthetic = {
        ..program.units[0],
        definition_cid: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
      }
      let source = unit_operation_source(synthetic, synthetic.pipeline, 3).unwrap()
      let budget : IdentityBudget = {
        work: 100000000,
        bytes: 10000000,
        nodes: 1000000,
        depth: 100,
      }
      let converted = assemble_traversal_limit(
        [synthetic],
        source,
        selected,
        budget,
      )
      assert_eq(
        @wire.limit_cid(traversal_limit_claim(converted, OutputRows)),
        expected_cid,
      )
      assert_eq(
        @wire.limit_cid(traversal_limit_claim(converted, SearchPaths)),
        "sha256:cbea458b621e07a2cdea43eed4ac8378835fbc0678b839fc158de7b58d820afe",
      )
      let work = 100000000 - budget.work
      let bytes = 10000000 - budget.bytes
      let nodes = 1000000 - budget.nodes
      let exact : IdentityBudget = { work, bytes, nodes, depth: 100, }
      let _ = assemble_traversal_limit([synthetic], source, selected, exact)
      assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
      for
        short in [
          IdentityBudget::{ work: work - 1, bytes, nodes, depth: 100, },
          IdentityBudget::{ work, bytes: bytes - 1, nodes, depth: 100, },
          IdentityBudget::{ work, bytes, nodes: nodes - 1, depth: 100, },
        ] {
        try
          assemble_traversal_limit([synthetic], source, selected, short)
        catch {
          _ => ()
        } noraise {
          _ => fail("partial guard conversion")
        }
      }
    }
  }
}
