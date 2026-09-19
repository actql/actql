///|
pub(all) enum NativeHttpIssue {
  UnsupportedTarget
  InvalidConfiguration
  LibraryLoad(String)
  ClientCreate(String)
  InvalidRequest
  CapacityExceeded
  Cancelled
  Closed
  Transport(String)
}

///|
pub(all) struct NativeHttpResponse {
  status : Int
  body : Bytes
}
