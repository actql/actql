///|
/// Select this actual installed domain's fresh initialization purpose. The
/// caller retains BOTH Ready and Pending live-child acquisitions before its
/// next fallible call. No existing Read/retained-execution record is converted.
pub fn[I] InstalledArenaHost::prepare_domain_initialization_child(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  input : I,
) -> Result[
  @bootstrap.NativeBackedLiveChildAcquisition[
    InstalledArenaHost,
    InstalledArenaDomain,
    I,
  ],
  @bootstrap.NativeBackedExecutionIssue,
] {
  match self.require_domain_read_current(domain) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if domain.crypto_component is Some(_) ||
    domain.sqlite_library is Some(_) ||
    domain.live_channel is Some(_) ||
    domain.original_read is Some(_) ||
    domain.retained_execution is Some(_) {
    return Err(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed))
  }
  let original = match self.original_read_domain(domain) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  domain.backing.prepare_backed_initialization_live_child(
    self, original, domain, input,
  )
}

///|
/// The exact installed Host and original retained child, not a caller's
/// reconstructed domain/input pair. Native assembly retains its own census
/// and frame; the shared Host receives only the input-bound admission.
pub fn[I] InstalledArenaHost::initialize_preparation(
  self : InstalledArenaHost,
  live : @bootstrap.NativeBackedLiveChild[
    InstalledArenaHost,
    InstalledArenaDomain,
    I,
  ],
  input : I,
  budget : @bootstrap.NativeBackedInitializationBudget,
) -> Result[
  @resources.BackedInitializationAdmission[I],
  @bootstrap.NativeBackedInitializationIssue,
] {
  let backing = match self.original_backing() {
    Err(issue) => return Err(@bootstrap.Domain(@bootstrap.Bootstrap(issue)))
    Ok(value) => value
  }
  backing.initialize_backed_preparation(self, live, input, budget)
}

///|
/// Cleanup uses the retained original backing even after ordinary current
/// work is closing. Native still requires its actual physical ACK, complete
/// census retirement and original usage report; no caller supplies those.
pub fn[I] InstalledArenaHost::close_preparation(
  self : InstalledArenaHost,
  live : @bootstrap.NativeBackedLiveChild[
    InstalledArenaHost,
    InstalledArenaDomain,
    I,
  ],
) -> Result[Unit, @bootstrap.NativeBackedInitializationIssue] {
  guard self.backing is Some(backing) else {
    return Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  backing.close_backed_preparation(self, live)
}
