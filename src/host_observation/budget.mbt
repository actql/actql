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
  fact_hashes : Array[String]
} derive(Eq, Debug)

///|
struct ObservationBudget {
  scope : ObservationScope
  request_key : String
  max_records : Int
  max_bytes : Int
  mut records : Int
  mut bytes : Int
  fact_hashes : Array[String]
}

///|
fn valid_fact_hash(text : String) -> Bool {
  if text.length() != 64 {
    return false
  }
  for index in 0..<64 {
    let char = text[index]
    if !(char >= '0' && char <= '9') && !(char >= 'a' && char <= 'f') {
      return false
    }
  }
  true
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
  let (records, bytes, fact_hashes) = match saved {
    None => {
      if !fresh_request {
        return Err(ObservationBudgetUnavailable)
      }
      (0, 0, [])
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
        saved.fact_hashes.length() > saved.records {
        return Err(ObservationBudgetUnavailable)
      }
      let hashes : Array[String] = []
      for hash in saved.fact_hashes {
        if !valid_fact_hash(hash) || hashes.contains(hash) {
          return Err(ObservationBudgetUnavailable)
        }
        hashes.push(hash)
      }
      (saved.records, saved.bytes, hashes)
    }
  }
  Ok({
    scope,
    request_key,
    max_records,
    max_bytes,
    records,
    bytes,
    fact_hashes,
  })
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
  // At most max_records fixed-width digests are retained. Raw diagnostic
  // identities are not persisted; fact-free records remain individually charged.
  let hash = match fact {
    None => None
    Some(text) =>
      match @sha256.text_hex(text) {
        Ok(hash) => Some(hash)
        Err(_) => return Err(ObservationRecordLimit)
      }
  }
  if hash is Some(value) && budget.fact_hashes.contains(value) {
    return Ok(ObservationRepeated)
  }
  if budget.records >= budget.max_records ||
    record_bytes > budget.max_bytes - budget.bytes {
    return Err(ObservationRunLimit)
  }
  budget.records = budget.records + 1
  budget.bytes = budget.bytes + record_bytes
  if hash is Some(value) {
    budget.fact_hashes.push(value)
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
    fact_hashes: budget.fact_hashes.copy(),
  }
}
