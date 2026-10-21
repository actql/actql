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
  Filesystem(@local_filesystem.NativeFilesystemIssue)
  Unavailable
}

///|
// The same private installer carrier retains every partial stage. It does not
// replace the existing Host/domain/component Owners or any of their ACKs.
priv struct InitialCryptoOriginal {
  package_original : @local_host.NativeLocalPackagedRuntime
  profile : InitialCryptoProfile
  mut host : @initial_arena.InstalledArenaHost?
  mut backing_scope : @initial_arena.InstalledArenaBackingBorrow?
  mut backing_entered : Bool
  mut domain : @initial_arena.InstalledArenaDomain?
  mut component : @initial_arena.InstalledArenaCryptoComponent?
  mut outer_library : @local_crypto.Library?
  mut inner_library : @local_crypto.Library?
  mut read_failure : @files.NativeBoundedTextFailure?
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
// Return the same original after its one physical attempt, including partial
// acquisition. The actual Host retains mapping and reservation cleanup duties.
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
    host: None,
    backing_scope: None,
    backing_entered: false,
    domain: None,
    component: None,
    outer_library: None,
    inner_library: None,
    read_failure: None,
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
  if self.host is Some(_) ||
    self.closing ||
    self.closed ||
    self.primary is Some(_) {
    return Err(Unavailable)
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
  match host.acquire().map_err(issue => Host(issue)) {
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
      .prepare_domain_in_process(
        scope,
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
  }
  if self.host is Some(host) && self.domain is Some(domain) {
    if self.read_failure is Some(_) ||
      self.inner_library is Some(_) ||
      self.outer_library is Some(_) {
      match
        host.enter_domain_read_cleanup(domain).map_err(issue => Domain(issue)) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.scope_open = true
      if self.read_failure is Some(failure) {
        match failure.retry_cleanup() {
          Ok(_) => self.read_failure = None
          Err(issue) => return Err(Filesystem(issue))
        }
      }
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
    match host.try_close().map_err(issue => Host(issue)) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    self.host = None
  }
  self.closed = true
  Ok(())
}

///|
let initial_crypto_invocation : Ref[InitialCryptoOriginal?] = Ref(None)

///|
fn initial_crypto_hex_recipe(value : String) -> Bytes raise ClientStop {
  let encoded = @utf8.encode(value)
  if encoded.length() != 64 {
    stop("InitialCryptoProfileUnavailable")
  }
  let digit = fn(byte : Byte) -> Int raise ClientStop {
    let value = byte.to_int()
    if value >= 48 && value <= 57 {
      value - 48
    } else if value >= 97 && value <= 102 {
      value - 87
    } else {
      stop("InitialCryptoProfileUnavailable")
    }
  }
  Bytes::makei(32, index => {
    (digit(encoded[index * 2]) * 16 + digit(encoded[index * 2 + 1])).to_byte()
  })
}

///|
// Private first-consumer declaration, selected before physical acquisition.
// The component digest and executable Source bind this finite recipe. No
// initial-control credit is transferred to a business Run or another allocator.
fn local_initial_crypto_profile(
  runtime : LocalPackagedRuntime,
) -> InitialCryptoProfile raise ClientStop {
  let wire = @run_host.client_native_local_runtime_original(runtime.manifest)
  let fields = @decode.open_object(local_input_cursor(wire)).unwrap_or_else(() => {
    stop("InitialCryptoProfileUnavailable")
  })
  let source = @decode.lookup(fields, "sourceSha")
    .bind(value => @decode.text(value).to_option())
    .unwrap_or_else(() => stop("InitialCryptoProfileUnavailable"))
  let members = @run_host.client_native_local_runtime_members(runtime.manifest).filter(value => {
      value.role == "crypto"
    },
  )
  if members.length() != 1 {
    stop("InitialCryptoProfileUnavailable")
  }
  {
    source,
    recipe: initial_crypto_hex_recipe(members[0].sha256),
    arena_bytes: 16777216L,
    domain_bytes: 15728640L,
    heap_bytes: 2097152L,
    control_bytes: 262144L,
    host_limits: {
      planning_work: 64,
      // One original capacity + one provisioning + the child maximum.
      attempts: 1 + 1 + 8,
      holdings: 8,
      transfer_bytes: 1048576L,
      retained_bytes: 0L,
      execution_bytes: 16777216L,
    },
    domain_limits: {
      planning_work: 32,
      attempts: 8,
      holdings: 8,
      transfer_bytes: 1048576L,
      retained_bytes: 4194304L,
      execution_bytes: 11534336L,
    },
    diagnostic_ceiling: 4096,
  }
}

///|
// Report the retained typed primary only. No original key, policy, path or
// physical carrier is reconstructed from a diagnostic value.
fn initial_crypto_issue_message(issue : InitialCryptoIssue) -> String {
  match issue {
    InvalidProfile => "InvalidProfile"
    BackingUnavailable(code) => "Backing(" + code.to_string() + ")"
    Host(issue) => "Host(" + @debug.to_string(issue) + ")"
    Domain(issue) => "Domain(" + @debug.to_string(issue) + ")"
    Component(@initial_arena.Domain(issue)) =>
      "ComponentDomain(" + @debug.to_string(issue) + ")"
    Component(@initial_arena.Signature(issue)) =>
      "ComponentSignature(" + @debug.to_string(issue) + ")"
    Signature(issue) => "Signature(" + @debug.to_string(issue) + ")"
    Filesystem(_) => "Filesystem"
    Unavailable => "Unavailable"
  }
}

///|
fn local_begin_initial_crypto(
  runtime : LocalPackagedRuntime,
) -> InitialCryptoOriginal raise ClientStop {
  if initial_crypto_invocation.val is Some(_) {
    // A prior partial/Unknown attempt is not a fresh acquisition opportunity.
    stop("InitialCryptoAlreadySelected")
  }
  let original = prepare_initial_crypto_original(
    runtime.physical,
    local_initial_crypto_profile(runtime),
  ).unwrap_or_else(() => stop("InitialCryptoProfileUnavailable"))
  initial_crypto_invocation.val = Some(original)
  if original.primary is Some(issue) {
    stop(
      "InitialCryptoAcquisitionUnavailable: " +
      initial_crypto_issue_message(issue),
    )
  }
  original.enter().unwrap_or_else(() => stop("InitialCryptoScopeUnavailable"))
  original
}

///|
fn local_finish_initial_crypto() -> Bool {
  match initial_crypto_invocation.val {
    None => true
    Some(original) =>
      match original.close_checked() {
        Err(_) => false
        Ok(_) => {
          initial_crypto_invocation.val = None
          true
        }
      }
  }
}

///|
// The existing Reader algorithm owns byte/generation/UTF8 and physical close.
// Only this selected initial scope chooses its existing current-context port.
fn local_initial_crypto_text_file(
  original : InitialCryptoOriginal,
  root : String,
  name : String,
  maximum : Int64,
) -> String raise ClientStop {
  if !original.scope_open || original.require_current() is Err(_) {
    stop("InitialCryptoReadUnavailable")
  }
  match
    @files.read_bounded_text_file_in_current_read_context_with_custody(
      root,
      name,
      maximum,
      original.profile.diagnostic_ceiling,
    ) {
    Ok(text) => text
    Err(failure) => {
      // Retain the exact failed Reader/Root, not just its DATA issue. The first
      // error terminates this phase, so no second read replaces the receiver.
      original.read_failure = Some(failure)
      original.retain_primary(Unavailable)
      stop("failed to read bounded file " + name)
    }
  }
}
