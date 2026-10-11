///|
test "original filesystem names need owned Writing and retain exact request revision" {
  let record = prepare_publication_payload_record(payload_request())
  assert_true(
    publication_payload_filesystem_names_json(record) is Err(InvalidTransition),
  )
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
  assert_true(
    publication_payload_filesystem_names_json(record) is Err(InvalidTransition),
  )
  commit_publication_payload_transition(
    prepare_publication_payload_owned(record, { device: 9UL, inode: 8UL, }).unwrap(),
    true,
  ).unwrap()
  |> ignore
  assert_eq(
    publication_payload_filesystem_names_json(record).unwrap(),
    "{\"material_generation_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"object_name\":\"payload-3333333333333333333333333333333333333333333333333333333333333333\",\"record_revision\":\"3\",\"request_cid\":\"sha256:957551a348a169a8a8a9ac333e517fab5a022b1accc352726b6c86549cb6458e\",\"staging_name\":\"stage-3333333333333333333333333333333333333333333333333333333333333333\",\"store_authority_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"}",
  )
  assert_eq(publication_payload_record_revision(record), 3)
  assert_eq(publication_payload_record_state(record), Writing)
  commit_publication_payload_transition(
    prepare_publication_payload_sealed(
      record,
      { device: 9UL, inode: 8UL, size: 12L, },
      payload_cid("a"),
    ).unwrap(),
    true,
  ).unwrap()
  |> ignore
  assert_eq(
    publication_payload_filesystem_names_json(record).unwrap(),
    "{\"material_generation_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"object_name\":\"payload-3333333333333333333333333333333333333333333333333333333333333333\",\"record_revision\":\"3\",\"request_cid\":\"sha256:957551a348a169a8a8a9ac333e517fab5a022b1accc352726b6c86549cb6458e\",\"staging_name\":\"stage-3333333333333333333333333333333333333333333333333333333333333333\",\"store_authority_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"}".replace(
      old="\"record_revision\":\"3\"",
      new="\"record_revision\":\"4\"",
    ),
  )
  commit_publication_payload_transition(
    prepare_publication_payload_reclaiming(record).unwrap(),
    true,
  ).unwrap()
  |> ignore
  assert_true(
    publication_payload_filesystem_names_json(record) is Err(InvalidTransition),
  )
}

///|
test "opaque ownership cannot supply filesystem names" {
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
  commit_publication_payload_transition(
    prepare_publication_payload_opaque_owned(record, payload_cid("a")).unwrap(),
    true,
  ).unwrap()
  |> ignore
  assert_true(
    publication_payload_filesystem_names_json(record) is Err(InvalidTransition),
  )
}
