///|
fn allocation_writing_record() -> PublicationPayloadRecord {
  let record = prepare_publication_payload_record(payload_request())
  for transition in [prepare_publication_payload_reserved(record).unwrap()] {
    let body = publication_payload_transition_durable_json(transition).unwrap()
    commit_observed_publication_payload_transition(
      transition,
      payload_cid("1"),
      payload_cid("3"),
      1L,
      admit_durable_publication_payload_record(@utf8.encode(body)).unwrap(),
    ).unwrap()
    |> ignore
  }
  let transition = prepare_publication_payload_writing(record).unwrap()
  let body = publication_payload_transition_durable_json(transition).unwrap()
  commit_observed_publication_payload_transition(
    transition,
    payload_cid("1"),
    payload_cid("3"),
    2L,
    admit_durable_publication_payload_record(@utf8.encode(body)).unwrap(),
  ).unwrap()
  |> ignore
  record
}

///|
fn allocation_observation(
  record : PublicationPayloadRecord,
  revision : Int64,
  body : String,
) -> PublicationPayloadAllocationObservation {
  admit_observed_publication_payload_allocation(
    publication_payload_record_request(record),
    payload_cid("1"),
    "publication_payload_allocation",
    payload_cid("3"),
    revision,
    @utf8.encode(body),
  ).unwrap()
}

///|
test "allocation intent exact successor is bound to unowned original Writing" {
  let record = allocation_writing_record()
  let write = prepare_publication_payload_allocation_intent_write(record, None).unwrap()
  let expected_name = "alloc-" + "3".repeat(64) + "-1"
  assert_eq(
    publication_payload_allocation_write_body(write),
    @utf8.encode(expected_name),
  )
  assert_eq(publication_payload_allocation_write_previous_revision(write), None)
  assert_eq(publication_payload_allocation_write_previous_body(write), None)
  assert_eq(
    publication_payload_request_identity(
      publication_payload_allocation_write_request(write),
    ),
    publication_payload_request_identity(payload_request()),
  )
  let observed = allocation_observation(record, 0L, expected_name)
  confirm_observed_publication_payload_allocation_write(write, observed).unwrap()
  |> ignore
  // Confirmation is read-only even if the first caller loses its reply.
  confirm_observed_publication_payload_allocation_write(write, observed).unwrap()
  |> ignore
  assert_eq(publication_payload_record_revision(record), 2)
  assert_eq(publication_payload_record_state(record), Writing)
  assert_eq(publication_payload_record_ownership(record), None)
}

///|
test "allocation ordinal comes from original recorded area not physical revision" {
  let record = allocation_writing_record()
  let old_body = "alloc-" + "3".repeat(64) + "-7|41|73"
  let previous = allocation_observation(record, 19L, old_body)
  let write = prepare_publication_payload_allocation_intent_write(
    record,
    Some(previous),
  ).unwrap()
  let expected = "alloc-" + "3".repeat(64) + "-8"
  assert_eq(
    publication_payload_allocation_write_body(write),
    @utf8.encode(expected),
  )
  assert_eq(
    publication_payload_allocation_write_previous_revision(write),
    Some(19L),
  )
  assert_eq(
    publication_payload_allocation_write_previous_body(write),
    Some(@utf8.encode(old_body)),
  )
  assert_true(
    confirm_observed_publication_payload_allocation_write(
      write,
      allocation_observation(record, 19L, expected),
    )
    is Err(StateCollision),
  )
  confirm_observed_publication_payload_allocation_write(
    write,
    allocation_observation(record, 20L, expected),
  ).unwrap()
  |> ignore
}

///|
test "allocation directory ownership keeps original payload file unowned" {
  let record = allocation_writing_record()
  let name = "alloc-" + "3".repeat(64) + "-1"
  let intent = allocation_observation(record, 0L, name)
  let write = prepare_publication_payload_allocation_ownership_write(
    record,
    intent,
    { device: 41UL, inode: 73UL, },
  ).unwrap()
  assert_eq(
    publication_payload_allocation_write_body(write),
    @utf8.encode(name + "|41|73"),
  )
  assert_eq(
    publication_payload_allocation_write_previous_revision(write),
    Some(0L),
  )
  assert_eq(
    publication_payload_allocation_ownership(
      publication_payload_allocation_write_value(write),
    ),
    Some({ device: 41UL, inode: 73UL, }),
  )
  let confirmed = confirm_observed_publication_payload_allocation_write(
    write,
    allocation_observation(record, 1L, name + "|41|73"),
  ).unwrap()
  assert_true(
    prepare_publication_payload_allocation_ownership_write(record, confirmed, {
      device: 41UL,
      inode: 74UL,
    })
    is Err(StateCollision),
  )
  assert_eq(publication_payload_record_state(record), Writing)
  assert_eq(publication_payload_record_revision(record), 2)
  assert_eq(publication_payload_record_ownership(record), None)
}

///|
test "allocation observation refuses different namespace store material request and revision" {
  let record = allocation_writing_record()
  let request = payload_request()
  let body = @utf8.encode("alloc-" + "3".repeat(64) + "-1")
  for
    (store, storage_namespace, material, revision) in [
      (payload_cid("9"), "publication_payload_allocation", payload_cid("3"), 0L),
      (payload_cid("1"), "publication_payload", payload_cid("3"), 0L),
      (payload_cid("1"), "publication_payload_allocation", payload_cid("9"), 0L),
      (
        payload_cid("1"),
        "publication_payload_allocation",
        payload_cid("3"),
        -1L,
      ),
    ] {
    assert_true(
      admit_observed_publication_payload_allocation(
        request, store, storage_namespace, material, revision, body,
      )
      is Err(StateCollision),
    )
  }
  let foreign_request = prepare_publication_payload_request(
    payload_cid("1"),
    payload_cid("9"),
    payload_cid("3"),
    payload_cid("4"),
    payload_cid("5"),
    payload_cid("6"),
    payload_cid("7"),
    payload_cid("8"),
    1024L,
    2L,
  ).unwrap()
  let foreign = admit_observed_publication_payload_allocation(
    foreign_request,
    payload_cid("1"),
    "publication_payload_allocation",
    payload_cid("3"),
    0L,
    body,
  ).unwrap()
  assert_true(
    prepare_publication_payload_allocation_intent_write(record, Some(foreign))
    is Err(StateCollision),
  )
  let exhausted = allocation_observation(
    record,
    9223372036854775807L,
    "alloc-" + "3".repeat(64) + "-1",
  )
  assert_true(
    prepare_publication_payload_allocation_intent_write(record, Some(exhausted))
    is Err(StateCollision),
  )
}

///|
test "allocation confirmation rejects later body and original record advance" {
  let record = allocation_writing_record()
  let name = "alloc-" + "3".repeat(64) + "-1"
  let write = prepare_publication_payload_allocation_intent_write(record, None).unwrap()
  for
    observed in [
      allocation_observation(record, 1L, name),
      allocation_observation(record, 0L, name + "|41|73"),
      allocation_observation(record, 0L, "alloc-" + "3".repeat(64) + "-2"),
    ] {
    assert_true(
      confirm_observed_publication_payload_allocation_write(write, observed)
      is Err(StateCollision),
    )
  }
  let observed = allocation_observation(record, 0L, name)
  let owned = prepare_publication_payload_owned(record, {
    device: 5UL,
    inode: 6UL,
  }).unwrap()
  let body = publication_payload_transition_durable_json(owned).unwrap()
  commit_observed_publication_payload_transition(
    owned,
    payload_cid("1"),
    payload_cid("3"),
    3L,
    admit_durable_publication_payload_record(@utf8.encode(body)).unwrap(),
  ).unwrap()
  |> ignore
  assert_true(
    validate_publication_payload_allocation_write(write) is Err(StateCollision),
  )
  assert_true(
    confirm_observed_publication_payload_allocation_write(write, observed)
    is Err(StateCollision),
  )
  assert_eq(publication_payload_record_revision(record), 3)
  assert_eq(
    publication_payload_record_ownership(record),
    Some({ device: 5UL, inode: 6UL, }),
  )
}

///|
test "allocation preparation cannot replace missing or wrong payload phase" {
  let record = prepare_publication_payload_record(payload_request())
  assert_true(
    prepare_publication_payload_allocation_intent_write(record, None)
    is Err(InvalidTransition),
  )
  let transition = prepare_publication_payload_reserved(record).unwrap()
  let body = publication_payload_transition_durable_json(transition).unwrap()
  commit_observed_publication_payload_transition(
    transition,
    payload_cid("1"),
    payload_cid("3"),
    1L,
    admit_durable_publication_payload_record(@utf8.encode(body)).unwrap(),
  ).unwrap()
  |> ignore
  assert_true(
    prepare_publication_payload_allocation_intent_write(record, None)
    is Err(InvalidTransition),
  )
  assert_eq(publication_payload_record_revision(record), 1)
  assert_eq(publication_payload_record_state(record), Reserved)
}
