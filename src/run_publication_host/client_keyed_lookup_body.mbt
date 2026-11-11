///|
// Source-input wrapper controls and this owner's retained receipt/body aliases.
// Original Values/schema/sequence and scan-owned strings are borrowed. The
// constructor quote is added to, never substituted for, the live lookup basis.
fn keyed_lookup_body_grow(
  lookup : ClientKeyedLookupInput,
  basis_retained : Int64,
  basis_execution : Int64,
  controls : Int64,
  scan : @execution.ExecutionCapacity?,
) -> Result[Unit, ClientKeyedRequestIssue] {
  let r = scan.map(@execution.execution_capacity_retained_bytes).unwrap_or(0L)
  let e = scan.map(@execution.execution_capacity_execution_bytes).unwrap_or(0L)
  if controls > 9223372036854775807L - basis_retained ||
    controls > 9223372036854775807L - basis_execution ||
    r > 9223372036854775807L - basis_retained - controls ||
    e > 9223372036854775807L - basis_execution - controls {
    return Err(Assembly("capacity_overflow"))
  }
  let retained = Int64::max(
    lookup.retained_bytes,
    basis_retained + controls + r,
  )
  let execution = Int64::max(
    lookup.execution_bytes,
    basis_execution + controls + e,
  )
  if retained > lookup.retained_bytes || execution > lookup.execution_bytes {
    lookup.growing = true
    let result = @resources.grow_execution_reservation_capacity(
      lookup.ledger,
      lookup.reservation,
      retained,
      execution,
    )
    lookup.growing = false
    match result {
      Err(issue) => return Err(Physical(issue))
      Ok(_) => {
        lookup.retained_bytes = retained
        lookup.execution_bytes = execution
      }
    }
  }
  if lookup.closed || lookup.left.lookup_issue is Some(_) {
    return Err(Assembly("retired_publication_input"))
  }
  Ok(())
}

///|
// The Native publication purpose finishes BEFORE the Model Read is claimed.
// All growth belongs to the SAME lookup reservation; no later ledger mutation
// can invalidate a claimed Read's original snapshot. Older purposes keep their
// existing identity path and cannot be upgraded by replaying an equal input.
fn finish_keyed_lookup_identity_bodies(
  lookup : ClientKeyedLookupInput,
  native_completion? : (String, Int64, Int, Int, Int)? = None,
) -> Result[@execution.SuppliedRelationRead, ClientKeyedRequestIssue] {
  if lookup.identity_receipt is Some(_) {
    if lookup.identity_output is None || lookup.identity_bodies is None {
      return Err(Assembly("incomplete_body_receipt"))
    }
    if native_completion is Some(_) && lookup.native_completion is None {
      return Err(Assembly("late_native_completion_purpose"))
    }
    return finish_client_keyed_lookup_input(lookup)
  }
  if lookup.closed ||
    lookup.growing ||
    lookup.identifying ||
    lookup.identity is Some(_) ||
    lookup.holding is Some(_) ||
    !@resources.reservation_open(lookup.reservation) {
    return Err(Assembly("unavailable_body_purpose"))
  }
  lookup.identifying = true
  let result = build_keyed_lookup_identity_bodies(lookup, native_completion~)
  lookup.identifying = false
  match result {
    Err(issue) => {
      keyed_lookup_fail(lookup.left, issue) |> ignore
      Err(issue)
    }
    Ok(_) => finish_client_keyed_lookup_input(lookup)
  }
}

///|
fn build_keyed_lookup_identity_bodies(
  lookup : ClientKeyedLookupInput,
  native_completion? : (String, Int64, Int, Int, Int)? = None,
) -> Result[Unit, ClientKeyedRequestIssue] {
  guard lookup.completed is Some(rows) && lookup.left.composed is Some(original) else {
    return Err(Assembly("body_original_sequence"))
  }
  guard @execution.supplied_source_input_capture_capacity(rows) is Some(capture) &&
    @execution.preparation_representation_cost({
      // Original read/binding/Some/Result and available closure (six records),
      // then retained output/scan/receipt/body tuple/Some aliases (six records).
      record_headers: 12L,
      reference_slots: 16L,
      scalar_words: 11L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(host) else {
    return Err(Assembly("capacity_overflow"))
  }
  let capture_bytes = @execution.execution_capacity_retained_bytes(capture)
  if capture_bytes > 9223372036854775807L - host {
    return Err(Assembly("capacity_overflow"))
  }
  let controls = capture_bytes + host
  let basis_retained = lookup.retained_bytes
  let basis_execution = lookup.execution_bytes
  match
    keyed_lookup_body_grow(
      lookup,
      basis_retained,
      basis_execution,
      controls,
      None,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let read = match keyed_lookup_supplied_read(lookup) {
    Ok(read) => read
    Err(issue) => return Err(issue)
  }
  let output = match
    @execution.capture_generated_supplied_source_input(
      original.sequence,
      read,
      lookup.max_work,
      lookup.max_bytes,
    ) {
    Ok(output) => output
    Err(_) => return Err(Assembly("body_source_input"))
  }
  lookup.identity_output = Some(output)
  if lookup.closed || lookup.left.lookup_issue is Some(_) {
    return Err(Assembly("retired_publication_input"))
  }
  guard @execution.completed_relation_identity_scan_start_construction_capacity(
      output,
      retain_body=true,
    )
    is Some(start) else {
    return Err(Assembly("body_start_capacity"))
  }
  match
    keyed_lookup_body_grow(
      lookup,
      basis_retained,
      basis_execution,
      controls,
      Some(start),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if lookup.max_work > 2147483647 / 16 {
    return Err(Assembly("body_workspace_limit"))
  }
  let wire : @execution.RowWireLimits = {
    max_bytes: lookup.max_bytes,
    max_nodes: lookup.max_work,
    max_columns: lookup.max_work,
    max_order_work: lookup.max_work,
    max_depth: 100,
  }
  let scan = match
    @execution.start_completed_relation_identity_scan(
      output,
      lookup.rows,
      {
        max_work: lookup.max_work,
        max_nodes: lookup.max_work,
        max_depth: 100,
        max_text_bytes: lookup.max_bytes,
      },
      wire,
      wire,
      {
        max_fields: lookup.max_work,
        max_bytes: lookup.max_bytes,
        max_nodes: lookup.max_work,
        max_depth: 100,
      },
      lookup.max_work,
      lookup.max_work * 16,
      incremental_metadata=true,
      retain_body=true,
      source_input=Some(read),
    ) {
    Ok(scan) => scan
    Err(_) => return Err(Assembly("body_start"))
  }
  lookup.identity_scan = Some(scan)
  while true {
    guard @execution.completed_relation_identity_scan_next_construction_capacity(
        scan,
      )
      is Some(next) else {
      return Err(Assembly("body_next_capacity"))
    }
    match
      keyed_lookup_body_grow(
        lookup,
        basis_retained,
        basis_execution,
        controls,
        Some(next),
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let advanced = @execution.advance_completed_relation_identity_scan(
      scan,
      31,
      construction_capacity=Some(next),
    )
    lookup.identity_work = @execution.completed_relation_identity_scan_work(
      scan,
    )
    match advanced {
      Err(_) => return Err(Assembly("body_advance"))
      Ok((true, _)) => break
      Ok((false, _)) => ()
    }
  }
  let receipt = match @execution.finish_completed_relation_identity_scan(scan) {
    Ok(receipt) => receipt
    Err(_) => return Err(Assembly("body_finish"))
  }
  // Retain the exact receipt BEFORE any subsequent fallible step. Its one
  // scan already measured and hashed the payload/logical/schema preimages.
  lookup.identity_receipt = Some(receipt)
  guard @execution.completed_relation_identity_scan_body(scan, receipt)
    is Some(body) else {
    return Err(Assembly("body_unavailable"))
  }
  let logical = @execution.completed_relation_export_identity(receipt)
  let schema = @execution.completed_relation_export_schema_identity(receipt)
  let logical_bytes = @execution.logical_relation_usage(logical).0
  let schema_bytes = @execution.relation_schema_usage(schema).0
  if logical_bytes > 16777216 || schema_bytes > 16777216 - logical_bytes {
    return Err(Assembly("body_dependency_limit"))
  }
  lookup.identity_bodies = Some((body, @execution.relation_schema_wire(schema)))
  @execution.cancel_completed_relation_identity_scan(scan) |> ignore
  lookup.identity_scan = None
  if native_completion is Some((at, now_ms, max_bytes, max_nodes, max_depth)) {
    match
      prepare_native_keyed_lookup_completion(
        lookup, at, now_ms, max_bytes, max_nodes, max_depth,
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if lookup.closed || lookup.left.lookup_issue is Some(_) {
    return Err(Assembly("retired_publication_input"))
  }
  let holding = match
    @resources.retain_allocation(
      lookup.ledger,
      lookup.reservation,
      lookup.retained_bytes,
    ) {
    Ok(holding) => holding
    Err(issue) => return Err(Physical(issue))
  }
  lookup.holding = Some(holding)
  lookup.identity = Some(
    @execution.output_stream_identity(
      @execution.completed_relation_export_content(receipt),
    ).0,
  )
  Ok(())
}

///|
fn clear_keyed_lookup_identity_bodies(lookup : ClientKeyedLookupInput) -> Unit {
  for (_, _, history) in lookup.known {
    if history is Some(history) && history._retained_native_page is Some(page) {
      if page.scan is Some(scan) {
        @execution.cancel_completed_relation_identity_scan(scan) |> ignore
      }
      page.scan = None
      if page.receipt is Some(receipt) {
        @execution.cancel_completed_relation_export_receipt(receipt)
      }
      page.receipt = None
      page.output = None
      page.read = None
      page.capture = None
      page.result = None
      history._retained_native_page = None
    }
  }

  if lookup.identity_scan is Some(scan) {
    @execution.cancel_completed_relation_identity_scan(scan) |> ignore
  }
  lookup.identity_scan = None
  if lookup.native_sources is Some(state) {
    if state.source_scan is Some(scan) {
      @query.cancel_captured_source_cell_identity(scan) |> ignore
    }
    state.source_scan = None
    if state.source_identity_custody is ScannedHere &&
      state.source_identity is Some(identity) {
      @query.clear_captured_source_relation_dependency_bodies(identity)
    }
    state.source_identity = None
    for entry in state.sources {
      // Borrowed capture bodies belong to their still-live original Source.
      // Dropping this alias retires no Source and clears no foreign preimage.
      if entry.identity_custody is ScannedHere {
        @query.clear_captured_source_relation_dependency_bodies(entry.identity)
      }
    }
    state.sources.clear()
    state.sources.shrink_to_fit()
    state.relation = None
    state.request = None
  }
  lookup.native_sources = None
  lookup.native_started_at = None
  lookup.native_issuer = None
  lookup.native_completion = None
  lookup.native_left_identity = None
  if lookup.native_left_receipt is Some(receipt) {
    @execution.cancel_completed_relation_export_receipt(receipt)
  }
  lookup.native_left_receipt = None
  lookup.identity_bodies = None
  if lookup.identity_receipt is Some(receipt) {
    @execution.cancel_completed_relation_export_receipt(receipt)
  }
  lookup.identity_receipt = None
  lookup.identity_output = None
}

///|
/// Borrow only this live original observation's retained preimages. This is
/// dependency DATA, not a lookup-attempt/transport receipt or an access grant.
pub fn client_keyed_lookup_observation_dependency_bodies(
  observation : ClientKeyedLookupObservation,
) -> (String, String)? {
  let lookup = observation.lookup
  if client_keyed_lookup_input_identity(lookup) is None {
    return None
  }
  lookup.identity_bodies
}
