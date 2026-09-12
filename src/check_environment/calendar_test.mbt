///|
fn calendar_table() -> Bytes {
  @utf8.encode(
    "{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"coverage_end_ms\":253402300800000,\"coverage_start_ms\":-62135596800000,\"tzdb_version\":\"test-fixture\",\"version\":\"actql-tzdb-table/0.1\",\"zones\":{\"UTC\":{\"initial_offset_seconds\":0,\"transitions\":[]}}}",
  )
}

///|
fn calendar_component(
  release? : String = "test-fixture",
  pin? : String = "sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca",
) -> String {
  "{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"table_bytes_cid\":\"" +
  pin +
  "\",\"tzdb_version\":\"" +
  release +
  "\",\"version\":\"actql-calendar-selection/0.1\"}"
}

///|
fn calendar_environment(component : String) -> WireEnvironment {
  let (body, id) = wire("{\"calendar\":" + component + "}", "[]")
  read(@utf8.encode(body), id, caps()).unwrap()
}

///|
test "Calendar selection binds independent byte and external release pins" {
  let env = calendar_environment(calendar_component())
  let selection = read_calendar_selection(env, 1000).unwrap()
  assert_true(physical_equal(calendar_selection_environment(selection), env))
  assert_eq(calendar_selection_release(selection), "test-fixture")
  let used = calendar_selection_work(selection)
  assert_true(read_calendar_selection(env, used) is Ok(_))
  assert_true(read_calendar_selection(env, used - 1) is Err(BudgetExceeded))
  assert_true(read_calendar_selection(env, -1) is Err(InvalidLimits))
  let bytes = calendar_table()
  let limits : @calendar.Limits = {
    max_bytes: bytes.length(),
    max_nodes: 100,
    max_depth: 10,
    max_zones: 1,
    max_transitions: 0,
  }
  let bound = admit_calendar_profile(selection, bytes, limits).unwrap()
  assert_true(physical_equal(selected_calendar_selection(bound), selection))
  assert_eq(
    @calendar.cid(selected_calendar_profile(bound)),
    calendar_selection_cid(selection),
  )
  assert_eq(
    @calendar.tzdb_version(selected_calendar_profile(bound)),
    "test-fixture",
  )
  assert_true(
    @calendar.zone(selected_calendar_profile(bound), "UTC") is Some(_),
  )
  assert_true(
    admit_calendar_profile(selection, bytes, {
      ..limits,
      max_bytes: bytes.length() - 1,
    })
    is Err(BudgetExceeded),
  )
  let other_release = read_calendar_selection(
    calendar_environment(calendar_component(release="2025b")),
    1000,
  ).unwrap()
  assert_true(admit_calendar_profile(other_release, bytes, limits) is Err(_))
  let other_pin = read_calendar_selection(
    calendar_environment(calendar_component(pin="sha256:" + "0".repeat(64))),
    1000,
  ).unwrap()
  assert_true(
    admit_calendar_profile(other_pin, bytes, limits) is Err(IdentityMismatch),
  )
  assert_true(
    admit_calendar_profile(selection, @utf8.encode(" " + @utf8.decode(bytes)), {
      ..limits,
      max_bytes: bytes.length() + 1,
    })
    is Err(_),
  )
}

///|
test "Calendar selection absence differs from malformed supplied selections" {
  let (body, id) = wire("{}", "[]")
  assert_true(
    read_calendar_selection(read(@utf8.encode(body), id, caps()).unwrap(), 1000)
    is Err(MissingSelection),
  )
  for
    component in [
      "null",
      "[]",
      "{}",
      calendar_component(release=""),
      calendar_component(pin="sha256:" + "A".repeat(64)),
      calendar_component().replace(
        old="actql-calendar-boundaries/0.1",
        new="other",
      ),
      calendar_component().replace(
        old="actql-calendar-selection/0.1",
        new="other",
      ),
      calendar_component().replace(old="\"version\":", new="\"unknown\":"),
    ] {
    assert_true(
      read_calendar_selection(calendar_environment(component), 1000)
      is Err(InvalidComponent),
    )
  }
}
