///|
// Existing report holder's new original-configuration field (R1) and its
// Some carrier (H1/R1/W1). The same Row owner quotes and reserves it before
// constructing either, independently of the supplier's unchanged report data.
fn row_listing_original_binding_bytes() -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: 1L,
    reference_slots: 2L,
    scalar_words: 1L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
// Checked addition of the complete supplementary listing envelope to the
// existing Source allowance. No value here is an allocation or a byte grant.
fn row_listing_capacity_sum(
  retained : Int64,
  execution : Int64,
  scratch : Int64,
  declaration : @execution.ExecutionCapacity?,
) -> Result[(Int64, Int64), RowHostIssue] {
  guard declaration is Some(capacity) else {
    return Err(Physical(InvalidLimits))
  }
  let report_retained = @execution.execution_capacity_retained_bytes(capacity)
  let report_execution = @execution.execution_capacity_execution_bytes(capacity)
  if retained < 0L ||
    execution < 0L ||
    scratch < 0L ||
    report_retained <= 0L ||
    report_execution < report_retained ||
    report_retained > 9223372036854775807L - retained ||
    report_execution > 9223372036854775807L - execution {
    return Err(Physical(InvalidLimits))
  }
  guard row_listing_original_binding_bytes() is Some(binding) else {
    return Err(Physical(InvalidLimits))
  }
  let total_retained = retained + report_retained
  let total_execution = execution + report_execution
  if binding > 9223372036854775807L - total_retained ||
    binding > 9223372036854775807L - total_execution ||
    scratch > 9223372036854775807L - total_execution - binding {
    return Err(Physical(InvalidLimits))
  }
  Ok((total_retained + binding, total_execution + binding + scratch))
}

///|
/// Same listing composition used by the actual reservation below. This pure
/// projection issues no bytes, capacity grant, Source read or report evidence.
pub fn row_acquisition_listing_capacity(
  value : RowAcquisition,
  declaration : @execution.ExecutionCapacity?,
) -> @execution.ExecutionCapacity? {
  if !row_acquisition_is_listing(value) {
    return None
  }
  match
    row_listing_capacity_sum(
      row_acquisition_retained_capacity(value),
      row_acquisition_execution_capacity(value),
      0L,
      declaration,
    ) {
    Ok((retained, execution)) =>
      @execution.execution_capacity(retained, execution)
    Err(_) => None
  }
}

///|
// Trusted installation only: the supplier selects this declaration for this
// exact opaque acquisition, implementation and target recipe. A syntactically
// valid ExecutionCapacity alone proves neither that selection nor a physical
// upper bound. An unavailable/unjustified supplier must provide None.
//
// Reserve before constructing additional attempt/control state or admitting
// pages. The same immutable Source configuration enters the existing RowRun;
// no standing field, auxiliary Ledger, reservation token or public grant is
// introduced. The installation's existing preparation also owns the finite
// supplier/count-result workspace before this entry.
pub fn start_accounted_listing_row_acquisition(
  value : RowAcquisition,
  declaration : @execution.ExecutionCapacity?,
  nonce : String,
  verify : (RowAttempt) -> Bool,
  ledger : @resources.Ledger,
  transfer_bytes : Int64,
  execution_scratch : Int64,
) -> Result[RowRun, RowHostIssue] {
  if declaration is None || transfer_bytes < 0L {
    return Err(Physical(InvalidLimits))
  }
  guard row_acquisition_is_listing(value) else {
    return Err(Source(ForeignSource))
  }
  guard value.configuration.listing_rows is Some(ResolvedListingRows(resolved)) else {
    return Err(Source(ForeignSource))
  }
  match row_acquisition_listing_report_bounds(value) {
    Ok(_) => ()
    Err(issue) => return Err(Source(issue))
  }
  let (retained, execution) = match
    row_listing_capacity_sum(
      row_acquisition_retained_capacity(value),
      row_acquisition_execution_capacity(value),
      execution_scratch,
      declaration,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let reservation = match
    @resources.reserve_attempt(
      ledger,
      transfer_bytes,
      retained,
      execution,
      quantities=@resources.quantity_neutral_amounts(ledger),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  // The supplementary declaration includes this payload/backing, original
  // scan reference and cleanup sentinel, plus the transition overlap. None
  // of these listing-only allocations precedes the successful reservation.
  let reports = new_row_listing_reports()
  reports.original_configuration = Some(value.configuration)
  let configuration : RowHostConfiguration = {
    ..value.configuration,
    listing_rows: Some(ReportListingRows(resolved, reports)),
  }
  // This short-lived capsule copies only existing checked references. Include
  // its three fields and the original/configuration overlap in the declared
  // envelope; do not add a forwarding frame to ordinary acquisitions.
  let selected : RowAcquisition = { ..value, configuration, }
  let run = match start_row_acquisition(selected, nonce, verify) {
    Ok(value) => value
    Err(issue) =>
      // Registration failure closed its own issuer; no input or provider I/O
      // exists. This same reservation is settled, never replaced or retried.
      match @resources.settle_reservation(ledger, reservation) {
        Ok(_) => return Err(issue)
        Err(resource_issue) => return Err(Physical(resource_issue))
      }
  }
  install_row_reservation(run, ledger, reservation, execution_scratch)
  Ok(run)
}

///|
// Capture does not retire explicitly selected report/provider backing or later
// evidence encoding. Keep its remaining allowance until actual Row cleanup.
// Ordinary profiles retain immediate settlement; listing limits alone select
// neither report backing nor supplementary provider capacity.
fn settle_row_capture_capacity(
  extended_selected : Bool,
  physical : RowPhysical,
) -> Result[Unit, RowHostIssue] {
  if extended_selected {
    if !@resources.reservation_open(physical.reservation) {
      return Err(Physical(ClosedReservation))
    }
    Ok(())
  } else {
    @resources.settle_reservation(physical.ledger, physical.reservation).map_err(issue => {
        Physical(issue)
      },
    )
  }
}
