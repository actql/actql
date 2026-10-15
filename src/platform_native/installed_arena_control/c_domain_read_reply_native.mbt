///|
/// Same immutable original domain reply. These operations introduce no handle,
/// profile, callback permission, child identity or foreign cleanup controller.
pub fn prepare_installed_arena_domain_read_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
) -> InstalledArenaDomainReply {
  domain_unit_reply(PrepareDomainRead, domain, host.prepare_domain_read(domain))
}

///|
pub fn current_installed_arena_domain_read_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
) -> InstalledArenaDomainReply {
  domain_unit_reply(
    ObserveDomainRead,
    domain,
    host.require_domain_read_current(domain),
  )
}

///|
pub fn enter_installed_arena_domain_read_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
) -> InstalledArenaDomainReply {
  domain_unit_reply(EnterDomainRead, domain, host.enter_domain_read(domain))
}

///|
pub fn leave_installed_arena_domain_read_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
) -> InstalledArenaDomainReply {
  domain_unit_reply(LeaveDomainRead, domain, host.leave_domain_read(domain))
}

///|
pub fn cleanup_installed_arena_domain_read_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
) -> InstalledArenaDomainReply {
  domain_unit_reply(
    EnterDomainReadCleanup,
    domain,
    host.enter_domain_read_cleanup(domain),
  )
}

///|
pub fn close_installed_arena_domain_read_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
) -> InstalledArenaDomainReply {
  domain_unit_reply(CloseDomainRead, domain, host.close_domain_read(domain))
}
