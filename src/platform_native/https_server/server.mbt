///|
pub(all) enum NativeHttpsServerIssue {
  InvalidConfiguration
  Start(String)
  Closed
  InvalidRequest
  ResponseFailed
}

///|
pub struct NativeHttpsRequest {
  request : Request
}

///|
pub struct NativeHttpsServer {
  server : Server
  max_response_bytes : Int
}

///|
fn decode(bytes : Bytes) -> String {
  @utf8.decode(bytes) catch {
    _ => ""
  }
}

///|
fn valid_text(value : String) -> Bool {
  !value.is_empty() && value.length() <= 4096 && !value.contains("\u{0}")
}

///|
pub fn open(
  host : String,
  port : Int,
  certificate_path : String,
  key_path : String,
  client_ca_path : String,
  max_request_bytes : Int,
  max_response_bytes : Int,
  max_pending_requests : Int,
) -> Result[NativeHttpsServer, NativeHttpsServerIssue] {
  if !valid_text(host) ||
    !valid_text(certificate_path) ||
    !valid_text(key_path) ||
    !valid_text(client_ca_path) ||
    port < 0 ||
    port > 65535 ||
    max_request_bytes < 1 ||
    max_response_bytes < 1 ||
    max_pending_requests < 1 {
    return Err(InvalidConfiguration)
  }
  let host_bytes = @utf8.encode(host)
  let certificate_bytes = @utf8.encode(certificate_path)
  let key_bytes = @utf8.encode(key_path)
  let client_ca_bytes = @utf8.encode(client_ca_path)
  let server = open_ffi(
    host_bytes,
    host_bytes.length(),
    port,
    certificate_bytes,
    certificate_bytes.length(),
    key_bytes,
    key_bytes.length(),
    client_ca_bytes,
    client_ca_bytes.length(),
    max_request_bytes,
    max_pending_requests,
  )
  if !ready_ffi(server) {
    return Err(Start(decode(error_ffi(server))))
  }
  Ok({ server, max_response_bytes, })
}

///|
pub fn NativeHttpsServer::port(self : NativeHttpsServer) -> Int {
  port_ffi(self.server)
}

///|
pub fn NativeHttpsServer::poll(
  self : NativeHttpsServer,
  timeout_milliseconds : Int,
) -> Result[NativeHttpsRequest?, NativeHttpsServerIssue] {
  if timeout_milliseconds < 0 {
    return Err(InvalidRequest)
  }
  let request = poll_ffi(self.server, timeout_milliseconds)
  if request_available_ffi(request) {
    Ok(Some({ request, }))
  } else if closed_ffi(self.server) {
    Err(Closed)
  } else {
    Ok(None)
  }
}

///|
pub fn NativeHttpsRequest::request_method(self : NativeHttpsRequest) -> String {
  decode(method_ffi(self.request))
}

///|
pub fn NativeHttpsRequest::path(self : NativeHttpsRequest) -> String {
  decode(path_ffi(self.request))
}

///|
pub fn NativeHttpsRequest::body(self : NativeHttpsRequest) -> Bytes {
  body_ffi(self.request)
}

///|
pub fn NativeHttpsRequest::peer_fingerprint(
  self : NativeHttpsRequest,
) -> String {
  decode(peer_fingerprint_ffi(self.request))
}

///|
pub fn NativeHttpsRequest::header(
  self : NativeHttpsRequest,
  name : String,
) -> String? {
  if name.is_empty() || name.length() > 128 || name.contains("\u{0}") {
    return None
  }
  let encoded = @utf8.encode(name)
  let value = header_ffi(self.request, encoded, encoded.length())
  if header_present_ffi(self.request) {
    Some(decode(value))
  } else {
    None
  }
}

///|
pub fn NativeHttpsServer::respond(
  self : NativeHttpsServer,
  request : NativeHttpsRequest,
  status : Int,
  content_type : String,
  body : Bytes,
) -> Result[Unit, NativeHttpsServerIssue] {
  if status < 100 ||
    status > 599 ||
    !valid_text(content_type) ||
    body.length() > self.max_response_bytes {
    return Err(InvalidRequest)
  }
  let encoded_type = @utf8.encode(content_type)
  if respond_ffi(
      request.request,
      status,
      encoded_type,
      encoded_type.length(),
      body,
      body.length(),
    ) {
    Ok(())
  } else {
    Err(ResponseFailed)
  }
}

///|
pub fn NativeHttpsServer::close(self : NativeHttpsServer) -> Bool {
  close_ffi(self.server)
}
