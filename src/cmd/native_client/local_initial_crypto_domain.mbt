///|
// Trusted installed selection only. These finite declarations are fixed by the
// compiled installer before acquisition; no Program/SDK wire constructs them.
// They issue no capacity, permission or replacement initialization by themselves.
priv struct InitialCryptoProfile {
  source : String
  recipe : Bytes
  arena_bytes : Int64
  domain_bytes : Int64
  heap_bytes : Int64
  control_bytes : Int64
  host_limits : @initial_resources.LedgerLimits
  domain_limits : @initial_resources.LedgerLimits
  diagnostic_ceiling : Int
}

///|
priv enum InitialCryptoIssue {
  InvalidProfile
  BackingUnavailable(Int)
  Host(@initial_bootstrap.NativeBootstrapIssue)
  Domain(@initial_bootstrap.NativeBackedExecutionIssue)
  Component(@initial_arena.InstalledArenaCryptoIssue)
  Signature(@local_crypto.NativeSignatureIssue)
  Unavailable
}

///|
// The same private installer carrier retains every partial stage. It does not
// replace the existing Host/domain/component Owners or any of their ACKs.
priv struct InitialCryptoOriginal {
  package_original : @local_host.NativeLocalPackagedRuntime
  profile : InitialCryptoProfile
  backing : InitialCryptoBacking
  mut host : @initial_arena.InstalledArenaHost?
  mut backing_scope : @initial_arena.InstalledArenaBackingBorrow?
  mut backing_entered : Bool
  mut domain : @initial_arena.InstalledArenaDomain?
  mut component : @initial_arena.InstalledArenaCryptoComponent?
  mut outer_library : @local_crypto.Library?
  mut inner_library : @local_crypto.Library?
  mut scope_open : Bool
  mut primary : InitialCryptoIssue?
  mut closing : Bool
  mut closed : Bool
}

///|
fn InitialCryptoOriginal::retain_primary(
  self : InitialCryptoOriginal,
  issue : InitialCryptoIssue,
) -> Unit {
  if self.primary is None {
    self.primary = Some(issue)
  }
}

///|
// Return the original after physical open, including any failure. In particular
// failed initial stat custody is never converted into an empty failure value.
fn prepare_initial_crypto_original(
  package_original : @local_host.NativeLocalPackagedRuntime,
  profile : InitialCryptoProfile,
) -> Result[InitialCryptoOriginal, InitialCryptoIssue] {
  if profile.source.length() != 40 ||
    profile.recipe.length() != 32 ||
    profile.arena_bytes <= 0L ||
    profile.domain_bytes <= 0L ||
    profile.domain_bytes > profile.arena_bytes ||
    profile.heap_bytes <= 0L ||
    profile.heap_bytes > profile.domain_bytes ||
    profile.control_bytes <= 0L ||
    profile.diagnostic_ceiling <= 0 ||
    profile.diagnostic_ceiling > 4096 ||
    profile.host_limits.execution_bytes != profile.arena_bytes ||
    profile.domain_limits.execution_bytes > profile.domain_bytes ||
    package_original.check_current() is Err(_) {
    return Err(InvalidProfile)
  }
  let original : InitialCryptoOriginal = {
    package_original,
    profile,
    backing: initial_crypto_backing_open(profile.arena_bytes),
    host: None,
    backing_scope: None,
    backing_entered: false,
    domain: None,
    component: None,
    outer_library: None,
    inner_library: None,
    scope_open: false,
    primary: None,
    closing: false,
    closed: false,
  }
  match original.acquire() {
    Ok(_) => ()
    Err(issue) => original.retain_primary(issue)
  }
  Ok(original)
}

///|
fn InitialCryptoOriginal::acquire(
  self : InitialCryptoOriginal,
) -> Result[Unit, InitialCryptoIssue] {
  if !self.backing.current() {
    return Err(BackingUnavailable(self.backing.acquisition_issue()))
  }
  let profile = self.profile
  let host = match
    @initial_arena.prepare_installed_arena_host(
      profile.source,
      profile.recipe,
      1L,
      profile.arena_bytes,
      profile.host_limits,
      profile.control_bytes,
    ).map_err(issue => Host(issue)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.host = Some(host)
  match
    host.acquire_fd(self.backing.descriptor()).map_err(issue => Host(issue)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let scope = match host.borrow_backing().map_err(issue => Host(issue)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.backing_scope = Some(scope)
  match host.enter_backing_borrow_scope(scope).map_err(issue => Host(issue)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.backing_entered = true
  let domain = match
    (match
      host
      .prepare_domain(
        scope,
        self.backing.descriptor(),
        profile.domain_bytes,
        profile.domain_limits,
      )
      .map_err(issue => Domain(issue)) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }) {
    PreparedDomain(domain) => domain
    PendingDomain(domain, issue) => {
      self.domain = Some(domain)
      return Err(Domain(issue))
    }
  }
  self.domain = Some(domain)
  match host.transfer_domain(domain).map_err(issue => Domain(issue)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match host.leave_backing_borrow_scope(scope).map_err(issue => Host(issue)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.backing_entered = false
  match host.return_backing_borrow(scope).map_err(issue => Host(issue)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.backing_scope = None
  match host.prepare_domain_read(domain).map_err(issue => Domain(issue)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (_, path) = match
    self.package_original.library_paths().map_err(_ => Unavailable) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    (match
      host
      .prepare_crypto_component(
        domain,
        path,
        profile.heap_bytes,
        profile.diagnostic_ceiling,
      )
      .map_err(issue => Component(issue)) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }) {
    ReadyCrypto(component) => self.component = Some(component)
    PendingCrypto(component, issue) => {
      self.component = Some(component)
      return Err(Component(issue))
    }
  }
  self.require_current()
}

///|
fn InitialCryptoOriginal::require_current(
  self : InitialCryptoOriginal,
) -> Result[Unit, InitialCryptoIssue] {
  if self.closing ||
    self.closed ||
    self.primary is Some(_) ||
    !self.backing.current() ||
    self.package_original.check_current() is Err(_) {
    return Err(Unavailable)
  }
  guard self.host is Some(host) &&
    self.domain is Some(domain) &&
    self.component is Some(component) else {
    return Err(Unavailable)
  }
  match
    host.require_domain_read_current(domain).map_err(issue => Domain(issue)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  (match
    host.current_crypto_component(component).map_err(issue => Component(issue)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  })
  |> ignore
  Ok(())
}

///|
// The caller brackets only its selected finite initial phase. This is not a
// business-Run capacity entry or permission to allocate in another domain.
fn InitialCryptoOriginal::enter(
  self : InitialCryptoOriginal,
) -> Result[Unit, InitialCryptoIssue] {
  match self.require_current() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if self.scope_open {
    return Err(Unavailable)
  }
  match
    self.host
    .unwrap()
    .enter_domain_read(self.domain.unwrap())
    .map_err(issue => Domain(issue)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.scope_open = true
  Ok(())
}

///|
fn InitialCryptoOriginal::leave(
  self : InitialCryptoOriginal,
) -> Result[Unit, InitialCryptoIssue] {
  if !self.scope_open {
    return Ok(())
  }
  match
    self.host
    .unwrap()
    .leave_domain_read(self.domain.unwrap())
    .map_err(issue => Domain(issue)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.scope_open = false
  Ok(())
}

///|
fn InitialCryptoOriginal::library(
  self : InitialCryptoOriginal,
  inner : Bool,
) -> Result[@local_crypto.Library, InitialCryptoIssue] {
  match self.require_current() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !self.scope_open {
    return Err(Unavailable)
  }
  let retained = if inner { self.inner_library } else { self.outer_library }
  if retained is Some(library) {
    return Ok(library)
  }
  let component = match
    self.host
    .unwrap()
    .current_crypto_component(self.component.unwrap())
    .map_err(issue => Component(issue)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let acquired = match
    component.new_library().map_err(issue => Signature(issue)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (library, issue) = match acquired {
    ReadyCryptoLibrary(library) => (library, None)
    PendingCryptoLibrary(library, issue) => (library, Some(Signature(issue)))
  }
  if inner {
    self.inner_library = Some(library)
  } else {
    self.outer_library = Some(library)
  }
  match issue {
    None => Ok(library)
    Some(issue) => {
      self.retain_primary(issue)
      Err(issue)
    }
  }
}

///|
// Only after the selected managed phase and Writer/session have actually
// stopped. Each Library, component, context/domain/map, Host and FD ACK remains
// separate. Pending aliases and Unknown retain this same carrier for cleanup.
fn InitialCryptoOriginal::close_checked(
  self : InitialCryptoOriginal,
) -> Result[Unit, InitialCryptoIssue] {
  if self.closed {
    return Ok(())
  }
  self.closing = true
  match self.leave() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if self.host is Some(host) && self.domain is Some(domain) {
    if self.inner_library is Some(_) || self.outer_library is Some(_) {
      match
        host.enter_domain_read_cleanup(domain).map_err(issue => Domain(issue)) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.scope_open = true
      if self.inner_library is Some(library) {
        match library.close_checked() {
          Ok(_) => self.inner_library = None
          Err(issue) => return Err(Signature(issue))
        }
      }
      if self.outer_library is Some(library) {
        match library.close_checked() {
          Ok(_) => self.outer_library = None
          Err(issue) => return Err(Signature(issue))
        }
      }
      match self.leave() {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    }
    if self.component is Some(component) {
      match
        host
        .close_crypto_component(component)
        .map_err(issue => Component(issue)) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.component = None
    }
    match
      host.close_domain_after_owner_ack(domain).map_err(issue => Domain(issue)) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    self.domain = None
  }
  if self.host is Some(host) {
    if self.backing_scope is Some(scope) {
      if self.backing_entered {
        match
          host.leave_backing_borrow_scope(scope).map_err(issue => Host(issue)) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        self.backing_entered = false
      }
      match host.return_backing_borrow(scope).map_err(issue => Host(issue)) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.backing_scope = None
    }
    match host.try_close().map_err(issue => Host(issue)) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    self.host = None
  }
  if !self.backing.close_checked() {
    return Err(BackingUnavailable(self.backing.acquisition_issue()))
  }
  self.closed = true
  Ok(())
}
