///|
test "row target binding preserves exact producer, target and work across stages" {
  let root = pipeline(
    "[{\"take\":7},{\"filter\":{\"literal\":true}},{\"select\":[\"id\"]}]",
  )
  let seed = proof("actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}")
  let bound = @capacity_program_step.check(root, 0, seed).unwrap()
  let middle = consume(root, @pipeline.Step(2), "[]")
  let consumer = consume(middle, @pipeline.Input(0), "[{\"drop\":[]}]")
  for
    (p, target, work) in [
      (root, @pipeline.Step(0), 1),
      (root, @pipeline.Step(2), 3),
      (middle, @pipeline.Input(0), 4),
      (consumer, @pipeline.Step(0), 6),
    ] {
    let v = @capacity_program_step.check_target_rows(p, target, bound, work).unwrap()
    assert_true(
      physical_equal(@capacity_program_step.target_rows_pipeline(v), p),
    )
    assert_eq(@capacity_program_step.target_rows_target(v), target)
    assert_true(
      physical_equal(@capacity_program_step.target_rows_bound(v), bound),
    )
    assert_eq(@capacity_program_step.target_rows_value(v), 7L)
    assert_eq(@capacity_program_step.target_rows_work(v), work)
    let (measured, measured_work) = @capacity_program_step.check_target_rows_usage(
      p, target, bound, work,
    )
    assert_true(measured is Ok(_))
    assert_eq(measured_work, work)
    let (short, short_work) = @capacity_program_step.check_target_rows_usage(
      p,
      target,
      bound,
      work - 1,
    )
    assert_true(short is Err(@capacity_program_step.WorkLimit))
    assert_eq(short_work, work - 1)
    assert_eq(
      @capacity_program_step.check_target_rows(p, target, bound, work - 1).unwrap_err(),
      @capacity_program_step.WorkLimit,
    )
  }
  let foreign = pipeline("[{\"take\":7}]")
  let foreign_bound = @capacity_program_step.check(foreign, 0, seed).unwrap()
  let (unrelated, rejected_work) = @capacity_program_step.check_target_rows_usage(
    root,
    @pipeline.Step(2),
    foreign_bound,
    100,
  )
  assert_true(unrelated is Err(_))
  assert_true(rejected_work >= 3)
  assert_true(
    @capacity_program_step.check_target_rows(
      root,
      @pipeline.Step(0),
      foreign_bound,
      100,
    )
    is Err(_),
  )
  assert_eq(
    @capacity_program_step.check_target_rows(
      root,
      @pipeline.Input(0),
      bound,
      100,
    ).unwrap_err(),
    @capacity_program_step.MissingProducer,
  )
  for
    target in [
      @pipeline.Step(-1),
      @pipeline.Step(3),
      @pipeline.Input(-1),
      @pipeline.Input(1),
    ] {
    assert_eq(
      @capacity_program_step.check_target_rows(root, target, bound, 100).unwrap_err(),
      @capacity_program_step.InvalidTarget,
    )
  }
  assert_eq(
    @capacity_program_step.check_target_rows(root, @pipeline.Step(0), bound, -1).unwrap_err(),
    @capacity_program_step.InvalidLimits,
  )
}

///|
test "row target binding rejects expansion and retains zero bounds without inventing rows" {
  let root = pipeline(
    "[{\"take\":7},{\"select\":[\"id\"]},{\"unnest\":{\"column\":\"id\",\"as\":\"x\"}}]",
    field_type=@contract.array_contract(
      @contract.primitive(NumberType, nullable=false),
      nullable=false,
      max_items=Some(2L),
    ).unwrap(),
  )
  let bound = @capacity_program_step.check(
    root,
    0,
    proof("actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}"),
  ).unwrap()
  let retained = @capacity_program_step.check_target_rows(
    root,
    @pipeline.Step(1),
    bound,
    10,
  ).unwrap()
  assert_eq(@capacity_program_step.target_rows_value(retained), 7L)
  assert_eq(
    @capacity_program_step.check_target_rows(root, @pipeline.Step(2), bound, 10).unwrap_err(),
    @capacity_program_step.UnrelatedBound,
  )
  let empty = graph_measure_pipeline(
    "[" + graph_seed("empty", 0) + ",{\"filter\":{\"literal\":true}}]",
  )
  let empty_bound = @capacity_program_step.check(
    empty,
    0,
    proof("actql.bound.values", 0, "{\"op\":\"source\"}"),
  ).unwrap()
  let zero = @capacity_program_step.check_target_rows(
    empty,
    @pipeline.Step(1),
    empty_bound,
    2,
  ).unwrap()
  assert_eq(@capacity_program_step.target_rows_value(zero), 0L)
}

///|
test "row target binding traverses long producer chains without recursion" {
  let root = pipeline("[{\"take\":1}]")
  let bound = @capacity_program_step.check(
    root,
    0,
    proof("actql.bound.take", 1, "{\"maximum\":1,\"op\":\"clamp\"}"),
  ).unwrap()
  let mut owner = root
  let mut target = @pipeline.Step(0)
  for _ in 0..<1000 {
    owner = consume(owner, target, "[]")
    target = @pipeline.Input(0)
  }
  let checked = @capacity_program_step.check_target_rows(
    owner, target, bound, 1001,
  ).unwrap()
  assert_eq(@capacity_program_step.target_rows_work(checked), 1001)
  assert_eq(
    @capacity_program_step.check_target_rows(owner, target, bound, 1000).unwrap_err(),
    @capacity_program_step.WorkLimit,
  )
}
