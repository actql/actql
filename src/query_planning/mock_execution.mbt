///|
/// Explicit mock source setup: immutable cursors and a bounded copied container.
/// No external provider is read, and offer/selection never performs this work.
struct MockQueryAttempt {
  mut state : MockQueryState
  requirement : QueryRequirement?
}

///|
priv enum MockQueryState {
  Pending(QueryStrategy, Array[@decode.Cursor])
  Computing
  AwaitingCapture(MockQueryComputation)
  Retained(MockQueryRetention)
  Failed(MockQueryIssue)
  Cancelled
}

///|
/// An intermediate computation, NOT a completed acquisition. There is no public
/// output handle accessor: capture admission must verify evidence before a
/// fixed-input consumer can use this acquisition result.
struct MockQueryComputation {
  strategy : QueryStrategy
  // Preserve full-scan provenance even when the native receipt is projected.
  // Kept private: this alone never authorizes process-evidence issuance.
  _scan : @execution.QueryReceipt
  output : @execution.CompletedOutput
  source_rows : Int
  received_rows : Int
  received_columns : Int
}

///|
pub(all) enum MockQueryIssue {
  InvalidLimits
  PreparationLimit
  ReceiptRowsLimit
  ReceiptCellsLimit
  Local(@execution.QuerySequenceIssue)
  MissingCaptureOutput
  AlreadyStarted
  NotComputed
  Cancelled
  ForeignRequirement
  GuardLimitsRequired
  Guard(@execution.QueryGuardIssue)
  Retention(MockRetentionIssue)
}

///|
pub(all) struct MockQueryLimits {
  source_rows : Int
  received_rows : Int
  received_cells : Int
  source_admission : @execution.ValueLimits
  computation : @execution.SequenceExecutionLimits
}

///|
pub fn prepare_mock_query_attempt(
  strategy : QueryStrategy,
  source : Array[@decode.Cursor],
  max_entries : Int,
) -> Result[MockQueryAttempt, MockQueryIssue] {
  if max_entries < 0 {
    return Err(InvalidLimits)
  }
  if source.length() > max_entries {
    return Err(PreparationLimit)
  }
  Ok({ state: Pending(strategy, source.copy()), requirement: None, })
}

///|
/// Bind the canonical requirement before starting an attempt. This does not
/// authorize an issuer; execution still produces only unpublished computation.
pub fn prepare_requirement_mock_query_attempt(
  requirement : QueryRequirement,
  strategy : QueryStrategy,
  source : Array[@decode.Cursor],
  max_entries : Int,
) -> Result[MockQueryAttempt, MockQueryIssue] {
  if !physical_equal(requirement.material.owner, strategy.offer.owner) {
    return Err(ForeignRequirement)
  }
  if max_entries < 0 {
    return Err(InvalidLimits)
  }
  if source.length() > max_entries {
    return Err(PreparationLimit)
  }
  Ok({
    state: Pending(strategy, source.copy()),
    requirement: Some(requirement),
  })
}

///|
fn check_receipt(
  rows : Int,
  columns : Int,
  limits : MockQueryLimits,
) -> Result[Unit, MockQueryIssue] {
  if rows > limits.received_rows {
    return Err(ReceiptRowsLimit)
  }
  // Division bounds the product without overflowing; zero columns still count
  // rows. These are physical receipt cells, not canonical logical value bytes.
  if columns > 0 && rows > limits.received_cells / columns {
    return Err(ReceiptCellsLimit)
  }
  Ok(())
}

///|
fn compute_mock_query(
  strategy : QueryStrategy,
  source : Array[@decode.Cursor],
  limits : MockQueryLimits,
  guards : (QueryLogicalGuards, @execution.QueryGuardMeasureLimits)?,
) -> Result[MockQueryComputation, MockQueryIssue] {
  if limits.source_rows < 0 ||
    limits.received_rows < 0 ||
    limits.received_cells < 0 {
    return Err(InvalidLimits)
  }
  let query = @execution.query_sequence_requirement(strategy.offer.owner)
  guard @pipeline.schema_at(
      @acquisition.query_acquisition_pipeline(query),
      @acquisition.query_acquisition_input(query),
    )
    is Some(schema) else {
    return Err(MissingCaptureOutput)
  }
  let width = @schema.field_count(schema)
  if strategy.offer.realization == BroadWithResidual {
    // In a broad realization receipt precedes local residual. Physical failure
    // can stop this mock attempt before it discovers an expression/value error.
    match check_receipt(source.length(), width, limits) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  // Both realizations use precisely the same checked semantics and full-source
  // admission. Native executes this inside the mock source, before receipt;
  // BroadWithResidual executes it locally, after broad receipt. There is no
  // separate mock predicate interpreter or weak-prefilter completion claim.
  let scan = match
    @execution.admit_query_receipt(
      strategy.offer.owner,
      source,
      limits.source_rows,
      limits.source_admission,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Local(issue))
  }
  let completed = match guards {
    Some((ceilings, physical)) =>
      match
        @execution.execute_query_receipt_guarded(
          strategy.offer.owner,
          scan,
          limits.computation,
          max_output_rows=ceilings.max_rows,
          max_value_bytes=ceilings.max_value_bytes,
          physical,
        ) {
        Ok((value, _)) => value
        Err(issue) => return Err(Guard(issue))
      }
    None =>
      match
        @execution.execute_query_receipt(
          strategy.offer.owner,
          scan,
          limits.computation,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Local(issue))
      }
  }
  guard @execution.completed_output(
      completed,
      @acquisition.query_acquisition_capture(query),
    )
    is Some(output) else {
    return Err(MissingCaptureOutput)
  }
  let (received_rows, received_columns) = match strategy.offer.realization {
    NativeQuery =>
      (
        @execution.completed_row_count(output),
        @execution.completed_column_count(output),
      )
    BroadWithResidual => (source.length(), width)
  }
  match check_receipt(received_rows, received_columns, limits) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok({
    strategy,
    _scan: scan,
    output,
    source_rows: source.length(),
    received_rows,
    received_columns,
  })
}

///|
/// Synchronous local mock realization only. No implicit source reread, route
/// fallback, external I/O, authority grant or completed observation is produced.
pub fn execute_mock_query(
  attempt : MockQueryAttempt,
  limits : MockQueryLimits,
  guard_measure? : @execution.QueryGuardMeasureLimits? = None,
) -> Result[MockQueryComputation, MockQueryIssue] {
  match attempt.state {
    Pending(strategy, source) => {
      let guards = match (attempt.requirement, guard_measure) {
        (Some(requirement), Some(physical)) =>
          Some((requirement.guards, physical))
        (Some(_), None) => return Err(GuardLimitsRequired)
        (None, _) => None
      }
      attempt.state = Computing
      match compute_mock_query(strategy, source, limits, guards) {
        Ok(value) => {
          attempt.state = AwaitingCapture(value)
          Ok(value)
        }
        Err(issue) => {
          attempt.state = Failed(issue)
          Err(issue)
        }
      }
    }
    Cancelled => Err(Cancelled)
    _ => Err(AlreadyStarted)
  }
}

///|
pub fn mock_query_computation(
  attempt : MockQueryAttempt,
) -> Result[MockQueryComputation, MockQueryIssue] {
  match attempt.state {
    AwaitingCapture(value) => Ok(value)
    Retained(value) => Ok(value.computation)
    Failed(issue) => Err(issue)
    Cancelled => Err(Cancelled)
    Pending(_, _) | Computing => Err(NotComputed)
  }
}

///|
/// Cancellation before dispatch or between computation and capture discards
/// this attempt's owned references. Other owners' source/preparation stay valid.
pub fn cancel_mock_query(attempt : MockQueryAttempt) -> Bool {
  match attempt.state {
    Pending(_, _) | AwaitingCapture(_) | Retained(_) => {
      attempt.state = Cancelled
      true
    }
    _ => false
  }
}

///|
pub fn mock_query_strategy(v : MockQueryComputation) -> QueryStrategy {
  v.strategy
}

///|
pub fn mock_query_source_rows(v : MockQueryComputation) -> Int {
  v.source_rows
}

///|
pub fn mock_query_received_rows(v : MockQueryComputation) -> Int {
  v.received_rows
}

///|
pub fn mock_query_received_columns(v : MockQueryComputation) -> Int {
  v.received_columns
}

///|
pub fn mock_query_output_rows(v : MockQueryComputation) -> Int {
  @execution.completed_row_count(v.output)
}
