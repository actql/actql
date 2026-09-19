///|
type Library

///|
type Client

///|
#borrow(path)
extern "C" fn load_library_ffi(path : Bytes, length : Int) -> Library = "actql_native_http_load_library"

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
#borrow(client)
extern "C" fn client_status_ffi(client : Client) -> Int = "actql_native_http_client_status"

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
fn valid_path(path : String) -> Bool {
  !path.is_empty() && path.length() <= 4096 && !path.contains("\u{0}")
}

///|
pub fn load_library(path : String) -> Result[Library, NativeHttpIssue] {
  if !valid_path(path) {
    return Err(InvalidConfiguration)
  }
  let encoded = @utf8.encode(path)
  let library = load_library_ffi(encoded, encoded.length())
  if library_ready_ffi(library) {
    Ok(library)
  } else {
    Err(LibraryLoad(decode_message(library_error_ffi(library))))
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
  if !valid_path(ca_path) ||
    !valid_path(certificate_path) ||
    !valid_path(key_path) ||
    max_response_bytes < 0L ||
    max_response_bytes > 2147483647L ||
    connect_timeout_ms <= 0 ||
    operation_timeout_ms <= 0 ||
    operation_timeout_ms < connect_timeout_ms {
    return Err(InvalidConfiguration)
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
  if client_ready_ffi(client) {
    Ok(client)
  } else {
    Err(ClientCreate(decode_message(client_error_ffi(client))))
  }
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
    _ => Err(Transport(decode_message(client_error_ffi(self))))
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
