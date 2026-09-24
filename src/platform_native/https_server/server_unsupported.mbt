///|
type Server

///|
type Request

///|
fn supported_ffi() -> Bool {
  false
}

///|
fn open_ffi(
  _host : Bytes,
  _host_length : Int,
  _port : Int,
  _certificate_path : Bytes,
  _certificate_path_length : Int,
  _key_path : Bytes,
  _key_path_length : Int,
  _client_ca_path : Bytes,
  _client_ca_path_length : Int,
  _max_request_bytes : Int,
  _max_pending_requests : Int,
) -> Server {
  abort("native HTTPS server is unavailable")
}

///|
fn ready_ffi(_server : Server) -> Bool {
  false
}

///|
fn error_ffi(_server : Server) -> Bytes {
  b""
}

///|
fn port_ffi(_server : Server) -> Int {
  0
}

///|
fn closed_ffi(_server : Server) -> Bool {
  true
}

///|
fn poll_ffi(_server : Server, _timeout_milliseconds : Int) -> Request {
  abort("native HTTPS server is unavailable")
}

///|
fn request_available_ffi(_request : Request) -> Bool {
  false
}

///|
fn method_ffi(_request : Request) -> Bytes {
  b""
}

///|
fn path_ffi(_request : Request) -> Bytes {
  b""
}

///|
fn body_ffi(_request : Request) -> Bytes {
  b""
}

///|
fn peer_fingerprint_ffi(_request : Request) -> Bytes {
  b""
}

///|
fn header_ffi(_request : Request, _name : Bytes, _name_length : Int) -> Bytes {
  b""
}

///|
fn header_present_ffi(_request : Request) -> Bool {
  false
}

///|
fn respond_ffi(
  _request : Request,
  _status : Int,
  _content_type : Bytes,
  _content_type_length : Int,
  _body : Bytes,
  _body_length : Int,
) -> Bool {
  false
}

///|
fn close_ffi(_server : Server) -> Bool {
  false
}
