///|
struct InstalledArenaChannelLedgerReply {
  host : InstalledArenaHost
  domain : InstalledArenaDomain
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ]
  frame : @resources.ImportedChildLedger?
  operation : Int
  issue : @bootstrap.NativeBackedOriginalReadIssue?
  limits : @resources.LedgerLimits?
}

///|
fn original_channel_ledger_frame(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
) -> Result[
  @resources.ImportedChildLedger?,
  @bootstrap.NativeBackedOriginalReadIssue,
] {
  match host.original_live_channel(domain, channel) {
    Err(issue) => return Err(@bootstrap.Domain(issue))
    Ok(_) => ()
  }
  domain.backing.original_backed_channel_ledger_frame(host, channel)
}

///|
pub fn prepare_installed_arena_channel_ledger_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
) -> InstalledArenaChannelLedgerReply {
  let result = host.prepare_live_channel_original_ledger(domain, channel)
  let (frame, issue) = match result {
    Ok(frame) => (Some(frame), None)
    Err(issue) =>
      (
        original_channel_ledger_frame(host, domain, channel).unwrap_or(None),
        Some(issue),
      )
  }
  {
    host: domain.host,
    domain,
    channel,
    frame,
    operation: 1,
    issue,
    limits: None,
  }
}

///|
pub fn operate_installed_arena_channel_ledger_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
  frame : @resources.ImportedChildLedger,
  operation : Int,
  retained : Int64,
  execution : Int64,
) -> InstalledArenaChannelLedgerReply {
  let mut limits = None
  let result : Result[Unit, @bootstrap.NativeBackedOriginalReadIssue] = if operation !=
    3 &&
    (retained != 0L || execution != 0L) {
    Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  } else {
    match original_channel_ledger_frame(host, domain, channel) {
      Err(issue) => Err(issue)
      Ok(Some(original)) if physical_equal(original, frame) => {
        let backing = domain.backing
        match operation {
          2 => backing.start_backed_channel_ledger(host, channel, frame)
          3 =>
            backing.reserve_backed_channel_bootstrap(
              host, channel, frame, retained, execution,
            )
          4 =>
            backing.require_backed_channel_ledger_current(host, channel, frame)
          5 =>
            match backing.backed_channel_ledger_limits(host, channel, frame) {
              Ok(value) => {
                limits = Some(value)
                Ok(())
              }
              Err(issue) => Err(issue)
            }
          6 => backing.report_backed_channel_ledger(host, channel, frame)
          7 => backing.stop_backed_channel_ledger(host, channel, frame)
          9 =>
            backing.require_backed_channel_bootstrap_current(
              host, channel, frame,
            )
          10 => backing.stop_backed_live_channel_transport_use(host, channel)
          8 =>
            backing.retire_backed_channel_bootstrap_after_owner_ack(
              host, channel, frame,
            )
          _ =>
            Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
        }
      }
      Ok(_) =>
        Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)))
    }
  }
  {
    host: domain.host,
    domain,
    channel,
    frame: Some(frame),
    operation,
    issue: match result {
      Ok(_) => None
      Err(issue) => Some(issue)
    },
    limits,
  }
}

///|
pub fn InstalledArenaChannelLedgerReply::original_host(
  self : InstalledArenaChannelLedgerReply,
) -> InstalledArenaHost {
  self.host
}

///|
pub fn InstalledArenaChannelLedgerReply::original_domain(
  self : InstalledArenaChannelLedgerReply,
) -> InstalledArenaDomain {
  self.domain
}

///|
pub fn InstalledArenaChannelLedgerReply::original_channel(
  self : InstalledArenaChannelLedgerReply,
) -> @bootstrap.NativeBackedLiveChannel[
  InstalledArenaHost,
  InstalledArenaDomain,
] {
  self.channel
}

///|
pub fn InstalledArenaChannelLedgerReply::original_frame(
  self : InstalledArenaChannelLedgerReply,
) -> @resources.ImportedChildLedger? {
  self.frame
}

///|
pub fn InstalledArenaChannelLedgerReply::operation_tag(
  self : InstalledArenaChannelLedgerReply,
) -> Int {
  self.operation
}

///|
pub fn InstalledArenaChannelLedgerReply::issue_family(
  self : InstalledArenaChannelLedgerReply,
) -> Int {
  match self.issue {
    None => 0
    Some(@bootstrap.Domain(@bootstrap.Accounting(_))) => 8
    Some(@bootstrap.Domain(@bootstrap.Bootstrap(issue))) =>
      installed_arena_issue_family(Some(issue))
    Some(@bootstrap.Child(@resources.Unknown)) => 10
    Some(@bootstrap.Child(_)) => 9
  }
}

///|
pub fn InstalledArenaChannelLedgerReply::limit(
  self : InstalledArenaChannelLedgerReply,
  ordinal : Int,
) -> Int64 {
  guard self.limits is Some(limits) else { return -1L }
  match ordinal {
    0 => limits.planning_work.to_int64()
    1 => limits.attempts.to_int64()
    2 => limits.holdings.to_int64()
    3 => limits.transfer_bytes
    4 => limits.retained_bytes
    5 => limits.execution_bytes
    _ => -1L
  }
}

///|
pub fn InstalledArenaChannelLedgerReply::issue_description(
  self : InstalledArenaChannelLedgerReply,
) -> String {
  match self.issue {
    None => ""
    Some(@bootstrap.Domain(issue)) => "Domain(" + @debug.to_string(issue) + ")"
    Some(@bootstrap.Child(issue)) => "Child(" + @debug.to_string(issue) + ")"
  }
}
