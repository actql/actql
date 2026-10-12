///|
test "portable capacity observation prepares the original transition only" {
  let record = prepare_publication_payload_record(payload_request())
  let transition = prepare_observed_publication_payload_reserved(
    record,
    payload_cid("1"),
    "publication_payload",
    payload_cid("3"),
    1024L,
    1L,
  ).unwrap()
  assert_eq(publication_payload_record_state(record), Intent)
  assert_eq(publication_payload_record_revision(record), 0)
  assert_eq(publication_payload_record_ownership(record), None)
  assert_eq(publication_payload_record_generation(record), None)
  let confirmed = commit_observed_publication_payload_transition(
    transition,
    payload_cid("1"),
    payload_cid("3"),
    1L,
    persistence_observation(transition),
  ).unwrap()
  assert_true(physical_equal(confirmed, record))
  assert_eq(publication_payload_record_state(record), Reserved)
  assert_eq(publication_payload_record_revision(record), 1)
  assert_eq(publication_payload_record_ownership(record), None)
  assert_eq(publication_payload_record_generation(record), None)
}

///|
test "portable capacity observation rejects foreign or changed reservations" {
  let record = prepare_publication_payload_record(payload_request())
  for
    (store, scope, material, bytes, objects) in [
      (payload_cid("a"), "publication_payload", payload_cid("3"), 1024L, 1L),
      (payload_cid("1"), "other", payload_cid("3"), 1024L, 1L),
      (payload_cid("1"), "", payload_cid("3"), 1024L, 1L),
      (payload_cid("1"), "publication_payload", payload_cid("a"), 1024L, 1L),
      (payload_cid("1"), "publication_payload", payload_cid("3"), 1023L, 1L),
      (payload_cid("1"), "publication_payload", payload_cid("3"), 1025L, 1L),
      (payload_cid("1"), "publication_payload", payload_cid("3"), -1L, 1L),
      (payload_cid("1"), "publication_payload", payload_cid("3"), 1024L, 0L),
      (payload_cid("1"), "publication_payload", payload_cid("3"), 1024L, 2L),
    ] {
    assert_true(
      prepare_observed_publication_payload_reserved(
        record, store, scope, material, bytes, objects,
      )
      is Err(StateCollision),
    )
  }
  assert_eq(publication_payload_record_state(record), Intent)
  assert_eq(publication_payload_record_revision(record), 0)
  assert_eq(publication_payload_record_ownership(record), None)
}

///|
test "portable capacity observation cannot replace durable commit evidence" {
  let record = prepare_publication_payload_record(payload_request())
  let transition = prepare_observed_publication_payload_reserved(
    record,
    payload_cid("1"),
    "publication_payload",
    payload_cid("3"),
    1024L,
    1L,
  ).unwrap()
  let durable = persistence_observation(transition)
  assert_true(
    commit_publication_payload_transition(transition, false)
    is Err(InvalidTransition),
  )
  assert_true(
    commit_observed_publication_payload_transition(
      transition,
      payload_cid("1"),
      payload_cid("3"),
      0L,
      durable,
    )
    is Err(StateCollision),
  )
  assert_eq(publication_payload_record_state(record), Intent)
  assert_eq(publication_payload_record_revision(record), 0)
  commit_observed_publication_payload_transition(
    transition,
    payload_cid("1"),
    payload_cid("3"),
    1L,
    durable,
  ).unwrap()
  |> ignore
  assert_true(
    prepare_observed_publication_payload_reserved(
      record,
      payload_cid("1"),
      "publication_payload",
      payload_cid("3"),
      1024L,
      1L,
    )
    is Err(InvalidTransition),
  )
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
  assert_eq(publication_payload_record_state(record), Reserved)
  assert_eq(publication_payload_record_revision(record), 1)
}
