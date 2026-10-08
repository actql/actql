///|
pub(all) enum ObservationIssue {
  InvalidObservationBudget
  ObservationBudgetUnavailable
  ForeignObservationCustody
  ObservationRecordLimit
  ObservationRunLimit
} derive(Eq, Debug)

///|
pub(all) enum ObservationCharge {
  ObservationCharged
  ObservationRepeated
} derive(Eq, Debug)

///|
/// Optional storage copies these finite fields exactly. Missing custody is not
/// a zero balance. Run/request identity is independent of observation scope.
pub(all) struct ObservationBudgetSnapshot {
  scope_key : String
  request_key : String
  max_records : Int
  max_bytes : Int
  records : Int
  bytes : Int
  last_fact : String?
} derive(Eq, Debug)

///|
struct ObservationBudget {
  scope : ObservationScope
  request_key : String
  max_records : Int
  max_bytes : Int
  mut records : Int
  mut bytes : Int
  mut last_fact : String?
}

///|
fn valid_fact(value : String?) -> Bool {
  match value {
    None => true
    Some(text) => {
      if text.length() == 0 || text.length() > 512 {
        return false
      }
      for index in 0..<text.length() {
        if text[index] < ' ' || text[index] > '~' {
          return false
        }
      }
      true
    }
  }
}

///|
/// Only a freshly committed request may initialize missing optional custody.
/// The physical journal supplies that fact, never a Run caller or trace flag.
/// Existing requests and changed scopes cannot replenish observation budgets.
pub fn open_observation_budget(
  scope : ObservationScope,
  request_key : String,
  max_records : Int,
  max_bytes : Int,
  fresh_request : Bool,
  saved : ObservationBudgetSnapshot?,
) -> Result[ObservationBudget, ObservationIssue] {
  if !observation_subject(request_key) ||
    max_records < 1 ||
    max_records > 2048 ||
    max_bytes < 1 ||
    max_bytes > 1048576 {
    return Err(InvalidObservationBudget)
  }
  let (records, bytes, last_fact) = match saved {
    None => {
      if !fresh_request {
        return Err(ObservationBudgetUnavailable)
      }
      (0, 0, None)
    }
    Some(saved) => {
      if fresh_request ||
        saved.scope_key != observation_scope_key(scope) ||
        saved.request_key != request_key ||
        saved.max_records != max_records ||
        saved.max_bytes != max_bytes {
        return Err(ForeignObservationCustody)
      }
      if saved.records < 0 ||
        saved.records > max_records ||
        saved.bytes < 0 ||
        saved.bytes > max_bytes ||
        (saved.records == 0 && saved.bytes != 0) ||
        (saved.records > 0 && saved.bytes < saved.records) ||
        (saved.records == 0 && saved.last_fact != None) ||
        !valid_fact(saved.last_fact) {
        return Err(ObservationBudgetUnavailable)
      }
      (saved.records, saved.bytes, saved.last_fact)
    }
  }
  Ok({ scope, request_key, max_records, max_bytes, records, bytes, last_fact, })
}

///|
/// Charge before queueing. A queue drop does not refund cumulative consumption.
/// Deduplication suppresses only an already verified diagnostic fact; it never
/// skips dispatch, execution, publication, cleanup, or evidence capture.
pub fn charge_observation(
  budget : ObservationBudget,
  scope : ObservationScope,
  request_key : String,
  fact : String?,
  record_bytes : Int,
) -> Result[ObservationCharge, ObservationIssue] {
  if budget.scope != scope || budget.request_key != request_key {
    return Err(ForeignObservationCustody)
  }
  if record_bytes < 1 || record_bytes > 4096 || !valid_fact(fact) {
    return Err(ObservationRecordLimit)
  }
  if fact != None && fact == budget.last_fact {
    return Ok(ObservationRepeated)
  }
  if budget.records >= budget.max_records ||
    record_bytes > budget.max_bytes - budget.bytes {
    return Err(ObservationRunLimit)
  }
  budget.records = budget.records + 1
  budget.bytes = budget.bytes + record_bytes
  if fact != None {
    budget.last_fact = fact
  }
  Ok(ObservationCharged)
}

///|
pub fn observation_budget_snapshot(
  budget : ObservationBudget,
) -> ObservationBudgetSnapshot {
  {
    scope_key: observation_scope_key(budget.scope),
    request_key: budget.request_key,
    max_records: budget.max_records,
    max_bytes: budget.max_bytes,
    records: budget.records,
    bytes: budget.bytes,
    last_fact: budget.last_fact,
  }
}
