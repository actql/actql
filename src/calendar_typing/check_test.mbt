///|
fn cursor(s : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(s, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 20,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 20,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn profile() -> @profile.Profile {
  let bytes = @utf8.encode(
    "{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"coverage_end_ms\":253402300800000,\"coverage_start_ms\":-62135596800000,\"tzdb_version\":\"test\",\"version\":\"actql-tzdb-table/0.1\",\"zones\":{\"UTC\":{\"initial_offset_seconds\":0,\"transitions\":[]}}}",
  )
  @profile.admit(bytes, "sha256:" + @sha.hex(bytes), "test", {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
    max_zones: 1,
    max_transitions: 0,
  }).unwrap()
}

///|
fn limits() -> @options.Limits {
  { max_work: 10000, max_nodes: 10000, max_depth: 20, max_text_bytes: 10000, }
}

///|
fn input(nullable : Bool, open : Bool) -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("time"),
          Some(@contract.primitive(TimestampType, nullable~)),
        ),
      ],
      field_set=if open { Open } else { Closed },
      max_fields=1,
      max_name_bytes=4,
    ).unwrap(),
  )
}

///|
test "bucket validates its clock and requires known output freshness" {
  let s = cursor(
    "{\"time\":\"time\",\"into\":\"bucket\",\"unit\":\"day\",\"timezone\":\"UTC\"}",
  )
  let checked = @calendar_typing.check(
    Bucket,
    s,
    Some(input(false, false)),
    None,
    Some(profile()),
    limits(),
  ).unwrap()
  assert_eq(@calendar_typing.cardinality(checked), PreserveInput)
  let rows = @carrier.relation_rows(@calendar_typing.output(checked)).unwrap()
  assert_eq(@carrier.field_count(rows), 2)
  assert_true(
    @carrier.lookup(rows, Unqualified("bucket"))
    is Present(
      { contract: Some({ nullable: false, shape: @contract.Object(_), }), .. }
    ),
  )
  assert_true(
    @calendar_typing.check(
      Bucket,
      s,
      Some(input(true, false)),
      None,
      Some(profile()),
      limits(),
    )
    is Err({ kind: InvalidTime("time"), .. }),
  )
  assert_true(
    @calendar_typing.check(
      Bucket,
      s,
      Some(input(false, true)),
      None,
      Some(profile()),
      limits(),
    )
    is Err({ kind: UnknownOutputFields, .. }),
  )
  assert_true(
    @calendar_typing.check(
      Bucket,
      s,
      Some(input(false, false)),
      None,
      None,
      limits(),
    )
    is Err({ kind: MissingProfile, .. }),
  )
}

///|
test "series bound is finite and equal endpoints have zero rows" {
  for
    (end, empty) in [
      ("2000-01-01T00:00:00.000Z", true),
      ("2001-01-01T00:00:00.000Z", false),
    ] {
    let s = cursor(
      "{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"" +
      end +
      "\",\"unit\":\"month\",\"timezone\":\"UTC\"}",
    )
    let c = @calendar_typing.check(
      Series,
      s,
      None,
      None,
      Some(profile()),
      limits(),
    ).unwrap()
    assert_eq(
      @calendar_typing.cardinality(c),
      AtMost(if empty { 0 } else { 119990 }),
    )
    assert_true(
      @calendar_typing.check(
        Series,
        s,
        Some(input(false, false)),
        None,
        Some(profile()),
        limits(),
      )
      is Err({ kind: WrongInput, .. }),
    )
    let u = @calendar_typing.usage(c)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(
      @calendar_typing.check(Series, s, None, None, Some(profile()), exact)
      is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: u.work - 1, },
        { ..exact, max_nodes: u.nodes - 1, },
        { ..exact, max_text_bytes: u.text_bytes - 1, },
      ] {
      assert_true(
        @calendar_typing.check(Series, s, None, None, Some(profile()), cap)
        is Err(_),
      )
    }
  }
}
