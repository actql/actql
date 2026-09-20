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

///|
/// Methods required by bounded control and chunk exchanges. Redirect policy,
/// authentication and response limits remain properties of the client.
pub(all) enum NativeHttpMethod {
  Get
  Post
  Put
} derive(Eq, Debug)

///|
/// One bounded physical HTTP header. Header admission is deliberately narrow:
/// ActQL protocol meaning remains in the portable caller.
pub(all) struct NativeHttpHeader {
  name : String
  value : String
}
