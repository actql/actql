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
    Ok(_) => {
      self.library = None
      Ok(())
    }
    Err(issue) => Err(issue)
  }
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
  guard self.client is Some(original) else { return Ok(self.original_library) }
  match retire_failed_http_client(self.original_library, original) {
    Ok(_) => {
      self.client = None
      Ok(self.original_library)
    }
    Err(issue) => Err(issue)
  }
}

///|
type Library

///|
type Client

///|
#borrow(path)
extern "C" fn load_library_ffi(
  path : Bytes,
  length : Int,
  diagnostic_ceiling : Int,
) -> Library = "actql_native_http_load_library"

///|
#borrow(path)
extern "C" fn load_library_with_custody_ffi(
  path : Bytes,
  length : Int,
  diagnostic_ceiling : Int,
) -> Library = "actql_native_http_load_library_with_custody"

///|
#borrow(library)
extern "C" fn retire_failed_library_ffi(library : Library) -> Int = "actql_native_http_retire_failed_library"

///|
#borrow(library, client)
extern "C" fn retire_failed_client_ffi(
  library : Library,
  client : Client,
) -> Int = "actql_native_http_retire_failed_client"

///|
fn retire_failed_http_library(
  library : Library,
) -> Result[Unit, NativeHttpIssue] {
  match retire_failed_library_ffi(library) {
    0 => Ok(())
    _ => Err(Transport("HTTP library retirement unconfirmed"))
  }
}

///|
fn retire_failed_http_client(
  library : Library,
  client : Client,
) -> Result[Unit, NativeHttpIssue] {
  match retire_failed_client_ffi(library, client) {
    0 => Ok(())
    _ => Err(Transport("HTTP constructor metadata retirement unconfirmed"))
  }
}

///|
#borrow(library)
extern "C" fn library_ready_ffi(library : Library) -> Bool = "actql_native_http_library_ready"

///|
#borrow(library)
extern "C" fn library_error_ffi(library : Library) -> Bytes = "actql_native_http_library_error"

///|
#borrow(library)
extern "C" fn library_version_ffi(library : Library) -> Bytes = "actql_native_http_library_version"

///|
#borrow(library, ca_path, certificate_path, key_path)
extern "C" fn create_client_ffi(
  library : Library,
  ca_path : Bytes,
  ca_path_length : Int,
  certificate_path : Bytes,
  certificate_path_length : Int,
  key_path : Bytes,
  key_path_length : Int,
  max_response_bytes : Int64,
  connect_timeout_ms : Int,
  operation_timeout_ms : Int,
) -> Client = "actql_native_http_create_client"

///|
#borrow(library, ca_path, certificate_path, key_path, bearer_path)
extern "C" fn create_authenticated_client_ffi(
  library : Library,
  ca_path : Bytes,
  ca_path_length : Int,
  certificate_path : Bytes,
  certificate_path_length : Int,
  key_path : Bytes,
  key_path_length : Int,
  bearer_path : Bytes,
  bearer_path_length : Int,
  max_response_bytes : Int64,
  connect_timeout_ms : Int,
  operation_timeout_ms : Int,
) -> Client = "actql_native_http_create_authenticated_client"

///|
#borrow(client)
extern "C" fn client_ready_ffi(client : Client) -> Bool = "actql_native_http_client_ready"

///|
#borrow(client)
extern "C" fn client_error_ffi(client : Client) -> Bytes = "actql_native_http_client_error"

///|
#borrow(client, url, body)
extern "C" fn client_post_json_ffi(
  client : Client,
  url : Bytes,
  url_length : Int,
  body : Bytes,
  body_length : Int,
) -> Int = "actql_native_http_client_post_json"

///|
#borrow(client, verb, url, headers, body)
extern "C" fn client_request_ffi(
  client : Client,
  verb : Bytes,
  verb_length : Int,
  url : Bytes,
  url_length : Int,
  headers : Bytes,
  headers_length : Int,
  body : Bytes,
  body_length : Int,
) -> Int = "actql_native_http_client_request"

///|
#borrow(client, verb, url, headers, body, secret_path)
extern "C" fn client_request_bearer_file_ffi(
  client : Client,
  verb : Bytes,
  verb_length : Int,
  url : Bytes,
  url_length : Int,
  headers : Bytes,
  headers_length : Int,
  body : Bytes,
  body_length : Int,
  secret_path : Bytes,
  secret_path_length : Int,
  expires_at_milliseconds : Int64,
) -> Int = "actql_native_http_client_request_bearer_file"

///|
#borrow(client)
extern "C" fn client_status_ffi(client : Client) -> Int = "actql_native_http_client_status"

///|
#borrow(client)
extern "C" fn client_response_limit_ffi(client : Client) -> Int64 = "actql_native_http_client_response_limit"

///|
/// Project the actual immutable ceiling adopted by this HTTP Owner. This is
/// for prefunding existing response/Store custody before physical entry; it
/// neither reserves capacity nor grants send, disclosure or retry authority.
pub fn Client::response_limit(self : Client) -> Result[Int64, NativeHttpIssue] {
  match client_response_limit_ffi(self) {
    -1L => Err(Closed)
    -2L => Err(InvalidConfiguration)
    -3L => Err(Cancelled)
    value if value >= 0L && value <= 2147483647L => Ok(value)
    _ => Err(InvalidConfiguration)
  }
}

///|
#borrow(client)
extern "C" fn client_body_ffi(client : Client) -> Bytes = "actql_native_http_client_body"

///|
#borrow(client)
extern "C" fn client_cancel_ffi(client : Client) -> Bool = "actql_native_http_client_cancel"

///|
#borrow(client)
extern "C" fn client_close_ffi(client : Client) -> Bool = "actql_native_http_client_close"

///|
fn decode_message(bytes : Bytes) -> String {
  @utf8.decode_lossy(bytes)
}

///|
fn decode_diagnostic(bytes : Bytes) -> String {
  if bytes.is_empty() {
    "HTTP diagnostic detail omitted"
  } else {
    @utf8.decode_lossy(bytes)
  }
}

///|
fn valid_path(path : String) -> Bool {
  !path.is_empty() && path.length() <= 4096 && !path.contains("\u{0}")
}

///|
/// Select from trusted installer configuration bound to its source/ABI.
/// Omission preserves legacy behavior; this bound issues no funding/authority.
pub fn load_library(
  path : String,
  diagnostic_ceiling? : Int? = None,
) -> Result[Library, NativeHttpIssue] {
  if diagnostic_ceiling is Some(value) && value <= 0 {
    return Err(InvalidConfiguration)
  }
  if !valid_path(path) {
    return Err(InvalidConfiguration)
  }
  let encoded = @utf8.encode(path)
  let library = load_library_ffi(
    encoded,
    encoded.length(),
    diagnostic_ceiling.unwrap_or(0),
  )
  if library_ready_ffi(library) {
    Ok(library)
  } else {
    Err(LibraryLoad(decode_diagnostic(library_error_ffi(library))))
  }
}

///|
pub fn load_library_with_custody(
  path : String,
  diagnostic_ceiling? : Int? = None,
) -> Result[Library, NativeHttpLibraryLoadError] {
  if (diagnostic_ceiling is Some(value) && value <= 0) || !valid_path(path) {
    return Err(RefusedBeforeAcquisition(InvalidConfiguration))
  }
  let encoded = @utf8.encode(path)
  let library = load_library_with_custody_ffi(
    encoded,
    encoded.length(),
    diagnostic_ceiling.unwrap_or(0),
  )
  if library_ready_ffi(library) {
    Ok(library)
  } else {
    Err(
      CleanupRequired({
        original_issue: LibraryLoad(
          decode_diagnostic(library_error_ffi(library)),
        ),
        library: Some(library),
      }),
    )
  }
}

///|
fn http_client_create_result_with_custody(
  library : Library,
  client : Client,
) -> Result[Client, NativeHttpClientCreateError] {
  if client_ready_ffi(client) {
    Ok(client)
  } else {
    Err(
      CleanupRequired({
        original_issue: ClientCreate(
          decode_diagnostic(client_error_ffi(client)),
        ),
        original_library: library,
        client: Some(client),
      }),
    )
  }
}

///|
pub fn Library::version(self : Library) -> String {
  decode_message(library_version_ffi(self))
}

///|
pub fn Library::create_client(
  self : Library,
  ca_path : String,
  certificate_path : String,
  key_path : String,
  max_response_bytes : Int64,
  connect_timeout_ms : Int,
  operation_timeout_ms : Int,
) -> Result[Client, NativeHttpIssue] {
  match
    self.create_client_with_custody(
      ca_path, certificate_path, key_path, max_response_bytes, connect_timeout_ms,
      operation_timeout_ms,
    ) {
    Ok(client) => Ok(client)
    Err(RefusedBeforeAcquisition(issue)) => Err(issue)
    Err(CleanupRequired(failure)) => {
      // Legacy issue-only caller cannot retain a pending constructor carrier.
      // Its best-effort cleanup is not an upper-holder funding/retirement proof.
      ignore(failure.retry_cleanup())
      Err(failure.issue())
    }
  }
}

///|
pub fn Library::create_client_with_custody(
  self : Library,
  ca_path : String,
  certificate_path : String,
  key_path : String,
  max_response_bytes : Int64,
  connect_timeout_ms : Int,
  operation_timeout_ms : Int,
) -> Result[Client, NativeHttpClientCreateError] {
  if !valid_path(ca_path) ||
    !valid_path(certificate_path) ||
    !valid_path(key_path) ||
    max_response_bytes < 0L ||
    max_response_bytes > 2147483647L ||
    connect_timeout_ms <= 0 ||
    operation_timeout_ms <= 0 ||
    operation_timeout_ms < connect_timeout_ms {
    return Err(RefusedBeforeAcquisition(InvalidConfiguration))
  }
  if !library_ready_ffi(self) {
    return Err(RefusedBeforeAcquisition(Closed))
  }
  let ca = @utf8.encode(ca_path)
  let certificate = @utf8.encode(certificate_path)
  let key = @utf8.encode(key_path)
  let client = create_client_ffi(
    self,
    ca,
    ca.length(),
    certificate,
    certificate.length(),
    key,
    key.length(),
    max_response_bytes,
    connect_timeout_ms,
    operation_timeout_ms,
  )
  http_client_create_result_with_custody(self, client)
}

///|
/// Create a client that authenticates by client certificate, by a bearer
/// credential file read for every request, or by both.
pub fn Library::create_authenticated_client(
  self : Library,
  ca_path : String,
  authentication : NativeHttpAuthentication,
  max_response_bytes : Int64,
  connect_timeout_ms : Int,
  operation_timeout_ms : Int,
) -> Result[Client, NativeHttpIssue] {
  match
    self.create_authenticated_client_with_custody(
      ca_path, authentication, max_response_bytes, connect_timeout_ms, operation_timeout_ms,
    ) {
    Ok(client) => Ok(client)
    Err(RefusedBeforeAcquisition(issue)) => Err(issue)
    Err(CleanupRequired(failure)) => {
      // Legacy issue-only caller cannot retain a pending constructor carrier.
      // Its best-effort cleanup is not an upper-holder funding/retirement proof.
      ignore(failure.retry_cleanup())
      Err(failure.issue())
    }
  }
}

///|
pub fn Library::create_authenticated_client_with_custody(
  self : Library,
  ca_path : String,
  authentication : NativeHttpAuthentication,
  max_response_bytes : Int64,
  connect_timeout_ms : Int,
  operation_timeout_ms : Int,
) -> Result[Client, NativeHttpClientCreateError] {
  let (certificate_path, key_path, bearer_path, configured) = match
    authentication {
    MutualTls(certificate, key) =>
      (certificate, key, "", valid_path(certificate) && valid_path(key))
    Bearer(bearer) => ("", "", bearer, valid_path(bearer))
    MutualTlsAndBearer(certificate, key, bearer) =>
      (
        certificate,
        key,
        bearer,
        valid_path(certificate) && valid_path(key) && valid_path(bearer),
      )
  }
  if !valid_path(ca_path) ||
    !configured ||
    max_response_bytes < 0L ||
    max_response_bytes > 2147483647L ||
    connect_timeout_ms <= 0 ||
    operation_timeout_ms <= 0 ||
    operation_timeout_ms < connect_timeout_ms {
    return Err(RefusedBeforeAcquisition(InvalidConfiguration))
  }
  if !library_ready_ffi(self) {
    return Err(RefusedBeforeAcquisition(Closed))
  }
  let ca = @utf8.encode(ca_path)
  let certificate = @utf8.encode(certificate_path)
  let key = @utf8.encode(key_path)
  let bearer = @utf8.encode(bearer_path)
  let client = create_authenticated_client_ffi(
    self,
    ca,
    ca.length(),
    certificate,
    certificate.length(),
    key,
    key.length(),
    bearer,
    bearer.length(),
    max_response_bytes,
    connect_timeout_ms,
    operation_timeout_ms,
  )
  http_client_create_result_with_custody(self, client)
}

///|
pub fn Client::post_json(
  self : Client,
  url : String,
  body : Bytes,
) -> Result[NativeHttpResponse, NativeHttpIssue] {
  if !url.has_prefix("https://") || url.length() > 8192 || url.contains("\u{0}") {
    return Err(InvalidRequest)
  }
  let encoded_url = @utf8.encode(url)
  match
    client_post_json_ffi(
      self,
      encoded_url,
      encoded_url.length(),
      body,
      body.length(),
    ) {
    0 => Ok({ status: client_status_ffi(self), body: client_body_ffi(self), })
    1 => Err(CapacityExceeded)
    2 => Err(Cancelled)
    3 => Err(Closed)
    5 => Err(CredentialUnavailable)
    _ => Err(Transport(decode_diagnostic(client_error_ffi(self))))
  }
}

///|
fn method_name(verb : NativeHttpMethod) -> String {
  match verb {
    Get => "GET"
    Post => "POST"
    Put => "PUT"
    Patch => "PATCH"
  }
}

///|
fn valid_header_name_byte(byte : Byte) -> Bool {
  let value = byte.to_int()
  (value >= 97 && value <= 122) || (value >= 48 && value <= 57) || value == 45
}

///|
fn encode_headers(headers : Array[NativeHttpHeader]) -> Bytes? {
  if headers.length() > 32 {
    return None
  }
  let output : Array[Byte] = []
  for header in headers {
    let name = @utf8.encode(header.name)
    let value = @utf8.encode(header.value)
    if name.length() == 0 ||
      name.length() > 128 ||
      value.length() > 8192 ||
      output.length() + name.length() + value.length() + 3 > 32768 {
      return None
    }
    for byte in name {
      if !valid_header_name_byte(byte) {
        return None
      }
      output.push(byte)
    }
    output.push((58 : Byte))
    output.push((32 : Byte))
    for byte in value {
      let number = byte.to_int()
      if number < 32 || number > 126 {
        return None
      }
      output.push(byte)
    }
    output.push((10 : Byte))
  }
  Some(Bytes::from_array(output))
}

///|
/// Perform one bounded HTTPS request with the client's authentication. The entire response is bounded by the
/// client configuration. Callers use this for control bodies and one admitted
/// data chunk at a time, not for an unbounded whole-result materialization.
pub fn Client::request(
  self : Client,
  verb : NativeHttpMethod,
  url : String,
  headers : Array[NativeHttpHeader],
  body : Bytes,
) -> Result[NativeHttpResponse, NativeHttpIssue] {
  if !url.has_prefix("https://") ||
    url.length() > 8192 ||
    url.contains("\u{0}") ||
    (verb == Get && body.length() != 0) {
    return Err(InvalidRequest)
  }
  guard encode_headers(headers) is Some(encoded_headers) else {
    return Err(InvalidRequest)
  }
  let encoded_method = @utf8.encode(method_name(verb))
  let encoded_url = @utf8.encode(url)
  match
    client_request_ffi(
      self,
      encoded_method,
      encoded_method.length(),
      encoded_url,
      encoded_url.length(),
      encoded_headers,
      encoded_headers.length(),
      body,
      body.length(),
    ) {
    0 => Ok({ status: client_status_ffi(self), body: client_body_ffi(self), })
    1 => Err(CapacityExceeded)
    2 => Err(Cancelled)
    3 => Err(Closed)
    5 => Err(CredentialUnavailable)
    6 => Err(InvalidRequest)
    _ => Err(Transport(decode_diagnostic(client_error_ffi(self))))
  }
}

///|
/// Performs one bounded HTTPS GET while resolving the bearer credential from
/// an exact local file inside the physical adapter. The secret never crosses
/// the MoonBit boundary and redirects remain disabled.
pub fn Client::get_bearer_file(
  self : Client,
  url : String,
  secret_path : String,
  expires_at_milliseconds : Int64,
) -> Result[NativeHttpResponse, NativeHttpIssue] {
  self.request_bearer_file(
    Get,
    url,
    [{ name: "accept", value: "application/json", }],
    b"",
    secret_path,
    expires_at_milliseconds,
  )
}

///|
/// Perform one bounded request with an exact operation credential. Resolve the
/// secret only inside the physical adapter and recheck its deadline after that
/// resolution, before any send. Caller-supplied Authorization is forbidden.
pub fn Client::request_bearer_file(
  self : Client,
  verb : NativeHttpMethod,
  url : String,
  headers : Array[NativeHttpHeader],
  body : Bytes,
  secret_path : String,
  expires_at_milliseconds : Int64,
) -> Result[NativeHttpResponse, NativeHttpIssue] {
  if !url.has_prefix("https://") ||
    url.length() > 8192 ||
    url.contains("\u{0}") ||
    !valid_path(secret_path) ||
    expires_at_milliseconds < 1L ||
    (verb == Get && body.length() != 0) {
    return Err(InvalidRequest)
  }
  guard encode_headers(headers) is Some(encoded_headers) else {
    return Err(InvalidRequest)
  }
  let encoded_method = @utf8.encode(method_name(verb))
  let encoded_url = @utf8.encode(url)
  let encoded_secret_path = @utf8.encode(secret_path)
  match
    client_request_bearer_file_ffi(
      self,
      encoded_method,
      encoded_method.length(),
      encoded_url,
      encoded_url.length(),
      encoded_headers,
      encoded_headers.length(),
      body,
      body.length(),
      encoded_secret_path,
      encoded_secret_path.length(),
      expires_at_milliseconds,
    ) {
    0 => Ok({ status: client_status_ffi(self), body: client_body_ffi(self), })
    1 => Err(CapacityExceeded)
    2 => Err(Cancelled)
    3 => Err(Closed)
    4 => Err(DeadlineExpired)
    5 => Err(CredentialUnavailable)
    6 => Err(InvalidRequest)
    _ => Err(Transport(decode_diagnostic(client_error_ffi(self))))
  }
}

///|
pub fn Client::cancel(self : Client) -> Bool {
  client_cancel_ffi(self)
}

///|
pub fn Client::close(self : Client) -> Bool {
  client_close_ffi(self)
}

///|
#borrow(library)
extern "C" fn close_http_library_ffi(library : Library) -> Int = "actql_native_http_library_close_checked"

///|
/// Complete this original Library's init/loader retirement only after all
/// actual Client metadata holders and original easy-handle cleanup calls have
/// completed. Requests require ordinary resolver cleanup (QUICK_EXIT disabled),
/// not detached workers. TLS backend retirement is a separate obligation; it
/// uses the same component's per-thread cleanup and last-Library release,
/// and remains pending when the selected image has no such physical result.
/// Init/loader references retire only after both obligations; global cleanup
/// alone is not a thread acknowledgement.
/// A selected backed runtime also retains its same original Read through
/// construction, failed children and native buffer retirement. The enclosing
/// Read/domain's physical closure is separate from this reference return.
/// Neither this result nor Client close is a whole Host stop.
pub fn Library::close_checked(self : Library) -> Result[Unit, NativeHttpIssue] {
  match close_http_library_ffi(self) {
    0 => Ok(())
    _ => Err(Transport("original HTTP Library retirement unconfirmed"))
  }
}

///|
#borrow(client)
extern "C" fn close_http_client_checked_ffi(client : Client) -> Int = "actql_native_http_client_close_checked"

///|
/// Checked same-original metadata close. An in-flight request keeps its paths,
/// response and Library holder until the actual request has unwound; cancel is
/// only a request and cannot substitute that acknowledgement.
pub fn Client::close_checked(self : Client) -> Result[Unit, NativeHttpIssue] {
  match close_http_client_checked_ffi(self) {
    0 => Ok(())
    _ => Err(Transport("original HTTP Client retirement unconfirmed"))
  }
}
