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
  entries : Array[LookupCounts]
  work : Int
}

///|
fn lookup_product(a : Int64, b : Int64) -> Int64? {
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
  // All integer arguments come from admitted positive safe-integer contracts.
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
  for i in 0..<rows.bounds.length() {
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
    let counts = match
      lookup_counts(
        @capacity.target_rows_value(rows.bounds[i]),
        batch,
        @environment.lookup_capacity_pages_per_request(capacity),
        @environment.lookup_capacity_rows_per_key(capacity),
        @environment.lookup_capacity_response_bytes_per_page(capacity),
        @environment.lookup_execution_ceiling(
          selected,
          @environment.NetworkAttemptsPerRequest,
        ),
      ) {
      Some(v) => v
      None => return Err(UnrepresentableBound(step))
    }
    if counts.decoded_response_bytes >
      @environment.lookup_execution_ceiling(
        selected,
        @environment.TotalResponseDecodedBytes,
      ) {
      return Err(DecodedResponseLimit(step))
    }
    entries.push(counts)
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
  v.entries.get(i)
}
