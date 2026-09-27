///|
fn stepped_numeric_execution(
  operation : @numeric.Operation,
) -> NumericAggregateExecution {
  let profile = @numeric.builtin_profile()
  let reduction = @numeric.select(
    profile,
    @numeric.member_cid_at(profile, 0).unwrap(),
  ).unwrap()
  numeric_aggregate_execution_with_steps(
    (_step, _name, _occurrence, contributors, expected, max_work) => {
      Some(
        @numeric.execute(reduction, operation, contributors, expected, max_work),
      )
    },
    (_step, _name, _count) => true,
    (_step, _name, _occurrence, contributors, expected, max_work) => {
      match
        @numeric.start_reduction(
          reduction, operation, contributors, expected, max_work,
        ) {
        Err(issue) => Some(Err(issue))
        Ok(state) =>
          Some(
            Ok(
              numeric_aggregate_step(
                () => Some(@numeric.advance_reduction(state)),
                () => {
                  @numeric.close_reduction(state)
                  true
                },
              ),
            ),
          )
      }
    },
  )
}

///|
fn drain_numeric(
  values : Array[Value],
  execution : NumericAggregateExecution,
  control : ControlBudget,
) -> (Result[Value, RowIssue], Bool) {
  let state = start_aggregate_numeric(
    values,
    execution,
    1,
    "total",
    0,
    control,
    { limit: 100, live: 0, peak: 0, },
  )
  let mut at_most_one = true
  while true {
    let before = control.remaining
    let step = advance_aggregate_numeric(state)
    if before - control.remaining > 1 {
      at_most_one = false
    }
    match step {
      Ok(None) => ()
      Ok(Some(value)) => break (Ok(value), at_most_one)
      Err(issue) => break (Err(issue), at_most_one)
    }
  } nobreak {
    (Err(InvalidRows), at_most_one)
  }
}

///|
test "numeric steps pay the reported reduction work one unit per advance" {
  let values : Array[Value] = [Number(1.5), Number(2.5), Number(4.0)]
  let execution = stepped_numeric_execution(@numeric.Sum)
  let reference = @numeric.execute(
    @numeric.select(
      @numeric.builtin_profile(),
      @numeric.member_cid_at(@numeric.builtin_profile(), 0).unwrap(),
    ).unwrap(),
    @numeric.Sum,
    [1.5, 2.5, 4.0],
    3,
    1000,
  ).unwrap()
  let work = @numeric.outcome_work(reference)
  let exact : ControlBudget = { remaining: work, max_frames: 0, }
  let (value, at_most_one) = drain_numeric(values, execution, exact)
  assert_true(value is Ok(Number(8.0)))
  assert_true(at_most_one)
  assert_eq(exact.remaining, 0)
  let short : ControlBudget = { remaining: work - 1, max_frames: 0, }
  let (failed, _) = drain_numeric(values, execution, short)
  assert_true(failed is Err(RowLimit))
  let (rejected, _) = drain_numeric([Number(1.0), Null], execution, {
    remaining: 100,
    max_frames: 0,
  })
  assert_true(rejected is Err(InvalidRows))
}
