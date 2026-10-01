///|
pub fn Journal::retain_output_report(
  _self : Journal,
  _custody : @remote.RemoteOutputReportCustody,
) -> Result[Unit, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::ensure_output_report_capacity(
  _self : Journal,
  _output : @remote.RemotePollOutput,
  _payload : @payload.PublicationPayloadRequest,
  _transfer : @transfer.RemoteTransferRequest,
) -> Result[Unit, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::output_report(
  _self : Journal,
  _key : String,
) -> Result[
  (@remote.RemoteOutputReportCustody, @remote.RemoteOutputReportReply?),
  NativeRemoteJournalIssue,
] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::output_report_after(
  _self : Journal,
  _after : String,
) -> Result[
  (String, @remote.RemoteOutputReportCustody, @remote.RemoteOutputReportReply?)?,
  NativeRemoteJournalIssue,
] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::record_output_report_reply(
  _self : Journal,
  _key : String,
  _body : String,
) -> Result[Unit, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::retry_output_report(
  _self : Journal,
  _key : String,
) -> Result[Unit, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::reserve_output_report(
  _self : Journal,
  _output : @remote.RemotePollOutput,
) -> Result[Unit, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}
