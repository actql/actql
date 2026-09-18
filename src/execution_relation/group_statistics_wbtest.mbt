///|
fn statistical_group(raw : String) -> GeneratedSequence raise {
  let owner = bound_pipeline(raw)
  prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["group_1"],
    100000,
    10000,
  ).unwrap()
}

///|
fn run_statistical_group(raw : String) -> Table raise {
  let result = execute_generated_sequence(statistical_group(raw), [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  test_row_output(completed_output(result, Step(1)).unwrap())
}

///|
test "direct percentiles use their closed discrete and interpolation laws" {
  let table = run_statistical_group(
    (
      #|[{"values":{"schema":{"n":{"type":"number","nullable":true},"label":{"type":"string","nullable":true}},"rows":[{"n":4,"label":{"literal":"d"}},{"n":null,"label":null},{"n":1,"label":{"literal":"a"}},{"n":3,"label":{"literal":"c"}},{"n":2,"label":{"literal":"b"}}]},"as":"seed"},{"group":{"by":[],"aggregates":{"continuous":{"fn":"percentile_cont","field":"n","fraction":0.5},"discrete":{"fn":"percentile_disc","field":"label","fraction":0.5}}}}]
    ),
  )
  assert_eq(table.names, ["continuous", "discrete"])
  assert_eq(table.rows.length(), 1)
  assert_true(table.rows[0][0] is Number(2.5))
  assert_true(table.rows[0][1] is Text("b"))
}

///|
test "direct percentile endpoints and empty inputs retain typed laws" {
  let endpoints = run_statistical_group(
    (
      #|[{"values":{"schema":{"n":{"type":"number","nullable":true}},"rows":[{"n":null},{"n":3},{"n":1},{"n":2}]},"as":"seed"},{"group":{"by":[],"aggregates":{"high":{"fn":"percentile_cont","field":"n","fraction":1},"low":{"fn":"percentile_disc","field":"n","fraction":0}}}}]
    ),
  )
  assert_true(endpoints.rows[0][0] is Number(3))
  assert_true(endpoints.rows[0][1] is Number(1))
  let empty = run_statistical_group(
    (
      #|[{"values":{"schema":{"n":{"type":"number","nullable":true}},"rows":[{"n":null}]},"as":"seed"},{"group":{"by":[],"aggregates":{"continuous":{"fn":"percentile_cont","field":"n","fraction":0.5},"discrete":{"fn":"percentile_disc","field":"n","fraction":0.5}}}}]
    ),
  )
  assert_true(empty.rows[0][0] is Null)
  assert_true(empty.rows[0][1] is Null)
}

///|
test "direct statistics use population and sample divisors" {
  let table = run_statistical_group(
    (
      #|[{"values":{"schema":{"n":{"type":"number","nullable":true}},"rows":[{"n":3},{"n":null},{"n":1},{"n":2}]},"as":"seed"},{"group":{"by":[],"aggregates":{"population":{"fn":"var_pop","field":"n"},"population_deviation":{"fn":"stddev_pop","field":"n"},"sample":{"fn":"var_samp","field":"n"},"sample_deviation":{"fn":"stddev_samp","field":"n"}}}}]
    ),
  )
  assert_eq(table.names, [
    "population", "population_deviation", "sample", "sample_deviation",
  ])
  assert_true(table.rows[0][0] is Number(0.6666666666666666))
  assert_true(table.rows[0][1] is Number(0.816496580927726))
  assert_true(table.rows[0][2] is Number(1))
  assert_true(table.rows[0][3] is Number(1))
}

///|
test "statistical folds use value identity order instead of input order" {
  let prefix =
    #|[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":
  let suffix =
    #|},"as":"seed"},{"group":{"by":[],"aggregates":{"deviation":{"fn":"stddev_pop","field":"n"},"variance":{"fn":"var_pop","field":"n"}}}}]
  let forward_rows =
    #|[{"n":10000000000000000},{"n":1},{"n":-10000000000000000},{"n":3}]
  let reverse_rows =
    #|[{"n":3},{"n":-10000000000000000},{"n":1},{"n":10000000000000000}]
  let forward = run_statistical_group(prefix + forward_rows + suffix)
  let reverse = run_statistical_group(prefix + reverse_rows + suffix)
  guard forward.rows[0][0] is Number(forward_deviation) &&
    forward.rows[0][1] is Number(forward_variance) &&
    reverse.rows[0][0] is Number(reverse_deviation) &&
    reverse.rows[0][1] is Number(reverse_variance) else {
    fail("numeric statistical output expected")
  }
  assert_eq(forward_deviation, reverse_deviation)
  assert_eq(forward_variance, reverse_variance)
}

///|
test "sample statistics reject insufficient cardinality with null" {
  let table = run_statistical_group(
    (
      #|[{"values":{"schema":{"n":{"type":"number","nullable":true}},"rows":[{"n":7}]},"as":"seed"},{"group":{"by":[],"aggregates":{"population":{"fn":"var_pop","field":"n"},"sample":{"fn":"var_samp","field":"n"},"sample_deviation":{"fn":"stddev_samp","field":"n"}}}}]
    ),
  )
  assert_true(table.rows[0][0] is Number(0))
  assert_true(table.rows[0][1] is Null)
  assert_true(table.rows[0][2] is Null)
}

///|
test "statistical nonfinite intermediates fail without output" {
  let variance = statistical_group(
    (
      #|[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":1e308},{"n":1e308}]},"as":"seed"},{"group":{"by":[],"aggregates":{"result":{"fn":"var_pop","field":"n"}}}}]
    ),
  )
  let limits = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  assert_true(
    execute_generated_sequence(variance, [], limits)
    is Err(Rows(1, Aggregation(ArithmeticFailure))),
  )
  let percentile = statistical_group(
    (
      #|[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":-1e308},{"n":1e308}]},"as":"seed"},{"group":{"by":[],"aggregates":{"result":{"fn":"percentile_cont","field":"n","fraction":0.5}}}}]
    ),
  )
  assert_true(
    execute_generated_sequence(percentile, [], limits)
    is Err(Rows(1, Aggregation(ArithmeticFailure))),
  )
}

///|
test "statistical group shares bounded work across all folds" {
  let generated = statistical_group(
    (
      #|[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":1},{"n":2},{"n":3},{"n":4}]},"as":"seed"},{"group":{"by":[],"aggregates":{"continuous":{"fn":"percentile_cont","field":"n","fraction":0.5},"variance":{"fn":"var_pop","field":"n"}}}}]
    ),
  )
  let generous = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  assert_true(execute_generated_sequence(generated, [], generous) is Ok(_))
  assert_true(
    execute_generated_sequence(generated, [], { ..generous, max_work: 1, })
    is Err(_),
  )
}
