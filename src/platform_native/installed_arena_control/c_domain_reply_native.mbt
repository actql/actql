///|
pub(all) enum InstalledArenaDomainOperation {
  PrepareDomain
  ObserveDomain
  TransferDomain
  EnterDomain
  LeaveDomain
  CloseDomain
  ProjectDomain
} derive(Eq)

///|
/// Immutable original typed reply; private transport, not execution permission.
struct InstalledArenaDomainReply {
  operation : InstalledArenaDomainOperation
  host : InstalledArenaHost
  domain : InstalledArenaDomain?
  issue : @bootstrap.NativeBackedExecutionIssue?
  material : @bootstrap.NativePreparedDomainTransport?
}

///|
fn domain_unit_reply(operation : InstalledArenaDomainOperation, domain : InstalledArenaDomain,
  result : Result[Unit, @bootstrap.NativeBackedExecutionIssue]) -> InstalledArenaDomainReply {
  { operation, host: domain.host, domain: Some(domain), material: None, issue: match result { Ok(_) => None; Err(issue) => Some(issue) } }
}

///|
pub fn prepare_installed_arena_domain_reply(host : InstalledArenaHost,
  scope : InstalledArenaBackingBorrow, fd : Int, bytes : Int64,
  planning_work : Int, attempts : Int, holdings : Int, transfer_bytes : Int64,
  retained_bytes : Int64, execution_bytes : Int64) -> InstalledArenaDomainReply {
  let limits : @resources.LedgerLimits = { planning_work, attempts, holdings, transfer_bytes, retained_bytes, execution_bytes }
  match host.prepare_domain(scope, fd, bytes, limits) {
    Err(issue) => { operation: PrepareDomain, host, domain: None, material: None, issue: Some(issue) }
    Ok(PendingDomain(domain, issue)) => { operation: PrepareDomain, host, domain: Some(domain), material: None, issue: Some(issue) }
    Ok(PreparedDomain(domain)) => { operation: PrepareDomain, host, domain: Some(domain), material: None, issue: None }
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
pub fn project_installed_arena_domain_reply(host : InstalledArenaHost, domain : InstalledArenaDomain) -> InstalledArenaDomainReply {
  match host.project_prepared_domain(domain) {
    Err(issue) => { operation: ProjectDomain, host: domain.host, domain: Some(domain), material: None, issue: Some(issue) }
    Ok(material) => { operation: ProjectDomain, host: domain.host, domain: Some(domain), material: Some(material), issue: None }
  }
}

///|
/// Bounded immutable DATA getter. Absence and out-of-range never fabricate zero.
pub fn InstalledArenaDomainReply::material_scalar(self : InstalledArenaDomainReply, ordinal : Int) -> Int64 {
  guard self.material is Some(material) else { return -1L }
  match ordinal {
    0 => material.extent.generation
    1 => material.extent.device
    2 => material.extent.inode
    3 => material.extent.capacity
    4 => material.extent.mapping_offset
    5 => material.extent.mapping_length
    6 => material.extent.payload_offset
    7 => material.extent.payload_length
    8 => if material.extent.writable { 1L } else { 0L }
    9 => material.limits.planning_work.to_int64()
    10 => material.limits.attempts.to_int64()
    11 => material.limits.holdings.to_int64()
    12 => material.limits.transfer_bytes
    13 => material.limits.retained_bytes
    14 => material.limits.execution_bytes
    _ => -1L
  }
}

///|
pub fn InstalledArenaDomainReply::material_source(self : InstalledArenaDomainReply) -> String {
  match self.material { None => ""; Some(material) => material.extent.source }
}

///|
pub fn InstalledArenaDomainReply::material_recipe(self : InstalledArenaDomainReply) -> Bytes {
  match self.material { None => Bytes::new(0); Some(material) => material.extent.recipe }
}

///|
pub fn InstalledArenaDomainReply::original_host(self : InstalledArenaDomainReply) -> InstalledArenaHost { self.host }

///|
pub fn InstalledArenaDomainReply::original_domain(self : InstalledArenaDomainReply) -> InstalledArenaDomain? { self.domain }

///|
pub fn InstalledArenaDomainReply::operation_tag(self : InstalledArenaDomainReply) -> Int {
  match self.operation { PrepareDomain => 1; ObserveDomain => 2; TransferDomain => 3; EnterDomain => 4; LeaveDomain => 5; CloseDomain => 6; ProjectDomain => 7 }
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
