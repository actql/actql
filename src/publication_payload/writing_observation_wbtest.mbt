///|
fn writing_original() -> PublicationPayloadRecord {
  let record = prepare_publication_payload_record(payload_request())
  let reserved = prepare_publication_payload_reserved(record).unwrap()
  commit_observed_publication_payload_transition(
    reserved,
    payload_cid("1"),
    payload_cid("3"),
    1L,
    persistence_observation(reserved),
  ).unwrap()
  |> ignore
  record
}

///|
test "portable writing and exact ownership require separate original durable successors" {
  let original = writing_original()
  let writing = prepare_publication_payload_writing(original).unwrap()
  assert_eq(publication_payload_record_state(original), Reserved)
  assert_eq(publication_payload_record_revision(original), 1)
  assert_true(
    prepare_publication_payload_owned(original, { device: 1UL, inode: 2UL, })
    is Err(InvalidTransition),
  )
  let durable_writing = persistence_observation(writing)
  assert_true(
    confirm_committed_publication_payload_transition(
      writing,
      payload_cid("1"),
      payload_cid("3"),
      2L,
      durable_writing,
    )
    is Err(StateCollision),
  )
  let committed = commit_observed_publication_payload_transition(
    writing,
    payload_cid("1"),
    payload_cid("3"),
    2L,
    durable_writing,
  ).unwrap()
  assert_true(physical_equal(original, committed))
  assert_eq(publication_payload_record_state(original), Writing)
  assert_eq(publication_payload_record_revision(original), 2)
  assert_eq(publication_payload_record_ownership(original), None)
  // Independent exact values above binary64's precision and at UInt64's limit.
  let expected = { device: 9007199254740993UL, inode: 18446744073709551615UL, }
  let owned = prepare_publication_payload_owned(original, expected).unwrap()
  assert_eq(publication_payload_record_ownership(original), None)
  let durable_owned = persistence_observation(owned)
  commit_observed_publication_payload_transition(
    owned,
    payload_cid("1"),
    payload_cid("3"),
    3L,
    durable_owned,
  ).unwrap()
  |> ignore
  assert_eq(publication_payload_record_ownership(original), Some(expected))
  assert_eq(publication_payload_record_revision(original), 3)
  for _ in 0..<2 {
    let confirmed = confirm_committed_publication_payload_transition(
      owned,
      payload_cid("1"),
      payload_cid("3"),
      3L,
      durable_owned,
    ).unwrap()
    assert_true(physical_equal(original, confirmed))
    assert_eq(publication_payload_record_revision(original), 3)
  }
  assert_true(
    prepare_publication_payload_owned(original, expected)
    is Err(InvalidTransition),
  )
  assert_true(
    prepare_publication_payload_writing(original) is Err(InvalidTransition),
  )
  assert_true(
    confirm_committed_publication_payload_transition(
      writing,
      payload_cid("1"),
      payload_cid("3"),
      2L,
      durable_writing,
    )
    is Err(StateCollision),
  )
}

///|
test "portable writing refuses foreign store material revision or durable ownership" {
  let original = writing_original()
  let transition = prepare_publication_payload_writing(original).unwrap()
  let durable = persistence_observation(transition)
  for
    (store, material, revision) in [
      (payload_cid("a"), payload_cid("3"), 2L),
      (payload_cid("1"), payload_cid("a"), 2L),
      (payload_cid("1"), payload_cid("3"), 1L),
      (payload_cid("1"), payload_cid("3"), 3L),
    ] {
    assert_true(
      commit_observed_publication_payload_transition(
        transition, store, material, revision, durable,
      )
      is Err(StateCollision),
    )
    assert_eq(publication_payload_record_state(original), Reserved)
    assert_eq(publication_payload_record_revision(original), 1)
  }
  commit_observed_publication_payload_transition(
    transition,
    payload_cid("1"),
    payload_cid("3"),
    2L,
    durable,
  ).unwrap()
  |> ignore
  let owned = prepare_publication_payload_owned(original, {
    device: 1UL,
    inode: 2UL,
  }).unwrap()
  let another = prepare_publication_payload_owned(original, {
    device: 1UL,
    inode: 3UL,
  }).unwrap()
  assert_true(
    commit_observed_publication_payload_transition(
      owned,
      payload_cid("1"),
      payload_cid("3"),
      3L,
      persistence_observation(another),
    )
    is Err(StateCollision),
  )
  assert_eq(publication_payload_record_ownership(original), None)
  assert_eq(publication_payload_record_revision(original), 2)
}
