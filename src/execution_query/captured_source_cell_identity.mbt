///|
/// Cell identity continuation over the same captured Source. The separate
/// retained-storage scanner keeps its existing physical-frame verifier path.
/// Neither continuation exposes a raw completed input or a new source issuer.
struct CapturedSourceCellIdentityScan {
  mut origin : CapturedInputSource?
  mut scan : @execution.CompletedRelationIdentityScan?
  body_limit : Int
  mut advancing : Bool
  mut closed : Bool
  mut stopped : Bool
}

///|
// This wrapper, restricted output, optional exact input read, returned identity,
// body tuple/Some, two removable original aliases and Result carrier coexist
// at the original transfer. Source,
// schema/Values and immutable body strings are borrowed from the one
// paid scan; its own quote already includes their complete construction peak.
fn source_cell_identity_capacity(
  scan : @execution.ExecutionCapacity,
) -> @execution.ExecutionCapacity? {
  guard @execution.preparation_representation_cost({
      record_headers: 9L,
      reference_slots: 17L,
      scalar_words: 5L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(controls) else {
    return None
  }
  let r = @execution.execution_capacity_retained_bytes(scan)
  let e = @execution.execution_capacity_execution_bytes(scan)
  if r > 9223372036854775807L - controls || e > 9223372036854775807L - controls {
    return None
  }
  @execution.execution_capacity(r + controls, e + controls)
}

///|
/// Immutable constructor DATA only: no current callback, allocation or grant.
pub fn captured_source_cell_identity_start_capacity(
  source : CapturedInputSource,
) -> @execution.ExecutionCapacity? {
  @execution.completed_relation_identity_scan_start_construction_capacity(
    source.output,
    retain_body=true,
  ).bind(source_cell_identity_capacity)
}

///|
pub fn start_captured_source_cell_identity(
  source : CapturedInputSource,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema_limits : @execution.RelationSchemaIdentityLimits,
  max_work : Int,
  max_workspace_slots : Int,
  body_limit : Int,
) -> Result[CapturedSourceCellIdentityScan, CapturedSourceIssue] {
  if body_limit < 1 || body_limit > 16777216 {
    return Err(DependencyBodyLimit)
  }
  // The original Core scan observes the restricted output's current before
  // its first covered constructor; do not repeat that callback here.
  let input = match source.owner {
    InputCapture(input) => Some(input.read)
    QueryCapture(_) => None
  }
  @execution.start_completed_relation_identity_scan(
    @execution.restrict_completed_output(source.output, source.live),
    max_rows,
    values,
    payload_wire,
    logical_wire,
    schema_limits,
    max_work,
    max_workspace_slots,
    incremental_metadata=true,
    retain_body=true,
    source_input=input,
  )
  .map_err(issue => CapturedSourceIssue::Export(issue))
  .map(scan => {
    origin: Some(source),
    scan: Some(scan),
    body_limit,
    advancing: false,
    closed: false,
    stopped: false,
  })
}

///|
pub fn captured_source_cell_identity_next_capacity(
  value : CapturedSourceCellIdentityScan,
) -> @execution.ExecutionCapacity? {
  if value.closed || value.advancing {
    return None
  }
  guard value.scan is Some(scan) else { return None }
  @execution.completed_relation_identity_scan_next_construction_capacity(scan).bind(
    source_cell_identity_capacity,
  )
}

///|
pub fn advance_captured_source_cell_identity(
  value : CapturedSourceCellIdentityScan,
  quantum : Int,
  construction_capacity : @execution.ExecutionCapacity,
) -> Result[(Bool, Int), CapturedSourceIssue] {
  if value.closed || value.advancing {
    return Err(Unavailable)
  }
  guard value.scan is Some(scan) else { return Err(Unavailable) }
  value.advancing = true
  let result = @execution.advance_completed_relation_identity_scan(
    scan,
    quantum,
    construction_capacity=Some(construction_capacity),
  ).map_err(issue => CapturedSourceIssue::Export(issue))
  value.advancing = false
  if value.stopped {
    cancel_captured_source_cell_identity(value) |> ignore
    return Err(Unavailable)
  }
  result
}

///|
pub fn cancel_captured_source_cell_identity(
  value : CapturedSourceCellIdentityScan,
) -> Bool {
  value.stopped = true
  if value.advancing {
    return false
  }
  if value.scan is Some(scan) {
    @execution.cancel_completed_relation_identity_scan(scan) |> ignore
  }
  value.scan = None
  value.origin = None
  value.closed = true
  true
}

///|
/// Return exactly the one completed scan's identity and raw preimages. The
/// scan is severed after this original alias transfer; no second hash/export,
/// row admission or source read is performed. The paid caller keeps the
/// returned identity until its actual Store/dependency consumer retires.
pub fn finish_captured_source_cell_identity(
  value : CapturedSourceCellIdentityScan,
) -> Result[CapturedSourceRelationIdentity, CapturedSourceIssue] {
  if value.closed || value.advancing {
    return Err(Unavailable)
  }
  guard value.origin is Some(origin) && value.scan is Some(scan) else {
    return Err(Unavailable)
  }
  value.advancing = true
  defer {
    value.advancing = false
  }
  // Core finalization observes this same restricted Source at its original
  // receipt boundary. The wrapper keeps only the post-callback stop fence.
  let receipt = match @execution.finish_completed_relation_identity_scan(scan) {
    Ok(receipt) => receipt
    Err(issue) => return Err(Export(issue))
  }
  if value.stopped {
    return Err(Unavailable)
  }
  guard @execution.completed_relation_identity_scan_body(scan, receipt)
    is Some(body) else {
    return Err(DependencyBodyLimit)
  }
  let logical_identity = @execution.completed_relation_export_identity(receipt)
  let schema_identity = @execution.completed_relation_export_schema_identity(
    receipt,
  )
  let schema = @execution.relation_schema_wire(schema_identity)
  // The SAME receipt already measured both exact canonical preimages. Do not
  // encode/count the retained strings again to apply this byte refusal bound.
  let body_bytes = @execution.logical_relation_usage(logical_identity).0
  let schema_bytes = @execution.relation_schema_usage(schema_identity).0
  if body_bytes > value.body_limit ||
    schema_bytes > value.body_limit - body_bytes {
    return Err(DependencyBodyLimit)
  }
  let identity : CapturedSourceRelationIdentity = {
    origin,
    logical_relation_cid: @execution.logical_relation_cid(logical_identity),
    schema_cid: @execution.relation_schema_cid(schema_identity),
    row_count: @execution.completed_relation_export_measurement(receipt).row_count,
    dependency_bodies: Some((body, schema)),
  }
  // Cancellation cuts the scan's aliases, never the returned identity or the
  // original Source/Read. No physical capacity is released by this operation.
  value.advancing = false
  cancel_captured_source_cell_identity(value) |> ignore
  Ok(identity)
}
