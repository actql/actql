///|
/// Shared canonical DATA codec only. Authentication, durable original Run
/// association, physical-stop CAS and wake retirement stay with the caller.
#export_name("coordinatorHolderTerminalReportAdmit")
pub fn coordinator_holder_terminal_report_admit(
  body : String,
  maximum : Int,
) -> Result[@remote.RemoteHolderTerminalReport, @remote.DispatchIssue] {
  @remote.admit_remote_holder_terminal_report_json(body, maximum)
}

///|
#export_name("coordinatorHolderTerminalReportProjection")
pub fn coordinator_holder_terminal_report_projection(
  report : @remote.RemoteHolderTerminalReport,
) -> Array[String] {
  [
    @remote.remote_holder_terminal_report_identity(report),
    @remote.dispatch_request_identity(
      @remote.remote_holder_terminal_report_root(report),
    ),
  ]
}

///|
#export_name("coordinatorHolderTerminalReportDispatches")
pub fn coordinator_holder_terminal_report_dispatches(
  report : @remote.RemoteHolderTerminalReport,
) -> Array[@remote.DispatchRequest] {
  @remote.remote_holder_terminal_report_requests(report)
}

///|
/// Serialize only after the receiving Owner durably retains this inventory.
/// Its receipt does not establish that every holder of the Run has stopped.
#export_name("coordinatorHolderTerminalAcceptedJson")
pub fn coordinator_holder_terminal_accepted_json(
  report : @remote.RemoteHolderTerminalReport,
) -> Result[String, @remote.DispatchIssue] {
  @remote.prepare_remote_holder_terminal_reply(report).map(reply => {
    @remote.remote_holder_terminal_reply_json(reply)
  })
}

///|
#export_name("coordinatorHolderTerminalReplyAdmit")
pub fn coordinator_holder_terminal_reply_admit(
  report : @remote.RemoteHolderTerminalReport,
  body : String,
) -> Result[Unit, @remote.DispatchIssue] {
  @remote.admit_remote_holder_terminal_reply_json(body, report).map(_ => ())
}
