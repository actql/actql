///|
/// Immutable original transport, not a read grant or another cleanup Owner.
pub(all) enum InstalledArenaOriginalReadOperation {
  PrepareOriginalRead
  ObserveOriginalRead
  EnterOriginalRead
  LeaveOriginalRead
  CleanupOriginalRead
  CloseOriginalRead
} derive(Eq)

///|
struct InstalledArenaOriginalReadReply {
  operation : InstalledArenaOriginalReadOperation
  domain : InstalledArenaDomain
  original : InstalledArenaOriginalRead?
  issue : InstalledArenaOriginalReadIssue?
}

///|
fn original_read_unit_reply(
  operation : InstalledArenaOriginalReadOperation,
  original : InstalledArenaOriginalRead,
  result : Result[Unit, InstalledArenaOriginalReadIssue],
) -> InstalledArenaOriginalReadReply {
  {
    operation,
    domain: original.domain,
    original: Some(original),
    issue: match result {
      Ok(_) => None
      Err(issue) => Some(issue)
    },
  }
}

///|
/// Private selected-profile declaration only. The original Host/domain and
/// Common allowance decide acceptance; these scalars issue no grant or Root.
pub fn prepare_installed_arena_original_read_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
  bootstrap_retained : Int64,
  bootstrap_execution : Int64,
  workspace_execution : Int64,
  read_retained : Int64,
  read_execution : Int64,
) -> InstalledArenaOriginalReadReply {
  match
    host.prepare_domain_original_read(domain, {
      bootstrap_retained,
      bootstrap_execution,
      workspace_execution,
      read_retained,
      read_execution,
    }) {
    Err(issue) =>
      {
        operation: PrepareOriginalRead,
        domain,
        original: None,
        issue: Some(issue),
      }
    Ok(PendingOriginalRead(original, issue)) =>
      {
        operation: PrepareOriginalRead,
        domain,
        original: Some(original),
        issue: Some(issue),
      }
    Ok(ReadyOriginalRead(original)) =>
      {
        operation: PrepareOriginalRead,
        domain,
        original: Some(original),
        issue: None,
      }
  }
}

///|
pub fn current_installed_arena_original_read_reply(
  host : InstalledArenaHost,
  original : InstalledArenaOriginalRead,
) -> InstalledArenaOriginalReadReply {
  original_read_unit_reply(
    ObserveOriginalRead,
    original,
    host.require_domain_original_read_current(original),
  )
}

///|
pub fn enter_installed_arena_original_read_reply(
  host : InstalledArenaHost,
  original : InstalledArenaOriginalRead,
) -> InstalledArenaOriginalReadReply {
  original_read_unit_reply(
    EnterOriginalRead,
    original,
    host.enter_domain_original_read(original),
  )
}

///|
pub fn leave_installed_arena_original_read_reply(
  host : InstalledArenaHost,
  original : InstalledArenaOriginalRead,
) -> InstalledArenaOriginalReadReply {
  original_read_unit_reply(
    LeaveOriginalRead,
    original,
    host.leave_domain_original_read(original),
  )
}

///|
pub fn cleanup_installed_arena_original_read_reply(
  host : InstalledArenaHost,
  original : InstalledArenaOriginalRead,
) -> InstalledArenaOriginalReadReply {
  original_read_unit_reply(
    CleanupOriginalRead,
    original,
    host.enter_domain_original_read_cleanup(original),
  )
}

///|
pub fn close_installed_arena_original_read_reply(
  host : InstalledArenaHost,
  original : InstalledArenaOriginalRead,
) -> InstalledArenaOriginalReadReply {
  original_read_unit_reply(
    CloseOriginalRead,
    original,
    host.close_domain_original_read(original),
  )
}

///|
pub fn InstalledArenaOriginalReadReply::original_host(
  self : InstalledArenaOriginalReadReply,
) -> InstalledArenaHost {
  self.domain.host
}

///|
pub fn InstalledArenaOriginalReadReply::original_domain(
  self : InstalledArenaOriginalReadReply,
) -> InstalledArenaDomain {
  self.domain
}

///|
pub fn InstalledArenaOriginalReadReply::original_read(
  self : InstalledArenaOriginalReadReply,
) -> InstalledArenaOriginalRead? {
  self.original
}

///|
pub fn InstalledArenaOriginalReadReply::operation_tag(
  self : InstalledArenaOriginalReadReply,
) -> Int {
  match self.operation {
    PrepareOriginalRead => 1
    ObserveOriginalRead => 2
    EnterOriginalRead => 3
    LeaveOriginalRead => 4
    CleanupOriginalRead => 5
    CloseOriginalRead => 6
  }
}

///|
/// Preserve the existing imported Owner's Unknown as its own typed fact.
/// Family nine is never a known refusal, zero usage, or another attempt.
pub fn InstalledArenaOriginalReadReply::issue_family(
  self : InstalledArenaOriginalReadReply,
) -> Int {
  match self.issue {
    None => 0
    Some(Domain(@bootstrap.Bootstrap(issue))) => {
      let reply = original_unit_reply(Current, self.domain.host, Err(issue))
      reply.issue_family()
    }
    Some(Domain(@bootstrap.Accounting(_))) => 8
    Some(Child(@resources.Unknown)) => 9
    Some(Child(_)) => 10
    Some(Read(_)) => 11
    Some(Buffer(_)) => 12
  }
}
