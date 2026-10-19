///|
pub(all) enum InstalledArenaCryptoIssue {
  Domain(@bootstrap.NativeBackedExecutionIssue)
  Signature(@signature.NativeSignatureIssue)
}

///|
/// Registered before the foreign component load. The original component and
/// partial initialization remain separate from every outer/inner Library borrow.
struct InstalledArenaCryptoComponent {
  domain : InstalledArenaDomain
  mut component : @signature.OriginalCryptoComponent?
  mut attempted : Bool
  mut failed : Bool
  mut scope_open : Bool
  mut closed : Bool
}

///|
pub(all) enum InstalledArenaCryptoAcquisition {
  ReadyCrypto(InstalledArenaCryptoComponent)
  PendingCrypto(InstalledArenaCryptoComponent, InstalledArenaCryptoIssue)
}

///|
fn InstalledArenaHost::original_crypto_component(
  self : InstalledArenaHost,
  record : InstalledArenaCryptoComponent,
) -> Result[Unit, InstalledArenaCryptoIssue] {
  if !physical_equal(record.domain.host, self) ||
    !self.domains.any(domain => physical_equal(domain, record.domain)) ||
    !(record.domain.crypto_component is Some(original) &&
    physical_equal(original, record)) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)))
  }
  Ok(())
}

///|
fn register_crypto_component_original(
  domain : InstalledArenaDomain,
) -> InstalledArenaCryptoComponent {
  let record : InstalledArenaCryptoComponent = {
    domain,
    component: None,
    attempted: false,
    failed: false,
    scope_open: false,
    closed: false,
  }
  domain.crypto_component = Some(record)
  record
}

///|
// The caller owns its already entered original scope and eventual leave.
// Publish partial component custody before returning a foreign-call failure.
fn InstalledArenaHost::load_crypto_component_original(
  self : InstalledArenaHost,
  record : InstalledArenaCryptoComponent,
  path : String,
  heap_bytes : Int64,
  diagnostic_ceiling : Int,
  command_member? : @filesystem.NativeObservedComponentMember? = None,
) -> InstalledArenaCryptoIssue? {
  record.attempted = true
  let mut primary : InstalledArenaCryptoIssue? = None
  match
    @signature.load_current_crypto_component(
      path,
      heap_bytes,
      diagnostic_ceiling,
      command_member~,
    ) {
    Err(issue) => primary = Some(Signature(issue))
    Ok(@signature.ReadyCryptoComponent(component)) =>
      record.component = Some(component)
    Ok(@signature.PendingCryptoComponent(component, issue)) => {
      record.component = Some(component)
      primary = Some(Signature(issue))
    }
  }
  match self.require_domain_read_current(record.domain) {
    Err(issue) => if primary is None { primary = Some(Domain(issue)) }
    Ok(_) => ()
  }
  primary
}

///|
/// Trusted installed caller verifies the selected component/cohort first. This
/// binds its actual first initialization to the already admitted original domain;
/// declarations, paths and a current context do not issue funding or permission.
pub fn InstalledArenaHost::prepare_crypto_component(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  path : String,
  heap_bytes : Int64,
  diagnostic_ceiling : Int,
) -> Result[InstalledArenaCryptoAcquisition, InstalledArenaCryptoIssue] {
  match self.require_domain_read_current(domain) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  if domain.crypto_component is Some(_) ||
    domain.sqlite_library is Some(_) ||
    domain.original_read is Some(_) ||
    domain.live_channel is Some(_) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed)))
  }
  let record = register_crypto_component_original(domain)
  let mut primary : InstalledArenaCryptoIssue? = None
  match self.enter_domain_read(domain) {
    Err(issue) => primary = Some(Domain(issue))
    Ok(_) => {
      record.scope_open = true
      primary = self.load_crypto_component_original(
        record, path, heap_bytes, diagnostic_ceiling,
      )
      match self.leave_domain_read(domain) {
        Err(issue) => if primary is None { primary = Some(Domain(issue)) }
        Ok(_) => record.scope_open = false
      }
    }
  }
  record.failed = primary is Some(_)
  match primary {
    Some(issue) => Ok(PendingCrypto(record, issue))
    None => Ok(ReadyCrypto(record))
  }
}

///|
/// The caller surrounds its entire managed Library/Writer phase with the same
/// original domain Read scope. Each physical Signature operation rechecks that
/// context and constructor thread; this projection cannot bypass either fence.
pub fn InstalledArenaHost::current_crypto_component(
  self : InstalledArenaHost,
  record : InstalledArenaCryptoComponent,
) -> Result[@signature.OriginalCryptoComponent, InstalledArenaCryptoIssue] {
  match self.original_crypto_component(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.require_domain_read_current(record.domain) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  if record.closed || record.failed || record.scope_open {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  match record.component {
    Some(component) => Ok(component)
    None => Err(Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
}

///|
/// Separate Library/hasher ACKs precede component cleanup. Retain a failed
/// component or failed scope leave on this same receiver. Component/module ACK
/// does not close its Read context, domain, Host, descriptor or parent loan.
pub fn InstalledArenaHost::close_crypto_component(
  self : InstalledArenaHost,
  record : InstalledArenaCryptoComponent,
) -> Result[Unit, InstalledArenaCryptoIssue] {
  match self.original_crypto_component(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.closed {
    return Ok(())
  }
  record.failed = true
  if record.scope_open {
    match self.leave_domain_read(record.domain) {
      Err(issue) => return Err(Domain(issue))
      Ok(_) => record.scope_open = false
    }
  }
  guard record.component is Some(component) else {
    record.closed = true
    return Ok(())
  }
  match self.enter_domain_read_cleanup(record.domain) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => record.scope_open = true
  }
  let cleanup = component.close_checked()
  if cleanup is Ok(_) {
    record.component = None
  }
  let leave = self.leave_domain_read(record.domain)
  if leave is Ok(_) {
    record.scope_open = false
  }
  match cleanup {
    Err(issue) => return Err(Signature(issue))
    Ok(_) => ()
  }
  match leave {
    Err(issue) => Err(Domain(issue))
    Ok(_) => {
      record.closed = true
      Ok(())
    }
  }
}
