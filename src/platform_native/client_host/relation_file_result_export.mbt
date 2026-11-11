///|
pub fn NativeClientRelationFileWork::prepare_result_export(
  self : NativeClientRelationFileWork,
  limits : @host.PublicationOutputExportLimits,
) -> Result[@host.PublicationOutputExport, NativeClientSourceWorkIssue] {
  if !self.entry.arena.matches_business_scope(false) {
    return self.entry.unavailable_export
  }
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // One retained bridge at a time, with its original scope and close duty.
  // Repeated callers cannot accumulate unquoted output_bridge holders.
  if self.output_bridge is Some(_) {
    return Err(Configuration)
  }
  guard self.requirements.publication_limits(
      self.prepared,
      limits.payload_wire.max_bytes,
    )
    is Some((row_limits, _)) else {
    return Err(Configuration)
  }
  guard self.requirements.publication_entry_limits(self.prepared)
    is Some((bridge_entries, _)) else {
    return Err(Configuration)
  }
  let output_bridge = match
    self.execution.prepare_result_export(
      0,
      row_limits,
      bridge_entries,
      limits.schema.max_bytes,
      limits,
    ) {
    Err(issue) => return Err(LocalExport(issue))
    Ok(value) => value
  }
  self.output_bridge = Some(output_bridge)
  match self.require_current() {
    Err(issue) =>
      // A failed Read return may have suspended execution. Keep this bridge
      // until close runs inside the actual original cleanup scope.
      Err(issue)
    Ok(_) => Ok(output_bridge.output_export())
  }
}

///|
fn NativeClientRelationFileWork::close_export(
  self : NativeClientRelationFileWork,
) -> Unit {
  if !self.entry.arena.matches_business_scope(true) {
    return
  }
  if !values_original_cleanup_entered(Some(self.access.base)) {
    return
  }
  match self.output_bridge {
    None => ()
    Some(output_bridge) => {
      output_bridge.close()
      self.output_bridge = None
    }
  }
}
