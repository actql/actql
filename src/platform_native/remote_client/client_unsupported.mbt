///|
pub fn dispatch(
  _journal : @journal.CoordinatorJournal,
  _client : @http.Client,
  _url : String,
  _request : @remote.DispatchRequest,
) -> Result[@remote.RemoteDispatchResponse, NativeRemoteClientIssue] {
  ignore(@utf8.encode(""))
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
