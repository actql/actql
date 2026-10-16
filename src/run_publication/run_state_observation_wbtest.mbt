///|
fn revision_observation_fixture(
  at : String,
  state : ResultAvailabilityState,
  reason : ResultAvailabilityReason,
  revision : Int64,
) -> RunStateObservation raise {
  let wire = issue_succeeded_run_state(
    "original-run",
    at,
    ["answer"],
    [{ name: "answer", state, reason, }],
    [at],
    65536,
    1024,
    16,
  ).unwrap()
  let source = parse_contract_wire(wire, 65536, 1024, 16).unwrap()
  let writer = @encode.writer(65536, 1024, 16)
  emit_run_state_revision(writer, source, revision)
  let complete = @encode.finish(writer)
  assert_eq(
    complete,
    wire.replace(
      old="\"run_id\":",
      new="\"revision\":" + revision.to_string() + ",\"run_id\":",
    ),
  )
  let candidate = parse_contract_wire(complete, 65536, 1024, 16).unwrap()
  assert_true(
    validate_generated_protocol_shape(
      "run_state", candidate, true, 65536, 1024, 16,
    ),
  )
  let prepared = prepare_run_state_observation(
    wire, "original-run", revision, 65536, 1024, 16,
  )
  assert_eq(prepared.map(_ => true), Ok(true))
  prepared.unwrap()
}

///|
test "Run state revision is stable for rereads and advances for actual availability" {
  let first = revision_observation_fixture(
    "2026-10-16T00:00:00.000Z",
    Available,
    ConfirmedPresent,
    0L,
  )
  let later_read = revision_observation_fixture(
    "2026-10-16T00:00:01.000Z",
    Available,
    ConfirmedPresent,
    0L,
  )
  assert_eq(first.next_revision(None, 0L), Ok(0L))
  assert_eq(later_read.key(), first.key())
  assert_eq(later_read.next_revision(Some(first.key()), 0L), Ok(0L))
  let unknown = revision_observation_fixture(
    "2026-10-16T00:00:02.000Z",
    Unknown,
    StoreQueryFailed,
    0L,
  )
  assert_true(unknown.key() != first.key())
  assert_eq(unknown.next_revision(Some(first.key()), 0L), Ok(1L))
  let wire = unknown.wire(1L).unwrap()
  let value = parse_contract_wire(wire, 65536, 1024, 16).unwrap()
  assert_true(
    validate_generated_protocol_shape("run_state", value, true, 65536, 1024, 16),
  )
  assert_true(wire.contains("\"revision\":1"))
  assert_true(wire.contains("\"status\":\"succeeded\""))
  assert_true(wire.contains("\"state\":\"unknown\""))
}

///|
test "Run state revision refuses foreign Run malformed current wire and exhaustion" {
  let original = revision_observation_fixture(
    "2026-10-16T00:00:00.000Z",
    Available,
    ConfirmedPresent,
    7L,
  )
  let wire = original.wire(7L).unwrap()
  assert_true(
    prepare_run_state_observation(wire, "other-run", 7L, 65536, 1024, 16)
    is Err(ForeignRun),
  )
  for bad in ["null", "-1", "1.5", "9007199254740992", "true"] {
    assert_true(
      prepare_run_state_observation(
        wire.replace(old="\"revision\":7", new="\"revision\":" + bad),
        "original-run",
        7L,
        65536,
        1024,
        16,
      )
      is Err(InvalidRevision),
    )
  }
  assert_true(original.next_revision(None, 7L) is Err(InvalidPriorObservation))
  assert_true(
    original.next_revision(Some(""), 7L) is Err(InvalidPriorObservation),
  )
  assert_eq(
    original.next_revision(Some(original.key()), 9007199254740991L),
    Ok(9007199254740991L),
  )
  assert_true(
    original.next_revision(Some("changed"), 9007199254740991L)
    is Err(RevisionExhausted),
  )
  assert_true(original.wire(-1L) is Err(InvalidRevision))
  assert_true(original.wire(9007199254740992L) is Err(InvalidRevision))
  assert_true(
    prepare_run_state_observation(
      wire.replace(
        old="\"status\":\"succeeded\"",
        new="\"status\":\"invented\"",
      ),
      "original-run",
      7L,
      65536,
      1024,
      16,
    )
    is Err(InvalidObservation),
  )
}

///|
test "Run state revision retains control changes separately from its state clock" {
  let original = revision_observation_fixture(
    "2026-10-16T00:00:00.000Z",
    Available,
    ConfirmedPresent,
    0L,
  )
  let base = original.wire(0L).unwrap()
  let with_control = revision => {
    base.replace(
      old="{\"next_action\"",
      new="{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":" +
        revision +
        "},\"next_action\"",
    )
  }
  let first = prepare_run_state_observation(
    with_control("3"),
    "original-run",
    9L,
    65536,
    1024,
    16,
  ).unwrap()
  let next = prepare_run_state_observation(
    with_control("4"),
    "original-run",
    9L,
    65536,
    1024,
    16,
  ).unwrap()
  assert_true(first.key() != next.key())
  assert_eq(next.next_revision(Some(first.key()), 9L), Ok(10L))
  let public_wire = next.wire(10L).unwrap()
  assert_true(
    public_wire.contains("\"physical_stop\":\"unknown\",\"revision\":4"),
  )
  assert_true(public_wire.contains("\"revision\":10"))
}
