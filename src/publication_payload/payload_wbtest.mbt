///|
fn payload_cid(character : String) -> String {
  "sha256:" + character.repeat(64)
}

///|
fn payload_request() -> PublicationPayloadRequest {
  prepare_publication_payload_request(
    payload_cid("1"),
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
}

///|
test "publication payload lifecycle is monotonic and durable" {
  let request = payload_request()
  assert_true(
    publication_payload_request_identity(request).has_prefix("sha256:"),
  )
  assert_eq(
    publication_payload_staging_name(request),
    "stage-" + "3".repeat(64),
  )
  let record = prepare_publication_payload_record(request)
  let initial = publication_payload_record_durable_json(record).unwrap()
  let restored = restore_durable_publication_payload_record(
    admit_durable_publication_payload_record(@utf8.encode(initial)).unwrap(),
  ).unwrap()
  assert_eq(publication_payload_record_state(restored), Intent)
  commit_publication_payload_transition(
    prepare_publication_payload_reserved(record).unwrap(),
    true,
  )
  |> ignore
  commit_publication_payload_transition(
    prepare_publication_payload_writing(record).unwrap(),
    true,
  )
  |> ignore
  let generation = { device: 1UL, inode: 2UL, size: 12L, }
  commit_publication_payload_transition(
    prepare_publication_payload_sealed(record, generation, payload_cid("a")).unwrap(),
    true,
  )
  |> ignore
  assert_eq(publication_payload_record_state(record), Sealed)
  let sealed_body = publication_payload_record_durable_json(record).unwrap()
  let reopened = restore_durable_publication_payload_record(
    admit_durable_publication_payload_record(@utf8.encode(sealed_body)).unwrap(),
  ).unwrap()
  assert_eq(publication_payload_record_generation(reopened), Some(generation))
  assert_eq(publication_payload_record_digest(reopened), payload_cid("a"))
  commit_publication_payload_transition(
    prepare_publication_payload_reclaiming(reopened).unwrap(),
    true,
  )
  |> ignore
  commit_publication_payload_transition(
    prepare_publication_payload_reclaimed(reopened).unwrap(),
    true,
  )
  |> ignore
  assert_eq(publication_payload_record_state(reopened), Reclaimed)
  assert_true(prepare_publication_payload_reserved(reopened) is Err(_))
}

///|
test "publication payload rejects invalid limits and forged records" {
  assert_true(
    prepare_publication_payload_request(
      payload_cid("1"),
      payload_cid("2"),
      payload_cid("3"),
      payload_cid("4"),
      payload_cid("5"),
      payload_cid("6"),
      payload_cid("7"),
      payload_cid("8"),
      0L,
      0L,
    )
    is Err(InvalidRequest),
  )
  let record = prepare_publication_payload_record(payload_request())
  commit_publication_payload_transition(
    prepare_publication_payload_reserved(record).unwrap(),
    true,
  )
  |> ignore
  commit_publication_payload_transition(
    prepare_publication_payload_writing(record).unwrap(),
    true,
  )
  |> ignore
  assert_true(
    prepare_publication_payload_sealed(
      record,
      { device: 1UL, inode: 2UL, size: 1025L, },
      payload_cid("a"),
    )
    is Err(InvalidTransition),
  )
  let body = publication_payload_record_durable_json(record).unwrap()
  assert_true(
    admit_durable_publication_payload_record(
      @utf8.encode(body.replace(old="\"writing\"", new="\"sealed\"")),
    )
    is Err(InvalidRecord),
  )
}

///|
test "publication payload cleanup can bind a discovered exact generation" {
  let record = prepare_publication_payload_record(payload_request())
  commit_publication_payload_transition(
    prepare_publication_payload_reserved(record).unwrap(),
    true,
  )
  |> ignore
  let generation = { device: 9UL, inode: 8UL, size: 0L, }
  commit_publication_payload_transition(
    prepare_publication_payload_reclaiming(
      record,
      discovered_generation=Some(generation),
    ).unwrap(),
    true,
  )
  |> ignore
  assert_eq(publication_payload_record_generation(record), Some(generation))
  assert_true(
    prepare_publication_payload_reclaiming(
      record,
      discovered_generation=Some({ ..generation, inode: 7UL, }),
    )
    is Err(InvalidTransition),
  )
}
