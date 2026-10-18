///|
// Pure nominal correspondence using existing independently authored checked
// Source fixtures. This is not an operational parent, physical backing or
// permission positive, and constructs no substitute imported child.
test "Source read requirement keeps the same checked Program and occurrence" {
  let prepared = single_installed_prepared()
  let foreign = single_installed_prepared()
  let requirement = original_row_requirement(prepared)
  let other = original_row_requirement(foreign)
  assert_eq(
    @planning.query_requirement_cid(requirement),
    @planning.query_requirement_cid(other),
  )
  assert_true(
    @publication_host.client_query_requirement_matches_program(
      prepared, 0, 0, requirement,
    ),
  )
  assert_true(
    !@publication_host.client_query_requirement_matches_program(
      foreign, 0, 0, requirement,
    ),
  )
  assert_true(
    !@publication_host.client_query_requirement_matches_program(
      prepared, 0, 0, other,
    ),
  )
  for (stage, input) in [(-1, 0), (0, -1), (0, 1), (1, 0), (2, 0)] {
    assert_true(
      !@publication_host.client_query_requirement_matches_program(
        prepared, stage, input, requirement,
      ),
    )
  }
}
