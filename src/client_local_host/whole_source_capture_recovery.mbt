///|
/// Snapshot facts for existing private Source custody. No Query completion or
/// requirement is synthesized for the original checked Input.
pub fn export_client_whole_source_capture(
  source : @query.CapturedInputSource,
  capacity : ClientInstalledWholeSourceCapacity,
  binding : String,
) -> Result[
  (Array[String], String, String, Array[String]),
  ClientSourceCaptureIssue,
] {
  guard !binding.is_empty() &&
    binding.length() <= 262144 &&
    @query.captured_source_matches_input_acquisition(source, capacity.original) &&
    @query.captured_source_original_input_read(source) is Some(read) &&
    @row_source_host.row_input_capture_identity(capacity.acquisition)
    is Some(identity) else {
    return Err(BindingMismatch)
  }
  let exported = match
    @row_source_host.export_row_input_original_read(capacity.acquisition, read) {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  if !@query.captured_source_matches_input_acquisition(
      source,
      capacity.original,
    ) {
    return Err(CustodyUnavailable)
  }
  let (schema, rows_cid, rows) = @row_source_host.row_original_capture_export_facts(
    exported,
  )
  Ok((identity, schema, rows_cid, rows))
}

///|
/// Reconstruct this same original Input under the mandatory receiving Ledger.
/// The current constructor policy remains the only row/wire admission policy.
pub fn restore_accounted_client_whole_source_capture(
  capacity : ClientInstalledWholeSourceCapacity,
  expected_binding : String,
  saved_binding : String,
  saved_identity : Array[String],
  schema_cid : String,
  rows_cid : String,
  rows : Array[String],
  ledger : @resources.Ledger,
  custody_available : () -> Bool,
  reference_issuer? : @admitted.ReferenceIssuer,
) -> Result[ClientAccountedSourceCapture, ClientSourceCaptureIssue] {
  if expected_binding.is_empty() ||
    expected_binding.length() > 262144 ||
    expected_binding != saved_binding {
    return Err(BindingMismatch)
  }
  if !custody_available() {
    return Err(CustodyUnavailable)
  }
  let limits = @row_source_host.row_input_acquisition_limits(
    capacity.acquisition,
  )
  if rows.length() > limits.max_rows {
    return Err(Original(InvalidBinding))
  }
  // Admit the fixed identity/quote controls before constructing Source facts.
  // Invocation CIDs plus exact Stage/Input bind the checked request itself.
  let quote = match
    @resources.reserve_capacity(ledger, 0L, source_capture_restore_quote_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  let identity_matches = match
    @row_source_host.row_input_capture_identity(capacity.acquisition) {
    Some(identity) => identity == saved_identity
    None => false
  }
  guard identity_matches &&
    @row_source_host.row_input_acquisition_matches_source(
      capacity.acquisition,
      capacity.original,
    ) else {
    @resources.settle_capacity(ledger, quote) |> ignore
    return Err(BindingMismatch)
  }
  let sized = source_capture_restoration_capacity(
    "",
    rows,
    None,
    input_policy=limits,
  )
  match @resources.settle_capacity(ledger, quote) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  guard sized is Some(sized) &&
    @row_source_host.row_input_acquisition_capacity(capacity.acquisition, None)
    is Some(input_capacity) else {
    return Err(Physical(InvalidCharge))
  }
  let retained = @execution.execution_capacity_retained_bytes(sized)
  let execution = @execution.execution_capacity_execution_bytes(sized)
  let input_retained = @execution.execution_capacity_retained_bytes(
    input_capacity,
  )
  let input_execution = @execution.execution_capacity_execution_bytes(
    input_capacity,
  )
  if retained > 9223372036854775807L - input_retained ||
    execution > 9223372036854775807L - input_execution {
    return Err(Physical(InvalidCharge))
  }
  let retained = retained + input_retained
  let execution = execution + input_execution
  let reservation = match
    @resources.reserve_attempt(
      ledger,
      0L,
      retained,
      execution,
      quantities=@resources.quantity_neutral_amounts(ledger),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  let live = Ref(true)
  let allocation : Ref[() -> Bool] = Ref(() => {
    @resources.reservation_open(reservation)
  })
  let (original, source) = match
    @row_source_host.restore_row_input_capture(
      capacity.acquisition,
      schema_cid,
      rows_cid,
      rows,
      () => live.val && custody_available() && live.val && (allocation.val)(),
      reference_issuer?,
    ) {
    Ok(value) => value
    Err(issue) => {
      live.val = false
      @resources.settle_reservation(ledger, reservation) |> ignore
      return Err(Original(issue))
    }
  }
  let capture : ClientSourceCapture = { source, live, }
  // Match the live RowRun's post-capture ownership: its original input buffer
  // and observed wire remain; construction/provider scratch has retired.
  let (original_retained, _) = @row_source_host.row_original_input_capacity()
  let read = match @query.captured_source_original_input_read(source) {
    Some(value) => value
    None => {
      close_client_source_capture(capture) |> ignore
      while !@row_source_host.close_restored_row_original_input(original, 64) {

      }
      @resources.settle_reservation(ledger, reservation) |> ignore
      return Err(CustodyUnavailable)
    }
  }
  let actual = match
    @execution.supplied_relation_read_rows_identity(read, limits.wire) {
    Ok(value) => @execution.row_wire_usage(value).0.to_int64()
    Err(issue) => {
      close_client_source_capture(capture) |> ignore
      while !@row_source_host.close_restored_row_original_input(original, 64) {

      }
      @resources.settle_reservation(ledger, reservation) |> ignore
      return Err(Original(Wire(issue)))
    }
  }
  let sized_retained = @execution.execution_capacity_retained_bytes(sized)
  guard @execution.checked_preparation_add_product(
      original_retained, actual, 1L,
    )
    is Some(owned) &&
    @execution.checked_preparation_add_product(owned, sized_retained, 1L)
    is Some(owned) &&
    owned <= retained else {
    close_client_source_capture(capture) |> ignore
    while !@row_source_host.close_restored_row_original_input(original, 64) {

    }
    @resources.settle_reservation(ledger, reservation) |> ignore
    return Err(Physical(InvalidCharge))
  }
  let holding = match @resources.retain_allocation(ledger, reservation, owned) {
    Ok(value) => value
    Err(issue) => {
      close_client_source_capture(capture) |> ignore
      while !@row_source_host.close_restored_row_original_input(original, 64) {

      }
      @resources.settle_reservation(ledger, reservation) |> ignore
      return Err(Physical(issue))
    }
  }
  allocation.val = () => @resources.holding_available(ledger, holding)
  match @resources.settle_reservation(ledger, reservation) {
    Ok(_) => ()
    Err(issue) => {
      close_client_source_capture(capture) |> ignore
      while !@row_source_host.close_restored_row_original_input(original, 64) {

      }
      @resources.release_allocation(ledger, holding) |> ignore
      return Err(Physical(issue))
    }
  }
  // A Host callback can revoke custody during any receiving transition.
  if !custody_available() || !@query.captured_source_available(source) {
    close_client_source_capture(capture) |> ignore
    while !@row_source_host.close_restored_row_original_input(original, 64) {

    }
    @resources.release_allocation(ledger, holding) |> ignore
    return Err(CustodyUnavailable)
  }
  Ok({
    capture,
    ledger,
    holding,
    closed: Ref(false),
    close_requested: false,
    original: Some(original),
    dag: None,
    input_dag: None,
  })
}

///|
/// Two Inputs in one Compute keep their distinct Source holdings. They do not
/// compete for the single completed-task retention slot or release siblings.
pub fn retain_accounted_client_source_capture_input(
  value : ClientAccountedSourceCapture,
  dag : @strategy.CapturedDAG,
  task : Int,
) -> Result[Unit, ClientSourceCaptureIssue] {
  guard !value.close_requested &&
    !value.closed.val &&
    value.dag is None &&
    value.input_dag is None &&
    physical_equal(value.ledger, @strategy.captured_dag_ledger(dag)) &&
    accounted_client_source_capture_source(value) is Some(_) &&
    accounted_client_source_original_read(value) is Some(read) &&
    @strategy.source_input_dag_matches_read_at(dag, read, task) else {
    return Err(BindingMismatch)
  }
  value.input_dag = Some(dag)
  Ok(())
}
