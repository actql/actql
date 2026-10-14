///|
/// Private transport tags. Prepare success is an intent, not acquired funding.
pub(all) enum InstalledArenaOperation {
  Prepare
  Acquire
  Current
  Close
} derive(Eq)

///|
/// Immutable projection of an original typed result. This is not a lifecycle
/// controller. Keeping the original Host also keeps partial cleanup custody.
struct InstalledArenaReply {
  operation : InstalledArenaOperation
  original : InstalledArenaHost?
  issue : @bootstrap.NativeBootstrapIssue?
}

///|
fn original_unit_reply(
  operation : InstalledArenaOperation,
  original : InstalledArenaHost,
  result : Result[Unit, @bootstrap.NativeBootstrapIssue],
) -> InstalledArenaReply {
  let issue = match result {
    Ok(_) => None
    Err(value) => Some(value)
  }
  { operation, original: Some(original), issue, }
}

///|
pub fn prepare_installed_arena_reply(
  source : String,
  recipe : Bytes,
  generation : Int64,
  bytes : Int64,
  planning_work : Int,
  attempts : Int,
  holdings : Int,
  transfer_bytes : Int64,
  retained_bytes : Int64,
  execution_bytes : Int64,
  control_envelope_bytes : Int64,
) -> InstalledArenaReply {
  match
    prepare_installed_arena_from_primitives(
      source, recipe, generation, bytes, planning_work, attempts, holdings, transfer_bytes,
      retained_bytes, execution_bytes, control_envelope_bytes,
    ) {
    Ok(original) =>
      { operation: Prepare, original: Some(original), issue: None, }
    Err(issue) => { operation: Prepare, original: None, issue: Some(issue), }
  }
}

///|
pub fn acquire_installed_arena_reply(
  original : InstalledArenaHost,
) -> InstalledArenaReply {
  original_unit_reply(Acquire, original, original.acquire())
}

///|
pub fn acquire_installed_arena_fd_reply(
  original : InstalledArenaHost,
  fd : Int,
) -> InstalledArenaReply {
  original_unit_reply(Acquire, original, original.acquire_fd(fd))
}

///|
pub fn current_installed_arena_reply(
  original : InstalledArenaHost,
) -> InstalledArenaReply {
  original_unit_reply(Current, original, original.require_current())
}

///|
pub fn close_installed_arena_reply(
  original : InstalledArenaHost,
) -> InstalledArenaReply {
  original_unit_reply(Close, original, original.try_close())
}

///|
/// C must call typed accessors, not inspect generated struct/enum fields.
pub fn InstalledArenaReply::original_host(
  self : InstalledArenaReply,
) -> InstalledArenaHost? {
  self.original
}

///|
pub fn InstalledArenaReply::operation_tag(self : InstalledArenaReply) -> Int {
  match self.operation {
    Prepare => 1
    Acquire => 2
    Current => 3
    Close => 4
  }
}

///|
/// This identifies the existing typed issue family. The caller must retain
/// operation and original identity; zero is not VM/Run/Store or worker success.
pub fn InstalledArenaReply::issue_family(self : InstalledArenaReply) -> Int {
  match self.issue {
    None => 0
    Some(@bootstrap.Unavailable) => 1
    Some(@bootstrap.ForeignOriginal) => 2
    Some(@bootstrap.AlreadyConsumed) => 3
    Some(@bootstrap.Closing) => 4
    Some(@bootstrap.ReadersPending) => 5
    Some(@bootstrap.Physical(_)) => 6
    Some(@bootstrap.Resource(_)) => 7
  }
}

///|
/// Explanation only. Neither the C shim nor Python may classify success by it.
pub fn InstalledArenaReply::issue_description(
  self : InstalledArenaReply,
) -> String {
  match self.issue {
    None => ""
    Some(issue) => @debug.to_string(issue)
  }
}
