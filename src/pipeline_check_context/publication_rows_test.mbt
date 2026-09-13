///|
test "publication row candidates retain target policy and proof membership" {
  let index = join_resolution_fixture(artifact_rows=2)
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
  let selected = select_publication_row_limit(closed, 0, work + 2, 2).unwrap()
  assert_true(physical_equal(publication_row_limit_owner(selected), closed))
  assert_true(
    physical_equal(publication_row_limit_result(selected), publication),
  )
  assert_true(
    physical_equal(
      publication_row_limit_program_at(selected, 0).unwrap(),
      candidate,
    ),
  )
  assert_eq(publication_row_limit_program_count(selected), 1)
  assert_eq(publication_row_limit_maximum(selected), 1L)
  assert_eq(@policy.ceiling_value(publication_row_limit_host(selected)), 2L)
  assert_true(
    physical_equal(
      @policy.ceiling_policy(publication_row_limit_host(selected)),
      @capacity.application_closure_policy(
        checked_capacity(publication.context),
      ),
    ),
  )
  assert_eq(publication_row_limit_work(selected), work + 2)
  assert_true(
    select_publication_row_limit(closed, 0, work + 1, 2) is Err(BudgetExceeded),
  )
  assert_true(
    select_publication_row_limit(closed, 0, work + 2, 1) is Err(BudgetExceeded),
  )
  assert_true(
    select_publication_row_limit(closed, -1, work + 2, 2) is Err(InvalidResult),
  )
  assert_true(
    select_publication_row_limit(closed, 0, -1, 2) is Err(InvalidLimits),
  )
  assert_true(close_program_publications(owner, work, 2) is Ok(_))
  assert_true(
    close_program_publications(owner, work - 1, 2) is Err(BudgetExceeded),
  )
  assert_true(close_program_publications(owner, work, 1) is Err(BudgetExceeded))
  for i in [-1, 1, 2147483647] {
    assert_true(publication_row_candidate_at(closed, i) is None)
  }
}

///|
test "publication without a Program row bound retains an owned Host restriction" {
  let owner = staged_closure_fixture()
  let publications = close_program_publications(owner, 10000000, 10).unwrap()
  assert_eq(publication_row_candidate_count(publications), 0)
  let prefix = publication_closure_work(publications)
  for i in 0..<publication_closure_count(publications) {
    let selected = select_publication_row_limit(publications, i, prefix + 1, 1).unwrap()
    let host = publication_row_limit_host(selected)
    assert_eq(@policy.ceiling_field(host), "max_artifact_rows")
    assert_eq(
      publication_row_limit_maximum(selected),
      @policy.ceiling_value(host),
    )
    assert_eq(publication_row_limit_program_count(selected), 0)
    for j in [-1, 0, 2147483647] {
      assert_true(publication_row_limit_program_at(selected, j) is None)
    }
    assert_true(
      select_publication_row_limit(publications, i, prefix, 1)
      is Err(BudgetExceeded),
    )
    assert_true(
      select_publication_row_limit(publications, i, prefix + 1, 0)
      is Err(BudgetExceeded),
    )
  }
}

///|
test "publication scans sparse claims without renumbering proof membership" {
  for artifact_rows in [1, 2] {
    for host_first in [false, true] {
      let index = join_resolution_fixture(artifact_rows~, host_first~)
      let identity = expression_closure_identity(
        operation_requirements_expressions(
          operation_resolution_requirements(index),
        ),
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
      assert_eq(publication_row_candidate_count(closed), 1)
      let candidate = publication_row_candidate_at(closed, 0).unwrap()
      let claim = if host_first { 1 } else { 0 }
      assert_eq(
        @capacity.target_membership_coordinates(candidate.membership),
        (0, claim, 0),
      )
      let closure = @capacity.target_membership_closure(candidate.membership)
      let rows = @capacity.target_membership_rows(candidate.membership)
      assert_true(
        @capacity.bind_target_membership(closure, rows, 0, 1 - claim) is Err(_),
      )
      let work = publication_closure_work(closed)
      let selected = select_publication_row_limit(closed, 0, work + 2, 2).unwrap()
      assert_eq(publication_row_limit_maximum(selected), 1L)
      assert_eq(publication_row_limit_program_count(selected), 1)
      assert_true(close_program_publications(owner, work, 2) is Ok(_))
      assert_true(
        close_program_publications(owner, work - 1, 2) is Err(BudgetExceeded),
      )
    }
  }
}
