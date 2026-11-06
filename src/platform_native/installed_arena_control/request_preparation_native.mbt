///|
/// Select the actual domain's fresh Request purpose. The caller retains both
/// Ready and Pending acquisitions; no existing Read or Run is repurposed.
pub fn[I] InstalledArenaHost::prepare_domain_request_child(
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
  domain.backing.prepare_backed_request_live_child(
    self, original, domain, input,
  )
}

///|
/// Retain the original Native frame before Common's one-shot Request start.
/// No initialization inventory or new budget is inserted into that child.
pub fn[I] InstalledArenaHost::prepare_request_admission(
  self : InstalledArenaHost,
  live : @bootstrap.NativeBackedLiveChild[
    InstalledArenaHost,
    InstalledArenaDomain,
    I,
  ],
  input : I,
) -> Result[
  @resources.BackedPreparationAdmission[I],
  @bootstrap.NativeBackedRequestPreparationIssue,
] {
  let backing = match self.original_backing() {
    Err(issue) => return Err(@bootstrap.Domain(@bootstrap.Bootstrap(issue)))
    Ok(value) => value
  }
  backing.prepare_backed_request_admission(self, live, input)
}

///|
/// Cleanup still uses the retained original after Request transfers its
/// admission to Run. Common owns logical unwind; Native owns physical ACK.
pub fn[I] InstalledArenaHost::close_request_preparation(
  self : InstalledArenaHost,
  live : @bootstrap.NativeBackedLiveChild[
    InstalledArenaHost,
    InstalledArenaDomain,
    I,
  ],
) -> Result[Unit, @bootstrap.NativeBackedRequestPreparationIssue] {
  guard self.backing is Some(backing) else {
    return Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  backing.close_backed_request_preparation(self, live)
}

///|
/// The existing Request issuer's entered original frame, including after Run
/// transfer. It creates no observer record, new child, Ledger or cleanup owner.
pub fn[I] InstalledArenaHost::borrow_request_read_frame(
  self : InstalledArenaHost,
  live : @bootstrap.NativeBackedLiveChild[
    InstalledArenaHost,
    InstalledArenaDomain,
    I,
  ],
  input : I,
) -> Result[
  @resources.ImportedChildLedger,
  @bootstrap.NativeBackedRequestPreparationIssue,
] {
  let backing = match self.original_backing() {
    Err(issue) => return Err(@bootstrap.Domain(@bootstrap.Bootstrap(issue)))
    Ok(value) => value
  }
  backing.borrow_backed_request_read_frame(self, live, input)
}

///|
/// Identity-only cleanup observation remains available after ordinary stop.
/// It does not acknowledge any Reader, allocation, frame or domain retirement.
pub fn[I] InstalledArenaHost::observe_request_read_cleanup_scope(
  self : InstalledArenaHost,
  live : @bootstrap.NativeBackedLiveChild[
    InstalledArenaHost,
    InstalledArenaDomain,
    I,
  ],
  input : I,
) -> Result[
  @bootstrap.NativeBackedReadScope,
  @bootstrap.NativeBackedRequestPreparationIssue,
] {
  guard self.backing is Some(backing) else {
    return Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  backing.observe_backed_request_read_cleanup_scope(self, live, input)
}
