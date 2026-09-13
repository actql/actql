///|
test "publication row candidates retain target policy and proof membership" {
  let index = join_resolution_fixture()
  let identity = expression_closure_identity(
    operation_requirements_expressions(operation_resolution_requirements(index)),
  )
  let limits : IncomingLimits = {
    max_work: 10000000,
    max_name_units: 10000,
    max_requirements: 100,
  }
  let owner = link_resolved_program_incoming(
    index,
    collect_program_incoming(identity, limits).unwrap(),
    limits,
  ).unwrap()
  let closed = close_program_publications(owner, 10000000, 100).unwrap()
  assert_eq(publication_closure_count(closed), 1)
  assert_eq(publication_row_candidate_count(closed), 1)
  let candidate = publication_row_candidate_at(closed, 0).unwrap()
  let publication = publication_closure_at(closed, 0).unwrap()
  assert_true(physical_equal(candidate.publication, publication))
  let membership = candidate.membership
  assert_true(
    physical_equal(
      @capacity.target_membership_closure(membership),
      checked_capacity(publication.context),
    ),
  )
  let rows = @capacity.target_membership_rows(membership)
  assert_eq(@program.target_rows_value(rows), 1L)
  assert_eq(
    @program.target_rows_target(rows),
    @results.target(@results.port_result(publication.port)),
  )
  assert_true(
    physical_equal(
      @program.target_rows_pipeline(rows),
      @results.pipeline(
        @results.publication_results(@results.port_order(publication.port)),
      ),
    ),
  )
  let work = publication_closure_work(closed)
  assert_true(close_program_publications(owner, work, 2) is Ok(_))
  assert_true(
    close_program_publications(owner, work - 1, 2) is Err(BudgetExceeded),
  )
  assert_true(close_program_publications(owner, work, 1) is Err(BudgetExceeded))
  for i in [-1, 1, 2147483647] {
    assert_true(publication_row_candidate_at(closed, i) is None)
  }
}
