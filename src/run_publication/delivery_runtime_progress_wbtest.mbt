///|
fn delivery_runtime_record(state : String) -> PublicationContract {
  let wire = "{\"cleanup_owner_cids\":[],\"confirmed_byte_count\":0,\"delivered_sha256\":null,\"delivery_attempt_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"delivery_record_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"exposure\":\"exact\",\"failure_cid\":null,\"observed_at\":\"2026-09-19T00:00:00Z\",\"possible_unconfirmed_max_bytes\":null,\"prior_record_cid\":null,\"result_delivery_receipt_cid\":null,\"sequence\":0,\"state\":\"" +
    state +
    "\"}"
  {
    name: "delivery_record",
    identity_field: "delivery_record_cid",
    identity: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    wire,
    value: parse_contract_wire(wire, 4096, 128, 16).unwrap(),
  }
}

///|
test "existing delivery progression distinguishes reusable and terminal facts" {
  assert_eq(
    prepare_existing_delivery_attempt(
      Some(delivery_runtime_record("succeeded")),
    ),
    DeliveryConfirmSucceededRecord,
  )
  assert_eq(
    prepare_existing_delivery_attempt(
      Some(delivery_runtime_record("streaming")),
    ),
    DeliveryRejectUnresolvedAttempt,
  )
  assert_eq(
    prepare_existing_delivery_attempt(Some(delivery_runtime_record("failed"))),
    DeliveryRejectTerminalAttempt,
  )
  assert_eq(
    prepare_existing_delivery_attempt(None),
    ExistingDeliveryAttemptInvalid,
  )
}

///|
test "delivery failure terminal state follows the observed cancellation" {
  assert_eq(prepare_delivery_failure_terminal(false), DeliveryAppendFailed)
  assert_eq(prepare_delivery_failure_terminal(true), DeliveryAppendCancelled)
}

///|
test "delivery durability retry preserves issued record order" {
  assert_eq(prepare_delivery_record_retry_step(0, 2), DeliveryAppendNextRecord)
  assert_eq(prepare_delivery_record_retry_step(1, 2), DeliveryAppendNextRecord)
  assert_eq(
    prepare_delivery_record_retry_step(2, 2),
    DeliveryRecordRetryFinished,
  )
  assert_eq(
    prepare_delivery_record_retry_step(3, 2),
    DeliveryRecordRetryInvalid,
  )
}
