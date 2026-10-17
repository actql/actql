///|
/// Immutable private transport of the same original process/domain. Tags and
/// observations are DATA, never a substitute for its retained typed custody.
struct InstalledArenaProcessReply {
  host : InstalledArenaHost
  domain : InstalledArenaDomain
  process : InstalledArenaProcess?
  operation : Int
  issue : @bootstrap.NativeBackedProcessRegionIssue?
  descriptors : (Int, Int)?
  backing_descriptor : Int
  stop_observation : Int
}

///|
pub fn prepare_installed_arena_process_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
  path : String,
  descriptor : Int,
  nonce : Int64,
  retained : Int64,
  execution : Int64,
) -> InstalledArenaProcessReply {
  let (process, issue) = match
    host.prepare_process(domain, path, descriptor, nonce, retained, execution) {
    Err(issue) => (None, Some(issue))
    Ok(PreparedProcess(process)) => (Some(process), None)
    Ok(PendingProcess(process, issue)) => (Some(process), Some(issue))
  }
  {
    host: domain.host,
    domain,
    process,
    operation: 1,
    issue,
    descriptors: None,
    backing_descriptor: -1,
    stop_observation: 0,
  }
}

///|
pub fn operate_installed_arena_process_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
  process : InstalledArenaProcess,
  operation : Int,
) -> InstalledArenaProcessReply {
  let mut descriptors = None
  let mut backing_descriptor = -1
  let mut stop_observation = 0
  let result = match operation {
    2 => host.require_process_current(domain, process)
    3 =>
      match host.process_descriptors(domain, process) {
        Err(issue) => Err(issue)
        Ok(value) => {
          descriptors = Some(value)
          Ok(())
        }
      }
    4 => host.restrict_process_transport(domain, process)
    5 => host.return_process_transport(domain, process)
    6 =>
      match host.poll_process_stop(domain, process) {
        Err(issue) => Err(issue)
        Ok(stopped) => {
          stop_observation = if stopped { 2 } else { 1 }
          Ok(())
        }
      }
    7 => host.close_prepared_process(domain, process)
    8 => host.retire_stopped_process(domain, process)
    9 =>
      match host.process_backing_descriptor(domain, process) {
        Err(issue) => Err(issue)
        Ok(value) => {
          backing_descriptor = value
          Ok(())
        }
      }
    _ => Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  {
    host: process.domain.host,
    domain: process.domain,
    process: Some(process),
    operation,
    issue: match result {
      Ok(_) => None
      Err(issue) => Some(issue)
    },
    descriptors,
    backing_descriptor,
    stop_observation,
  }
}

///|
pub fn InstalledArenaProcessReply::original_host(
  self : InstalledArenaProcessReply,
) -> InstalledArenaHost {
  self.host
}

///|
pub fn InstalledArenaProcessReply::original_domain(
  self : InstalledArenaProcessReply,
) -> InstalledArenaDomain {
  self.domain
}

///|
pub fn InstalledArenaProcessReply::original_process(
  self : InstalledArenaProcessReply,
) -> InstalledArenaProcess? {
  self.process
}

///|
pub fn InstalledArenaProcessReply::original_channel(
  self : InstalledArenaProcessReply,
) -> @bootstrap.NativeBackedLiveChannel[
  InstalledArenaHost,
  InstalledArenaDomain,
]? {
  match self.process {
    None => None
    Some(process) => process.channel
  }
}

///|
pub fn InstalledArenaProcessReply::original_frame(
  self : InstalledArenaProcessReply,
) -> @resources.ImportedChildLedger? {
  match self.process {
    None => None
    Some(process) => process.frame
  }
}

///|
pub fn InstalledArenaProcessReply::operation_tag(
  self : InstalledArenaProcessReply,
) -> Int {
  self.operation
}

///|
pub fn InstalledArenaProcessReply::issue_family(
  self : InstalledArenaProcessReply,
) -> Int {
  match self.issue {
    None => 0
    Some(@bootstrap.Domain(@bootstrap.Bootstrap(issue))) =>
      installed_arena_issue_family(Some(issue))
    Some(@bootstrap.Domain(@bootstrap.Accounting(_))) => 8
    Some(@bootstrap.Process(_)) => 9
    Some(@bootstrap.OriginalChild(@resources.Unknown)) => 10
    Some(@bootstrap.OriginalChild(_)) => 11
  }
}

///|
pub fn InstalledArenaProcessReply::descriptor(
  self : InstalledArenaProcessReply,
  ordinal : Int,
) -> Int {
  match self.descriptors {
    Some((writer, _)) if ordinal == 0 => writer
    Some((_, reader)) if ordinal == 1 => reader
    _ => -1
  }
}

///|
pub fn InstalledArenaProcessReply::stop_observation(
  self : InstalledArenaProcessReply,
) -> Int {
  self.stop_observation
}

///|
pub fn InstalledArenaProcessReply::backing_descriptor(
  self : InstalledArenaProcessReply,
) -> Int {
  self.backing_descriptor
}

///|
pub fn InstalledArenaProcessReply::issue_description(
  self : InstalledArenaProcessReply,
) -> String {
  match self.issue {
    None => ""
    Some(issue) => @debug.to_string(issue)
  }
}
