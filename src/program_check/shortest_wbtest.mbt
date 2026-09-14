///|
fn shortest_program_suffix(
  source : String,
  target : String,
  selection : String,
  weighted : Bool,
  guard_text : String,
) -> String {
  ",{\"graph\":{\"nodes\":{\"from\":\"seed\",\"id\":\"id\",\"fields\":[]},\"edges\":{\"from\":\"derived\",\"source\":\"id\",\"target\":\"value\",\"fields\":[\"value\"]}},\"as\":\"g\"},{\"shortest_path\":{\"source\":" +
  source +
  ",\"target\":" +
  target +
  (if selection == "" { "" } else { ",\"selection\":\"" + selection + "\"" }) +
  ",\"direction\":\"both\",\"max_hops\":9007199254740992" +
  (if weighted { ",\"weight\":\"value\"" } else { "" }) +
  guard_text +
  "}},{\"select\":[{\"id\":\"source_id\"},{\"value\":\"hop_count\"}],\"as\":\"projected\"}"
}

///|
test "shortest row candidates rebuild selector dependencies without limiting search paths" {
  let seed = sequence_fixture_proof(
    "actql.bound.values",
    0,
    2,
    [],
    "{\"op\":\"source\"}",
  )
  let count = sequence_fixture_proof(
    "actql.bound.shortest-path",
    3,
    2,
    [@wire.cid(@wire.program_proof_witness(seed))],
    "{\"op\":\"source\"}",
  )
  for guard_value in [1, 20] {
    let programs : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      through_check=true,
      checked_results=programs,
      second_stage=true,
      sga=true,
      graph_construction_limit=Some(1000),
      traversal_capacity=true,
      traversal_kind="shortest_path",
      traversal_proofs=[seed, count],
      generated_rows=Some("[{\"id\":1},{\"id\":2}]"),
      producer_expression="id",
      producer_suffix=shortest_program_suffix(
        "{\"from\":\"seed\",\"id\":\"id\"}",
        "{\"from\":\"seed\",\"id\":\"id\"}",
        "nearest_per_source",
        false,
        ",\"max_output_rows\":" + guard_value.to_string(),
      ),
      producer_result_from="projected",
      extra_step_budget=3,
    )
    let program = programs[0]
    let selected = unit_traversal_limit_at(program, 0, 0).unwrap()
    assert_eq(unit_traversal_limit_count(program, 1), Some(0))
    assert_eq(traversal_limit_proof_count(selected), 1)
    let root = traversal_limit_proof_at(selected, 0).unwrap()
    assert_eq(proof_input_count(root), 1)
    let dependency = proof_input_at(root, 0).unwrap()
    assert_eq(proof_source(dependency).source_ordinal, 0)
    assert_eq(
      proof_source(dependency).unit_definition_cid,
      unit_definition_cid(program, 0).unwrap(),
    )
    assert_eq(
      @wire.program_proof_input_at(proof_claim(root), 0),
      Some(@wire.cid(@wire.program_proof_witness(proof_claim(dependency)))),
    )
    assert_true(
      @wire.cid(@wire.program_proof_witness(proof_claim(dependency))) !=
      @wire.cid(@wire.program_proof_witness(seed)),
    )
    let rows = traversal_limit_claim(selected, OutputRows)
    assert_eq(
      @derivation.minimum_value(@wire.limit_minimum(rows)),
      guard_value.min(2).to_int64(),
    )
    assert_eq(@derivation.minimum_candidate_count(@wire.limit_minimum(rows)), 3)
    let paths = traversal_limit_claim(selected, SearchPaths)
    assert_eq(@derivation.minimum_value(@wire.limit_minimum(paths)), 1000L)
    assert_eq(
      @derivation.minimum_candidate_count(@wire.limit_minimum(paths)),
      1,
    )
    let writer = @encode.writer(100000, 10000, 100)
    @wire.emit_limit(rows, writer)
    let wire = @encode.finish(writer)
    assert_true(wire.contains("actql.bound.shortest-path"))
    assert_true(
      wire.contains(
        "unit:" + unit_definition_cid(program, 0).unwrap() + "#/steps/3",
      ),
    )
    assert_false(wire.contains("checked-step:"))
    if guard_value == 20 {
      assert_true(
        wire.contains("\"author_guard_binding\":\"currently_non_binding\""),
      )
    }
  }
}

///|
test "formal shortest retains capacity semantics and endpoint roles through Result imports" {
  for
    (source, target, selection, weighted, parameter) in [
      ("1", "1", "", false, false),
      ("1", "2", "", true, false),
      (
        "{\"from\":\"seed\",\"id\":\"id\"}", "{\"from\":\"seed\",\"id\":\"id\"}",
        "each_pair", true, false,
      ),
      ("{\"ids\":[1,1]}", "{\"ids\":[2]}", "nearest_per_source", false, false),
      (
        "{\"where\":{\"literal\":false}}", "{\"ids\":[1]}", "nearest_pair", true,
        false,
      ),
      (
        "{\"where\":{\"literal\":false}}", "{\"where\":{\"literal\":false}}", "nearest_pair",
        false, true,
      ),
    ] {
    let programs : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      through_check=true,
      checked_results=programs,
      second_stage=true,
      parameters=parameter,
      sga=true,
      graph_construction_limit=Some(1000),
      traversal_capacity=true,
      traversal_kind="shortest_path",
      generated_rows=Some(
        if parameter {
          "[]"
        } else {
          "[{\"id\":1},{\"id\":2}]"
        },
      ),
      producer_expression="id",
      producer_suffix=shortest_program_suffix(
        source,
        target,
        selection,
        weighted,
        ",\"max_output_rows\":" +
        (if parameter { "{\"$param\":\"n\"}" } else { "1" }),
      ),
      producer_result_from="projected",
      extra_step_budget=3,
    )
    let program = programs[0]
    assert_eq(unit_traversal_limit_count(program, 0), Some(1))
    assert_eq(unit_traversal_limit_count(program, 1), Some(0))
    let limit = unit_traversal_limit_at(program, 0, 0).unwrap()
    let selected = traversal_limit_selection(limit)
    assert_true(selected.step.operation is @pipeline.Shortest(..))
    for
      (scope, suffix, maximum) in [
        (@step_bounds.SearchPaths, "paths", 1000L),
        (@step_bounds.OutputRows, "output", 1L),
      ] {
      let claim = traversal_limit_claim(limit, scope)
      assert_eq(
        @wire.limit_subject(claim),
        "unit:" +
        unit_definition_cid(program, 0).unwrap() +
        "#/steps/3/shortest_path/" +
        suffix,
      )
      assert_eq(@derivation.minimum_value(@wire.limit_minimum(claim)), maximum)
    }
    let closure = @context.stage_requirement_operations(program.requirements)
    let mut resources = 0
    let mut semantics = 0
    let mut guards = 0
    for i in 0..<@context.operation_closure_count(closure) {
      match @context.operation_closure_at(closure, i) {
        Some(ExecutionCheck(ShortestLimits(check) | ShortestOutputGuard(check))) => {
          if @context.operation_closure_at(closure, i)
            is Some(ExecutionCheck(ShortestLimits(_))) {
            resources += 1
          } else {
            guards += 1
          }
          assert_true(
            physical_equal(check.site.pipeline, selected.site.pipeline),
          )
          assert_true(
            physical_equal(
              @step_bounds.traversal_limit_claim(check.limits, OutputRows),
              @step_bounds.traversal_limit_claim(selected.limits, OutputRows),
            ),
          )
          assert_eq(
            @step_bounds.traversal_limit_guard_value(check.limits),
            Some(1L),
          )
        }
        Some(ExecutionCheck(ShortestExecution(check))) => {
          semantics += 1
          assert_true(
            physical_equal(check.site.pipeline, selected.site.pipeline),
          )
          if selection == "each_pair" {
            assert_true(check.source_relation is Some(_))
            assert_eq(check.source_relation, check.target_relation)
          }
        }
        _ => ()
      }
    }
    assert_eq(
      (resources, guards, semantics),
      (3, 3, if weighted { 24 } else { 15 }),
    )
  }
}

///|
test "formal shortest rejects absent or foreign operation capacity without partial success" {
  for
    (capacity, kind) in [
      (false, "shortest_path"),
      (true, "traverse"),
      (true, "reach"),
    ] {
    let programs : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        sga=true,
        graph_construction_limit=Some(1000),
        traversal_capacity=capacity,
        traversal_kind=kind,
        generated_rows=Some("[]"),
        producer_expression="id",
        producer_suffix=shortest_program_suffix(
          "{\"where\":{\"literal\":false}}", "{\"where\":{\"literal\":false}}", "nearest_pair",
          false, "",
        ),
        producer_result_from="projected",
        extra_step_budget=3,
      )
    catch {
      LocalConstructionFailure::Source(_) => ()
      _ => fail("capacity fails at source preparation")
    } noraise {
      _ => fail("missing capacity")
    }
    assert_eq(programs.length(), 0)
  }
}
