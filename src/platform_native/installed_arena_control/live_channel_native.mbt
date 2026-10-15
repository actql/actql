///|
/// Trusted installed physical caller after original funding/provisioning and
/// spawn. PID/FD DATA never replaces this original Host/domain/ticket. The same
/// domain retains partial capture before any reply can leave the component.
pub fn InstalledArenaHost::prepare_live_channel(
  self : InstalledArenaHost,
  record : InstalledArenaDomain,
  child_pid : Int,
  read_fd : Int,
  write_fd : Int,
  nonce : Int64,
) -> Result[
  @bootstrap.NativeBackedLiveChannelAcquisition[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
  @bootstrap.NativeBackedExecutionIssue,
] {
  match self.require_domain_current(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let result = record.backing.prepare_backed_live_channel(
    self,
    record.domain.unwrap(),
    record,
    child_pid,
    read_fd,
    write_fd,
    nonce,
  )
  match result {
    Ok(@bootstrap.PreparedLiveChannel(channel)) =>
      record.live_channel = Some(channel)
    Ok(@bootstrap.PendingLiveChannel(channel, _)) =>
      record.live_channel = Some(channel)
    Err(_) => ()
  }
  result
}

///|
/// Original references only. Closing preserves cleanup/report, not new work.
fn InstalledArenaHost::original_live_channel(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  match self.original_read_domain(domain) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if domain.live_channel is Some(selected) && physical_equal(selected, channel) {
    Ok(())
  } else {
    Err(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))
  }
}

///|
pub fn InstalledArenaHost::bind_live_channel_vm(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
  nonce : Int64,
  offset : Int64,
  bytes : Int64,
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  match self.original_live_channel(domain, channel) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  domain.backing.bind_backed_live_channel_vm(
    self, channel, nonce, offset, bytes,
  )
}

///|
pub fn InstalledArenaHost::admit_live_channel(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  match self.original_live_channel(domain, channel) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  domain.backing.admit_backed_live_channel(self, channel)
}

///|
pub fn InstalledArenaHost::live_channel_state(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
) -> Result[
  @resources.BackedExecutionLiveState,
  @bootstrap.NativeBackedExecutionIssue,
] {
  match self.original_live_channel(domain, channel) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  domain.backing.backed_live_channel_state(self, channel)
}

///|
pub fn InstalledArenaHost::live_channel_limits(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
) -> Result[@resources.LedgerLimits, @bootstrap.NativeBackedExecutionIssue] {
  match self.original_live_channel(domain, channel) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  domain.backing.backed_live_channel_limits(self, channel)
}

///|
pub fn InstalledArenaHost::report_live_channel(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
  usage : @resources.LedgerUsage,
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  match self.original_live_channel(domain, channel) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  domain.backing.report_backed_live_channel(self, channel, usage)
}

///|
pub fn InstalledArenaHost::stop_live_channel(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  match self.original_live_channel(domain, channel) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  domain.backing.stop_backed_live_channel(self, channel)
}

///|
/// Existing physical caller's separate original ACKs, never EOF/PID inference.
/// This drops only channel references; domain/loan/FD responsibility remains.
pub fn InstalledArenaHost::retire_live_channel_after_owner_ack(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  match self.original_live_channel(domain, channel) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    domain.backing.retire_backed_live_channel_after_owner_ack(self, channel) {
    Err(issue) => Err(issue)
    Ok(_) => {
      domain.live_channel = None
      Ok(())
    }
  }
}
