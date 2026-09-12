///|
test "source mode support binds the selected keyed request and aggregate budget" {
  let index = join_resolution_fixture()
  let identity = expression_closure_identity(
    operation_requirements_expressions(operation_resolution_requirements(index)),
  )
  let limits : IncomingLimits = {
    max_work: 10000000,
    max_name_units: 10000,
    max_requirements: 1000,
  }
  let owner = link_resolved_program_incoming(
    index,
    collect_program_incoming(identity, limits).unwrap(),
    limits,
  ).unwrap()
  let closed = close_program_source_modes(owner, 10000000, 1).unwrap()
  assert_true(physical_equal(source_mode_closure_owner(closed), owner))
  assert_eq(source_mode_closure_count(closed), 1)
  let check = source_mode_closure_at(closed, 0).unwrap()
  assert_eq((check.stage, check.input), (0, 0))
  guard check.request is @sourceviews.Keyed(mode, request) else {
    fail("must retain keyed request, not replace it with a direct scan")
  }
  assert_eq(
    @environment.read_mode_kind(@sourceviews.keyed_mode_contract(mode)),
    @environment.SnapshotMode,
  )
  assert_true(
    physical_equal(
      @sourceviews.keyed_mode_input(mode),
      @sourceviews.keyed_request_input(
        @sourceviews.parameterized_keyed_request(request),
      ),
    ),
  )
  assert_true(source_mode_closure_at(closed, 1) is None)
  let work = source_mode_closure_work(closed)
  assert_true(close_program_source_modes(owner, work, 1) is Ok(_))
  assert_true(
    close_program_source_modes(owner, work - 1, 1) is Err(BudgetExceeded),
  )
  assert_true(close_program_source_modes(owner, work, 0) is Err(BudgetExceeded))
  assert_true(close_program_source_modes(owner, -1, 1) is Err(InvalidLimits))
}

///|
test "Local-only staged closure has no fabricated acquisition check" {
  let owner = staged_closure_fixture()
  let closed = close_program_source_modes(owner, 10000000, 0).unwrap()
  assert_eq(source_mode_closure_count(closed), 0)
  assert_true(
    close_program_source_modes(owner, source_mode_closure_work(closed), 0)
    is Ok(_),
  )
}
