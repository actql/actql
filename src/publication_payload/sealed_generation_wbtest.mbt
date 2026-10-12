///|
fn sealed_generation_record() -> PublicationPayloadRecord {
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
    prepare_publication_payload_owned(record, { device: 9UL, inode: 8UL, }).unwrap(),
    true,
  ).unwrap()
  |> ignore
  commit_publication_payload_transition(
    prepare_publication_payload_sealed(
      record,
      { device: 9UL, inode: 8UL, size: 12L, },
      payload_cid("a"),
    ).unwrap(),
    true,
  ).unwrap()
  |> ignore
  record
}

///|
test "Sealed generation read-only observation retains original state body and revision" {
  let record = sealed_generation_record()
  let body = publication_payload_record_durable_json(record).unwrap()
  let revision = publication_payload_record_revision(record)
  validate_publication_payload_sealed_generation(
    record,
    { device: 9UL, inode: 8UL, size: 12L, },
    payload_cid("a"),
  ).unwrap()
  validate_publication_payload_sealed_generation(
    record,
    { device: 9UL, inode: 8UL, size: 12L, },
    payload_cid("a"),
  ).unwrap()
  assert_eq(publication_payload_record_durable_json(record).unwrap(), body)
  assert_eq(publication_payload_record_revision(record), revision)
  assert_eq(publication_payload_record_state(record), Sealed)
}

///|
test "Sealed generation independently refuses wrong device inode size and digest" {
  let record = sealed_generation_record()
  for
    bad in [
      { device: 10UL, inode: 8UL, size: 12L, },
      { device: 9UL, inode: 9UL, size: 12L, },
      { device: 9UL, inode: 8UL, size: 13L, },
      { device: 9UL, inode: 8UL, size: -1L, },
    ] {
    assert_true(
      validate_publication_payload_sealed_generation(
        record,
        bad,
        payload_cid("a"),
      )
      is Err(IdentityMismatch),
    )
  }
  for bad in [payload_cid("b"), "not-a-digest"] {
    assert_true(
      validate_publication_payload_sealed_generation(
        record,
        { device: 9UL, inode: 8UL, size: 12L, },
        bad,
      )
      is Err(IdentityMismatch),
    )
  }
}

///|
test "Sealed generation refuses unsealed and reclaimed records without mutation" {
  let initial = prepare_publication_payload_record(payload_request())
  assert_true(
    validate_publication_payload_sealed_generation(
      initial,
      { device: 9UL, inode: 8UL, size: 12L, },
      payload_cid("a"),
    )
    is Err(InvalidRecord),
  )
  let record = sealed_generation_record()
  commit_publication_payload_transition(
    prepare_publication_payload_reclaiming(record).unwrap(),
    true,
  ).unwrap()
  |> ignore
  assert_true(
    validate_publication_payload_sealed_generation(
      record,
      { device: 9UL, inode: 8UL, size: 12L, },
      payload_cid("a"),
    )
    is Err(InvalidRecord),
  )
  assert_eq(publication_payload_record_state(record), Reclaiming)
}

///|
test "Sealed generation rejects absent or inconsistent original ownership" {
  let record = sealed_generation_record()
  record.ownership = None
  assert_true(
    validate_publication_payload_sealed_generation(
      record,
      { device: 9UL, inode: 8UL, size: 12L, },
      payload_cid("a"),
    )
    is Err(InvalidRecord),
  )
  record.ownership = Some({ device: 10UL, inode: 8UL, })
  assert_true(
    validate_publication_payload_sealed_generation(
      record,
      { device: 9UL, inode: 8UL, size: 12L, },
      payload_cid("a"),
    )
    is Err(IdentityMismatch),
  )
}

///|
test "Sealed generation refuses opaque ownership or generation" {
  let record = sealed_generation_record()
  record.opaque_ownership_cid = Some(payload_cid("e"))
  assert_true(
    validate_publication_payload_sealed_generation(
      record,
      { device: 9UL, inode: 8UL, size: 12L, },
      payload_cid("a"),
    )
    is Err(InvalidRecord),
  )
  record.opaque_ownership_cid = None
  record.opaque_generation_cid = Some(payload_cid("f"))
  assert_true(
    validate_publication_payload_sealed_generation(
      record,
      { device: 9UL, inode: 8UL, size: 12L, },
      payload_cid("a"),
    )
    is Err(InvalidRecord),
  )
}

///|
test "Sealed generation compares actual byte count separately" {
  let record = sealed_generation_record()
  record.actual_bytes = 13L
  assert_true(
    validate_publication_payload_sealed_generation(
      record,
      { device: 9UL, inode: 8UL, size: 12L, },
      payload_cid("a"),
    )
    is Err(IdentityMismatch),
  )
}
