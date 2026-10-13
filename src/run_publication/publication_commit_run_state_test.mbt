///|
test "observed Run state uses original stored chain and leaves current Result availability unknown" {
  let fixture = commit_read_fixture()
  let owner = fixture.preparation
  commit_read_complete(owner, 64) |> ignore
  let view = owner.finish_view().unwrap()
  let (attempt, stored) = observed_commit_test_pair(fixture)
  assert_true(
    owner.observed_run_state_wire(
      view, "2026-09-17T00:00:03.000Z", 65536, 4096, 32,
    )
    is Err(Commit(CommitEncoding)),
  )
  owner
  .begin_observed_commit(view, fixture.originals[5], attempt, stored)
  .unwrap()
  assert_true(
    owner.observed_run_state_wire(
      view, "2026-09-17T00:00:03.000Z", 65536, 4096, 32,
    )
    is Err(Commit(CommitEncoding)),
  )
  observed_commit_test_complete(owner, view, 64) |> ignore
  let wire = owner
    .observed_run_state_wire(view, "2026-09-17T00:00:03.000Z", 65536, 4096, 32)
    .unwrap()
  let value = captured_test_value(wire)
  assert_true(
    @json.object_field(value, "status") is Some(@json.String("succeeded")),
  )
  assert_true(
    @json.object_field(value, "result_available") is Some(@json.Bool(false)),
  )
  let availability = @json.object_field(value, "result_availability").unwrap()
  let names = manifest_result_names(fixture.originals[2]).unwrap()
  for name in names {
    let result = @json.object_field(availability, name).unwrap()
    assert_true(
      @json.object_field(result, "state") is Some(@json.String("unknown")),
    )
    assert_true(
      @json.object_field(result, "reason")
      is Some(@json.String("verification_pending")),
    )
  }
  assert_true(
    physical_equal(owner.finish_observed_commit(view).unwrap(), stored),
  )
  assert_true(
    physical_equal(owner.view_contract(view, 7).unwrap(), fixture.originals[7]),
  )
  owner.release_observed_commit(view).unwrap()
  owner.release_view(view).unwrap()
}

///|
test "observed Run state rejects foreign view cancelled observation and invalid time or bounds" {
  let fixture = commit_read_fixture()
  let owner = fixture.preparation
  commit_read_complete(owner, 64) |> ignore
  let view = owner.finish_view().unwrap()
  let other = commit_read_fixture()
  commit_read_complete(other.preparation, 64) |> ignore
  let foreign = other.preparation.finish_view().unwrap()
  assert_true(
    owner.observed_run_state_wire(
      foreign, "2026-09-17T00:00:03.000Z", 65536, 4096, 32,
    )
    is Err(Commit(CommitEncoding)),
  )
  let (attempt, stored) = observed_commit_test_pair(fixture)
  owner
  .begin_observed_commit(view, fixture.originals[5], attempt, stored)
  .unwrap()
  observed_commit_test_complete(owner, view, 64) |> ignore
  assert_true(
    owner.observed_run_state_wire(view, "not-a-time", 65536, 4096, 32)
    is Err(State(InvalidObservationTime("run"))),
  )
  assert_true(
    owner.observed_run_state_wire(view, "2026-09-17T00:00:03.000Z", 1, 4096, 32)
    is Err(State(Encoding)),
  )
  owner.release_observed_commit(view).unwrap()
  assert_true(
    owner.observed_run_state_wire(
      view, "2026-09-17T00:00:03.000Z", 65536, 4096, 32,
    )
    is Err(Commit(CommitEncoding)),
  )
  owner.release_view(view).unwrap()
  other.preparation.release_view(foreign).unwrap()
}
