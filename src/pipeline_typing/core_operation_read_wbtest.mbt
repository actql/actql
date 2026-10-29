///|
fn operation_original_fixture(source : @decode.Cursor) -> PipelineCoreRead {
  let read = original_core_fixture(source)
  while pipeline_core_read_phase(read) != Steps &&
        pipeline_core_read_phase(read) != Failed {
    let _ = advance_pipeline_core_read(read)
  }
  read
}

///|
test "original operation continuation advances one body on the same Budget evidence and previous current" {
  let source = evidence_read_cursor(
    "[{\"derive\":{\"n1\":\"id + 1\"}},{\"derive\":{\"n2\":\"n1 + 2\"}},{\"select\":[\"n2\"]}]",
  )
  let read = operation_original_fixture(source)
  guard read.state is Reading(body) else {
    abort("original operation expected")
  }
  let budget = body.b
  let names = body.names
  let steps = body.steps.unwrap()
  let keyed = body.keyed_steps.unwrap()
  let ranked = body.ranked_steps.unwrap()
  let delta = body.delta_steps.unwrap()
  let mut work = pipeline_core_read_consumed_work(read).unwrap()
  for index, fields in [2, 3, 1] {
    assert_eq(steps.length(), index)
    let expected : PipelineCoreReadPhase = if index == 2 {
      FinalEvidence
    } else {
      Steps
    }
    assert_true(advance_pipeline_core_read(read) == expected)
    assert_eq(steps.length(), index + 1)
    assert_eq(body.current, Some(Step(index)))
    assert_true(physical_equal(body.b, budget))
    assert_true(physical_equal(body.names, names))
    assert_true(physical_equal(body.steps.unwrap(), steps))
    assert_true(physical_equal(body.keyed_steps.unwrap(), keyed))
    assert_true(physical_equal(body.ranked_steps.unwrap(), ranked))
    assert_true(physical_equal(body.delta_steps.unwrap(), delta))
    assert_true(physical_equal(steps[index].source, body.bodies[index]))
    let rows = @carrier.relation_rows(steps[index].output).unwrap()
    assert_eq(@carrier.field_count(rows), fields)
    let spent = pipeline_core_read_consumed_work(read).unwrap()
    assert_true(spent > work)
    work = spent
  }
  assert_true(advance_pipeline_core_read(read) == Complete)
  let checked = take_pipeline_core_read(read).unwrap().unwrap()
  assert_eq(step_count(checked), 3)
  assert_eq(current(checked), Some(Step(2)))
  let rows = @carrier.relation_rows(output_carrier(checked).unwrap()).unwrap()
  assert_eq(@carrier.field_at(rows, 0).unwrap().name, @schema.Unqualified("n2"))
  assert_true(physical_equal(checked.steps, steps))
  assert_true(physical_equal(checked.names, names))
}

///|
test "original later operation refusal retains completed prefix without inventing failed child work or running the tail" {
  let source = evidence_read_cursor(
    "[{\"derive\":{\"n1\":\"id + 1\"}},{\"nope\":{}},{\"derive\":{\"never\":\"n1 + 3\"}}]",
  )
  let read = operation_original_fixture(source)
  guard read.state is Reading(body) else {
    abort("original operation expected")
  }
  assert_true(advance_pipeline_core_read(read) == Steps)
  let first = body.steps.unwrap()[0]
  let spent = pipeline_core_read_consumed_work(read).unwrap()
  assert_true(advance_pipeline_core_read(read) == Failed)
  guard read.state is Rejected(original, issue) else {
    abort("typed original refusal expected")
  }
  assert_eq(issue.kind, UnsupportedOperation("nope"))
  assert_true(physical_equal(original, body))
  assert_eq(body.steps.unwrap().length(), 1)
  assert_true(physical_equal(body.steps.unwrap()[0], first))
  assert_eq(body.current, Some(Step(0)))
  assert_true(body.limits.max_work - body.b.work >= spent)
  assert_true(pipeline_core_read_consumed_work(read) is None)
  let remaining = body.b.work
  assert_true(advance_pipeline_core_read(read) == Failed)
  assert_eq(body.b.work, remaining)
  clear_pipeline_core_read(read)
  assert_true(advance_pipeline_core_read(read) == Cleared)
}

///|
test "empty operation table completes once and clear after one original operation never visits remaining bodies" {
  let empty = operation_original_fixture(evidence_read_cursor("[]"))
  guard empty.state is Reading(empty_body) else {
    abort("empty original expected")
  }
  let work = pipeline_core_read_consumed_work(empty)
  let current = empty_body.current
  assert_true(advance_pipeline_core_read(empty) == FinalEvidence)
  assert_eq(pipeline_core_read_consumed_work(empty), work)
  assert_eq(empty_body.current, current)
  clear_pipeline_core_read(empty)
  let read = operation_original_fixture(
    evidence_read_cursor("[{\"derive\":{\"n1\":\"id + 1\"}},{\"nope\":{}}]"),
  )
  guard read.state is Reading(body) else {
    abort("original operation expected")
  }
  assert_true(advance_pipeline_core_read(read) == Steps)
  assert_eq(body.steps.unwrap().length(), 1)
  let work = body.b.work
  clear_pipeline_core_read(read)
  assert_true(advance_pipeline_core_read(read) == Cleared)
  assert_eq(body.steps.unwrap().length(), 1)
  assert_eq(body.b.work, work)
  assert_true(pipeline_core_read_consumed_work(read) is None)
}
