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
#borrow(client, url, secret_path)
extern "C" fn client_get_bearer_file_ffi(
  client : Client,
  url : Bytes,
  url_length : Int,
  secret_path : Bytes,
  secret_path_length : Int,
  expires_at_milliseconds : Int64,
) -> Int = "actql_native_http_client_get_bearer_file"

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
fn method_name(verb : NativeHttpMethod) -> String {
  match verb {
    Get => "GET"
    Post => "POST"
    Put => "PUT"
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
/// Perform one bounded mTLS request. The entire response is bounded by the
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
    _ => Err(Transport(decode_message(client_error_ffi(self))))
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
  if !url.has_prefix("https://") ||
    url.length() > 8192 ||
    url.contains("\u{0}") ||
    !valid_path(secret_path) ||
    expires_at_milliseconds < 1L {
    return Err(InvalidRequest)
  }
  let encoded_url = @utf8.encode(url)
  let encoded_secret_path = @utf8.encode(secret_path)
  match
    client_get_bearer_file_ffi(
      self,
      encoded_url,
      encoded_url.length(),
      encoded_secret_path,
      encoded_secret_path.length(),
      expires_at_milliseconds,
    ) {
    0 => Ok({ status: client_status_ffi(self), body: client_body_ffi(self), })
    1 => Err(CapacityExceeded)
    2 => Err(Cancelled)
    3 => Err(Closed)
    4 => Err(DeadlineExpired)
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
