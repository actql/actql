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
  _requirement : @planning.QueryRequirement
  computation : MockQueryComputation
  scan : @execution.RowWireIdentity
  output : @execution.RowWireIdentity
  received_bytes : Int
  retained_bytes : Int
  measured_nodes : Int
}

///|
fn retain_mock_computation(
  requirement : @planning.QueryRequirement,
  computation : MockQueryComputation,
  limits : MockRetentionLimits,
) -> Result[MockQueryRetention, MockRetentionIssue] {
  let measured = match
    @planning.measure_query_retention(
      @query.query_receipt_rows(computation._scan),
      computation.output,
      computation.strategy.offer.realization == BroadWithResidual,
      {
        received_wire_bytes: limits.received_wire_bytes,
        retained_wire_bytes: limits.retained_wire_bytes,
        measurement: limits.measurement,
      },
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue {
          InvalidLimits => InvalidLimits
          ScanIdentity(issue) => ScanIdentity(issue)
          OutputIdentity(issue) => OutputIdentity(issue)
          ReceiptBytes => ReceiptBytes
          RetainedBytes => RetainedBytes
        },
      )
  }
  Ok({
    _requirement: requirement,
    computation,
    scan: measured.scan,
    output: measured.output,
    received_bytes: measured.received_bytes,
    retained_bytes: measured.retained_bytes,
    measured_nodes: measured.measured_nodes,
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
