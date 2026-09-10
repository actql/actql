///|
test "sequence consumes Events and exposes generated typed fields to later expressions" {
  let p = @pipeline_typing.check(
    cursor(
      "[{\"to_events\":{\"id\":\"id\",\"time\":\"amount\"}},{\"sequence\":{\"by\":[\"id\"],\"id\":\"id\",\"time\":\"amount\",\"pattern\":[{\"as\":\"start\",\"where\":\"amount > 0\"},{\"as\":\"end\",\"where\":{\"literal\":true}}],\"within\":1000,\"overlap\":\"allow\",\"contiguity\":\"adjacent\"},\"as\":\"matches\"},{\"derive\":{\"elapsed\":\"match_end_ms - match_start_ms\"}}]",
    ),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  let step = @pipeline_typing.step_at(p, 1).unwrap()
  assert_eq(@pipeline_typing.input_occurrences(step).map(e => e.target), [
    Step(0),
  ])
  assert_eq(@pipeline_typing.lookup(p, "matches"), Some(Step(1)))
  match step.operation {
    Sequence(c) => {
      assert_eq(@relation.sequence_overlap(c), Allow)
      assert_eq(@relation.sequence_pattern(c).length(), 2)
      assert_true(@relation.sequence_output_guard(c) is None)
    }
    _ => fail("expected sequence")
  }
  let output = @pipeline_typing.output_schema(p).unwrap()
  assert_true(
    @schema.lookup(output, Unqualified("start_id")).unwrap().shape
    is @contract.Text(_),
  )
  assert_true(
    @schema.lookup(output, Unqualified("elapsed")).unwrap().shape
    is @contract.Number,
  )
}

///|
test "sequence pipeline preserves nested predicate error paths and ranges" {
  let bad = @pipeline_typing.check(
    cursor(
      "[{\"sequence\":{\"by\":[\"id\"],\"id\":\"id\",\"time\":\"amount\",\"pattern\":[{\"as\":\"start\",\"where\":\"amount > missing\"},{\"as\":\"end\",\"where\":{\"literal\":true}}],\"within\":1000,\"overlap\":\"allow\",\"contiguity\":\"adjacent\"}}]",
    ),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(bad.kind, Operation(UnknownField("missing")))
  assert_eq(bad.path, [
    Index(0),
    Key("sequence"),
    Key("pattern"),
    Index(0),
    Key("where"),
  ])
  assert_true(bad.range is Some(_))
}
