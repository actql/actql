///|
pub fn Client::get_local_preparation(
  _self : Client,
  _url : String,
  _installation : @filesystem.PrivateFileProjection,
  _expires_at_milliseconds : Int64,
) -> Result[NativeHttpResponse, NativeHttpIssue] {
  Err(UnsupportedTarget)
}
