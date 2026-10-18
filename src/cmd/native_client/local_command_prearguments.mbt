///|
// Private source-pinned installer entrance. These raw observations are DATA,
// never a Host, backing, Read, capacity claim or acknowledgement.
extern "C" fn command_preargument_measure_ffi(
  maximum_arguments : Int,
  maximum_argument_bytes : Int,
  maximum_storage_bytes : Int,
  maximum_context_bytes : Int,
) -> Int = "actql_native_client_measure_prearguments"

///|
extern "C" fn command_preargument_count_ffi() -> Int = "actql_native_client_preargument_count"

///|
extern "C" fn command_preargument_storage_ffi() -> Int = "actql_native_client_preargument_storage_bytes"

///|
extern "C" fn command_preargument_context_size_ffi() -> Int = "actql_native_client_preargument_context_bytes"

///|
#borrow(bytes)
extern "C" fn command_preargument_source_ffi(
  bytes : Bytes,
  length : Int,
) -> Bool = "actql_native_client_copy_preargument_source"

///|
#borrow(bytes)
extern "C" fn command_preargument_context_ffi(
  bytes : Bytes,
  length : Int,
) -> Bool = "actql_native_client_copy_preargument_context"

///|
// Only the fixed 40-byte compiled source joins the declared initial control
// graph. The launcher context and argv are not copied at this boundary.
fn command_preargument_source() -> Result[String, LocalCommandPreparationIssue] {
  let bytes = Bytes::make(40, 0)
  if !command_preargument_source_ffi(bytes, bytes.length()) {
    return Err(CommandUnavailable)
  }
  Ok(@utf8.decode(bytes)) catch {
    _ => Err(CommandUnavailable)
  }
}

///|
fn LocalCommandPreparationOriginal::preargument_context(
  self : LocalCommandPreparationOriginal,
) -> Result[String, LocalCommandPreparationIssue] {
  if !self.prearguments_open ||
    self.closing ||
    self.closed ||
    self.primary is Some(_) {
    return Err(CommandUnavailable)
  }
  let length = command_preargument_context_size_ffi()
  if length <= 0 || length > 8192 {
    return Err(CommandUnavailable)
  }
  let bytes = Bytes::make(length, 0)
  if !command_preargument_context_ffi(bytes, length) {
    return Err(CommandUnavailable)
  }
  Ok(@utf8.decode(bytes)) catch {
    _ => Err(CommandUnavailable)
  }
}
