///|
test "portable initial payload observation keeps the original Intent" {
  let record = prepare_publication_payload_record(payload_request())
  let observed = admit_durable_publication_payload_record(
    @utf8.encode(publication_payload_record_durable_json(record).unwrap()),
  ).unwrap()
  let confirmed = confirm_initial_publication_payload_record(
    record,
    payload_cid("1"),
    payload_cid("3"),
    0L,
    observed,
  ).unwrap()
  assert_eq(publication_payload_record_state(confirmed), Intent)
  assert_eq(publication_payload_record_revision(confirmed), 0)
  assert_eq(publication_payload_record_ownership(confirmed), None)
  let transition = prepare_publication_payload_reserved(record).unwrap()
  commit_observed_publication_payload_transition(
    transition,
    payload_cid("1"),
    payload_cid("3"),
    1L,
    persistence_observation(transition),
  ).unwrap()
  |> ignore
  assert_eq(publication_payload_record_state(confirmed), Reserved)
  assert_true(
    confirm_initial_publication_payload_record(
      record,
      payload_cid("1"),
      payload_cid("3"),
      0L,
      observed,
    )
    is Err(StateCollision),
  )
}

///|
test "portable initial payload observation rejects foreign physical facts" {
  let record = prepare_publication_payload_record(payload_request())
  let observed = admit_durable_publication_payload_record(
    @utf8.encode(publication_payload_record_durable_json(record).unwrap()),
  ).unwrap()
  for
    (store, material, revision) in [
      (payload_cid("a"), payload_cid("3"), 0L),
      (payload_cid("1"), payload_cid("a"), 0L),
      (payload_cid("1"), payload_cid("3"), -1L),
      (payload_cid("1"), payload_cid("3"), 1L),
    ] {
    assert_true(
      confirm_initial_publication_payload_record(
        record, store, material, revision, observed,
      )
      is Err(StateCollision),
    )
  }
  assert_eq(publication_payload_record_state(record), Intent)
  assert_eq(publication_payload_record_revision(record), 0)
}

///|
test "portable initial payload observation rejects admitted later bytes" {
  let record = prepare_publication_payload_record(payload_request())
  let observed = persistence_observation(
    prepare_publication_payload_reserved(record).unwrap(),
  )
  assert_true(
    confirm_initial_publication_payload_record(
      record,
      payload_cid("1"),
      payload_cid("3"),
      0L,
      observed,
    )
    is Err(StateCollision),
  )
  assert_eq(publication_payload_record_state(record), Intent)
  assert_eq(publication_payload_record_revision(record), 0)
}
