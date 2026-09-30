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
  DeadlineExpired
  /// The configured bearer credential file was unreadable, empty, oversized,
  /// malformed or not private to this user; nothing was sent.
  CredentialUnavailable
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

///|
/// How a client authenticates itself to the server. The server is always
/// verified against the configured CA. A bearer credential is read from the
/// named file for every request, so an atomic replacement of that file
/// (write a new file, then rename it over the old one) takes effect on the
/// next request; a missing or invalid file stops the request, and no earlier
/// credential is reused.
pub(all) enum NativeHttpAuthentication {
  /// Client certificate and key paths.
  MutualTls(String, String)
  /// Bearer credential file path.
  Bearer(String)
  /// Client certificate, key and bearer credential file paths.
  MutualTlsAndBearer(String, String, String)
}
