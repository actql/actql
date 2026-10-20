///|
fn local_take_operation(
  program : CheckedProgram,
) -> (@pipeline.CheckedPipeline, @relation.CheckedOperation) raise {
  let pipeline = program.units[0].pipeline
  for index in 0..<@pipeline.step_count(pipeline) {
    if @pipeline.step_at(pipeline, index).unwrap().operation
      is @pipeline.Unary(operation) &&
      @relation.operation(operation) is Take {
      return (pipeline, operation)
    }
  }
  fail("original checked Take missing")
}

///|
test "Take audit charges both literal roles under the original finite budget" {
  let program = checked_direct_program_fixture(
    take="{\"count\":1,\"offset\":0}",
  )
  let (pipeline, operation) = local_take_operation(program)
  let closure = @context.stage_requirement_operations(program.requirements)
  assert_eq(
    audit_local_completion_free_take(operation, pipeline, 1, None, closure, 2),
    Some(0),
  )
  assert_eq(
    audit_local_completion_free_take(operation, pipeline, 1, None, closure, 3),
    Some(1),
  )
  assert_true(
    audit_local_completion_free_take(operation, pipeline, 1, None, closure, 1)
    is None,
  )
}

///|
test "Take Parameter audit requires original pipeline step supplied binding and scalar resolution" {
  let program = checked_direct_program_fixture(
    take="{\"count\":{\"$param\":\"limit\"}}",
    supplied=Some(supplied_fixture("{\"limit\":1}")),
  )
  let (pipeline, operation) = local_take_operation(program)
  let stage = @context.program_identity_stage_at(program.identity, 0).unwrap()
  let values = @parameter_refs.bound_values(
    @context.stage_identity_parameter_values(stage),
  )
  let closure = @context.stage_requirement_operations(program.requirements)
  assert_true(
    audit_local_completion_free_take(
      operation,
      pipeline,
      1,
      Some(values),
      closure,
      10000,
    )
    is Some(_),
  )
  assert_true(
    audit_local_completion_free_take(
      operation,
      pipeline,
      0,
      Some(values),
      closure,
      10000,
    )
    is None,
  )
  assert_true(
    audit_local_completion_free_take(
      operation,
      pipeline,
      1,
      None,
      closure,
      10000,
    )
    is None,
  )
  assert_true(
    audit_local_completion_free_take(
      operation,
      pipeline,
      1,
      Some(values),
      closure,
      2,
    )
    is None,
  )
  let equal_program = checked_direct_program_fixture(
    take="{\"count\":{\"$param\":\"limit\"}}",
    supplied=Some(supplied_fixture("{\"limit\":1}")),
  )
  let (foreign_pipeline, _) = local_take_operation(equal_program)
  assert_true(
    audit_local_completion_free_take(
      operation,
      foreign_pipeline,
      1,
      Some(values),
      closure,
      10000,
    )
    is None,
  )
  assert_true(
    audit_local_completion_free_take(
      operation,
      pipeline,
      1,
      Some(values),
      @context.stage_requirement_operations(equal_program.requirements),
      10000,
    )
    is None,
  )
}
