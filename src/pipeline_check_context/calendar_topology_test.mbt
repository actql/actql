///|
test "Calendar topology selection belongs to the registration Environment" {
  let host = capacity_profile(false).replace(
    old="\"capacity\":",
    new="\"calendar\":{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"table_bytes_cid\":\"sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca\",\"tzdb_version\":\"test-fixture\",\"version\":\"actql-calendar-selection/0.1\"},\"capacity\":",
  )
  let remote = []
  let (_, wiring, _, _, _, _) = wired_inputs_fixture(
    true,
    remote=Some(remote),
    repeat_remote=true,
    profile=host,
  )
  let (views, locals) = prepare_source_registrations(
    @stage_results.wiring_source(wiring),
    @sourceviews.catalog(@sourceviews.pipeline_resolution(remote[0])),
    {
      max_work: 1000000,
      max_nodes: 100000,
      max_text_bytes: 1000000,
      max_depth: 100,
    },
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  let selection = @environment.read_calendar_selection(
    @sourceviews.pipeline_environment(views),
    1000,
  ).unwrap()
  let selected = @environment.admit_calendar_profile(
    selection,
    program_calendar_table(),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 8,
      max_zones: 1,
      max_transitions: 0,
    },
  ).unwrap()
  let limits = local_program_context_source_limits()
  let (_, plain) = prepare_sourceview_program(views, locals, limits).unwrap()
  let (_, used) = prepare_sourceview_program(
    views,
    locals,
    limits,
    calendar=Some(selected),
  ).unwrap()
  assert_eq(
    used.work,
    plain.work + @environment.calendar_selection_work(selection),
  )
  let exact = { ..limits, max_work: used.work, }
  assert_true(
    prepare_sourceview_program(views, locals, exact, calendar=Some(selected))
    is Ok(_),
  )
  assert_true(
    prepare_sourceview_program(
      views,
      locals,
      { ..exact, max_work: used.work - 1, },
      calendar=Some(selected),
    )
    is Err(_),
  )
  let foreign = program_calendar_artifact(
    calendar_program(program_calendar_host()),
  )
  assert_true(
    prepare_sourceview_program(views, locals, limits, calendar=Some(foreign))
    is Err(ForeignCalendarEnvironment),
  )
}
