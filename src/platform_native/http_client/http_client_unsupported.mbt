///|
type Library

///|
type Client

///|
pub fn load_library(_path : String) -> Result[Library, NativeHttpIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Library::version(_self : Library) -> String {
  ""
}

///|
pub fn Library::create_client(
  _self : Library,
  ca_path : String,
  certificate_path : String,
  key_path : String,
  max_response_bytes : Int64,
  connect_timeout_ms : Int,
  operation_timeout_ms : Int,
) -> Result[Client, NativeHttpIssue] {
  ignore(ca_path)
  ignore(certificate_path)
  ignore(key_path)
  ignore(max_response_bytes)
  ignore(connect_timeout_ms)
  ignore(operation_timeout_ms)
  Err(UnsupportedTarget)
}

///|
pub fn Client::post_json(
  _self : Client,
  url : String,
  body : Bytes,
) -> Result[NativeHttpResponse, NativeHttpIssue] {
  ignore(url)
  ignore(body)
  Err(UnsupportedTarget)
}

///|
pub fn Client::cancel(_self : Client) -> Bool {
  false
}

///|
pub fn Client::close(_self : Client) -> Bool {
  false
}
