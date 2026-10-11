///|
test "original Sealed preparation needs owned generation and exact durable successor" {
  let record = prepare_publication_payload_record(payload_request())
  commit_publication_payload_transition(
    prepare_publication_payload_reserved(record).unwrap(),
    true,
  ).unwrap()
  |> ignore
  commit_publication_payload_transition(
    prepare_publication_payload_writing(record).unwrap(),
    true,
  ).unwrap()
  |> ignore
  let generation = { device: 9UL, inode: 8UL, size: 12L, }
  assert_true(
    prepare_publication_payload_sealed(record, generation, payload_cid("a"))
    is Err(InvalidTransition),
  )
  commit_publication_payload_transition(
    prepare_publication_payload_owned(record, { device: 9UL, inode: 8UL, }).unwrap(),
    true,
  ).unwrap()
  |> ignore
  for
    bad in [
      { device: 10UL, inode: 8UL, size: 12L, },
      { device: 9UL, inode: 9UL, size: 12L, },
      { device: 9UL, inode: 8UL, size: -1L, },
      { device: 9UL, inode: 8UL, size: 1025L, },
    ] {
    assert_true(
      prepare_publication_payload_sealed(record, bad, payload_cid("a"))
      is Err(InvalidTransition),
    )
  }
  assert_true(
    prepare_publication_payload_sealed(record, generation, "invalid")
    is Err(InvalidTransition),
  )
  let transition = prepare_publication_payload_sealed(
    record,
    generation,
    payload_cid("a"),
  ).unwrap()
  let wire = publication_payload_transition_durable_json(transition).unwrap()
  assert_eq(publication_payload_record_state(record), Writing)
  assert_eq(publication_payload_record_revision(record), 3)
  let durable = admit_durable_publication_payload_record(@utf8.encode(wire)).unwrap()
  assert_true(
    commit_observed_publication_payload_transition(
      transition,
      payload_cid("1"),
      payload_cid("3"),
      5L,
      durable,
    )
    is Err(StateCollision),
  )
  assert_eq(publication_payload_record_state(record), Writing)
  commit_observed_publication_payload_transition(
    transition,
    payload_cid("1"),
    payload_cid("3"),
    4L,
    durable,
  ).unwrap()
  |> ignore
  confirm_committed_publication_payload_transition(
    transition,
    payload_cid("1"),
    payload_cid("3"),
    4L,
    durable,
  ).unwrap()
  |> ignore
  assert_eq(publication_payload_record_revision(record), 4)
  assert_eq(publication_payload_record_state(record), Sealed)
  assert_eq(publication_payload_record_generation(record), Some(generation))
  assert_eq(publication_payload_record_digest(record), payload_cid("a"))
}
