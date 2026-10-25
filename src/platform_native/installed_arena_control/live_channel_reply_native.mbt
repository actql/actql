///|
priv enum LiveChannelOperation {
  PrepareLive
  BindVM
  AdmitLive
  ObserveLive
  LimitsLive
  ReportLive
  StopLive
  RetireLive
  CapacitiesLive
  PrepareBeforeSpawn
  BindChild
  InvalidLiveOperation
}

///|
/// Immutable private operation observation. Success never means FD/Store/Run
/// completion or whole funding. The original handles outlive failed replies.
struct InstalledArenaLiveChannelReply {
  host : InstalledArenaHost
  domain : InstalledArenaDomain
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ]?
  operation : LiveChannelOperation
  issue : @bootstrap.NativeBackedExecutionIssue?
  state : @resources.BackedExecutionLiveState?
  limits : @resources.LedgerLimits?
  capacities : (Int64, Int64)?
}

///|
fn live_channel_unit_reply(
  operation : LiveChannelOperation,
  domain : InstalledArenaDomain,
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
  result : Result[Unit, @bootstrap.NativeBackedExecutionIssue],
) -> InstalledArenaLiveChannelReply {
  {
    host: domain.host,
    domain,
    channel: Some(channel),
    operation,
    state: None,
    limits: None,
    capacities: None,
    issue: match result {
      Ok(_) => None
      Err(issue) => Some(issue)
    },
  }
}

///|
pub fn prepare_installed_arena_live_channel_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
  child_pid : Int,
  read_fd : Int,
  write_fd : Int,
  nonce : Int64,
) -> InstalledArenaLiveChannelReply {
  let (channel, issue) = match
    host.prepare_live_channel(domain, child_pid, read_fd, write_fd, nonce) {
    Err(issue) => (None, Some(issue))
    Ok(@bootstrap.PreparedLiveChannel(value)) => (Some(value), None)
    Ok(@bootstrap.PendingLiveChannel(value, issue)) =>
      (Some(value), Some(issue))
  }
  {
    host: domain.host,
    domain,
    channel,
    issue,
    operation: PrepareLive,
    state: None,
    limits: None,
    capacities: None,
  }
}

///|
pub fn prepare_installed_arena_live_channel_before_spawn_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
  read_fd : Int,
  write_fd : Int,
  nonce : Int64,
) -> InstalledArenaLiveChannelReply {
  let (channel, issue) = match
    host.prepare_live_channel_before_spawn(domain, read_fd, write_fd, nonce) {
    Err(issue) => (None, Some(issue))
    Ok(@bootstrap.PreparedLiveChannel(value)) => (Some(value), None)
    Ok(@bootstrap.PendingLiveChannel(value, issue)) =>
      (Some(value), Some(issue))
  }
  {
    host: domain.host,
    domain,
    channel,
    issue,
    operation: PrepareBeforeSpawn,
    state: None,
    limits: None,
    capacities: None,
  }
}

///|
pub fn bind_installed_arena_live_channel_child_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
  child_pid : Int,
) -> InstalledArenaLiveChannelReply {
  live_channel_unit_reply(
    BindChild,
    domain,
    channel,
    host.bind_live_channel_child(domain, channel, child_pid),
  )
}

///|
pub fn bind_installed_arena_live_channel_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
  nonce : Int64,
  offset : Int64,
  bytes : Int64,
) -> InstalledArenaLiveChannelReply {
  live_channel_unit_reply(
    BindVM,
    domain,
    channel,
    host.bind_live_channel_vm(domain, channel, nonce, offset, bytes),
  )
}

///|
/// Exact closed transport tags only. Invalid input returns a retained refusal,
/// never a fallback command, empty success or another operation's evidence.
pub fn operate_installed_arena_live_channel_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
  operation : Int,
) -> InstalledArenaLiveChannelReply {
  match operation {
    3 =>
      live_channel_unit_reply(
        AdmitLive,
        domain,
        channel,
        host.admit_live_channel(domain, channel),
      )
    4 => {
      let (state, issue) = match host.live_channel_state(domain, channel) {
        Ok(value) => (Some(value), None)
        Err(issue) => (None, Some(issue))
      }
      {
        host: domain.host,
        domain,
        channel: Some(channel),
        operation: ObserveLive,
        state,
        issue,
        limits: None,
        capacities: None,
      }
    }
    5 => {
      let (limits, issue) = match host.live_channel_limits(domain, channel) {
        Ok(value) => (Some(value), None)
        Err(issue) => (None, Some(issue))
      }
      {
        host: domain.host,
        domain,
        channel: Some(channel),
        operation: LimitsLive,
        state: None,
        issue,
        limits,
        capacities: None,
      }
    }
    9 => {
      let (capacities, issue) = match
        host.live_channel_capacities(domain, channel) {
        Ok(value) => (Some(value), None)
        Err(issue) => (None, Some(issue))
      }
      {
        host: domain.host,
        domain,
        channel: Some(channel),
        operation: CapacitiesLive,
        state: None,
        limits: None,
        capacities,
        issue,
      }
    }
    7 =>
      live_channel_unit_reply(
        StopLive,
        domain,
        channel,
        host.stop_live_channel(domain, channel),
      )
    8 =>
      live_channel_unit_reply(
        RetireLive,
        domain,
        channel,
        host.retire_live_channel_after_owner_ack(domain, channel),
      )
    _ =>
      live_channel_unit_reply(
        InvalidLiveOperation,
        domain,
        channel,
        Err(@bootstrap.Bootstrap(@bootstrap.Unavailable)),
      )
  }
}

///|
pub fn report_installed_arena_live_channel_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
  channel : @bootstrap.NativeBackedLiveChannel[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
  planning : Int,
  attempts : Int,
  holdings : Int,
  transferred : Int64,
  uncertain : Int64,
  reserved_transfer : Int64,
  held : Int64,
  reserved_retention : Int64,
  reserved_execution : Int64,
  peak_retention : Int64,
  reserved_attempts : Int,
  live_reservations : Int,
  live_delegations : Int,
) -> InstalledArenaLiveChannelReply {
  live_channel_unit_reply(
    ReportLive,
    domain,
    channel,
    host.report_live_channel(domain, channel, {
      planning_work: planning,
      attempts,
      holdings,
      transferred_bytes: transferred,
      uncertain_transfer_bytes: uncertain,
      reserved_transfer_bytes: reserved_transfer,
      held_bytes: held,
      reserved_retention_bytes: reserved_retention,
      reserved_execution_bytes: reserved_execution,
      peak_retention_bytes: peak_retention,
      reserved_attempts,
      live_reservations,
      live_delegations,
    }),
  )
}

///|
pub fn InstalledArenaLiveChannelReply::original_host(
  self : InstalledArenaLiveChannelReply,
) -> InstalledArenaHost {
  self.host
}

///|
pub fn InstalledArenaLiveChannelReply::original_domain(
  self : InstalledArenaLiveChannelReply,
) -> InstalledArenaDomain {
  self.domain
}

///|
pub fn InstalledArenaLiveChannelReply::original_channel(
  self : InstalledArenaLiveChannelReply,
) -> @bootstrap.NativeBackedLiveChannel[
  InstalledArenaHost,
  InstalledArenaDomain,
]? {
  self.channel
}

///|
pub fn InstalledArenaLiveChannelReply::operation_tag(
  self : InstalledArenaLiveChannelReply,
) -> Int {
  match self.operation {
    PrepareLive => 1
    BindVM => 2
    AdmitLive => 3
    ObserveLive => 4
    LimitsLive => 5
    ReportLive => 6
    StopLive => 7
    RetireLive => 8
    CapacitiesLive => 9
    PrepareBeforeSpawn => 10
    BindChild => 11
    InvalidLiveOperation => -1
  }
}

///|
pub fn InstalledArenaLiveChannelReply::issue_family(
  self : InstalledArenaLiveChannelReply,
) -> Int {
  match self.issue {
    None => 0
    Some(@bootstrap.Accounting(_)) => 8
    Some(@bootstrap.Bootstrap(issue)) =>
      installed_arena_issue_family(Some(issue))
  }
}

///|
pub fn InstalledArenaLiveChannelReply::state_tag(
  self : InstalledArenaLiveChannelReply,
) -> Int {
  match self.state {
    Some(@resources.LiveOpen) => 0
    Some(@resources.LiveClosing) => 1
    None => -1
  }
}

///|
pub fn InstalledArenaLiveChannelReply::limit(
  self : InstalledArenaLiveChannelReply,
  ordinal : Int,
) -> Int64 {
  // The existing exact i64 callback carries two additional closed ordinals
  // only on its distinct typed baseline observation. No signature or pointer
  // representation changes; C still checks operation and original identities.
  if self.capacities is Some((vm, host)) {
    return match ordinal {
      6 => vm
      7 => host
      _ => -1L
    }
  }
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
pub fn InstalledArenaLiveChannelReply::issue_description(
  self : InstalledArenaLiveChannelReply,
) -> String {
  match self.issue {
    None => ""
    Some(issue) => @debug.to_string(issue)
  }
}
