///|
/// Fixed physical metadata from this same retained execution, not capacity,
/// current authority or a retirement acknowledgement. The existing bootstrap
/// observer requires clear outer control and never enters the child Read.
pub fn InstalledArenaHost::observe_domain_retained_execution_cleanup(
  self : InstalledArenaHost,
  record : InstalledArenaRetainedExecution,
) -> Result[
  @bootstrap.NativeReadCleanupObservation,
  InstalledArenaRetainedExecutionIssue,
] {
  match self.original_retained_execution(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !record.owns_read || record.closed || record.physical_retired {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  let domain = record.domain
  domain.backing
  .observe_backed_read_cleanup(self, domain.domain.unwrap(), domain)
  .map_err(issue => Domain(issue))
}
