///|
fn time_series_owner(
  body : String,
  declarations? : @parameter.Declarations? = None,
  bindings? : @parameter.BoundValues? = None,
) -> @lowering_relation.BoundPrepared {
  let checked = @pipeline.check(
    cursor("[{\"time_series\":" + body + ",\"as\":\"ticks\"}]"),
    [],
    declarations,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    bindings,
    max_parameters=3,
    max_name_bytes=3,
  ).unwrap()
}

///|
test "time series lowers a finite zero-input occurrence" {
  let owner = time_series_owner(
    "{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:02.500Z\",\"step\":1000}",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, {
    ..sequence_limits(),
    max_rows: 3,
    max_cells: 3,
  }).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.TimeSeriesStep(series)) else {
    fail("expected time-series step")
  }
  assert_eq(
    @lowering_relation.time_series_start(series),
    "2000-01-01T00:00:00.000Z",
  )
  assert_eq(
    @lowering_relation.time_series_end(series),
    "2000-01-01T00:00:02.500Z",
  )
  assert_eq(@lowering_relation.time_series_step(series), 1000L)
  assert_eq(@lowering_relation.time_series_row_count(series), 3)
  let occurrence = @lowering_relation.sequence_canonical_node_at(sequence, 0, 0).unwrap()
  assert_eq(
    (occurrence.id, occurrence.operation),
    ("time_series_0", "TEA.time_series"),
  )
  let writer = @encode.writer(1000, 100, 20)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"time_series_0\",\"in\":[],\"op\":\"TEA.time_series\",\"params\":{\"end\":\"2000-01-01T00:00:02.500Z\",\"start\":\"2000-01-01T00:00:00.000Z\",\"step\":1000}}]",
  )
}

///|
test "time series resolves exact bindings before canonical emission" {
  let declarations = @parameter.read_declarations(
    Some(
      cursor(
        "{\"a\":{\"type\":\"timestamp\"},\"z\":{\"type\":\"timestamp\"},\"s\":{\"type\":\"number\"}}",
      ),
    ),
    { max_parameters: 3, max_nodes: 30, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let bindings = match
    @parameter.bind(
      declarations,
      Some(
        cursor(
          "{\"a\":\"2000-02-28T00:00:00.000Z\",\"z\":\"2000-03-01T00:00:00.000Z\",\"s\":86400000}",
        ),
      ),
      { max_nodes: 10, max_depth: 5, max_text_bytes: 100, },
    ).unwrap() {
    @parameter.Ready(values) => values
    @parameter.NeedsBindings(_) => fail("missing time-series binding")
  }
  let owner = time_series_owner(
    "{\"start\":{\"$param\":\"a\"},\"end\":{\"$param\":\"z\"},\"step\":{\"$param\":\"s\"}}",
    declarations=Some(declarations),
    bindings=Some(bindings),
  )
  let exact = {
    ..sequence_limits(),
    max_rows: 2,
    max_cells: 2,
    max_bindings: 3,
    max_name_bytes: 3,
    expressions: { ..expression_limits(), max_work: 4, },
  }
  let sequence = @lowering_relation.prepare_sequence(owner, exact).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.TimeSeriesStep(series)) else {
    fail("expected time-series step")
  }
  assert_eq(@lowering_relation.time_series_row_count(series), 2)
  assert_eq(@lowering_relation.time_series_step(series), 86400000L)
  for
    constrained in [
      { ..exact, max_rows: 1, },
      { ..exact, max_cells: 1, },
      { ..exact, max_bindings: 2, },
      { ..exact, max_name_bytes: 2, },
      { ..exact, expressions: { ..exact.expressions, max_work: 3, }, },
    ] {
    assert_true(
      @lowering_relation.prepare_sequence(owner, constrained)
      is Err(
        @lowering_relation.TimeSeriesFailure(
          0,
          @lowering_relation.TimeSeriesPreparationLimit
        )
      ),
    )
  }
}

///|
test "empty time series still validates a bound positive step" {
  let declarations = @parameter.read_declarations(
    Some(cursor("{\"s\":{\"type\":\"number\"}}")),
    { max_parameters: 1, max_nodes: 10, max_depth: 5, max_text_bytes: 20, },
  ).unwrap()
  let bound = match
    @parameter.bind(declarations, Some(cursor("{\"s\":0}")), {
      max_nodes: 4,
      max_depth: 2,
      max_text_bytes: 10,
    }).unwrap() {
    @parameter.Ready(values) => values
    @parameter.NeedsBindings(_) => fail("missing step binding")
  }
  let owner = time_series_owner(
    "{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.000Z\",\"step\":{\"$param\":\"s\"}}",
    declarations=Some(declarations),
    bindings=Some(bound),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, sequence_limits())
    is Err(
      @lowering_relation.TimeSeriesFailure(
        0,
        @lowering_relation.InvalidTimeSeriesParameter("s")
      )
    ),
  )
}
