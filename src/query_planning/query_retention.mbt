///|
/// Canonical row-wire budgets, not allocator bytes, transport frames or RSS.
pub(all) struct QueryRetentionLimits {
  received_wire_bytes : Int
  retained_wire_bytes : Int
  measurement : @execution.RowWireLimits
}

///|
pub(all) enum QueryRetentionIssue {
  InvalidLimits
  ScanIdentity(@execution.RowWireIssue)
  OutputIdentity(@execution.RowWireIssue)
  ReceiptBytes
  RetainedBytes
}

///|
priv struct MeasuredQueryRows {
  scan : @execution.RowWireIdentity
  output : @execution.RowWireIdentity
  received_bytes : Int
  retained_bytes : Int
  measured_nodes : Int
}

///|
/// Shared accounting only. The caller owns the input/output provenance and
/// one-shot lifecycle. No scan re-admission, expression replay or row copying.
fn measure_query_retention(
  source : @execution.CapturedRows,
  completed : @execution.CompletedOutput,
  received_is_scan : Bool,
  limits : QueryRetentionLimits,
) -> Result[MeasuredQueryRows, QueryRetentionIssue] {
  if limits.received_wire_bytes < 0 || limits.retained_wire_bytes < 0 {
    return Err(InvalidLimits)
  }
  let scan = match
    @execution.identify_captured_rows(source, limits.measurement) {
    Ok(value) => value
    Err(issue) => return Err(ScanIdentity(issue))
  }
  let scan_usage = @execution.row_wire_usage(scan)
  if scan_usage.0 > limits.retained_wire_bytes {
    return Err(RetainedBytes)
  }
  if received_is_scan && scan_usage.0 > limits.received_wire_bytes {
    return Err(ReceiptBytes)
  }
  if scan_usage.1 == limits.measurement.max_nodes {
    return Err(
      OutputIdentity(@execution.RowWireIssue::Encoding(@encode.OutputLimit)),
    )
  }
  let output = match
    @execution.identify_completed_rows(completed, {
      ..limits.measurement,
      max_bytes: limits.measurement.max_bytes - scan_usage.0,
      max_nodes: limits.measurement.max_nodes - scan_usage.1,
    }) {
    Ok(value) => value
    Err(issue) => return Err(OutputIdentity(issue))
  }
  let output_usage = @execution.row_wire_usage(output)
  if output_usage.0 > limits.retained_wire_bytes - scan_usage.0 {
    return Err(RetainedBytes)
  }
  let received_bytes = if received_is_scan {
    scan_usage.0
  } else {
    output_usage.0
  }
  if received_bytes > limits.received_wire_bytes {
    return Err(ReceiptBytes)
  }
  Ok({
    scan,
    output,
    received_bytes,
    retained_bytes: scan_usage.0 + output_usage.0,
    measured_nodes: scan_usage.1 + output_usage.1,
  })
}
