///|
test "portable committed observation acknowledges the exact original without another commit" {
  let record = prepare_publication_payload_record(payload_request())
  let transition = prepare_publication_payload_reserved(record).unwrap()
  let durable = persistence_observation(transition)
  commit_observed_publication_payload_transition(
    transition,
    payload_cid("1"),
    payload_cid("3"),
    1L,
    durable,
  ).unwrap()
  |> ignore
  for _ in 0..<2 {
    let confirmed = confirm_committed_publication_payload_transition(
      transition,
      payload_cid("1"),
      payload_cid("3"),
      1L,
      durable,
    ).unwrap()
    assert_true(physical_equal(confirmed, record))
    assert_eq(publication_payload_record_revision(record), 1)
    assert_eq(publication_payload_record_state(record), Reserved)
  }
  assert_true(
    commit_observed_publication_payload_transition(
      transition,
      payload_cid("1"),
      payload_cid("3"),
      1L,
      durable,
    )
    is Err(StateCollision),
  )
}

///|
test "portable committed observation refuses uncommitted or foreign observations" {
  let record = prepare_publication_payload_record(payload_request())
  let transition = prepare_publication_payload_reserved(record).unwrap()
  let durable = persistence_observation(transition)
  assert_true(
    confirm_committed_publication_payload_transition(
      transition,
      payload_cid("1"),
      payload_cid("3"),
      1L,
      durable,
    )
    is Err(StateCollision),
  )
  assert_eq(publication_payload_record_revision(record), 0)
  commit_observed_publication_payload_transition(
    transition,
    payload_cid("1"),
    payload_cid("3"),
    1L,
    durable,
  ).unwrap()
  |> ignore
  for
    (store, material, revision) in [
      (payload_cid("a"), payload_cid("3"), 1L),
      (payload_cid("1"), payload_cid("a"), 1L),
      (payload_cid("1"), payload_cid("3"), 0L),
      (payload_cid("1"), payload_cid("3"), 2L),
    ] {
    assert_true(
      confirm_committed_publication_payload_transition(
        transition, store, material, revision, durable,
      )
      is Err(StateCollision),
    )
  }
  assert_eq(publication_payload_record_revision(record), 1)
}

///|
test "portable committed observation refuses later or partially changed original state" {
  let record = prepare_publication_payload_record(payload_request())
  let transition = prepare_publication_payload_reserved(record).unwrap()
  let durable = persistence_observation(transition)
  commit_observed_publication_payload_transition(
    transition,
    payload_cid("1"),
    payload_cid("3"),
    1L,
    durable,
  ).unwrap()
  |> ignore
  record.state = Writing
  assert_true(
    confirm_committed_publication_payload_transition(
      transition,
      payload_cid("1"),
      payload_cid("3"),
      1L,
      durable,
    )
    is Err(StateCollision),
  )
  record.state = Reserved
  commit_publication_payload_transition(
    prepare_publication_payload_writing(record).unwrap(),
    true,
  ).unwrap()
  |> ignore
  assert_true(
    confirm_committed_publication_payload_transition(
      transition,
      payload_cid("1"),
      payload_cid("3"),
      1L,
      durable,
    )
    is Err(StateCollision),
  )
  assert_eq(publication_payload_record_revision(record), 2)
  assert_eq(publication_payload_record_state(record), Writing)
}
