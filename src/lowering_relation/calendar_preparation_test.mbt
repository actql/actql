///|
fn calendar_preparation_profile() -> @calendar_profile.Profile {
  @calendar_profile.admit(
    @utf8.encode(
      "{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"coverage_end_ms\":253402300800000,\"coverage_start_ms\":-62135596800000,\"tzdb_version\":\"test-fixture\",\"version\":\"actql-tzdb-table/0.1\",\"zones\":{\"UTC\":{\"initial_offset_seconds\":0,\"transitions\":[]}}}",
    ),
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
}

///|
fn calendar_preparation_owner(
  body : String,
  declarations? : @parameter.Declarations? = None,
  bindings? : @parameter.BoundValues? = None,
) -> @lowering_relation.BoundPrepared {
  let checked = @pipeline.check(
    cursor(body),
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
    calendar_profile=Some(calendar_preparation_profile()),
  ).unwrap()
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    bindings,
    max_parameters=2,
    max_name_bytes=2,
  ).unwrap()
}

///|
test "Calendar sequence retains original selected profile bound range and schema" {
  let owner = calendar_preparation_owner(
    "[{\"calendar_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-03T00:00:00.000Z\",\"unit\":\"day\",\"timezone\":\"UTC\"},\"as\":\"days\"}]",
  )
  let caps = { ..sequence_limits(), max_rows: 4, max_cells: 8, }
  let sequence = @lowering_relation.prepare_sequence(owner, caps).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(CalendarStep(prepared)) else {
    fail("a real Calendar step must retain its own checked operation")
  }
  assert_true(
    physical_equal(@lowering_relation.calendar_owner(prepared), owner),
  )
  assert_eq(@lowering_relation.calendar_step(prepared), 0)
  assert_eq(
    @lowering_relation.calendar_start(prepared),
    Some("2000-01-01T00:00:00.000Z"),
  )
  assert_eq(
    @lowering_relation.calendar_end(prepared),
    Some("2000-01-03T00:00:00.000Z"),
  )
  // Interval length plus two conservative edges. This is an upper bound,
  // not a generated row count or an execution completion certificate.
  assert_eq(@lowering_relation.calendar_row_bound(prepared), Some(4))
  assert_true(
    @lowering_relation.prepare_sequence(owner, { ..caps, max_cells: 7, })
    is Err(CalendarFailure(0, CalendarPreparationLimit)),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, { ..caps, max_rows: 3, })
    is Err(CalendarFailure(0, CalendarPreparationLimit)),
  )
  let writer = @encode.writer(2000, 100, 20)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"calendar_series_0\",\"in\":[],\"op\":\"TEA.calendar_series\",\"params\":{\"end\":\"2000-01-03T00:00:00.000Z\",\"profile\":{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"table_bytes_cid\":\"sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca\",\"tzdb_version\":\"test-fixture\"},\"start\":\"2000-01-01T00:00:00.000Z\",\"timezone\":\"UTC\",\"unit\":\"day\"}}]",
  )
}

///|
test "Calendar bucket remains one input and preserves original checked profile" {
  let owner = calendar_preparation_owner(
    "[{\"calendar_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-03T00:00:00.000Z\",\"unit\":\"day\",\"timezone\":\"UTC\"},\"as\":\"days\"},{\"calendar_bucket\":{\"time\":\"start\",\"into\":\"month\",\"unit\":\"month\",\"timezone\":\"UTC\"},\"as\":\"bucketed\"}]",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(CalendarStep(prepared)) else {
    fail("Calendar bucket is a real one-input operation")
  }
  assert_eq(@lowering_relation.calendar_start(prepared), None)
  assert_eq(@lowering_relation.calendar_row_bound(prepared), None)
  assert_eq(@lowering_relation.calendar_step(prepared), 1)
  let node = @lowering_relation.node_at(
    @lowering_relation.bound_preparation(owner),
    1,
  ).unwrap()
  assert_eq(@lowering_relation.input_ids(node), ["calendar_series_0"])
  assert_eq(@lowering_relation.operation(node), "TEA.calendar_bucket")
  assert_eq(
    @calendar_profile.cid(
      @calendar.profile(@lowering_relation.calendar_checked(prepared)),
    ),
    "sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca",
  )
}

///|
test "Calendar bound endpoints retain timestamp admission and reject year zero before execution" {
  let declarations = @parameter.read_declarations(
    Some(
      cursor("{\"a\":{\"type\":\"timestamp\"},\"z\":{\"type\":\"timestamp\"}}"),
    ),
    { max_parameters: 2, max_nodes: 30, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  for
    (start, end, expected) in [
      (
        "0000-01-01T00:00:00.000Z",
        "2000-01-03T00:00:00.000Z",
        @calendar_options.InvalidTimestamp,
      ),
      (
        "2000-01-03T00:00:00.000Z",
        "2000-01-01T00:00:00.000Z",
        @calendar_options.ReversedRange,
      ),
    ] {
    let values = match
      @parameter.bind(
        declarations,
        Some(cursor("{\"a\":\"" + start + "\",\"z\":\"" + end + "\"}")),
        { max_nodes: 10, max_depth: 5, max_text_bytes: 100, },
      ).unwrap() {
      Ready(values) => values
      _ => fail("independent timestamp fixture must bind")
    }
    let owner = calendar_preparation_owner(
      "[{\"calendar_series\":{\"start\":{\"$param\":\"a\"},\"end\":{\"$param\":\"z\"},\"unit\":\"day\",\"timezone\":\"UTC\"}}]",
      declarations=Some(declarations),
      bindings=Some(values),
    )
    match @lowering_relation.prepare_sequence(owner, sequence_limits()) {
      Err(CalendarFailure(0, CalendarRange(issue))) =>
        assert_eq(issue, expected)
      _ => fail("bound Calendar range obligation must not be erased")
    }
  }
}

///|
test "selected original UTC Calendar series reaches normal lowering" {
  let profile = calendar_preparation_profile()
  let checked = @pipeline.check(
    cursor(
      "[{\"calendar_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-03T00:00:00.000Z\",\"unit\":\"day\",\"timezone\":\"UTC\"},\"as\":\"days\"}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
    calendar_profile=Some(profile),
  ).unwrap()
  let prepared = @lowering_relation.prepare(checked, limits()).unwrap()
  let node = @lowering_relation.node_at(prepared, 0).unwrap()
  assert_eq(@lowering_relation.operation(node), "TEA.calendar_series")
  assert_eq(@lowering_relation.input_ids(node), [])
  assert_eq(
    @decode.cursor_span(@lowering_relation.source(node)),
    @decode.cursor_span(@pipeline.step_at(checked, 0).unwrap().source),
  )
  guard @pipeline.step_at(checked, 0).unwrap().operation is Calendar(original) &&
    @lowering_relation.payload(node) is CalendarValue(retained) else {
    fail("exact checked Calendar owner must remain available")
  }
  assert_true(physical_equal(original, retained))
}
