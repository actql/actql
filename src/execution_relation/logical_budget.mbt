///|
/// Runtime enforcement values, not static capacity or self-CID evidence.
type LogicalLimits = @lower.FragmentRowLimits

///|
priv struct LogicalBudget {
  limits : LogicalLimits
  host_bytes : Int
  host_nodes : Int
  host_depth : Int
  mut work : Int64
  mut rows : Int64
  mut live : Int64
  mut peak : Int64
  mut failed : Bool
}

///|
priv struct LogicalRoot {
  owner : LogicalBudget
  bytes : Int64
  mut released : Bool
}

///|
priv enum LogicalBudgetIssue {
  InvalidLogicalLimits
  FailedLogicalBudget
  InputRowLimit
  WorkLimit
  LiveValueLimit
  InvalidRootLifetime
  ValueMeasure(LogicalMeasureIssue)
} derive(Eq, Debug)

///|
fn logical_budget(
  limits : LogicalLimits,
  host_bytes : Int,
  host_nodes : Int,
  host_depth : Int,
) -> Result[LogicalBudget, LogicalBudgetIssue] {
  match validate_logical_limits(limits) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if host_bytes < 0 || host_nodes < 0 || host_depth < 0 {
    return Err(InvalidLogicalLimits)
  }
  Ok({
    limits,
    host_bytes,
    host_nodes,
    host_depth,
    work: 0L,
    rows: 0L,
    live: 0L,
    peak: 0L,
    failed: false,
  })
}

///|
fn validate_logical_limits(
  limits : LogicalLimits,
) -> Result[Unit, LogicalBudgetIssue] {
  if @lower.fragment_row_limits_valid(limits) {
    Ok(())
  } else {
    Err(InvalidLogicalLimits)
  }
}

///|
/// Count all input occurrences before evaluation; row-entry work is charged
/// separately when the evaluator enters each row.
fn admit_logical_rows(
  b : LogicalBudget,
  count : Int64,
) -> Result[Unit, LogicalBudgetIssue] {
  if b.failed {
    return Err(FailedLogicalBudget)
  }
  if count < 0L || count > b.limits.max_input_rows - b.rows {
    b.failed = true
    return Err(InputRowLimit)
  }
  b.rows += count
  Ok(())
}

///|
fn charge_logical_work(
  b : LogicalBudget,
  count : Int64,
) -> Result[Unit, LogicalBudgetIssue] {
  if b.failed {
    return Err(FailedLogicalBudget)
  }
  if count < 0L || count > b.limits.max_work - b.work {
    b.failed = true
    return Err(WorkLimit)
  }
  b.work += count
  Ok(())
}

///|
/// Consuming an operand charges its complete value weight, without inventing
/// another live root. Repeated consumption is deliberately not memoized.
fn charge_logical_value(
  b : LogicalBudget,
  value : Value,
) -> Result[LogicalValueMeasure, LogicalBudgetIssue] {
  if b.failed {
    return Err(FailedLogicalBudget)
  }
  let cap = Int64::min(b.limits.max_value_bytes, b.host_bytes.to_int64()).to_int()
  let measured = match
    measure_logical_value(
      value,
      b.limits.max_work - b.work,
      cap,
      b.host_nodes,
      b.host_depth,
    ) {
    Ok(m) => m
    Err(issue) => {
      b.failed = true
      return Err(ValueMeasure(issue))
    }
  }
  // Measurement already checked the exact remaining allowance.
  b.work += measured.weight
  Ok(measured)
}

///|
/// An admitted or produced value is a new logical root, even if its immutable
/// storage aliases another root. Transfer passes this same handle, not this call.
fn retain_logical_value(
  b : LogicalBudget,
  value : Value,
) -> Result[LogicalRoot, LogicalBudgetIssue] {
  let m = match charge_logical_value(b, value) {
    Ok(m) => m
    Err(e) => return Err(e)
  }
  let bytes = m.wire_bytes.to_int64()
  reserve_logical_bytes(b, bytes)
}

///|
fn reserve_logical_bytes(
  b : LogicalBudget,
  bytes : Int64,
) -> Result[LogicalRoot, LogicalBudgetIssue] {
  if b.failed {
    return Err(FailedLogicalBudget)
  }
  if bytes < 0L || bytes > b.limits.max_live_value_bytes - b.live {
    b.failed = true
    return Err(LiveValueLimit)
  }
  b.live += bytes
  b.peak = Int64::max(b.peak, b.live)
  Ok({ owner: b, bytes, released: false, })
}

///|
/// Cleanup is legal after failure, but cannot refund work or revive the budget.
fn release_logical_root(
  b : LogicalBudget,
  root : LogicalRoot,
) -> Result[Unit, LogicalBudgetIssue] {
  if !physical_equal(b, root.owner) || root.released || root.bytes > b.live {
    b.failed = true
    return Err(InvalidRootLifetime)
  }
  root.released = true
  b.live -= root.bytes
  Ok(())
}
