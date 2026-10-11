///|
fn observed_commit_test_pair(
  fixture : CommitReadFixture,
) -> (PublicationContract, PublicationContract) {
  let original = fixture.originals
  let attempt = issue_publication_attempt(
    original[5],
    original[0],
    "original-earlier-attempt",
    ordering_test_cid("6"),
    None,
    "2026-09-17T00:00:01.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let index = issue_public_index_entry(
    original[0], original[1], original[2], original[3], original[4], [original[13]],
    original[5], attempt, "2026-09-17T00:00:02.000Z", 65536, 4096, 32,
  ).unwrap()
  (attempt, index)
}

///|
fn observed_commit_test_complete(
  owner : PublicationCommitPreparation,
  view : PublicationCommitReadView,
  quantum : Int,
) -> Int raise {
  let mut work = 0
  for _ in 0..<500000 {
    let (done, used) = owner.advance_observed_commit(view, quantum).unwrap()
    assert_true(used <= quantum)
    work += used
    if done {
      return work
    }
    assert_true(used > 0)
  }
  abort("Observed validation exceeded the original finite fixture bound")
}

///|
test "stored commit validates full original chain and returns actual earlier index" {
  let mut expected_work = None
  for quantum in [1, 7, 64] {
    let fixture = commit_read_fixture()
    let owner = fixture.preparation
    commit_read_complete(owner, 64) |> ignore
    let view = owner.finish_view().unwrap()
    let (attempt, stored) = observed_commit_test_pair(fixture)
    let candidate = fixture.originals[7]
    assert_true(public_index_same_committed_content(stored, candidate))
    assert_true(publication_contract_identity(stored) != publication_contract_identity(candidate))
    owner.begin_observed_commit(view, fixture.originals[5], attempt, stored).unwrap()
    assert_true(owner.finish_observed_commit(view) is Err(CommitEncoding))
    assert_true(owner.release_view(view) is Err(CommitEncoding))
    let work = observed_commit_test_complete(owner, view, quantum)
    match expected_work {
      Some(expected) => assert_eq(work, expected)
      None => expected_work = Some(work)
    }
    let returned = owner.finish_observed_commit(view).unwrap()
    assert_true(physical_equal(returned, stored))
    assert_true(physical_equal(owner.view_contract(view, 7).unwrap(), candidate))
    for ordinal in 0..<14 {
      assert_true(physical_equal(owner.view_contract(view, ordinal).unwrap(), fixture.originals[ordinal]))
    }
    assert_true(owner.release_view(view) is Err(CommitEncoding))
    owner.release_observed_commit(view).unwrap()
    owner.release_observed_commit(view).unwrap()
    assert_true(owner.finish_observed_commit(view) is Err(CommitEncoding))
    assert_true(owner.begin_observed_commit(view, fixture.originals[5], attempt, stored) is Err(CommitEncoding))
    owner.release_view(view).unwrap()
  }
}

///|
test "same committed content cannot bypass wrong saved attempt full chain" {
  let fixture = commit_read_fixture()
  let owner = fixture.preparation
  commit_read_complete(owner, 64) |> ignore
  let view = owner.finish_view().unwrap()
  let (attempt, stored) = observed_commit_test_pair(fixture)
  // The existing same-content predicate intentionally excludes attempt/time.
  // A valid contract with a dangling attempt must still fail full validation.
  let wrong = admit_publication_contract(
    "public_index_entry",
    publication_contract_json(stored).replace(
      old=publication_contract_identity(attempt),
      new=ordering_test_cid("f"),
    ),
    65536, 4096, 32,
  ).unwrap()
  assert_true(public_index_same_committed_content(wrong, fixture.originals[7]))
  owner.begin_observed_commit(view, fixture.originals[5], attempt, wrong).unwrap()
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
  assert_eq(owner.view_count(view).unwrap(), 14)
  owner.release_observed_commit(view).unwrap()
  owner.release_view(view).unwrap()
}

///|
test "stored request mismatch does not acquire a child or replace original scope" {
  let fixture = commit_read_fixture()
  let owner = fixture.preparation
  commit_read_complete(owner, 64) |> ignore
  let view = owner.finish_view().unwrap()
  let (attempt, index) = observed_commit_test_pair(fixture)
  let wrong = admit_publication_contract(
    "publication_request",
    publication_contract_json(fixture.originals[5]).replace(old="local", new="other-namespace"),
    65536, 4096, 32,
  ).unwrap()
  assert_true(owner.begin_observed_commit(view, wrong, attempt, index) is Err(CommitReferenceMismatch("stored_request")))
  assert_true(owner.advance_observed_commit(view, 1) is Err(CommitEncoding))
  assert_true(owner.finish_observed_commit(view) is Err(CommitEncoding))
  owner.release_view(view).unwrap()
}

///|
test "stored index altered binding cannot borrow original schema evidence" {
  let fixture = commit_read_fixture()
  let owner = fixture.preparation
  commit_read_complete(owner, 64) |> ignore
  let view = owner.finish_view().unwrap()
  let (attempt, index) = observed_commit_test_pair(fixture)
  let wrong = admit_publication_contract(
    "public_index_entry",
    publication_contract_json(index).replace(old=publication_contract_identity(fixture.originals[13]), new=ordering_test_cid("f")),
    65536, 4096, 32,
  ).unwrap()
  assert_true(!public_index_same_committed_content(wrong, fixture.originals[7]))
  owner.begin_observed_commit(view, fixture.originals[5], attempt, wrong).unwrap()
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

///|
test "stored validation rejects foreign view and cancelled original owner" {
  let first = commit_read_fixture()
  let second = commit_read_fixture()
  commit_read_complete(first.preparation, 64) |> ignore
  commit_read_complete(second.preparation, 64) |> ignore
  let view = first.preparation.finish_view().unwrap()
  let foreign = second.preparation.finish_view().unwrap()
  let (attempt, index) = observed_commit_test_pair(first)
  assert_true(first.preparation.begin_observed_commit(foreign, first.originals[5], attempt, index) is Err(CommitEncoding))
  first.preparation.begin_observed_commit(view, first.originals[5], attempt, index).unwrap()
  assert_true(first.preparation.advance_observed_commit(foreign, 1) is Err(CommitEncoding))
  first.preparation.advance_observed_commit(view, 1).unwrap() |> ignore
  first.preparation.cancel()
  assert_true(first.preparation.advance_observed_commit(view, 1) is Err(CommitEncoding))
  assert_true(first.preparation.finish_observed_commit(view) is Err(CommitEncoding))
  first.preparation.release_observed_commit(view).unwrap()
  first.preparation.release_view(view).unwrap()
  second.preparation.release_view(foreign).unwrap()
}
