///|
pub fn dispatch(
  _journal : @journal.CoordinatorJournal,
  _client : @http.Client,
  _url : String,
  request : @remote.DispatchRequest,
  authorization : @authorization.RuntimeAction,
) -> Result[@remote.RemoteDispatchResponse, NativeRemoteClientIssue] {
  ignore(@utf8.encode(""))
  if !remote_dispatch_authorized(authorization, request) {
    return Err(NotAuthorized)
  }
  Err(UnsupportedTarget)
}

///|
pub fn query(
  _journal : @journal.CoordinatorJournal,
  _client : @http.Client,
  _url : String,
  _request : @remote.DispatchRequest,
) -> Result[@remote.RemoteDispatchResponse, NativeRemoteClientIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn cancel(
  _journal : @journal.CoordinatorJournal,
  _client : @http.Client,
  _url : String,
  _request : @remote.DispatchRequest,
) -> Result[@remote.RemoteDispatchResponse, NativeRemoteClientIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn poll(
  _client : @http.Client,
  _url : String,
) -> Result[@remote.DispatchRequest?, NativeRemoteClientIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn poll_operation(
  _client : @http.Client,
  _url : String,
) -> Result[@remote.RemotePollOperation?, NativeRemoteClientIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn acknowledge_acceptance(
  _journal : @journal.Journal,
  _client : @http.Client,
  _url : String,
  _request : @remote.DispatchRequest,
) -> Result[@remote.DispatchRecord, NativeRemoteClientIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn acknowledge_status(
  _journal : @journal.Journal,
  _client : @http.Client,
  _url : String,
  _request : @remote.DispatchRequest,
) -> Result[@remote.DispatchRecord?, NativeRemoteClientIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn acknowledge_output_result(
  _client : @http.Client,
  _url : String,
  _result : @remote.RemoteOutputResult,
) -> Result[Unit, NativeRemoteClientIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn acknowledge_retained_output_report(
  _journal : @journal.Journal,
  _client : @http.Client,
  _url : String,
  _key : String,
  checkpoint? : (String) -> Unit = fn(_) {  },
) -> Result[Unit, NativeRemoteClientIssue] {
  ignore(checkpoint)
  Err(UnsupportedTarget)
}

///|
pub fn acknowledge_output_plan(
  _client : @http.Client,
  _url : String,
  _plan : @remote.RemoteOutputPlan,
) -> Result[Unit, NativeRemoteClientIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn acknowledge_retained_input_plan(
  _client : @http.Client,
  _url : String,
  _plan : @remote.RemoteRetainedInputPlan,
) -> Result[Unit, NativeRemoteClientIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn acknowledge_retained_input_result(
  _client : @http.Client,
  _url : String,
  _result : @remote.RemoteRetainedInputResult,
) -> Result[Unit, NativeRemoteClientIssue] {
  Err(UnsupportedTarget)
}

///|
/// A transport ACK does not extend the lifetime of this current observation.
pub fn acknowledge_retained_input_current(
  _client : @http.Client,
  _url : String,
  _reply : @remote.RemoteRetainedCurrentReply,
) -> Result[Unit, NativeRemoteClientIssue] {
  Err(UnsupportedTarget)
}
