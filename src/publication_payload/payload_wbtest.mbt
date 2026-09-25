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
  let ownership = { device: generation.device, inode: generation.inode, }
  commit_publication_payload_transition(
    prepare_publication_payload_owned(record, ownership).unwrap(),
    true,
  )
  |> ignore
  commit_publication_payload_transition(
    prepare_publication_payload_sealed(record, generation, payload_cid("a")).unwrap(),
    true,
  )
  |> ignore
  assert_eq(publication_payload_record_state(record), Sealed)
  let sealed_body = publication_payload_record_durable_json(record).unwrap()
  assert_true(sealed_body.contains("actql-publication-payload-record/0.2"))
  assert_true(
    admit_durable_publication_payload_record(
      @utf8.encode(
        sealed_body.replace(
          old="actql-publication-payload-record/0.2",
          new="actql-publication-payload-record/0.1",
        ),
      ),
    )
    is Err(InvalidRecord),
  )
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
  commit_publication_payload_transition(
    prepare_publication_payload_owned(record, { device: 1UL, inode: 2UL, }).unwrap(),
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
test "publication payload cleanup requires recorded allocation ownership" {
  let record = prepare_publication_payload_record(payload_request())
  commit_publication_payload_transition(
    prepare_publication_payload_reserved(record).unwrap(),
    true,
  )
  |> ignore
  let generation = { device: 9UL, inode: 8UL, size: 0L, }
  assert_true(
    prepare_publication_payload_reclaiming(
      record,
      discovered_generation=Some(generation),
    )
    is Err(StateCollision),
  )
  commit_publication_payload_transition(
    prepare_publication_payload_writing(record).unwrap(),
    true,
  )
  |> ignore
  commit_publication_payload_transition(
    prepare_publication_payload_owned(record, {
      device: generation.device,
      inode: generation.inode,
    }).unwrap(),
    true,
  )
  |> ignore
  commit_publication_payload_transition(
    prepare_publication_payload_reclaiming(
      record,
      discovered_generation=Some(generation),
    ).unwrap(),
    true,
  )
  |> ignore
  assert_eq(publication_payload_record_generation(record), None)
  assert_eq(
    publication_payload_record_ownership(record),
    Some({ device: generation.device, inode: generation.inode, }),
  )
  assert_true(
    prepare_publication_payload_reclaiming(
      record,
      discovered_generation=Some({ ..generation, inode: 7UL, }),
    )
    is Err(InvalidTransition),
  )
}

///|
test "opaque payload custody uses the same durable transition owner" {
  let record = prepare_publication_payload_record(payload_request())
  let custody = payload_cid("9")
  let digest = payload_cid("a")
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
    prepare_publication_payload_opaque_sealed(record, custody, 12L, digest)
    is Err(InvalidTransition),
  )
  commit_publication_payload_transition(
    prepare_publication_payload_opaque_owned(record, custody).unwrap(),
    true,
  )
  |> ignore
  let writing = publication_payload_record_durable_json(record).unwrap()
  assert_true(writing.contains("actql-publication-payload-record/0.3"))
  let reopened = restore_durable_publication_payload_record(
    admit_durable_publication_payload_record(@utf8.encode(writing)).unwrap(),
  ).unwrap()
  assert_true(
    prepare_publication_payload_sealed(
      reopened,
      { device: 1UL, inode: 2UL, size: 12L, },
      digest,
    )
    is Err(InvalidTransition),
  )
  assert_true(
    prepare_publication_payload_opaque_sealed(
      reopened,
      payload_cid("b"),
      12L,
      digest,
    )
    is Err(InvalidTransition),
  )
  commit_publication_payload_transition(
    prepare_publication_payload_opaque_sealed(reopened, custody, 12L, digest).unwrap(),
    true,
  )
  |> ignore
  let sealed_body = publication_payload_record_durable_json(reopened).unwrap()
  let restored = restore_durable_publication_payload_record(
    admit_durable_publication_payload_record(@utf8.encode(sealed_body)).unwrap(),
  ).unwrap()
  assert_eq(
    publication_payload_record_opaque_generation(restored),
    Some(custody),
  )
  assert_eq(publication_payload_record_digest(restored), digest)
  assert_true(
    admit_durable_publication_payload_record(
      @utf8.encode(
        sealed_body.replace(
          old="\"custody_generation_cid\":\"" + custody + "\"",
          new="\"custody_generation_cid\":\"" + payload_cid("b") + "\"",
        ),
      ),
    )
    is Err(InvalidRecord),
  )
  assert_true(
    prepare_publication_payload_opaque_reclaiming(restored, payload_cid("b"))
    is Err(StateCollision),
  )
  commit_publication_payload_transition(
    prepare_publication_payload_opaque_reclaiming(restored, custody).unwrap(),
    true,
  )
  |> ignore
  commit_publication_payload_transition(
    prepare_publication_payload_reclaimed(restored).unwrap(),
    true,
  )
  |> ignore
  assert_eq(publication_payload_record_state(restored), Reclaimed)
}
