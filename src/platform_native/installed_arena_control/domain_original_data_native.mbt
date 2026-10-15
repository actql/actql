///|
/// The same registered installed child and actual backing issue both halves.
/// Equal scalars or copied transport cannot construct an original live ticket.
/// This does not authorize journal access, worker startup or cold adoption.
pub fn InstalledArenaHost::project_domain_original(
  self : InstalledArenaHost,
  record : InstalledArenaDomain,
) -> Result[
  (@bootstrap.NativePreparedDomainTransport, @resources.BackedExecutionOriginalData),
  @bootstrap.NativeBackedExecutionIssue,
] {
  match self.require_domain_current(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  record.backing.project_prepared_domain_original(
    self, record.domain.unwrap(), record,
  )
}
