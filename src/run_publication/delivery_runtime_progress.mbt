///|
/// Progression when a delivery attempt already exists. The portable owner
/// decides whether a terminal receipt can be reused or whether the attempt is
/// unresolved; the Store only supplies the admitted latest record.
pub(all) enum ExistingDeliveryAttemptAction {
  DeliveryConfirmSucceededRecord
  DeliveryRejectUnresolvedAttempt
  DeliveryRejectTerminalAttempt
  ExistingDeliveryAttemptInvalid
} derive(Eq, Debug)

///|
fn delivery_record_state(record : PublicationContract) -> String? {
  if record.name != "delivery_record" {
    return None
  }
  contract_string(record, "state")
}

///|
pub fn prepare_existing_delivery_attempt(
  record : PublicationContract?,
) -> ExistingDeliveryAttemptAction {
  match record {
    None => ExistingDeliveryAttemptInvalid
    Some(value) =>
      match delivery_record_state(value) {
        Some("succeeded") => DeliveryConfirmSucceededRecord
        Some("streaming") => DeliveryRejectUnresolvedAttempt
        Some("failed") | Some("cancelled") => DeliveryRejectTerminalAttempt
        _ => ExistingDeliveryAttemptInvalid
      }
  }
}

///|
pub fn existing_delivery_attempt_action_code(
  action : ExistingDeliveryAttemptAction,
) -> Int {
  match action {
    DeliveryConfirmSucceededRecord => 0
    DeliveryRejectUnresolvedAttempt => 1
    DeliveryRejectTerminalAttempt => 2
    ExistingDeliveryAttemptInvalid => 3
  }
}

///|
pub(all) struct DeliveryRecordProjection {
  delivery_attempt_cid : String
  state : String
  confirmed_byte_count : Int64
  delivered_sha256 : String?
  result_delivery_receipt_cid : String?
}

///|
pub fn project_delivery_record(
  record : PublicationContract,
) -> Result[DeliveryRecordProjection, DeliveryIssuanceIssue] {
  if record.name != "delivery_record" {
    return Err(DeliveryIssuanceWrongContract("delivery_record"))
  }
  guard contract_string(record, "delivery_attempt_cid") is Some(attempt_cid) &&
    contract_string(record, "state") is Some(state) &&
    contract_count(record, "confirmed_byte_count") is Some(confirmed) else {
    return Err(DeliveryIssuanceReferenceMismatch("delivery_record"))
  }
  Ok({
    delivery_attempt_cid: attempt_cid,
    state,
    confirmed_byte_count: confirmed,
    delivered_sha256: contract_string(record, "delivered_sha256"),
    result_delivery_receipt_cid: contract_string(
      record, "result_delivery_receipt_cid",
    ),
  })
}

///|
/// Terminal record state after a delivery failure. Cancellation is an
/// observed request, not proof that a partially exposed prefix was retracted.
pub(all) enum DeliveryFailureTerminalAction {
  DeliveryAppendFailed
  DeliveryAppendCancelled
} derive(Eq, Debug)

///|
pub fn prepare_delivery_failure_terminal(
  cancellation_observed : Bool,
) -> DeliveryFailureTerminalAction {
  if cancellation_observed {
    DeliveryAppendCancelled
  } else {
    DeliveryAppendFailed
  }
}

///|
pub fn delivery_failure_terminal_action_code(
  action : DeliveryFailureTerminalAction,
) -> Int {
  match action {
    DeliveryAppendFailed => 0
    DeliveryAppendCancelled => 1
  }
}

///|
pub fn delivery_failure_terminal_state(
  action : DeliveryFailureTerminalAction,
) -> String {
  match action {
    DeliveryAppendFailed => "failed"
    DeliveryAppendCancelled => "cancelled"
  }
}

///|
/// Ordered durability retry for records already issued by the portable
/// contract owner. A retry never regenerates a record or resends payload.
pub(all) enum DeliveryRecordRetryAction {
  DeliveryAppendNextRecord
  DeliveryRecordRetryFinished
  DeliveryRecordRetryInvalid
} derive(Eq, Debug)

///|
pub fn prepare_delivery_record_retry_step(
  next_record : Int,
  record_count : Int,
) -> DeliveryRecordRetryAction {
  if next_record < 0 || record_count < 0 || next_record > record_count {
    return DeliveryRecordRetryInvalid
  }
  if next_record == record_count {
    DeliveryRecordRetryFinished
  } else {
    DeliveryAppendNextRecord
  }
}

///|
pub fn delivery_record_retry_action_code(
  action : DeliveryRecordRetryAction,
) -> Int {
  match action {
    DeliveryAppendNextRecord => 0
    DeliveryRecordRetryFinished => 1
    DeliveryRecordRetryInvalid => 2
  }
}
