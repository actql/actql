///|
priv struct CommitReadFixture {
  preparation : PublicationCommitPreparation
  originals : Array[PublicationContract]
}

///|
/// Actual Receipt/Captured Run and full Result dependencies, rather than the
/// deliberately incomplete reference-only commit_cursor_fixture.
fn commit_read_fixture() -> CommitReadFixture {
  // Independently hashed canonical literal schema, not issuer output.
  let chain = captured_run_test_chain(
    schema_cid="sha256:98fbcb0aa0d1065cf0b027b6390716452941ac4723d0b2cadfce3476280683db",
  )
  let snapshot = admit_captured_result_snapshot(
    chain.definition,
    chain.artifact,
    "[{\"value\":7}]",
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  let captured = issue_effect_free_captured_run(
    chain.run,
    chain.invocation,
    [chain.definition],
    [chain.artifact],
    chain.manifest,
    chain.receipt,
    [snapshot],
    [],
    chain.authoring,
    [],
    65536,
    4096,
    32,
  ).unwrap()
  let derivation = result_ordering_derivation_contract(chain.evidence)
  let ordering = result_ordering_evidence_contract(chain.evidence)
  let binding = issue_durable_result_binding(
    chain.run,
    chain.definition,
    chain.invocation,
    chain.artifact,
    ordering,
    chain.retention,
    ordering_test_cid("1"),
    ["value"],
    "{\"value\":{\"nullable\":false,\"type\":\"integer\"}}",
    ordering_test_cid("2"),
    ordering_test_cid("3"),
    1,
    13,
    "4".repeat(64),
    65536,
    4096,
    32,
  ).unwrap()
  let request = issue_publication_request(
    chain.run,
    [chain.definition],
    "local",
    ordering_test_cid("3"),
    ordering_test_cid("4"),
    ordering_test_cid("5"),
    "2026-09-18T00:00:00.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let attempt = issue_publication_attempt(
    request,
    chain.run,
    "attempt",
    ordering_test_cid("6"),
    None,
    "2026-09-18T00:00:01.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let index_entry = issue_public_index_entry(
    chain.run,
    chain.invocation,
    chain.manifest,
    chain.receipt,
    captured,
    [binding],
    request,
    attempt,
    "2026-09-18T00:00:02.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  {
    preparation: start_effect_free_publication_commit_check(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      [derivation],
      [ordering],
      [chain.retention],
      [binding],
      chain.manifest,
      chain.receipt,
      captured,
      request,
      attempt,
      index_entry,
      65536,
      4096,
      32,
      32768,
    ),
    originals: [
      chain.run,
      chain.invocation,
      chain.manifest,
      chain.receipt,
      captured,
      request,
      attempt,
      index_entry,
      chain.definition,
      chain.artifact,
      derivation,
      ordering,
      chain.retention,
      binding,
    ],
  }
}

///|
fn commit_read_complete(
  preparation : PublicationCommitPreparation,
  quantum : Int,
) -> Int raise {
  let mut work = 0
  for _ in 0..<500000 {
    let (done, used) = preparation.advance(quantum).unwrap()
    assert_true(used <= quantum)
    work += used
    if done {
      return work
    }
    assert_true(used > 0)
  }
  abort("Commit preparation exceeded the finite fixture work bound")
}

///|
test "commit read view projects original full chain with quantum independent work" {
  let mut expected_work = None
  for quantum in [1, 7, 64] {
    let fixture = commit_read_fixture()
    let work = commit_read_complete(fixture.preparation, quantum)
    match expected_work {
      Some(expected) => assert_eq(work, expected)
      None => expected_work = Some(work)
    }
    let view = fixture.preparation.finish_view().unwrap()
    assert_eq(fixture.preparation.view_count(view).unwrap(), 14)
    let expected_names = [
      "run_definition", "run_invocation", "result_manifest", "run_receipt", "captured_run",
      "publication_request", "publication_attempt", "public_index_entry", "result_definition",
      "result_artifact", "derivation_evidence", "ordering_evidence", "result_retention_policy",
      "durable_result_binding",
    ]
    for ordinal in 0..<14 {
      let contract = fixture.preparation.view_contract(view, ordinal).unwrap()
      assert_true(physical_equal(contract, fixture.originals[ordinal]))
      assert_eq(publication_contract_name(contract), expected_names[ordinal])
      assert_eq(
        publication_contract_json(contract),
        publication_contract_json(fixture.originals[ordinal]),
      )
    }
    assert_true(
      fixture.preparation.view_contract(view, -1) is Err(CommitEncoding),
    )
    assert_true(
      fixture.preparation.view_contract(view, 14) is Err(CommitEncoding),
    )
    assert_true(fixture.preparation.finish() is Err(CommitEncoding))
    assert_true(fixture.preparation.finish_view() is Err(CommitEncoding))
    assert_true(fixture.preparation.advance(1) is Err(CommitEncoding))
    fixture.preparation.release_view(view).unwrap()
    fixture.preparation.release_view(view).unwrap()
    assert_true(fixture.preparation.view_count(view) is Err(CommitEncoding))
    assert_true(
      fixture.preparation.view_contract(view, 0) is Err(CommitEncoding),
    )
  }
}

///|
test "commit read view refuses unfinished and cancelled checks" {
  let fixture = commit_read_fixture()
  assert_true(fixture.preparation.finish_view() is Err(CommitEncoding))
  assert_true(fixture.preparation.finish() is Err(CommitEncoding))
  fixture.preparation.advance(1).unwrap() |> ignore
  assert_true(fixture.preparation.finish_view() is Err(CommitEncoding))
  fixture.preparation.cancel()
  fixture.preparation.cancel()
  assert_true(fixture.preparation.finish_view() is Err(CommitEncoding))
  assert_true(fixture.preparation.advance(1) is Err(CommitEncoding))
}

///|
test "commit read view cancellation refuses reads until original cleanup releases it" {
  let fixture = commit_read_fixture()
  commit_read_complete(fixture.preparation, 64) |> ignore
  let view = fixture.preparation.finish_view().unwrap()
  let index_entry = fixture.originals[7]
  let original_wire = publication_contract_json(index_entry)
  fixture.preparation.cancel()
  fixture.preparation.cancel()
  assert_true(fixture.preparation.view_count(view) is Err(CommitEncoding))
  assert_true(fixture.preparation.view_contract(view, 7) is Err(CommitEncoding))
  assert_eq(publication_contract_json(index_entry), original_wire)
  fixture.preparation.release_view(view).unwrap()
  assert_true(fixture.preparation.finish_view() is Err(CommitEncoding))
}

///|
test "commit read view rejects another cursor despite identical original contracts" {
  let first = commit_read_fixture()
  let second = commit_read_fixture()
  commit_read_complete(first.preparation, 64) |> ignore
  commit_read_complete(second.preparation, 64) |> ignore
  let first_view = first.preparation.finish_view().unwrap()
  let second_view = second.preparation.finish_view().unwrap()
  assert_true(second.preparation.view_count(first_view) is Err(CommitEncoding))
  assert_true(
    second.preparation.view_contract(first_view, 7) is Err(CommitEncoding),
  )
  assert_true(
    second.preparation.release_view(first_view) is Err(CommitEncoding),
  )
  assert_eq(first.preparation.view_count(first_view).unwrap(), 14)
  assert_eq(second.preparation.view_count(second_view).unwrap(), 14)
  first.preparation.release_view(first_view).unwrap()
  second.preparation.release_view(second_view).unwrap()
}

///|
test "legacy commit finish releases validation without yielding Store authority" {
  let fixture = commit_read_fixture()
  commit_read_complete(fixture.preparation, 7) |> ignore
  fixture.preparation.finish().unwrap()
  assert_true(fixture.preparation.finish_view() is Err(CommitEncoding))
  assert_true(fixture.preparation.advance(1) is Err(CommitEncoding))
}
