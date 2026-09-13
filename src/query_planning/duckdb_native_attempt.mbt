///|
pub(all) enum DuckDBNativeAttemptIssue {
  ForeignChoice
  InvalidState
  Receiving(@duckdb.NativeReceivingIssue)
  Demand(@duckdb.NativeDemandIssue)
  Receipts(@duckdb.NativeReceiptIdentityIssue)
}

///|
priv enum DuckDBNativeState {
  Receiving
  Settled
  Measured(DuckDBNativeMeasurement)
  Failed
}

///|
/// One selected physical attempt. The native receiver implements metadata,
/// receipt ordering, full-column admission and common acquisition guards.
/// This lifecycle cannot manufacture execution records or engine completion.
struct DuckDBNativeAttempt {
  preparation : DuckDBNativePreparation
  receiver : @duckdb.NativeReceiving
  mut state : DuckDBNativeState
}

///|
struct DuckDBNativeMeasurement {
  attempt : DuckDBNativeAttempt
  demand : @duckdb.NativeDemandMeasurement
  receipts : @duckdb.NativeReceiptIdentities
}

///|
pub fn prepare_duckdb_native_attempt(
  choice : AcquisitionChoice,
  candidate : PreparedAcquisition[DuckDBNativePreparation],
  physical : @duckdb.PhysicalResultLimits,
  max_metadata_work : Int,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[DuckDBNativeAttempt, DuckDBNativeAttemptIssue] {
  guard acquisition_choice_payload(choice, candidate) is Some(preparation) else {
    return Err(ForeignChoice)
  }
  if !@duckdb.native_root_guard_matches(
      preparation.root,
      @duckdb.native_scan_query(preparation.scan),
      preparation.requirement.guards.max_value_bytes,
    ) {
    return Err(InvalidState)
  }
  @duckdb.prepare_native_receiving(
    preparation.scan,
    physical,
    max_metadata_work,
    {
      max_value_bytes: preparation.requirement.guards.max_value_bytes,
      max_output_rows: preparation.requirement.guards.max_rows,
    },
    measurement,
  )
  .map_err(issue => DuckDBNativeAttemptIssue::Receiving(issue))
  .map(receiver => { preparation, receiver, state: Receiving, })
}

///|
pub fn duckdb_native_attempt_preparation(
  attempt : DuckDBNativeAttempt,
) -> DuckDBNativePreparation {
  attempt.preparation
}

///|
pub fn abort_duckdb_native_attempt(attempt : DuckDBNativeAttempt) -> Unit {
  @duckdb.abort_native_receiving(attempt.receiver)
  attempt.state = Failed
}

///|
fn[T] native_attempt_receive(
  attempt : DuckDBNativeAttempt,
  action : () -> Result[T, @duckdb.NativeReceivingIssue],
) -> Result[T, DuckDBNativeAttemptIssue] {
  if !(attempt.state is Receiving) {
    abort_duckdb_native_attempt(attempt)
    return Err(InvalidState)
  }
  match action() {
    Ok(value) => Ok(value)
    Err(issue) => {
      abort_duckdb_native_attempt(attempt)
      Err(Receiving(issue))
    }
  }
}

///|
pub fn admit_duckdb_native_metadata(
  attempt : DuckDBNativeAttempt,
  rows : Int,
  fields : Array[(String, @duckdb.PhysicalType)],
  columns : Array[@decode.Cursor],
) -> Result[Unit, DuckDBNativeAttemptIssue] {
  native_attempt_receive(attempt, () => {
    @duckdb.admit_native_table_metadata(attempt.receiver, rows, fields, columns)
  })
}

///|
pub fn begin_duckdb_native_receipt(
  attempt : DuckDBNativeAttempt,
  role : @duckdb.NativeReceiptRole,
  fields : Array[(String, @duckdb.PhysicalType)],
) -> Result[@duckdb.NativeReceiptPort, DuckDBNativeAttemptIssue] {
  native_attempt_receive(attempt, () => {
    @duckdb.begin_native_receipt(attempt.receiver, role, fields)
  })
}

///|
pub fn accept_duckdb_native_chunk(
  attempt : DuckDBNativeAttempt,
  port : @duckdb.NativeReceiptPort,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, DuckDBNativeAttemptIssue] {
  native_attempt_receive(attempt, () => {
    @duckdb.accept_native_receipt_chunk(attempt.receiver, port, rows, columns)
  })
}

///|
pub fn finish_duckdb_native_receipt(
  attempt : DuckDBNativeAttempt,
  port : @duckdb.NativeReceiptPort,
) -> Result[Unit, DuckDBNativeAttemptIssue] {
  native_attempt_receive(attempt, () => {
    @duckdb.finish_native_receipt(attempt.receiver, port)
  })
}

///|
/// Trusted Host acknowledgement after real read transaction and cleanup settle.
/// A later issuer must independently verify exact live transport provenance;
/// calling this operation alone is not that proof.
pub fn settle_duckdb_native_transport(
  attempt : DuckDBNativeAttempt,
) -> Result[Unit, DuckDBNativeAttemptIssue] {
  if !(attempt.state is Receiving) ||
    !@duckdb.native_receiving_has_both(attempt.receiver) {
    abort_duckdb_native_attempt(attempt)
    return Err(InvalidState)
  }
  attempt.state = Settled
  Ok(())
}

///|
/// Exact demanded-value and retained-receipt accounting, with no Local predicate
/// replay. Separate physical allowances do not waive common acquisition guards.
pub fn measure_duckdb_native_attempt(
  attempt : DuckDBNativeAttempt,
  demand_limits : @execution.FixedInputGuardMeasureLimits,
  wire_limits : @execution.RowWireLimits,
  max_received_rows : Int,
  max_received_bytes : Int,
) -> Result[DuckDBNativeMeasurement, DuckDBNativeAttemptIssue] {
  if !(attempt.state is Settled) {
    abort_duckdb_native_attempt(attempt)
    return Err(InvalidState)
  }
  let demand = match
    @duckdb.measure_native_demand(attempt.receiver, demand_limits) {
    Ok(value) => value
    Err(issue) => {
      abort_duckdb_native_attempt(attempt)
      return Err(Demand(issue))
    }
  }
  let receipts = match
    @duckdb.identify_native_receipts(
      attempt.receiver,
      wire_limits,
      max_received_rows,
      max_received_bytes,
    ) {
    Ok(value) => value
    Err(issue) => {
      abort_duckdb_native_attempt(attempt)
      return Err(Receipts(issue))
    }
  }
  let result = { attempt, demand, receipts, }
  attempt.state = Measured(result)
  Ok(result)
}

///|
pub fn duckdb_native_measurement_matches(
  measurement : DuckDBNativeMeasurement,
  attempt : DuckDBNativeAttempt,
) -> Bool {
  guard attempt.state is Measured(issued) else { return false }
  physical_equal(measurement.attempt, attempt) &&
  physical_equal(issued, measurement) &&
  @duckdb.native_demand_matches(measurement.demand, attempt.receiver) &&
  @duckdb.native_receipts_match(measurement.receipts, attempt.receiver)
}

///|
pub fn duckdb_native_measured_demand(
  measurement : DuckDBNativeMeasurement,
) -> @duckdb.NativeDemandUsage {
  @duckdb.native_demand_usage(measurement.demand)
}

///|
pub fn duckdb_native_measured_receipt(
  measurement : DuckDBNativeMeasurement,
  role : @duckdb.NativeReceiptRole,
) -> (String, Int, Int, Int) {
  @duckdb.native_receipt_digest(measurement.receipts, role)
}
