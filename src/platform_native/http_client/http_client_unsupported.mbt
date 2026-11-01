///|
type NativeHttpLibraryLoadFailure

///|
pub fn NativeHttpLibraryLoadFailure::issue(
  _self : NativeHttpLibraryLoadFailure,
) -> NativeHttpIssue {
  UnsupportedTarget
}

///|
pub fn NativeHttpLibraryLoadFailure::retry_cleanup(
  _self : NativeHttpLibraryLoadFailure,
) -> Result[Unit, NativeHttpIssue] {
  Err(UnsupportedTarget)
}

///|
type NativeHttpClientCreateFailure

///|
pub fn NativeHttpClientCreateFailure::issue(
  _self : NativeHttpClientCreateFailure,
) -> NativeHttpIssue {
  UnsupportedTarget
}

///|
pub fn NativeHttpClientCreateFailure::retry_cleanup(
  _self : NativeHttpClientCreateFailure,
) -> Result[Library, NativeHttpIssue] {
  Err(UnsupportedTarget)
}

///|
type Library

///|
type Client

///|
pub fn load_library(
  _path : String,
  diagnostic_ceiling? : Int? = None,
) -> Result[Library, NativeHttpIssue] {
  if diagnostic_ceiling is Some(value) && value <= 0 {
    return Err(InvalidConfiguration)
  }
  ignore(@utf8.encode(""))
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
pub fn Library::create_authenticated_client(
  _self : Library,
  _ca_path : String,
  _authentication : NativeHttpAuthentication,
  _max_response_bytes : Int64,
  _connect_timeout_ms : Int,
  _operation_timeout_ms : Int,
) -> Result[Client, NativeHttpIssue] {
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
pub fn Client::request(
  _self : Client,
  _verb : NativeHttpMethod,
  _url : String,
  _headers : Array[NativeHttpHeader],
  _body : Bytes,
) -> Result[NativeHttpResponse, NativeHttpIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Client::request_bearer_file(
  _self : Client,
  _verb : NativeHttpMethod,
  _url : String,
  _headers : Array[NativeHttpHeader],
  _body : Bytes,
  _secret_path : String,
  _expires_at_milliseconds : Int64,
) -> Result[NativeHttpResponse, NativeHttpIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Client::get_bearer_file(
  _self : Client,
  url : String,
  secret_path : String,
  expires_at_milliseconds : Int64,
) -> Result[NativeHttpResponse, NativeHttpIssue] {
  ignore(url)
  ignore(secret_path)
  ignore(expires_at_milliseconds)
  Err(UnsupportedTarget)
}

///|
pub fn Client::cancel(_self : Client) -> Bool {
  false
}

///|
pub fn Client::response_limit(_self : Client) -> Result[Int64, NativeHttpIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Client::close(_self : Client) -> Bool {
  false
}

///|
pub fn load_library_with_custody(
  _path : String,
  diagnostic_ceiling? : Int? = None,
) -> Result[Library, NativeHttpLibraryLoadError] {
  if diagnostic_ceiling is Some(value) && value <= 0 {
    return Err(RefusedBeforeAcquisition(InvalidConfiguration))
  }
  Err(RefusedBeforeAcquisition(UnsupportedTarget))
}

///|
pub fn Library::create_client_with_custody(
  _self : Library,
  _ca_path : String,
  _certificate_path : String,
  _key_path : String,
  _max_response_bytes : Int64,
  _connect_timeout_ms : Int,
  _operation_timeout_ms : Int,
) -> Result[Client, NativeHttpClientCreateError] {
  Err(RefusedBeforeAcquisition(UnsupportedTarget))
}

///|
pub fn Library::create_authenticated_client_with_custody(
  _self : Library,
  _ca_path : String,
  _authentication : NativeHttpAuthentication,
  _max_response_bytes : Int64,
  _connect_timeout_ms : Int,
  _operation_timeout_ms : Int,
) -> Result[Client, NativeHttpClientCreateError] {
  Err(RefusedBeforeAcquisition(UnsupportedTarget))
}

///|
pub fn Library::close_checked(_self : Library) -> Result[Unit, NativeHttpIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Client::close_checked(_self : Client) -> Result[Unit, NativeHttpIssue] {
  Err(UnsupportedTarget)
}
