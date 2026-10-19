///|
/// Metadata from only this joined original's retained physical context. A
/// zero count is not retirement and failed observation is never inactivity.
pub fn InstalledArenaHost::observe_domain_original_read_cleanup(
  self : InstalledArenaHost,
  record : InstalledArenaOriginalRead,
) -> Result[
  @bootstrap.NativeReadCleanupObservation,
  InstalledArenaOriginalReadIssue,
] {
  match self.original_domain_read(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !record.owns_read || record.closed || record.physical_retired.val {
    return Err(Read(@resources.CleanupPending))
  }
  record.domain.backing
  .observe_backed_read_cleanup(
    self,
    record.domain.domain.unwrap(),
    record.domain,
  )
  .map_err(issue => Domain(issue))
}
