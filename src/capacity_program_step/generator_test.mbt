///|
fn generator_pipeline(
  body : String,
  parameters? : @parameter.Declarations? = None,
  profile? : @calendar_profile.Profile? = None,
) -> @pipeline.CheckedPipeline {
  @pipeline.check_carriers(
    cursor("[{" + body + ",\"as\":\"generated\"}]"),
    [],
    parameters,
    None,
    {
      max_steps: 1,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
    calendar_profile=profile,
  ).unwrap()
}

///|
test "values source bounds retain exact authored row occurrences and cell obligations" {
  let declarations = count_declarations()
  for count in [0, 1, 5] {
    let rows = Array::makei(count, _ => "{\"id\":{\"$param\":\"n\"}}").join(",")
    let p = generator_pipeline(
      "\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
      rows +
      "]}",
      parameters=Some(declarations),
    )
    let claim = proof(
      "actql.bound.values",
      count.to_int64(),
      "{\"op\":\"source\"}",
    )
    let app = @capacity_program_step.check(p, 0, claim).unwrap()
    assert_eq(@capacity_program_step.input_count(app), 0)
    let step = @pipeline.step_at(
      @capacity_program_step.checked_pipeline(app),
      0,
    ).unwrap()
    assert_eq(@pipeline.input_occurrence_count(step), 0)
    guard step.operation is Values(values) else { fail("values expected") }
    assert_eq(@values.row_count(values), count)
    assert_eq(
      @values.pending_validations(values).contains(BindCell("n")),
      count > 0,
    )
    assert_true(
      @capacity_program_step.check(
        p,
        0,
        proof("actql.bound.values", count.to_int64() + 1, "{\"op\":\"source\"}"),
      )
      is Err(ValueMismatch),
    )
    assert_true(
      @capacity_program_step.check(
        p,
        0,
        proof(
          "actql.bound.global-group",
          count.to_int64(),
          "{\"op\":\"source\"}",
        ),
      )
      is Err(LawMismatch),
    )
    assert_true(
      @capacity_program_step.check_applications(
        program_claims([claim]),
        [app],
        max_work=3,
      )
      is Ok(_),
    )
  }
}

///|
test "time series source applications resolve bound timestamps and numeric or duration steps" {
  for duration in [false, true] {
    let d = @parameter.read_declarations(
      Some(
        cursor(
          "{\"a\":{\"type\":\"timestamp\",\"default\":\"2000-01-01T00:00:00.000Z\"},\"z\":{\"type\":\"timestamp\",\"default\":\"2000-01-01T00:00:00.010Z\"},\"s\":" +
          (if duration {
            "{\"type\":\"string\",\"format\":\"duration\",\"default\":\"3ms\"}"
          } else {
            "{\"type\":\"number\",\"default\":3}"
          }) +
          "}",
        ),
      ),
      {
        max_parameters: 3,
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      },
    ).unwrap()
    let p = generator_pipeline(
      "\"time_series\":{\"start\":{\"$param\":\"a\"},\"end\":{\"$param\":\"z\"},\"step\":{\"$param\":\"s\"}}",
      parameters=Some(d),
    )
    let claim = proof("actql.bound.time-series", 4, "{\"op\":\"source\"}")
    assert_true(
      @capacity_program_step.check(p, 0, claim) is Err(UnresolvedCount),
    )
    let values = count_values(d, None)
    let bindings = @capacity_program_step.bind_parameters(
      p,
      values,
      max_work=3,
      max_text_bytes=if duration { 6 } else { 3 },
    ).unwrap()
    let app = @capacity_program_step.check_with_inputs(
      p,
      0,
      claim,
      [],
      bindings=Some(bindings),
    ).unwrap()
    assert_true(
      physical_equal(
        @capacity_program_step.checked_bindings(app).unwrap(),
        bindings,
      ),
    )
    guard @pipeline.step_at(p, 0).unwrap().operation is TimeSeries(series) else {
      fail("series expected")
    }
    assert_true(
      @series.pending_validations(series).contains(BindTimestamp("a")),
    )
    assert_true(@series.pending_validations(series).contains(ResolveResources))
    let reversed = @capacity_program_step.bind_parameters(
      p,
      count_values(d, Some("{\"a\":\"2000-01-02T00:00:00.000Z\"}")),
      max_work=3,
      max_text_bytes=6,
    ).unwrap()
    assert_true(
      @capacity_program_step.check_with_inputs(
        p,
        0,
        claim,
        [],
        bindings=Some(reversed),
      )
      is Err(InvalidSeriesCount(@series.ReversedRange)),
    )
    let empty = @capacity_program_step.bind_parameters(
      p,
      count_values(d, Some("{\"z\":\"2000-01-01T00:00:00.000Z\"}")),
      max_work=3,
      max_text_bytes=6,
    ).unwrap()
    assert_true(
      @capacity_program_step.check_with_inputs(
        p,
        0,
        proof("actql.bound.time-series", 0, "{\"op\":\"source\"}"),
        [],
        bindings=Some(empty),
      )
      is Ok(_),
    )
    if !duration {
      for step in ["0", "-1", "0.5", "9007199254740992"] {
        let bad = @capacity_program_step.bind_parameters(
          p,
          count_values(
            d,
            Some("{\"z\":\"2000-01-01T00:00:00.000Z\",\"s\":" + step + "}"),
          ),
          max_work=3,
          max_text_bytes=3,
        ).unwrap()
        assert_true(
          @capacity_program_step.check_with_inputs(
            p,
            0,
            proof("actql.bound.time-series", 0, "{\"op\":\"source\"}"),
            [],
            bindings=Some(bad),
          )
          is Err(InvalidBoundMilliseconds("s")),
        )
      }
    }
  }
  for
    (end, expected) in [
      ("0000-01-01T00:00:00.000Z", 0L),
      ("9999-12-31T23:59:59.999Z", 315569519999999L),
    ] {
    let p = generator_pipeline(
      "\"time_series\":{\"start\":\"0000-01-01T00:00:00.000Z\",\"end\":\"" +
      end +
      "\",\"step\":1}",
    )
    assert_true(
      @capacity_program_step.check(
        p,
        0,
        proof("actql.bound.time-series", expected, "{\"op\":\"source\"}"),
      )
      is Ok(_),
    )
  }
}

///|
test "calendar series domain bounds retain selected profiles without claiming exact counts" {
  let text = "{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"coverage_end_ms\":253402300800000,\"coverage_start_ms\":-62135596800000,\"tzdb_version\":\"test-fixture\",\"version\":\"actql-tzdb-table/0.1\",\"zones\":{\"UTC\":{\"initial_offset_seconds\":0,\"transitions\":[]}}}"
  let profile = @calendar_profile.admit(
    @utf8.encode(text),
    "sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca",
    "test-fixture",
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 8,
      max_zones: 1,
      max_transitions: 0,
    },
  ).unwrap()
  for
    (unit, expected) in [
      ("day", 3652061L),
      ("week", 521725L),
      ("month", 119990L),
      ("quarter", 39998L),
      ("year", 10001L),
    ] {
    for empty in [false, true] {
      let p = generator_pipeline(
        "\"calendar_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"" +
        (if empty {
          "2000-01-01T00:00:00.000Z"
        } else {
          "2001-01-01T00:00:00.000Z"
        }) +
        "\",\"unit\":\"" +
        unit +
        "\",\"timezone\":\"UTC\"" +
        (if unit == "week" { ",\"week_start\":\"monday\"" } else { "" }) +
        "}",
        profile=Some(profile),
      )
      let bound = if empty { 0L } else { expected }
      let app = @capacity_program_step.check(
        p,
        0,
        proof("actql.bound.calendar-series", bound, "{\"op\":\"source\"}"),
      ).unwrap()
      guard @pipeline.step_at(@capacity_program_step.checked_pipeline(app), 0).unwrap().operation
        is Calendar(calendar) else {
        fail("calendar expected")
      }
      assert_true(physical_equal(@calendar.profile(calendar), profile))
      assert_true(
        @calendar.pending_validations(calendar).contains(ValidateBoundaryDomain),
      )
      assert_eq(@capacity_program_step.input_count(app), 0)
      assert_true(
        @capacity_program_step.check(
          p,
          0,
          proof("actql.bound.calendar-series", bound + 1, "{\"op\":\"source\"}"),
        )
        is Err(ValueMismatch),
      )
    }
  }
}
