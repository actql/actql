///|
/// Original installed Host selection retained before worker-child provisioning.
/// This is neither an acquired backing nor a provisioning/launch permission.
struct InstalledArenaWorkerSelection {
  host : InstalledArenaHost
}

///|
pub fn InstalledArenaHost::worker_provisioning_selection(
  self : InstalledArenaHost,
) -> Result[InstalledArenaWorkerSelection, @bootstrap.NativeBootstrapIssue] {
  if self.closing || self.closed {
    return Err(@bootstrap.Closing)
  }
  if self.acquisition_started {
    match self.require_current() {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  guard self.supplier is Some(_) else { return Err(@bootstrap.Unavailable) }
  Ok({ host: self, })
}

///|
/// Same nominal selection only. Equal DATA cannot adopt another physical Host.
/// Existing Host backing may already fund Host initialization. Observing that
/// same Host never acquires or creates another Ledger. Child ticket/backing
/// projection remains a separate operation after its original provisioning.
pub fn installed_worker_selection_data(
  original : InstalledArenaWorkerSelection,
) -> Result[(String, Bytes, Int64), @bootstrap.NativeBootstrapIssue] {
  let host = original.host
  if host.closing || host.closed {
    return Err(@bootstrap.Closing)
  }
  if host.acquisition_started {
    match host.require_current() {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  guard host.supplier is Some(_) else { return Err(@bootstrap.Unavailable) }
  Ok((host.source, host.recipe, host.generation))
}
