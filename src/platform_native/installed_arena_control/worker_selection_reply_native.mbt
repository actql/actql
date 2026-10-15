///|
priv enum WorkerSelectionOperation {
  Select
  Current
}

///|
/// In-process transport only. The original Host owns this nominal selection;
/// neither the reply nor projected DATA supplies worker funding or authority.
struct InstalledArenaWorkerSelectionReply {
  operation : WorkerSelectionOperation
  original : InstalledArenaHost
  selection : InstalledArenaWorkerSelection?
  issue : @bootstrap.NativeBootstrapIssue?
}

///|
pub fn installed_arena_worker_selection_reply(
  original : InstalledArenaHost,
) -> InstalledArenaWorkerSelectionReply {
  match original.worker_provisioning_selection() {
    Ok(selection) =>
      { operation: Select, original, selection: Some(selection), issue: None, }
    Err(issue) =>
      { operation: Select, original, selection: None, issue: Some(issue), }
  }
}

///|
pub fn InstalledArenaWorkerSelectionReply::original_host(
  self : InstalledArenaWorkerSelectionReply,
) -> InstalledArenaHost {
  self.original
}

///|
pub fn InstalledArenaWorkerSelectionReply::original_selection(
  self : InstalledArenaWorkerSelectionReply,
) -> InstalledArenaWorkerSelection? {
  self.selection
}

///|
/// Reuse the existing original-control issue family without a new outcome map.
pub fn InstalledArenaWorkerSelectionReply::issue_family(
  self : InstalledArenaWorkerSelectionReply,
) -> Int {
  installed_arena_issue_family(self.issue)
}

///|
/// Observe this same nominal selection without issuing a replacement. Current
/// here means metadata custody only, never acquired funding or worker permission.
pub fn current_installed_arena_worker_selection_reply(
  original : InstalledArenaHost,
  selection : InstalledArenaWorkerSelection,
) -> InstalledArenaWorkerSelectionReply {
  if !physical_equal(selection.host, original) {
    return {
      operation: Current,
      original,
      selection: None,
      issue: Some(@bootstrap.ForeignOriginal),
    }
  }
  let issue = match installed_worker_selection_data(selection) {
    Ok(_) => None
    Err(issue) => Some(issue)
  }
  { operation: Current, original, selection: Some(selection), issue, }
}

///|
pub fn InstalledArenaWorkerSelectionReply::operation_tag(
  self : InstalledArenaWorkerSelectionReply,
) -> Int {
  match self.operation {
    Select => 1
    Current => 2
  }
}
