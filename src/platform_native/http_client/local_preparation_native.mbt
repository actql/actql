///|
#borrow(client, encoded_method, url, headers, body, installation)
extern "C" fn get_local_preparation_ffi(
  client : Client,
  encoded_method : Bytes,
  method_length : Int,
  url : Bytes,
  url_length : Int,
  headers : Bytes,
  headers_length : Int,
  body : Bytes,
  body_length : Int,
  installation : @filesystem.PrivateFileProjection,
  expires_at_milliseconds : Int64,
) -> Int = "actql_native_http_client_get_local_preparation"

///|
/// Read-only Local preparation uses the original private-root installation,
/// never a newly resolved path or caller-authored generation. Ordinary bearer
/// requests retain their existing rotation behavior. Host authorization,
/// durable use claims and cancellation remain the credential Owner's duties.
pub fn Client::get_local_preparation(
  self : Client,
  url : String,
  installation : @filesystem.PrivateFileProjection,
  expires_at_milliseconds : Int64,
) -> Result[NativeHttpResponse, NativeHttpIssue] {
  if !url.has_prefix("https://") ||
    url.length() > 8192 ||
    url.contains("\u{0}") ||
    expires_at_milliseconds < 1L {
    return Err(InvalidRequest)
  }
  let encoded_method = b"GET"
  let headers = b"accept: application/json\n"
  let body = b""
  let encoded_url = @utf8.encode(url)
  match
    get_local_preparation_ffi(
      self,
      encoded_method,
      encoded_method.length(),
      encoded_url,
      encoded_url.length(),
      headers,
      headers.length(),
      body,
      body.length(),
      installation,
      expires_at_milliseconds,
    ) {
    0 => Ok({ status: client_status_ffi(self), body: client_body_ffi(self), })
    1 => Err(CapacityExceeded)
    2 => Err(Cancelled)
    3 => Err(Closed)
    4 => Err(DeadlineExpired)
    5 => Err(CredentialUnavailable)
    6 => Err(InvalidRequest)
    _ => Err(Transport(decode_message(client_error_ffi(self))))
  }
}
