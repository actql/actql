///|
/// A requested identity pass over the exact held acquisition. The physical
/// adapter supplies bounded row frames; the existing storage verifier owns
/// admission and exact content matching. This never creates a consumer grant.
struct CapturedSourceIdentityScan {
  origin : CapturedInputSource
  storage : @execution.ProducerStorage
  scan : @execution.RetainedStorageScan
  schema : @execution.RelationSchemaIdentity
}

///|
pub(all) enum CapturedSourceIdentityScanIssue {
  Source(CapturedSourceIssue)
  Scan(@execution.CompletedImportIssue)
  Schema(@execution.RelationSchemaIdentityIssue)
  Unavailable
}

///|
/// Unlike the cell exporter, this preparation does not require materializing
/// the captured rows. The caller keeps the acquisition alive until the pass
/// finishes or is cancelled; cancellation does not close that original owner.
pub fn prepare_captured_source_identity_scan(
  source : CapturedInputSource,
  max_entries : Int,
  max_name_bytes : Int,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema_limits : @execution.RelationSchemaIdentityLimits,
  max_batch_bytes : Int,
) -> Result[CapturedSourceIdentityScan, CapturedSourceIdentityScanIssue] {
  let storage = match
    captured_source_storage(source, max_entries, max_name_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Source(issue))
  }
  let schema = match
    @execution.identify_relation_schema(
      @execution.producer_storage_schema(storage),
      schema_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Schema(issue))
  }
  @execution.prepare_retained_relation_identity_scan(
    storage, max_rows, values, payload_wire, logical_wire, max_batch_bytes,
  )
  .map_err(issue => CapturedSourceIdentityScanIssue::Scan(issue))
  .map(scan => { origin: source, storage, scan, schema, })
}

///|
/// Installed representation access only. It preserves the exact acquisition
/// and does not permit an adapter-supplied CID to replace the full scan.
pub fn captured_source_identity_scan_storage(
  value : CapturedSourceIdentityScan,
) -> @execution.ProducerStorage? {
  if !captured_source_available(value.origin) ||
    !@execution.producer_storage_available(value.storage) {
    return None
  }
  Some(value.storage)
}

///|
pub fn append_captured_source_identity_scan(
  value : CapturedSourceIdentityScan,
  row : String,
  limits : @execution.RetainedRowDecodeLimits,
) -> Result[Unit, CapturedSourceIdentityScanIssue] {
  if !captured_source_available(value.origin) {
    cancel_captured_source_identity_scan(value) |> ignore
    return Err(Unavailable)
  }
  @execution.append_retained_storage_scan_wire(value.scan, row, limits)
  .map(_ => ())
  .map_err(issue => CapturedSourceIdentityScanIssue::Scan(issue))
}

///|
pub fn cancel_captured_source_identity_scan(
  value : CapturedSourceIdentityScan,
) -> Bool {
  @execution.cancel_retained_storage_scan(value.scan)
}

///|
/// The identity is issued only after the original storage receipt matched in
/// full. Changed, reordered or truncated frames cannot produce source evidence.
pub fn finish_captured_source_identity_scan(
  value : CapturedSourceIdentityScan,
) -> Result[CapturedSourceRelationIdentity, CapturedSourceIdentityScanIssue] {
  if !captured_source_available(value.origin) {
    cancel_captured_source_identity_scan(value) |> ignore
    return Err(Unavailable)
  }
  let verified = match @execution.finish_retained_storage_scan(value.scan) {
    Ok(value) => value
    Err(issue) => return Err(Scan(issue))
  }
  guard @execution.verified_storage_scan_matches(verified, value.storage) &&
    @execution.verified_storage_scan_relation_identity(verified)
    is Some(logical) else {
    return Err(Unavailable)
  }
  Ok({
    origin: value.origin,
    logical_relation_cid: @execution.logical_relation_cid(logical),
    schema_cid: @execution.relation_schema_cid(value.schema),
    row_count: @execution.logical_relation_usage(logical).2,
    dependency_bodies: None,
  })
}
