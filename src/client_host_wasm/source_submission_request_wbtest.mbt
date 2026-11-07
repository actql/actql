///|
// Actual issued preparation and same original input loans. No physical Host,
// durable Run, clock, Account operation or provider child is supplied.
test "Source request handoff refuses substituted submitted view before Run preparation" {
  let nonce = 6281L
  let (value, record, pool, capacity, slot, environment_slot) = published_preparation_fixture(
    nonce, "SELECT 1 AS n",
  )
  assert_eq(prepare_program(nonce, 2), 0)
  let original = record.submitted.unwrap()
  assert_true(
    physical_equal(
      original,
      stored_preparation_source_submission(value, 2).unwrap(),
    ),
  )
  let pair = record.source.unwrap()
  let foreign = @host.prepare_client_submitted_intent(
    @host.client_submitted_intent_wire(pair.0),
    65536,
    8192,
    64,
  ).unwrap()
  let environment = value.environments[1].environment
  let foreign_source = @preparation.prepare_local_source_computation(
    foreign,
    environment,
    value.environments[1].publication.unwrap(),
  ).unwrap()
  record.submitted = @preparation.local_source_pure_submitted_preparation(
    foreign_source, foreign, environment,
  )
  assert_true(stored_preparation_source_submission(value, 2) is None)
  record.submitted = Some(original)
  let expected = @preparation.local_source_computation_request(
    pair.1,
    "sha256:" + "b".repeat(64),
    "source-request-handoff",
  ).unwrap()
  assert_eq(
    @preparation.local_submitted_preparation_request(
      stored_preparation_source_submission(value, 2).unwrap(),
      "sha256:" + "b".repeat(64),
      "source-request-handoff",
    ).unwrap(),
    expected,
  )
  assert_eq(value.runs.length(), 0)
  published_preparation_close(nonce, pool, capacity, slot, environment_slot)
  assert_true(stored_preparation_source_submission(value, 2) is None)
}
