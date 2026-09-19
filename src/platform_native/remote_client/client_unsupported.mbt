///|
pub fn dispatch(
  _journal : @journal.CoordinatorJournal,
  _client : @http.Client,
  _url : String,
  _request : @remote.DispatchRequest,
) -> Result[@remote.RemoteDispatchResponse, NativeRemoteClientIssue] {
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
