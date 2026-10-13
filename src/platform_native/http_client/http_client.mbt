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
  Patch
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

///|
/// Refusal precedes the physical constructor. After entry, the actual rejected
/// Library remains nominal custody, even when diagnostic text was omitted.
pub(all) enum NativeHttpLibraryLoadError {
  RefusedBeforeAcquisition(NativeHttpIssue)
  CleanupRequired(NativeHttpLibraryLoadFailure)
}

///|
struct NativeHttpLibraryLoadFailure {
  original_issue : NativeHttpIssue
  mut library : Library?
}

///|
pub fn NativeHttpLibraryLoadFailure::issue(
  self : NativeHttpLibraryLoadFailure,
) -> NativeHttpIssue {
  self.original_issue
}

///|
/// A failed init or unconfirmed unload remains pending on the same Library.
/// There is no load retry, replacement handle or successful-runtime close here.
pub fn NativeHttpLibraryLoadFailure::retry_cleanup(
  self : NativeHttpLibraryLoadFailure,
) -> Result[Unit, NativeHttpIssue] {
  guard self.library is Some(original) else { return Ok(()) }
  match retire_failed_http_library(original) {
    Ok(_) => { self.library = None; Ok(()) }
    Err(issue) => Err(issue)
  }
}

///|
pub(all) enum NativeHttpClientCreateError {
  RefusedBeforeAcquisition(NativeHttpIssue)
  CleanupRequired(NativeHttpClientCreateFailure)
}

///|
struct NativeHttpClientCreateFailure {
  original_issue : NativeHttpIssue
  original_library : Library
  mut client : Client?
}

///|
pub fn NativeHttpClientCreateFailure::issue(
  self : NativeHttpClientCreateFailure,
) -> NativeHttpIssue {
  self.original_issue
}

///|
/// Retire only the rejected Client's owned paths/response/diagnostic storage.
/// The original Library reference remains in this carrier through its caller
/// lifetime and is returned explicitly as residual custody, not a cleanup ACK
/// for global libcurl or runtime retirement. No new Library is loaded.
pub fn NativeHttpClientCreateFailure::retry_cleanup(
  self : NativeHttpClientCreateFailure,
) -> Result[Library, NativeHttpIssue] {
  guard self.client is Some(original) else {
    return Ok(self.original_library)
  }
  match retire_failed_http_client(self.original_library, original) {
    Ok(_) => {
      self.client = None
      Ok(self.original_library)
    }
    Err(issue) => Err(issue)
  }
}
