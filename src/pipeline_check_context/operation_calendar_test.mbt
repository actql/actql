///|
fn program_calendar_table(release? : String = "test-fixture") -> Bytes {
  @utf8.encode(
    "{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"coverage_end_ms\":253402300800000,\"coverage_start_ms\":-62135596800000,\"tzdb_version\":\"" +
    release +
    "\",\"version\":\"actql-tzdb-table/0.1\",\"zones\":{\"UTC\":{\"initial_offset_seconds\":0,\"transitions\":[]}}}",
  )
}

///|
fn program_calendar_host(release? : String = "test-fixture") -> String {
  let pin = "sha256:" + @sha.hex(program_calendar_table(release~))
  let component = "\"calendar\":{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"table_bytes_cid\":\"" +
    pin +
    "\",\"tzdb_version\":\"" +
    release +
    "\",\"version\":\"actql-calendar-selection/0.1\"},"
  bound_profile().replace(old="\"capacity\":", new=component + "\"capacity\":")
}

///|
fn calendar_program(host : String) -> ProgramOperationLexical {
  let steps = "[{\"calendar_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-02T00:00:00.000Z\",\"unit\":\"day\",\"timezone\":\"UTC\"},\"as\":\"days\"},{\"calendar_bucket\":{\"time\":\"start\",\"into\":\"bucket\",\"unit\":\"month\",\"timezone\":\"UTC\"}},{\"derive\":{\"p_copy\":\"$p\",\"n_copy\":\"$n\"}}]"
  let requirements = operation_order_fixture(
    steps,
    calendar=true,
    tea=true,
    host_profile=host,
  )
  let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
  let scalars = check_program_operation_scalars(orders, 10000000, 100).unwrap()
  let frames = check_program_operation_frames(scalars, 10000000, 100).unwrap()
  let fills = check_program_operation_fills(frames, 10000000, 100).unwrap()
  let ranges = check_program_operation_ranges(fills, 10000000, 100).unwrap()
  let queries = check_program_operation_queries(ranges, 10000000, 100).unwrap()
  let cells = check_program_operation_cells(queries, 10000000, 100).unwrap()
  check_program_operation_lexical(cells, None, 10000000, 0).unwrap()
}

///|
fn program_calendar_artifact(
  program : ProgramOperationLexical,
  release? : String = "test-fixture",
) -> @environment.SelectedCalendarProfile {
  let env = operation_cells_environment(operation_lexical_cells(program))
  let selected = @environment.read_calendar_selection(env, 1000).unwrap()
  @environment.admit_calendar_profile(
    selected,
    program_calendar_table(release~),
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
test "Calendar Program links series and bucket profiles at every producer visit" {
  let program = calendar_program(program_calendar_host())
  let selected = program_calendar_artifact(program)
  let result = check_program_operation_calendar(
    program,
    Some(selected),
    10000000,
    6,
  ).unwrap()
  assert_eq(operation_calendar_count(result), 6)
  assert_true(physical_equal(operation_calendar_lexical(result), program))
  assert_true(
    physical_equal(operation_calendar_profile(result).unwrap(), selected),
  )
  for i in 0..<6 {
    let entry = operation_calendar_at(result, i).unwrap()
    assert_eq(entry.step, i % 2)
    assert_true(physical_equal(entry.selected, selected))
    assert_eq(
      @calendar_profile.cid(@calendar.profile(entry.operation)),
      @calendar_profile.cid(@environment.selected_calendar_profile(selected)),
    )
  }
  let work = operation_calendar_work(result)
  assert_true(
    check_program_operation_calendar(program, Some(selected), work, 6) is Ok(_),
  )
  assert_true(
    check_program_operation_calendar(program, Some(selected), work - 1, 6)
    is Err(BudgetExceeded),
  )
  assert_true(
    check_program_operation_calendar(program, Some(selected), work, 5)
    is Err(BudgetExceeded),
  )
  assert_true(
    check_program_operation_calendar(program, Some(selected), -1, 6)
    is Err(InvalidLimits),
  )
  assert_true(
    check_program_operation_calendar(program, Some(selected), work, -1)
    is Err(InvalidLimits),
  )
  assert_true(operation_calendar_at(result, -1) is None)
  assert_true(operation_calendar_at(result, 6) is None)
  assert_true(
    check_program_operation_calendar(program, None, work, 6)
    is Err(MissingArtifact),
  )
  let foreign = program_calendar_artifact(
    calendar_program(program_calendar_host()),
  )
  assert_true(
    check_program_operation_calendar(program, Some(foreign), work, 6)
    is Err(ForeignEnvironment),
  )
}

///|
test "Calendar operations cannot rely on an unselected or differently selected table" {
  let absent = calendar_program(bound_profile())
  assert_true(
    check_program_operation_calendar(absent, None, 10000000, 6)
    is Err(MissingProfile(0, 0, 0)),
  )
  let mismatch = calendar_program(
    program_calendar_host(release="other-release"),
  )
  let selected = program_calendar_artifact(mismatch, release="other-release")
  assert_true(
    check_program_operation_calendar(mismatch, Some(selected), 10000000, 6)
    is Err(ProfileMismatch(0, 0, 0)),
  )
  let no_calendar = check_program_operation_lexical(
    lexical_cells(bound_profile(), false),
    None,
    10000000,
    0,
  ).unwrap()
  assert_true(
    check_program_operation_calendar(no_calendar, None, 10000000, 0) is Ok(_),
  )
  let unused = check_program_operation_lexical(
    lexical_cells(program_calendar_host(), false),
    None,
    10000000,
    0,
  ).unwrap()
  assert_true(
    check_program_operation_calendar(unused, None, 10000000, 0)
    is Err(MissingArtifact),
  )
  assert_true(
    check_program_operation_calendar(
      unused,
      Some(program_calendar_artifact(unused)),
      10000000,
      0,
    )
    is Ok(_),
  )
  let malformed_host = program_calendar_host().replace(
    old="\"tzdb_version\":\"test-fixture\"",
    new="\"tzdb_version\":null",
  )
  let malformed = check_program_operation_lexical(
    lexical_cells(malformed_host, false),
    None,
    10000000,
    0,
  ).unwrap()
  assert_true(
    check_program_operation_calendar(malformed, None, 10000000, 0)
    is Err(Selection(InvalidComponent)),
  )
}
