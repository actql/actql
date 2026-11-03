///|
pub(all) enum LookupBoundsIssue {
  InvalidLimits
  ForeignEnvironment
  WorkLimit
  MissingPolicy(Int)
  UnrepresentableBound(Int)
  DecodedResponseLimit(Int)
} derive(Eq, Debug)

///|
pub struct LookupCounts {
  input_rows : Int64
  distinct_keys : Int64
  keys_per_batch : Int64
  batches : Int64
  pages_per_batch : Int64
  requests : Int64
  network_attempts : Int64
  rows_per_key : Int64
  response_rows : Int64
  decoded_response_bytes : Int64
} derive(Eq, Debug)

///|
struct LookupBounds {
  rows : KeyedRowBounds
  policy : @environment.LookupExecution
  entries : Array[LookupRequirement]
  work : Int
}

///|
/// Whether the optional estimate fits the declared planning envelope. Neither
/// variant grants resources: every acquisition still requires runtime admission.
pub enum LookupAdmission {
  EstimatedEnvelope
  RuntimeAdmission
}

///|
pub struct LookupRequirement {
  join : KeyedJoin
  estimate : LookupCounts?
  admission : LookupAdmission
}

///|
fn lookup_product(a : Int64, b : Int64) -> Int64? {
  if a == 0 || b == 0 {
    return Some(0L)
  }
  if a > 9007199254740991L / b {
    None
  } else {
    Some(a * b)
  }
}

///|
fn lookup_counts(
  rows : Int64,
  batch_cap : Double?,
  pages : Int64,
  per_key : Int64,
  page_bytes : Int64,
  attempts : Int64,
) -> LookupCounts? {
  // The estimate can be genuinely zero. All capability arguments are admitted
  // positive safe integers. No batch, page or provider attempt is needed then.
  if rows == 0 {
    return Some({
      input_rows: 0L,
      distinct_keys: 0L,
      keys_per_batch: 0L,
      batches: 0L,
      pages_per_batch: pages,
      requests: 0L,
      network_attempts: 0L,
      rows_per_key: per_key,
      response_rows: 0L,
      decoded_response_bytes: 0L,
    })
  }
  // Clamp the declared batch capability before conversion: it can exceed 2^53.
  let keys = match batch_cap {
    None => 1L
    Some(cap) => if cap >= rows.to_double() { rows } else { cap.to_int64() }
  }
  let batches = rows / keys + (if rows % keys == 0 { 0L } else { 1L })
  guard lookup_product(batches, pages) is Some(requests) else { return None }
  guard lookup_product(requests, attempts) is Some(network_attempts) else {
    return None
  }
  guard lookup_product(rows, per_key) is Some(response_rows) else {
    return None
  }
  guard lookup_product(requests, page_bytes) is Some(decoded_response_bytes) else {
    return None
  }
  Some({
    input_rows: rows,
    distinct_keys: rows,
    keys_per_batch: keys,
    batches,
    pages_per_batch: pages,
    requests,
    network_attempts,
    rows_per_key: per_key,
    response_rows,
    decoded_response_bytes,
  })
}

///|
/// Resolve logical acquisition extents, retaining all producer and policy owners.
/// Transport reservations, source authority and producer closure remain required.
pub fn check_lookup_bounds(
  rows : KeyedRowBounds,
  policy : @environment.LookupExecution,
  max_work : Int,
) -> Result[LookupBounds, LookupBoundsIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let inputs = rows.facts.joins.requests.uses.attachment.inputs
  if !physical_equal(
      pipeline_environment(inputs),
      @environment.lookup_execution_environment(policy),
    ) {
    return Err(ForeignEnvironment)
  }
  let mut work = 0
  let entries = []
  for i in 0..<rows.requirements.length() {
    if work >= max_work {
      return Err(WorkLimit)
    }
    work += 1
    let facts = rows.facts.entries[i]
    let step = facts.join.step_index
    let selected = match @environment.lookup_execution_policy(policy) {
      Some(v) => v
      None => return Err(MissingPolicy(step))
    }
    let source = keyed_request_input(facts.join.request.request)
    let batch = @environment.source_request_batching(source.selected.contract).map(
      @environment.source_batching_max_keys,
    )
    let capacity = facts.capacity
    let counts = keyed_rows_at(rows, i).bind(bound =>
      lookup_counts(
        @capacity.target_rows_value(bound),
        batch,
        @environment.lookup_capacity_pages_per_request(capacity),
        @environment.lookup_capacity_rows_per_key(capacity),
        @environment.lookup_capacity_response_bytes_per_page(capacity),
        @environment.lookup_execution_ceiling(
          selected,
          @environment.NetworkAttemptsPerRequest,
        ),
      ),
    )
    let admission = match counts {
      Some(counts) if counts.decoded_response_bytes <= @environment.lookup_execution_ceiling(
        selected,
        @environment.TotalResponseDecodedBytes,
      ) => LookupAdmission::EstimatedEnvelope
      _ => LookupAdmission::RuntimeAdmission
    }
    // A conservative upper estimate exceeding a ceiling is not a proof that
    // actual execution exceeds it. Retain the estimate, original join and
    // policy, then require actual runtime admission before allocation/access.
    entries.push({ join: facts.join, estimate: counts, admission, })
  }
  Ok({ rows, policy, entries, work, })
}

///|
pub fn lookup_bounds_rows(v : LookupBounds) -> KeyedRowBounds {
  v.rows
}

///|
pub fn lookup_bounds_policy(v : LookupBounds) -> @environment.LookupExecution {
  v.policy
}

///|
pub fn lookup_bounds_work(v : LookupBounds) -> Int {
  v.work
}

///|
pub fn lookup_bounds_count(v : LookupBounds) -> Int {
  v.entries.length()
}

///|
pub fn lookup_bounds_at(v : LookupBounds, i : Int) -> LookupCounts? {
  v.entries.get(i).bind(entry => entry.estimate)
}

///|
pub fn lookup_requirement_at(v : LookupBounds, i : Int) -> LookupRequirement? {
  v.entries.get(i)
}

///|
pub fn lookup_requirement_join(v : LookupRequirement) -> KeyedJoin {
  v.join
}

///|
pub fn lookup_requirement_estimate(v : LookupRequirement) -> LookupCounts? {
  v.estimate
}

///|
pub fn lookup_requirement_admission(v : LookupRequirement) -> LookupAdmission {
  v.admission
}
