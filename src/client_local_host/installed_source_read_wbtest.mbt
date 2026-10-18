///|
// Pure nominal correspondence using existing independently authored checked
// Source fixtures. This is not an operational parent, physical backing or
// permission positive, and constructs no substitute imported child.
fn installed_source_read_prepared_fixture() -> @publication_host.PreparedClientProgram {
  // The retained environment declares this original evidence identity. The
  // older single-installed helper still expects a different historical CID.
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:4ea01561b9ac9815baaf04a81cff8260c8a47c56f19828b5889cf45ec1436e78",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  @publication_host.prepare_effect_free_client_program(
    source_query_original_document,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
test "Source read requirement keeps the same checked Program and occurrence" {
  let prepared = installed_source_read_prepared_fixture()
  let foreign = installed_source_read_prepared_fixture()
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
