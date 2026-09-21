///|
type Server

///|
type Request

///|
#borrow(host, certificate_path, key_path, client_ca_path)
extern "C" fn open_ffi(
  host : Bytes,
  host_length : Int,
  port : Int,
  certificate_path : Bytes,
  certificate_path_length : Int,
  key_path : Bytes,
  key_path_length : Int,
  client_ca_path : Bytes,
  client_ca_path_length : Int,
  max_request_bytes : Int,
  max_pending_requests : Int,
) -> Server = "actql_native_https_server_open"

///|
#borrow(server)
extern "C" fn ready_ffi(server : Server) -> Bool = "actql_native_https_server_ready"

///|
#borrow(server)
extern "C" fn error_ffi(server : Server) -> Bytes = "actql_native_https_server_error"

///|
#borrow(server)
extern "C" fn port_ffi(server : Server) -> Int = "actql_native_https_server_port"

///|
#borrow(server)
extern "C" fn closed_ffi(server : Server) -> Bool = "actql_native_https_server_closed"

///|
#borrow(server)
extern "C" fn poll_ffi(server : Server, timeout_milliseconds : Int) -> Request = "actql_native_https_server_poll"

///|
#borrow(request)
extern "C" fn request_available_ffi(request : Request) -> Bool = "actql_native_https_request_available"

///|
#borrow(request)
extern "C" fn method_ffi(request : Request) -> Bytes = "actql_native_https_request_method"

///|
#borrow(request)
extern "C" fn path_ffi(request : Request) -> Bytes = "actql_native_https_request_path"

///|
#borrow(request)
extern "C" fn body_ffi(request : Request) -> Bytes = "actql_native_https_request_body"

///|
#borrow(request)
extern "C" fn peer_fingerprint_ffi(request : Request) -> Bytes = "actql_native_https_request_peer_fingerprint"

///|
#borrow(request, name)
extern "C" fn header_ffi(
  request : Request,
  name : Bytes,
  name_length : Int,
) -> Bytes = "actql_native_https_request_header"

///|
#borrow(request)
extern "C" fn header_present_ffi(request : Request) -> Bool = "actql_native_https_request_header_present"

///|
#borrow(request, content_type, body)
extern "C" fn respond_ffi(
  request : Request,
  status : Int,
  content_type : Bytes,
  content_type_length : Int,
  body : Bytes,
  body_length : Int,
) -> Bool = "actql_native_https_request_respond"

///|
#borrow(server)
extern "C" fn close_ffi(server : Server) -> Bool = "actql_native_https_server_close"
