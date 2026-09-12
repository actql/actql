///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 100,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn limits() -> @time_series.Limits {
  { max_work: 1000, max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, }
}

///|
test "literal series endpoints retain canonical timestamp semantics and an empty interval" {
  for end in ["0000-02-29T00:00:00.000Z", "9999-12-31T23:59:59.999Z"] {
    let source = cursor(
      "{\"start\":\"0000-02-29T00:00:00.000Z\",\"end\":\"" +
      end +
      "\",\"step\":\"1d\"}",
    )
    let checked = @time_series.check(source, None, limits()).unwrap()
    assert_true(
      @time_series.start(checked) is Literal("0000-02-29T00:00:00.000Z"),
    )
    assert_true(@time_series.step(checked) is Literal(86400000L))
    let rows = @carrier.relation_rows(@time_series.output(checked)).unwrap()
    assert_eq(@carrier.field_count(rows), 1)
    assert_true(
      @carrier.lookup(rows, Unqualified("time"))
      is Present({ contract: Some({ shape: Timestamp, nullable: false, }), .. }),
    )
    let u = @time_series.usage(checked)
    let cap = limits()
    let exact : @time_series.Limits = {
      ..cap,
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(@time_series.check(source, None, exact) is Ok(_))
    assert_true(
      @time_series.check(source, None, {
        ..exact,
        max_text_bytes: u.text_bytes - 1,
      })
      is Err(_),
    )
  }
  let issue = @time_series.check(
    cursor(
      "{\"start\":\"2000-01-02T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.000Z\",\"step\":1}",
    ),
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, @time_series.ReversedRange)
  assert_eq(issue.path, [@source.Key("end")])
}

///|
test "series endpoints reject noncanonical dates and defer timestamp parameter binding" {
  for
    start in [
      "1900-02-29T00:00:00.000Z", "2000-01-01", "2000-01-01T00:00:00Z", "2000-01-01T00:00:00.000+00:00",
    ] {
    assert_true(
      @time_series.check(
        cursor(
          "{\"start\":\"" +
          start +
          "\",\"end\":\"2001-01-01T00:00:00.000Z\",\"step\":1}",
        ),
        None,
        limits(),
      )
      is Err({ kind: InvalidTimestamp, .. }),
    )
  }
  let ds = @parameter.read_declarations(
    Some(
      cursor(
        "{\"start\":{\"type\":\"timestamp\"},\"step\":{\"type\":\"number\",\"default\":-1}}",
      ),
    ),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let checked = @time_series.check(
    cursor(
      "{\"start\":{\"$param\":\"start\"},\"end\":\"2001-01-01T00:00:00.000Z\",\"step\":{\"$param\":\"step\"}}",
    ),
    Some(ds),
    limits(),
  ).unwrap()
  let pending = indexed_obligation_copy(
    @time_series.pending_validations(checked),
    @time_series.pending_validation_count(checked),
    i => @time_series.pending_validation_at(checked, i),
    (a, b) => a == b,
  )
  assert_true(pending.contains(BindTimestamp("start")))
  assert_true(pending.contains(BindStep("step")))
  assert_true(pending.contains(ResolveRowBound))
}
