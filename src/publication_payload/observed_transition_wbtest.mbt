///|
fn persistence_observation(
  transition : PublicationPayloadTransition,
) -> DurablePublicationPayloadRecord {
  admit_durable_publication_payload_record(
    @utf8.encode(
      publication_payload_transition_durable_json(transition).unwrap(),
    ),
  ).unwrap()
}

///|
test "portable payload persistence accepts the original exact successor once" {
  let record = prepare_publication_payload_record(payload_request())
  let transition = prepare_publication_payload_reserved(record).unwrap()
  let observed = persistence_observation(transition)
  let committed = commit_observed_publication_payload_transition(
    transition,
    payload_cid("1"),
    payload_cid("3"),
    1L,
    observed,
  ).unwrap()
  assert_eq(publication_payload_record_state(committed), Reserved)
  assert_eq(publication_payload_record_revision(committed), 1)
  assert_true(
    commit_observed_publication_payload_transition(
      transition,
      payload_cid("1"),
      payload_cid("3"),
      1L,
      observed,
    )
    is Err(StateCollision),
  )
  assert_eq(publication_payload_record_revision(record), 1)
}

///|
test "portable payload persistence rejects foreign material and CAS generation" {
  let record = prepare_publication_payload_record(payload_request())
  let transition = prepare_publication_payload_reserved(record).unwrap()
  let observed = persistence_observation(transition)
  assert_true(
    commit_observed_publication_payload_transition(
      transition,
      payload_cid("1"),
      payload_cid("a"),
      1L,
      observed,
    )
    is Err(StateCollision),
  )
  assert_true(
    commit_observed_publication_payload_transition(
      transition,
      payload_cid("a"),
      payload_cid("3"),
      1L,
      observed,
    )
    is Err(StateCollision),
  )
  for physical in [-1L, 0L, 2L, 9223372036854775807L] {
    assert_true(
      commit_observed_publication_payload_transition(
        transition,
        payload_cid("1"),
        payload_cid("3"),
        physical,
        observed,
      )
      is Err(StateCollision),
    )
  }
  assert_eq(publication_payload_record_state(record), Intent)
  assert_eq(publication_payload_record_revision(record), 0)
}

///|
test "portable payload persistence rejects a different request in the same material" {
  let request = prepare_publication_payload_request(
    payload_cid("a"),
    payload_cid("2"),
    payload_cid("3"),
    payload_cid("4"),
    payload_cid("5"),
    payload_cid("6"),
    payload_cid("7"),
    payload_cid("8"),
    1024L,
    2L,
  ).unwrap()
  let foreign = prepare_publication_payload_record(request)
  let observed = persistence_observation(
    prepare_publication_payload_reserved(foreign).unwrap(),
  )
  let record = prepare_publication_payload_record(payload_request())
  assert_true(
    commit_observed_publication_payload_transition(
      prepare_publication_payload_reserved(record).unwrap(),
      payload_cid("1"),
      payload_cid("3"),
      1L,
      observed,
    )
    is Err(StateCollision),
  )
  assert_eq(publication_payload_record_state(record), Intent)
  assert_eq(publication_payload_record_revision(record), 0)
}

///|
test "portable payload persistence rejects admitted bytes for another successor" {
  let record = prepare_publication_payload_record(payload_request())
  let transition = prepare_publication_payload_reserved(record).unwrap()
  let wire = publication_payload_transition_durable_json(transition).unwrap()
  for
    changed in [
      wire.replace(old="\"state\":\"reserved\"", new="\"state\":\"writing\""),
      wire.replace(old="\"revision\":\"1\"", new="\"revision\":\"2\""),
    ] {
    let observed = admit_durable_publication_payload_record(
      @utf8.encode(changed),
    ).unwrap()
    assert_true(
      commit_observed_publication_payload_transition(
        transition,
        payload_cid("1"),
        payload_cid("3"),
        1L,
        observed,
      )
      is Err(StateCollision),
    )
  }
  assert_eq(publication_payload_record_state(record), Intent)
  assert_eq(publication_payload_record_revision(record), 0)
}
