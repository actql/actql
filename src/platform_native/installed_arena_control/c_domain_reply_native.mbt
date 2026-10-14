///|
pub(all) enum InstalledArenaDomainOperation {
  PrepareDomain
  ObserveDomain
  TransferDomain
  EnterDomain
  LeaveDomain
  CloseDomain
} derive(Eq)

///|
/// Immutable original typed reply; private transport, not execution permission.
struct InstalledArenaDomainReply {
  operation : InstalledArenaDomainOperation
  host : InstalledArenaHost
  domain : InstalledArenaDomain?
  issue : @bootstrap.NativeBackedExecutionIssue?
}

///|
fn domain_unit_reply(operation : InstalledArenaDomainOperation, domain : InstalledArenaDomain,
  result : Result[Unit, @bootstrap.NativeBackedExecutionIssue]) -> InstalledArenaDomainReply {
  { operation, host: domain.host, domain: Some(domain), issue: match result { Ok(_) => None; Err(issue) => Some(issue) } }
}

///|
pub fn prepare_installed_arena_domain_reply(host : InstalledArenaHost,
  scope : InstalledArenaBackingBorrow, fd : Int, bytes : Int64,
  planning_work : Int, attempts : Int, holdings : Int, transfer_bytes : Int64,
  retained_bytes : Int64, execution_bytes : Int64) -> InstalledArenaDomainReply {
  let limits : @resources.LedgerLimits = { planning_work, attempts, holdings, transfer_bytes, retained_bytes, execution_bytes }
  match host.prepare_domain(scope, fd, bytes, limits) {
    Err(issue) => { operation: PrepareDomain, host, domain: None, issue: Some(issue) }
    Ok(PendingDomain(domain, issue)) => { operation: PrepareDomain, host, domain: Some(domain), issue: Some(issue) }
    Ok(PreparedDomain(domain)) => { operation: PrepareDomain, host, domain: Some(domain), issue: None }
  }
}

///|
pub fn current_installed_arena_domain_reply(host : InstalledArenaHost, domain : InstalledArenaDomain) -> InstalledArenaDomainReply {
  domain_unit_reply(ObserveDomain, domain, host.require_domain_current(domain))
}

///|
pub fn transfer_installed_arena_domain_reply(host : InstalledArenaHost, domain : InstalledArenaDomain) -> InstalledArenaDomainReply {
  domain_unit_reply(TransferDomain, domain, host.transfer_domain(domain))
}

///|
pub fn enter_installed_arena_domain_reply(host : InstalledArenaHost, domain : InstalledArenaDomain) -> InstalledArenaDomainReply {
  domain_unit_reply(EnterDomain, domain, host.enter_domain(domain))
}

///|
pub fn leave_installed_arena_domain_reply(host : InstalledArenaHost, domain : InstalledArenaDomain) -> InstalledArenaDomainReply {
  domain_unit_reply(LeaveDomain, domain, host.leave_domain(domain))
}

///|
pub fn close_installed_arena_domain_reply(host : InstalledArenaHost, domain : InstalledArenaDomain) -> InstalledArenaDomainReply {
  domain_unit_reply(CloseDomain, domain, host.close_domain_after_owner_ack(domain))
}

///|
pub fn InstalledArenaDomainReply::original_host(self : InstalledArenaDomainReply) -> InstalledArenaHost { self.host }

///|
pub fn InstalledArenaDomainReply::original_domain(self : InstalledArenaDomainReply) -> InstalledArenaDomain? { self.domain }

///|
pub fn InstalledArenaDomainReply::operation_tag(self : InstalledArenaDomainReply) -> Int {
  match self.operation { PrepareDomain => 1; ObserveDomain => 2; TransferDomain => 3; EnterDomain => 4; LeaveDomain => 5; CloseDomain => 6 }
}

///|
pub fn InstalledArenaDomainReply::issue_family(self : InstalledArenaDomainReply) -> Int {
  match self.issue {
    None => 0
    Some(@bootstrap.Accounting(_)) => 8
    Some(@bootstrap.Bootstrap(issue)) => {
      let reply = original_unit_reply(Current, self.host, Err(issue))
      reply.issue_family()
    }
  }
}

///|
pub fn InstalledArenaDomainReply::issue_description(self : InstalledArenaDomainReply) -> String {
  match self.issue { None => ""; Some(issue) => @debug.to_string(issue) }
}
