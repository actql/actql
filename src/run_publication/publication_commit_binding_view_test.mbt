///|
test "commit binding view borrows original contract after bounded quantum preparation" {
  for quantum in [1, 7, 64] {
    let fixture = commit_read_fixture()
    let work = commit_read_complete(fixture.preparation, quantum)
    let view = fixture.preparation.finish_view().unwrap()
    let binding = fixture.preparation.view_binding(view, 0).unwrap()
    assert_eq(publication_contract_name(binding), "durable_result_binding")
    assert_true(physical_equal(binding, fixture.originals[13]))
    assert_eq(fixture.preparation.view_count(view).unwrap(), 14)
    assert_true(
      fixture.preparation.view_binding(view, -1) is Err(CommitEncoding),
    )
    assert_true(
      fixture.preparation.view_binding(view, 1) is Err(CommitEncoding),
    )
    assert_true(
      physical_equal(
        fixture.preparation.view_binding(view, 0).unwrap(),
        binding,
      ),
    )
    assert_true(work > 0)
    fixture.preparation.release_view(view).unwrap()
  }
}

///|
test "commit binding view refuses foreign cursor with equal-looking complete contracts" {
  let first = commit_read_fixture()
  let second = commit_read_fixture()
  commit_read_complete(first.preparation, 64) |> ignore
  commit_read_complete(second.preparation, 64) |> ignore
  let first_view = first.preparation.finish_view().unwrap()
  let second_view = second.preparation.finish_view().unwrap()
  assert_true(
    second.preparation.view_binding(first_view, 0) is Err(CommitEncoding),
  )
  assert_true(
    first.preparation.view_binding(second_view, 0) is Err(CommitEncoding),
  )
  assert_true(
    physical_equal(
      first.preparation.view_binding(first_view, 0).unwrap(),
      first.originals[13],
    ),
  )
  first.preparation.release_view(first_view).unwrap()
  second.preparation.release_view(second_view).unwrap()
}

///|
test "commit binding view refuses cancellation and cleanup while original contracts stay immutable" {
  let fixture = commit_read_fixture()
  assert_true(fixture.preparation.finish_view() is Err(CommitEncoding))
  commit_read_complete(fixture.preparation, 64) |> ignore
  let view = fixture.preparation.finish_view().unwrap()
  let binding = fixture.preparation.view_binding(view, 0).unwrap()
  let original_wire = publication_contract_json(binding)
  fixture.preparation.cancel()
  assert_true(fixture.preparation.view_binding(view, 0) is Err(CommitEncoding))
  assert_eq(publication_contract_json(binding), original_wire)
  fixture.preparation.release_view(view).unwrap()
  fixture.preparation.release_view(view).unwrap()
  assert_true(fixture.preparation.view_binding(view, 0) is Err(CommitEncoding))
}
