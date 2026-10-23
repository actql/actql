///|
test "stored original commit consumes completed private inventory once" {
  let fixture = commit_read_fixture()
  let rows = stored_publication_test_rows(fixture)
  let owner = stored_publication_test_load(fixture, cid => Ok(rows.get(cid)), () => {
    Ok(())
  }).unwrap()
  let first_work = commit_read_complete(owner, 64)
  assert_true(first_work > 1)
  let view = owner.finish_view().unwrap()
  let request = owner.view_contract(view, 5).unwrap()
  let attempt = owner.view_contract(view, 6).unwrap()
  let index = owner.view_contract(view, 7).unwrap()
  owner.begin_observed_commit(view, request, attempt, index).unwrap()
  assert_true(owner.finish_observed_commit(view) is Err(CommitEncoding))
  assert_true(owner.advance_observed_commit(view, 0) is Err(CommitEncoding))
  let observed_work = observed_commit_test_complete(owner, view, 1)
  assert_true(
    physical_equal(owner.finish_observed_commit(view).unwrap(), index),
  )
  let selected = owner
    .observed_result_read_materials(view, "answer", 16)
    .unwrap()
  assert_eq(
    publication_contract_json(selected.artifact),
    rows.get(publication_contract_identity(selected.artifact)).unwrap(),
  )
  assert_true(owner.release_view(view) is Err(CommitEncoding))
  owner.release_observed_commit(view).unwrap()
  assert_true(owner.finish_observed_commit(view) is Err(CommitEncoding))
  assert_true(
    owner.begin_observed_commit(view, request, attempt, index)
    is Err(CommitEncoding),
  )
  owner.release_view(view).unwrap()
  fixture.preparation.cancel()
  println(
    "stored original first work=\{first_work}, observed work=\{observed_work}",
  )
  assert_eq(observed_work, 1)
}

///|
test "stored original commit copied contract retains complete validation" {
  let fixture = commit_read_fixture()
  let rows = stored_publication_test_rows(fixture)
  for copied in [5, 6, 7] {
    let owner = stored_publication_test_load(
      fixture,
      cid => Ok(rows.get(cid)),
      () => Ok(()),
    ).unwrap()
    commit_read_complete(owner, 64) |> ignore
    let view = owner.finish_view().unwrap()
    let originals = [
      owner.view_contract(view, 5).unwrap(),
      owner.view_contract(view, 6).unwrap(),
      owner.view_contract(view, 7).unwrap(),
    ]
    let original = originals[copied - 5]
    originals[copied - 5] = admit_publication_contract(
      if copied == 5 {
        "publication_request"
      } else if copied == 6 {
        "publication_attempt"
      } else {
        "public_index_entry"
      },
      publication_contract_json(original),
      65536,
      4096,
      32,
    ).unwrap()
    assert_false(physical_equal(original, originals[copied - 5]))
    owner
    .begin_observed_commit(view, originals[0], originals[1], originals[2])
    .unwrap()
    let work = observed_commit_test_complete(owner, view, 64)
    assert_true(work > 1)
    assert_eq(
      publication_contract_json(owner.finish_observed_commit(view).unwrap()),
      publication_contract_json(originals[2]),
    )
    owner.release_observed_commit(view).unwrap()
    owner.release_view(view).unwrap()
  }
  fixture.preparation.cancel()
}

///|
test "stored original commit borrowed inventories and cancellation retain original duties" {
  let fixture = commit_read_fixture()
  let owner = fixture.preparation
  commit_read_complete(owner, 64) |> ignore
  let view = owner.finish_view().unwrap()
  owner
  .begin_observed_commit(
    view,
    fixture.originals[5],
    fixture.originals[6],
    fixture.originals[7],
  )
  .unwrap()
  assert_true(observed_commit_test_complete(owner, view, 64) > 1)
  owner.release_observed_commit(view).unwrap()
  owner.release_view(view).unwrap()
  let rows = stored_publication_test_rows(fixture)
  let loaded = stored_publication_test_load(fixture, cid => Ok(rows.get(cid)), () => {
    Ok(())
  }).unwrap()
  commit_read_complete(loaded, 64) |> ignore
  let loaded_view = loaded.finish_view().unwrap()
  loaded
  .begin_observed_commit(
    loaded_view,
    loaded.view_contract(loaded_view, 5).unwrap(),
    loaded.view_contract(loaded_view, 6).unwrap(),
    loaded.view_contract(loaded_view, 7).unwrap(),
  )
  .unwrap()
  loaded.cancel()
  assert_true(
    loaded.advance_observed_commit(loaded_view, 1) is Err(CommitEncoding),
  )
  assert_true(loaded.finish_observed_commit(loaded_view) is Err(CommitEncoding))
  loaded.release_observed_commit(loaded_view).unwrap()
  loaded.release_view(loaded_view).unwrap()
}
