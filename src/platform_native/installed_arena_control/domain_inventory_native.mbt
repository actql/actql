///|
/// Copy only this Host's same entered domain census. Normal original lifetime
/// and currentness remain required; zero occupancy is never a cleanup ACK.
pub fn InstalledArenaHost::observe_domain_inventory(
  self : InstalledArenaHost,
  record : InstalledArenaDomain,
) -> Result[
  @bootstrap.NativeDomainInventory,
  @bootstrap.NativeBackedExecutionIssue,
] {
  match self.require_domain_current(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  record.backing.observe_backed_domain_inventory(
    self,
    record.domain.unwrap(),
    record,
  )
}
