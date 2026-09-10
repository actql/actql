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
fn limits() -> @calendar_options.Limits {
  { max_work: 10000, max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, }
}

///|
test "calendar units require a weekday exactly for weeks" {
  for name in ["day", "week", "month", "quarter", "year"] {
    for
      weekday in [
        "", ",\"week_start\":\"monday\"", ",\"week_start\":\"sunday\"",
      ] {
      let body = cursor(
        "{\"time\":\"left.created_at\",\"into\":\"bucket\",\"unit\":\"" +
        name +
        "\",\"timezone\":\"UTC\"" +
        weekday +
        "}",
      )
      let result = @calendar_options.read(Bucket, body, None, limits())
      assert_eq(result is Ok(_), (name == "week") != (weekday == ""))
      if result is Ok(v) {
        assert_true(
          @calendar_options.input(v)
          is Field(time="left.created_at", into="bucket"),
        )
        assert_eq(@calendar_options.timezone(v), "UTC")
      }
    }
  }
}

///|
test "calendar series validates civil years and exact timestamp syntax" {
  for
    (start, end, accepted) in [
      ("0001-01-01T00:00:00.000Z", "0001-01-01T00:00:00.000Z", true),
      ("2000-02-29T00:00:00.000Z", "9999-12-31T23:59:59.999Z", true),
      ("0000-01-01T00:00:00.000Z", "2000-01-01T00:00:00.000Z", false),
      ("1900-02-29T00:00:00.000Z", "2000-01-01T00:00:00.000Z", false),
      ("2001-01-01T00:00:00.000Z", "2000-01-01T00:00:00.000Z", false),
      ("2000-01-01T00:00:00Z", "2001-01-01T00:00:00.000Z", false),
    ] {
    assert_eq(
      @calendar_options.read(
        Series,
        cursor(
          "{\"unit\":\"month\",\"timezone\":\"UTC\",\"start\":\"" +
          start +
          "\",\"end\":\"" +
          end +
          "\"}",
        ),
        None,
        limits(),
      )
      is Ok(_),
      accepted,
    )
  }
}

///|
test "calendar range Parameters require non-null timestamps without reading defaults" {
  let params = @parameter.read_declarations(
    Some(
      cursor(
        "{\"start\":{\"type\":\"timestamp\"},\"nullable\":{\"type\":\"timestamp\",\"nullable\":true},\"text\":{\"type\":\"string\"}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  for name in ["start", "nullable", "text", "missing"] {
    let result = @calendar_options.read(
      Series,
      cursor(
        "{\"unit\":\"day\",\"timezone\":\"UTC\",\"start\":{\"$param\":\"" +
        name +
        "\"},\"end\":\"2000-01-01T00:00:00.000Z\"}",
      ),
      Some(params),
      limits(),
    )
    assert_eq(result is Ok(_), name == "start")
    if result is Ok(v) {
      assert_true(
        @calendar_options.input(v) is Range(start=Parameter("start"), ..),
      )
    }
  }
}

///|
test "calendar option admission retains zone spelling without claiming membership" {
  let body = cursor(
    "{\"unit\":\"year\",\"timezone\":\"Not/ARegisteredZone\",\"time\":\"timestamp\",\"into\":\"year\"}",
  )
  let options = @calendar_options.read(Bucket, body, None, limits()).unwrap()
  assert_eq(@calendar_options.timezone(options), "Not/ARegisteredZone")
  let u = @calendar_options.usage(options)
  let exact : @calendar_options.Limits = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(@calendar_options.read(Bucket, body, None, exact) is Ok(_))
  for
    small in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
      { ..exact, max_depth: 0, },
    ] {
    assert_true(@calendar_options.read(Bucket, body, None, small) is Err(_))
  }
}

///|
test "calendar selectors are literal and bodies reject hidden host options" {
  for
    body in [
      "{\"unit\":\"DAY\",\"timezone\":\"UTC\",\"time\":\"t\",\"into\":\"b\"}", "{\"unit\":\"day\",\"timezone\":{\"$param\":\"zone\"},\"time\":\"t\",\"into\":\"b\"}",
      "{\"unit\":\"day\",\"timezone\":\"\",\"time\":\"t\",\"into\":\"b\"}", "{\"unit\":\"day\",\"timezone\":\"UTC\",\"time\":\"t\",\"into\":\"left.b\"}",
      "{\"unit\":\"week\",\"timezone\":\"UTC\",\"week_start\":null,\"time\":\"t\",\"into\":\"b\"}",
      "{\"unit\":\"day\",\"timezone\":\"UTC\",\"fold\":\"later\",\"time\":\"t\",\"into\":\"b\"}",
    ] {
    assert_true(
      @calendar_options.read(Bucket, cursor(body), None, limits()) is Err(_),
    )
  }
}
