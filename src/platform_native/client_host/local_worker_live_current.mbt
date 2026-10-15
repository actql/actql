///|
/// Recheck an already retained live child against its original committed rows.
/// This issues no funding, acquisition, launch, stop, settlement or cold adoption.
/// Unknown COMMIT fences remain authoritative even if a later cold lookup finds
/// the row: DATA cannot recover this original live attempt or its physical loan.
pub fn NativeLocalWorkerProvisioningAttempt::require_recorded_resource_current(
  self : NativeLocalWorkerProvisioningAttempt,
  domain : @arena.InstalledArenaDomain,
  principal : String,
  connection : String,
) -> Result[Unit, NativeLocalWorkerProvisioningIssue] {
  guard self.resource is Some(original) &&
    physical_equal(original.domain, domain) else {
    return Err(CustodyLost)
  }
  match self.require_worker_resource_current(original, principal, connection) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let observed = self.host.journal.transaction(() => {
    match self.require_worker_resource_current(original, principal, connection) {
      Err(issue) => return Err(worker_provisioning_journal_issue(issue))
      Ok(_) => ()
    }
    let row = match
      self.host.database.read_with_body_limit(
        "client_worker_provisioning",
        worker_resource_record_key(self.key),
        4096L,
      ) {
      Err(@sqlite.NotFound) => return Err(CustodyLost)
      Err(issue) => return Err(Physical(issue))
      Ok(value) => value
    }
    if row.revision != 0L || row.body != original.body {
      return Err(CustodyLost)
    }
    self.require_worker_resource_current(original, principal, connection)
    .map_err(worker_provisioning_journal_issue)
  })
  match observed {
    Err(issue) => Err(Journal(issue))
    Ok(_) =>
      self.require_worker_resource_current(original, principal, connection)
  }
}
