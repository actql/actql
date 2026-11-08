///|
// Pure nominal correspondence using existing independently authored checked
// Source fixtures. This is not an operational parent, physical backing or
// permission positive, and constructs no substitute imported child.
fn installed_source_read_prepared_fixture() -> @publication_host.PreparedClientProgram {
  // The retained environment declares this original evidence identity. The
  // older single-installed helper still expects a different historical CID.
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
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

///|
// No imported parent is fabricated here. An original-looking consumer with
// no child cannot issue capacity; copying a retired consumer cannot revive it.
test "Source read consumer identity without an original child is unavailable" {
  let value : ClientInstalledSourceRead = {
    original: None,
    child: None,
    managed_run: None,
    ledger: None,
    owner: None,
    declaration: None,
    requirement: None,
    acquisition: None,
    whole_input: None,
    run: None,
    start: Unstarted,
  }
  assert_true(
    check_installed_source_read_current(value) is Err(ForeignOriginal),
  )
  value.original = Some(value)
  assert_true(check_installed_source_read_current(value) is Err(Retired))
  // Merely supplying an actual Ledger cannot replace the missing imported
  // original. These are explicit unaccounted test limits, not a supplier.
  let expected = @resources.create_ledger({
    planning_work: 1,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 1L,
    retained_bytes: 1L,
    execution_bytes: 1L,
  }).unwrap()
  assert_true(
    check_installed_source_read_ledger(value, expected) is Err(Retired),
  )
  let copied = { ..value, }
  assert_true(
    check_installed_source_read_current(copied) is Err(ForeignOriginal),
  )
  assert_true(retire_installed_source_read(copied) is Err(ForeignOriginal))
  retire_installed_source_read(value).unwrap()
  assert_true(check_installed_source_read_current(value) is Err(Retired))
}
