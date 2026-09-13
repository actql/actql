///|
/// Actual canonical wire quantities, not allocator bytes or RSS. Existing
/// source admission and driver container limits remain independently enforced.
pub(all) struct MockRetentionLimits {
  received_wire_bytes : Int
  retained_wire_bytes : Int
  measurement : @execution.RowWireLimits
}

///|
pub(all) enum MockRetentionIssue {
  InvalidLimits
  RequirementRequired
  NotAwaitingCapture
  ScanIdentity(@execution.RowWireIssue)
  OutputIdentity(@execution.RowWireIssue)
  ReceiptBytes
  RetainedBytes
}

///|
/// Immutable capture material with actual full-scan provenance. No issuer
/// record or consumer permission can be reconstructed from these CIDs alone.
struct MockQueryRetention {
  _requirement : QueryRequirement
  computation : MockQueryComputation
  scan : @execution.RowWireIdentity
  output : @execution.RowWireIdentity
  received_bytes : Int
  retained_bytes : Int
  measured_nodes : Int
}

///|
fn retain_mock_computation(
  requirement : QueryRequirement,
  computation : MockQueryComputation,
  limits : MockRetentionLimits,
) -> Result[MockQueryRetention, MockRetentionIssue] {
  if limits.received_wire_bytes < 0 || limits.retained_wire_bytes < 0 {
    return Err(InvalidLimits)
  }
  // Hashing scans the exact immutable material without re-admission, expression
  // evaluation or constructing a row JSON matrix. Share bytes/nodes across both
  // artifacts; column-order/depth allowances apply to each artifact separately.
  let scan = match
    @execution.identify_query_receipt_rows(
      computation._scan,
      limits.measurement,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ScanIdentity(issue))
  }
  let scan_usage = @execution.row_wire_usage(scan)
  if scan_usage.0 > limits.retained_wire_bytes {
    return Err(RetainedBytes)
  }
  if computation.strategy.offer.realization == BroadWithResidual &&
    scan_usage.0 > limits.received_wire_bytes {
    return Err(ReceiptBytes)
  }
  // A valid measurement allowance may be exactly exhausted by the scan.
  // Every output array (even empty) needs a node; this is resource exhaustion,
  // not a malformed caller-supplied RowWireLimits configuration.
  if scan_usage.1 == limits.measurement.max_nodes {
    return Err(
      OutputIdentity(@execution.RowWireIssue::Encoding(@encode.OutputLimit)),
    )
  }
  let output = match
    @execution.identify_completed_rows(computation.output, {
      ..limits.measurement,
      max_bytes: limits.measurement.max_bytes - scan_usage.0,
      max_nodes: limits.measurement.max_nodes - scan_usage.1,
    }) {
    Ok(value) => value
    Err(issue) => return Err(OutputIdentity(issue))
  }
  let output_usage = @execution.row_wire_usage(output)
  // No overflow and no discount for sharing: both retained representations are
  // required. Native receipt savings do not remove the issuer's full scan.
  if output_usage.0 > limits.retained_wire_bytes - scan_usage.0 {
    return Err(RetainedBytes)
  }
  let received_bytes = match computation.strategy.offer.realization {
    NativeQuery => output_usage.0
    BroadWithResidual => scan_usage.0
  }
  if received_bytes > limits.received_wire_bytes {
    return Err(ReceiptBytes)
  }
  Ok({
    _requirement: requirement,
    computation,
    scan,
    output,
    received_bytes,
    retained_bytes: scan_usage.0 + output_usage.0,
    measured_nodes: scan_usage.1 + output_usage.1,
  })
}

///|
/// Finish retention on the owning one-shot task, not on an independently held
/// computation. Cancellation/failure cannot be bypassed with equal data/CIDs.
/// This still does not issue evidence or expose completed input to a consumer.
pub fn retain_mock_query(
  attempt : MockQueryAttempt,
  limits : MockRetentionLimits,
) -> Result[MockQueryRetention, MockRetentionIssue] {
  guard attempt.state is AwaitingCapture(computation) else {
    return Err(NotAwaitingCapture)
  }
  guard attempt.requirement is Some(requirement) else {
    return Err(RequirementRequired)
  }
  match retain_mock_computation(requirement, computation, limits) {
    Ok(value) => {
      attempt.state = Retained(value)
      Ok(value)
    }
    Err(issue) => {
      attempt.state = Failed(Retention(issue))
      Err(issue)
    }
  }
}

///|
/// Receipt wire bytes, retained scan+output wire bytes and measured value nodes.
/// These are neither logical-budget credits nor allocator/RSS measurements.
pub fn mock_retention_usage(value : MockQueryRetention) -> (Int, Int, Int) {
  (value.received_bytes, value.retained_bytes, value.measured_nodes)
}

///|
pub fn mock_retention_row_cids(value : MockQueryRetention) -> (String, String) {
  (@execution.row_wire_cid(value.scan), @execution.row_wire_cid(value.output))
}
