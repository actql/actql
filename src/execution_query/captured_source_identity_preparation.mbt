///|
/// A borrowed identity pass over the exact captured cells. The existing
/// Relation identity frame owns traversal, limits and logical work; this
/// preparation neither reads the Provider nor releases the acquisition.
struct CapturedSourceIdentityPreparation {
  origin : CapturedInputSource
  scan : @execution.CompletedRelationIdentityScan
}

///|
pub fn start_captured_source_identity(
  source : CapturedInputSource,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema_limits : @execution.RelationSchemaIdentityLimits,
  max_work : Int,
  max_workspace_slots : Int,
) -> Result[CapturedSourceIdentityPreparation, CapturedSourceIssue] {
  if !(source.live)() {
    return Err(Unavailable)
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
  )
  .map_err(issue => Export(issue))
  .map(scan => { origin: source, scan, })
}

///|
pub fn CapturedSourceIdentityPreparation::advance(
  self : CapturedSourceIdentityPreparation,
  quantum : Int,
) -> Result[(Bool, Int), CapturedSourceIssue] {
  if !(self.origin.live)() {
    self.cancel() |> ignore
    return Err(Unavailable)
  }
  @execution.advance_completed_relation_identity_scan(self.scan, quantum).map_err(issue => {
      Export(issue)
    },
  )
}

///|
pub fn CapturedSourceIdentityPreparation::finish(
  self : CapturedSourceIdentityPreparation,
) -> Result[CapturedSourceRelationIdentity, CapturedSourceIssue] {
  if !(self.origin.live)() {
    self.cancel() |> ignore
    return Err(Unavailable)
  }
  let receipt = match
    @execution.finish_completed_relation_identity_scan(self.scan) {
    Ok(receipt) => receipt
    Err(issue) => return Err(Export(issue))
  }
  let logical = @execution.completed_relation_export_identity(receipt)
  let identity = {
    origin: self.origin,
    logical_relation_cid: @execution.logical_relation_cid(logical),
    schema_cid: @execution.relation_schema_cid(
      @execution.completed_relation_export_schema_identity(receipt),
    ),
    row_count: @execution.logical_relation_usage(logical).2,
    dependency_bodies: None,
  }
  @execution.cancel_completed_relation_export_receipt(receipt)
  Ok(identity)
}

///|
pub fn CapturedSourceIdentityPreparation::work(
  self : CapturedSourceIdentityPreparation,
) -> Int64 {
  @execution.completed_relation_identity_scan_work(self.scan)
}

///|
pub fn CapturedSourceIdentityPreparation::cancel(
  self : CapturedSourceIdentityPreparation,
) -> Bool {
  @execution.cancel_completed_relation_identity_scan(self.scan)
}
