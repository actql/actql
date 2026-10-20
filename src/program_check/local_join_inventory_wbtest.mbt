///|
fn local_join_inventory_program(
  kind : String,
  parameter? : Bool = false,
  extra? : String = "",
) -> CheckedProgram raise {
  let checked : Array[CheckedProgram] = []
  ignore(
    local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      parameters=parameter,
      checked_results=checked,
      generated_rows=Some("[{\"id\":1},{\"id\":2}]"),
      producer_suffix=if kind == "full" {
        ",{\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"asserted\"}"
      } else {
        ""
      },
      producer_result_from=if kind == "full" { "asserted" } else { "derived" },
      extra_step_budget=if kind == "full" { 1 } else { 0 },
      second_stage=true,
      second_join_capacity=true,
      second_join_step=0,
      second_steps="[{\"join\":{\"with\":\"again\",\"kind\":\"" +
        kind +
        "\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"max_output_rows\":" +
        (if parameter { "{\"$param\":\"n\"}" } else { "4" }) +
        ",\"select\":{\"id\":\"left.id\",\"value\":\"left.value\"}" +
        extra +
        "},\"as\":\"joined\"}]",
      second_result_from="joined",
    ),
  ) catch {
    failure => {
      if diagnostic_pipeline_cause(failure) is Some(issue) {
        fail(
          "original Join fixture: " +
          @debug.to_string(issue.kind) +
          " at " +
          @debug.to_string(issue.path),
        )
      }
      fail(
        "original Join fixture category: " +
        @debug.to_string(classify_diagnostic_cause(failure)),
      )
    }
  }
  checked[0]
}

///|
test "keyed Join inventory retains both original inputs operation and runtime obligations" {
  for kind in ["inner", "left", "full", "semi", "anti"] {
    let owner = local_join_inventory_program(kind)
    let inventory = local_program_completion_free_inventory(owner).unwrap()
    assert_true(local_completion_free_inventory_uses_join(inventory))
    assert_true(local_completion_free_inventory_matches(inventory, owner))
    let pipeline = owner.units[1].pipeline
    let operation = @pipeline.step_at(pipeline, 0).unwrap().operation
    let closure = @context.stage_requirement_operations(owner.requirements)
    assert_true(
      audit_local_completion_free_join(
        operation,
        pipeline,
        0,
        None,
        closure,
        10000,
      )
      is Some(_),
    )
    let foreign = local_join_inventory_program(kind)
    let other = @pipeline.step_at(foreign.units[1].pipeline, 0).unwrap().operation
    assert_false(local_completion_free_inventory_matches(inventory, foreign))
    assert_true(
      audit_local_completion_free_join(other, pipeline, 0, None, closure, 10000)
      is None,
    )
    assert_true(
      audit_local_completion_free_join(
        operation,
        pipeline,
        1,
        None,
        closure,
        10000,
      )
      is None,
    )
  }
}

///|
test "keyed Join indexed traversal keeps its exact finite work refusal" {
  let owner = local_join_inventory_program(
    "full",
    extra=",\"null_key\":\"fail\",\"cardinality\":\"one_to_one\"",
  )
  let pipeline = owner.units[1].pipeline
  let operation = @pipeline.step_at(pipeline, 0).unwrap().operation
  let closure = @context.stage_requirement_operations(owner.requirements)
  let left = audit_local_completion_free_join(
    operation,
    pipeline,
    0,
    None,
    closure,
    10000,
  ).unwrap()
  let exact = 10000 - left
  assert_true(exact > 0)
  assert_eq(
    audit_local_completion_free_join(
      operation,
      pipeline,
      0,
      None,
      closure,
      exact,
    ),
    Some(0),
  )
  assert_true(
    audit_local_completion_free_join(
      operation,
      pipeline,
      0,
      None,
      closure,
      exact - 1,
    )
    is None,
  )
}

///|
test "Join Parameter guard retains the original Default and scalar resolution" {
  let owner = local_join_inventory_program("inner", parameter=true)
  let pipeline = owner.units[1].pipeline
  let operation = @pipeline.step_at(pipeline, 0).unwrap().operation
  let stage = @context.program_identity_stage_at(owner.identity, 0).unwrap()
  let values = @parameter_refs.bound_values(
    @context.stage_identity_parameter_values(stage),
  )
  let closure = @context.stage_requirement_operations(owner.requirements)
  assert_true(
    audit_local_completion_free_join(
      operation,
      pipeline,
      0,
      Some(values),
      closure,
      10000,
    )
    is Some(_),
  )
  assert_true(
    audit_local_completion_free_join(
      operation,
      pipeline,
      0,
      None,
      closure,
      10000,
    )
    is None,
  )
  let foreign = local_join_inventory_program("inner", parameter=true)
  assert_true(
    audit_local_completion_free_join(
      operation,
      pipeline,
      0,
      Some(values),
      @context.stage_requirement_operations(foreign.requirements),
      10000,
    )
    is None,
  )
}
