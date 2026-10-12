///|
test "stored lookup references retain original request and actual earlier attempt" {
  let fixture = commit_read_fixture()
  let owner = fixture.preparation
  commit_read_complete(owner, 64) |> ignore
  let view = owner.finish_view().unwrap()
  let (attempt, index) = observed_commit_test_pair(fixture)
  let reference = publication_contract_identity(index)
  assert_eq(
    owner.view_inspected_index_reference(view, reference, index, 0).unwrap(),
    publication_contract_identity(fixture.originals[5]),
  )
  assert_eq(
    owner.view_inspected_index_reference(view, reference, index, 1).unwrap(),
    publication_contract_identity(attempt),
  )
  assert_true(
    publication_contract_identity(attempt) !=
    publication_contract_identity(fixture.originals[6]),
  )
  // A lookup projection has not started or completed the full-chain child.
  assert_true(owner.finish_observed_commit(view) is Err(CommitEncoding))
  assert_true(
    physical_equal(owner.view_contract(view, 7).unwrap(), fixture.originals[7]),
  )
  owner.release_view(view).unwrap()
}

///|
test "stored lookup refuses reference identity scope and original request collisions" {
  let fixture = commit_read_fixture()
  let owner = fixture.preparation
  commit_read_complete(owner, 64) |> ignore
  let view = owner.finish_view().unwrap()
  let (_, index) = observed_commit_test_pair(fixture)
  assert_true(
    owner.view_inspected_index_reference(view, ordering_test_cid("f"), index, 0)
    is Err(CommitReferenceMismatch("stored_index.identity")),
  )
  let body = observed_commit_test_body(index)
  for
    (before, after) in [
      (
        project_public_index_read(index).unwrap().namespace_id,
        "another-namespace",
      ),
      (
        project_public_index_read(index).unwrap().authority_scope_cid,
        ordering_test_cid("f"),
      ),
      (
        project_public_index_read(index).unwrap().run_definition_cid,
        ordering_test_cid("f"),
      ),
      (
        project_public_index_read(index).unwrap().publication_request_cid,
        ordering_test_cid("f"),
      ),
    ] {
    assert_true(body.contains(before))
    let wrong = seal_publication_contract(
      "public_index_entry",
      body.replace(old=before, new=after),
      65536,
      4096,
      32,
    ).unwrap()
    assert_true(
      owner.view_inspected_index_reference(
        view,
        publication_contract_identity(wrong),
        wrong,
        0,
      )
      is Err(CommitReferenceMismatch("stored_index.scope")),
    )
  }
  owner.release_view(view).unwrap()
}

///|
test "stored lookup refuses foreign released cancelled and incomplete original views" {
  let fixture = commit_read_fixture()
  let owner = fixture.preparation
  assert_true(owner.finish_view() is Err(CommitEncoding))
  commit_read_complete(owner, 64) |> ignore
  let view = owner.finish_view().unwrap()
  let other = commit_read_fixture().preparation
  commit_read_complete(other, 64) |> ignore
  let foreign = other.finish_view().unwrap()
  let (_, index) = observed_commit_test_pair(fixture)
  let reference = publication_contract_identity(index)
  assert_true(
    owner.view_inspected_index_reference(foreign, reference, index, 0)
    is Err(CommitEncoding),
  )
  for field in [-1, 2] {
    assert_true(
      owner.view_inspected_index_reference(view, reference, index, field)
      is Err(CommitEncoding),
    )
  }
  owner.cancel()
  assert_true(
    owner.view_inspected_index_reference(view, reference, index, 0)
    is Err(CommitEncoding),
  )
  owner.release_view(view).unwrap()
  other.release_view(foreign).unwrap()
  assert_true(
    other.view_inspected_index_reference(foreign, reference, index, 0)
    is Err(CommitEncoding),
  )
}

///|
test "stored lookup cannot promote a dangling chain to observed completion" {
  let fixture = commit_read_fixture()
  let owner = fixture.preparation
  commit_read_complete(owner, 64) |> ignore
  let view = owner.finish_view().unwrap()
  let (attempt, index) = observed_commit_test_pair(fixture)
  let wrong = seal_publication_contract(
    "public_index_entry",
    observed_commit_test_body(index).replace(
      old=publication_contract_identity(attempt),
      new=ordering_test_cid("f"),
    ),
    65536,
    4096,
    32,
  ).unwrap()
  assert_eq(
    owner
    .view_inspected_index_reference(
      view,
      publication_contract_identity(wrong),
      wrong,
      1,
    )
    .unwrap(),
    ordering_test_cid("f"),
  )
  assert_true(owner.finish_observed_commit(view) is Err(CommitEncoding))
  owner
  .begin_observed_commit(view, fixture.originals[5], attempt, wrong)
  .unwrap()
  let mut rejected = false
  for _ in 0..<500000 {
    match owner.advance_observed_commit(view, 64) {
      Err(_) => {
        rejected = true
        break
      }
      Ok((true, _)) => break
      Ok((false, _)) => ()
    }
  }
  assert_true(rejected)
  assert_true(owner.finish_observed_commit(view) is Err(CommitEncoding))
  owner.release_observed_commit(view).unwrap()
  owner.release_view(view).unwrap()
}
