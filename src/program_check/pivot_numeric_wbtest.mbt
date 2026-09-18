///|
fn pivot_program_fixture(
  reduction? : String = "sum",
  empty? : Bool = false,
  supplied? : @decode.Cursor? = None,
  profile? : Bool = true,
  ordered? : Bool = true,
) -> CheckedProgram raise LocalConstructionFailure {
  let checked : Array[CheckedProgram] = []
  let suffix = (if reduction == "first" && ordered {
      ",{\"sort\":[{\"id\":\"asc\"}]}"
    } else {
      ""
    }) +
    ",{\"derive\":{\"kind\":{\"literal\":\"a\"}}},{\"pivot\":{\"index\":[\"id\"],\"column\":\"kind\",\"values\":" +
    (if empty { "[]" } else { "[\"z\",\"a\"]" }) +
    ",\"value\":\"value\",\"aggregate\":\"" +
    reduction +
    "\",\"fill\":0}},{\"select\":[\"id\",{\"value\":\"" +
    (if empty { "id" } else { "a" }) +
    "\"}],\"as\":\"pivoted\"}"
  let _ = local_construction_fixture(
    { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
    second_stage=true,
    through_check=true,
    checked_results=checked,
    parameters=true,
    supplied~,
    numeric_profile=if profile { Some(numeric_profile_fixture()) } else { None },
    producer_suffix=suffix,
    producer_result_from="pivoted",
    second_steps="[{\"select\":[\"id\",\"value\"],\"as\":\"selected\"}]",
    second_result_from="selected",
    extra_step_budget=5,
  )
  checked[0]
}

///|
test "formal pivot numeric slots preserve producer identity across imports and empty axes" {
  for reduction in ["sum", "avg", "count", "min", "max", "first"] {
    for empty in [false, true] {
      let program = pivot_program_fixture(reduction~, empty~)
      let numeric = reduction == "sum" || reduction == "avg"
      let width = if numeric && !empty { 2 } else { 0 }
      assert_eq(unit_pivot_numeric_slot_count(program, 0), Some(width))
      assert_eq(unit_pivot_numeric_slot_count(program, 1), Some(0))
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut original : PivotNumericSlots? = None
      let mut imports = 0
      for i in 0..<@context.operation_closure_count(closure) {
        guard @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(PivotExecution(check))) &&
          check.rule is CaptureNumericObservations(demand) else {
          assert_true(pivot_numeric_slots_for_requirement(program, i) is None)
          continue
        }
        assert_true(numeric)
        let bundle = pivot_numeric_slots_for_requirement(program, i).unwrap()
        assert_eq(pivot_numeric_slot_count(bundle), width)
        if original is Some(previous) {
          assert_true(physical_equal(bundle, previous))
        } else {
          original = Some(bundle)
        }
        assert_true(
          physical_equal(pivot_numeric_slots_demand(bundle).pivot, demand.pivot),
        )
        assert_eq(
          pivot_numeric_slots_operation(bundle).unit_definition_cid,
          program.units[0].definition_cid,
        )
        if check.site.stage == 1 {
          imports += 1
        }
        assert_true(pivot_numeric_slot_at(bundle, -1) is None)
        assert_true(pivot_numeric_slot_at(bundle, width) is None)
        for column in 0..<width {
          let slot = pivot_numeric_slot_at(bundle, column).unwrap()
          assert_true(
            physical_equal(
              slot,
              unit_pivot_numeric_slot_at(program, 0, column).unwrap(),
            ),
          )
          let name = if column == 0 { "a" } else { "z" }
          assert_eq(pivot_numeric_slot_name(slot), name)
          assert_eq(
            pivot_numeric_slot_reduction(slot),
            Some(
              if reduction == "sum" {
                @numeric.Sum
              } else {
                @numeric.Average
              },
            ),
          )
          assert_eq(pivot_numeric_slot_operation(slot).source_ordinal, 2)
          let expected = "{\"output_name\":\"" +
            name +
            "\",\"reduction_profile_cid\":\"" +
            @numeric.cid(demand.profile) +
            "\",\"source_ordinal\":2,\"unit_definition_cid\":\"" +
            program.units[0].definition_cid +
            "\",\"version\":\"actql-pivot-numeric-slot/0.1\"}"
          assert_eq(
            pivot_numeric_slot_cid(slot),
            "sha256:" + @sha.text_hex(expected).unwrap(),
          )
          let writer = @encode.writer(10000, 1000, 100)
          emit_pivot_numeric_slot(slot, writer)
          assert_eq(@encode.finish(writer), expected)
        }
      }
      assert_eq(original is Some(_), numeric)
      assert_eq(imports > 0, numeric)
      for stage in 0..<2 {
        let mut has_slot_contract = false
        for i in 0..<unit_contract_count(program, stage).unwrap() {
          if unit_contract_at(program, stage, i).unwrap().0 ==
            "sha256:54c19c5dc586979bfd5cfa7afed23011e8394dd4a8623c32ba6ca0f83fb01858" {
            has_slot_contract = true
          }
        }
        assert_eq(has_slot_contract, numeric && stage == 0)
      }
      assert_true(pivot_numeric_slots_for_requirement(program, -1) is None)
      assert_true(
        pivot_numeric_slots_for_requirement(
          program,
          @context.operation_closure_count(closure),
        )
        is None,
      )
      assert_true(unit_pivot_numeric_slot_at(program, 0, width) is None)
      assert_true(unit_pivot_numeric_slot_count(program, 2) is None)
    }
  }
}

///|
test "pivot numeric identity construction rejects foreign owners and budget shortages atomically" {
  for empty in [false, true] {
    let program = pivot_program_fixture(empty~)
    for supplied in [None, Some(supplied_fixture("{\"n\":2}"))] {
      let other = pivot_program_fixture(empty~, supplied~)
      let budget = IdentityBudget::{
        work: 1000000,
        bytes: 100000,
        nodes: 10000,
        depth: 100,
      }
      let failed = try {
        let _ = prepare_program_pivot_numeric_slot_identities(
          other.units,
          program.requirements,
          budget,
        )
        false
      } catch {
        ForeignOwner => true
        _ => false
      }
      assert_true(failed)
      assert_eq(
        (budget.work, budget.bytes, budget.nodes),
        (1000000, 100000, 10000),
      )
    }
    let budget = IdentityBudget::{
      work: 1000000,
      bytes: 100000,
      nodes: 10000,
      depth: 100,
    }
    let _ = prepare_program_pivot_numeric_slot_identities(
      program.units,
      program.requirements,
      budget,
    )
    let used_work = 1000000 - budget.work
    let used_bytes = 100000 - budget.bytes
    let used_nodes = 10000 - budget.nodes
    let exact = IdentityBudget::{
      work: used_work,
      bytes: used_bytes,
      nodes: used_nodes,
      depth: 100,
    }
    let _ = prepare_program_pivot_numeric_slot_identities(
      program.units,
      program.requirements,
      exact,
    )
    assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
    for dimension in 0..<3 {
      if empty && dimension != 0 {
        continue
      }
      let short = IdentityBudget::{
        work: used_work - (if dimension == 0 { 1 } else { 0 }),
        bytes: used_bytes - (if dimension == 1 { 1 } else { 0 }),
        nodes: used_nodes - (if dimension == 2 { 1 } else { 0 }),
        depth: 100,
      }
      let before = (short.work, short.bytes, short.nodes)
      let failed = try {
        let _ = prepare_program_pivot_numeric_slot_identities(
          program.units,
          program.requirements,
          short,
        )
        false
      } catch {
        BudgetExceeded | Encoding(_) => true
        _ => false
      }
      assert_true(failed)
      assert_eq((short.work, short.bytes, short.nodes), before)
    }
  }
}

///|
test "formal pivot retains numeric and stable-order requirements rather than bypassing them" {
  for empty in [false, true] {
    try pivot_program_fixture(empty~, profile=false) catch {
      Closure(UnresolvedOperation(site)) => {
        guard site.requirement is @pipeline.RelationRequirement(pending) else {
          fail("wrong missing-profile requirement")
        }
        assert_eq(pending.kind, @relation.NumericAggregateObservation)
      }
      error => raise error
    } noraise {
      _ => fail("missing profile bypassed")
    }
  }
  try pivot_program_fixture(reduction="first", ordered=false) catch {
    Source(
      SourceView(
        @context.Program(@context.Program(@results.Pipeline(_, issue)))
      )
    )
    | Source(
      SourceView(
        @context.Program(
          @context.Program(@results.Order(_, @publication.PipelineOrder(issue)))
        )
      )
    ) => assert_eq(issue.kind, @pipeline.UnresolvedOrder)
    error => raise error
  } noraise {
    _ => fail("first acquired an unproven stable order")
  }
}

///|
test "formal decimal pivot keeps exact reduction without floating observation slots" {
  let checked : Array[CheckedProgram] = []
  let _ = local_construction_fixture(
    { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
    through_check=true,
    checked_results=checked,
    producer_expression="CAST(id AS DECIMAL(4,2))",
    producer_suffix=",{\"derive\":{\"kind\":{\"literal\":\"a\"}}},{\"pivot\":{\"index\":[\"id\"],\"column\":\"kind\",\"values\":[\"a\"],\"value\":\"value\",\"aggregate\":\"sum\",\"fill\":\"0.00\"}},{\"select\":[\"id\",{\"value\":\"a\"}],\"as\":\"pivoted\"}",
    producer_result_from="pivoted",
    extra_step_budget=4,
  )
  let program = checked[0]
  assert_eq(unit_pivot_numeric_slot_count(program, 0), Some(0))
  let closure = @context.stage_requirement_operations(requirements(program))
  let mut reductions = 0
  let mut domains = 0
  for i in 0..<@context.operation_closure_count(closure) {
    assert_true(pivot_numeric_slots_for_requirement(program, i) is None)
    guard @context.operation_closure_at(closure, i)
      is Some(ExecutionCheck(PivotExecution(check))) else {
      continue
    }
    match check.rule {
      EvaluatePivot => reductions += 1
      ValidatePivotResult => domains += 1
      PartitionPivot => ()
      CaptureNumericObservations(_) =>
        fail("exact decimal acquired floating profile")
    }
  }
  assert_eq((reductions, domains), (1, 1))
}

///|
test "formal global empty-axis pivot retains execution and profile checks for empty values input" {
  for rows in ["[]", "[{\"id\":0}]"] {
    let checked : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=checked,
      generated_rows=Some(rows),
      numeric_profile=Some(numeric_profile_fixture()),
      producer_suffix=",{\"derive\":{\"kind\":\"CAST(NULL AS STRING)\"}},{\"pivot\":{\"index\":[],\"column\":\"kind\",\"values\":[],\"value\":\"value\",\"aggregate\":\"sum\",\"fill\":0}},{\"derive\":{\"id\":{\"literal\":1},\"value\":{\"literal\":2}},\"as\":\"pivoted\"}",
      producer_result_from="pivoted",
      extra_step_budget=5,
    )
    let program = checked[0]
    assert_eq(unit_pivot_numeric_slot_count(program, 0), Some(0))
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut captures = 0
    let mut evaluations = 0
    for i in 0..<@context.operation_closure_count(closure) {
      guard @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(PivotExecution(check))) else {
        continue
      }
      match check.rule {
        CaptureNumericObservations(_) => {
          captures += 1
          let bundle = pivot_numeric_slots_for_requirement(program, i).unwrap()
          assert_eq(pivot_numeric_slot_count(bundle), 0)
        }
        EvaluatePivot => evaluations += 1
        _ => ()
      }
    }
    assert_eq((captures, evaluations), (1, 1))
  }
}
