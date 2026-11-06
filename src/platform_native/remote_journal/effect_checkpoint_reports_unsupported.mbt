///|
pub fn Journal::has_effect_checkpoint_reports(
  _self : Journal,
) -> Result[Bool, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::effect_checkpoint_report(
  _self : Journal,
  _request : @remote.DispatchRequest,
  _limits : @checkpoint.WireLimits,
) -> Result[
  (@remote.RemoteEffectCheckpointReport, @remote.RemoteEffectCheckpointReply?),
  NativeRemoteJournalIssue,
] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::retain_effect_checkpoint_report(
  _self : Journal,
  _report : @remote.RemoteEffectCheckpointReport,
) -> Result[Unit, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::record_effect_checkpoint_reply(
  _self : Journal,
  _request : @remote.DispatchRequest,
  _body : String,
  _limits : @checkpoint.WireLimits,
) -> Result[Unit, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}
