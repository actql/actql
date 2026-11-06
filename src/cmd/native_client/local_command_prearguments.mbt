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
extern "C" fn command_compiled_platform_ffi() -> Int = "actql_native_client_compiled_platform"

///|
fn command_compiled_platform_matches(platform : String) -> Bool {
  match command_compiled_platform_ffi() {
    1 => platform == "darwin-arm64"
    2 => platform == "linux-x64-gnu"
    _ => false
  }
}

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
// The compiled source and bounded launcher context belong to the explicit
// initial argument/control inventory. Neither supplies physical authority.
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
fn command_preargument_context() -> Result[String, LocalCommandPreparationIssue] {
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

///|
extern "C" fn command_preargument_selection_ffi() -> Int = "actql_native_client_preargument_selection"

///|
// Selected input consumes the same bounded original bytes even after another
// initializer changes the environment. None means genuinely unselected; an
// invalid or missing original must not enter that compatibility path.
fn command_preargument_retained_context() -> Result[
  String?,
  LocalCommandPreparationIssue,
] {
  match command_preargument_selection_ffi() {
    0 => command_preargument_context().map(value => Some(value))
    5 => Ok(None)
    _ => Err(CommandUnavailable)
  }
}

///|
// This entrance performs only the original raw observation. Its caller must
// account for the pinned parser and all decoded/control aliases separately;
// input ceilings are not backing or a managed-heap capacity claim.
fn command_preargument_bound(
  maximum_arguments : Int,
  maximum_argument_bytes : Int,
  maximum_storage_bytes : Int,
  maximum_context_bytes : Int,
) -> Result[Bool, LocalCommandPreparationIssue] {
  match
    command_preargument_measure_ffi(
      maximum_arguments, maximum_argument_bytes, maximum_storage_bytes, maximum_context_bytes,
    ) {
    0 => Ok(true)
    5 => Ok(false)
    _ => Err(CommandUnavailable)
  }
}

///|
extern "C" fn command_preargument_class_ffi(field : Int) -> Int64 = "actql_native_client_preargument_class_bytes"

///|
// Same original measured argv only. These partial class terms exclude the
// complete Command/Matches/render graph and do not admit physical resources.
priv struct LocalCommandArgumentClasses {
  arguments : Int
  original_storage_bytes : Int
  raw_reference_bytes : Int64
  raw_bytes : Int64
  decode_overlap_bytes : Int64
  argument_growth_bytes : Int64
}

///|
fn command_preargument_classes() -> Result[
  LocalCommandArgumentClasses,
  LocalCommandPreparationIssue,
] {
  let arguments = command_preargument_count_ffi()
  let original_storage_bytes = command_preargument_storage_ffi()
  let raw_reference_bytes = command_preargument_class_ffi(0)
  let raw_bytes = command_preargument_class_ffi(1)
  let decode_overlap_bytes = command_preargument_class_ffi(2)
  let argument_growth_bytes = command_preargument_class_ffi(3)
  if arguments <= 0 ||
    original_storage_bytes < arguments ||
    raw_reference_bytes <= 0L ||
    raw_bytes <= 0L ||
    decode_overlap_bytes <= 0L ||
    argument_growth_bytes <= 0L {
    return Err(CommandUnavailable)
  }
  Ok({
    arguments,
    original_storage_bytes,
    raw_reference_bytes,
    raw_bytes,
    decode_overlap_bytes,
    argument_growth_bytes,
  })
}

///|
#borrow(bytes)
extern "C" fn command_bounded_home_ffi(bytes : Bytes, length : Int) -> Int = "actql_native_client_copy_bounded_home"

///|
// Same lossy OS-string conversion as the pinned env implementation, after the
// raw bound. This path selection is metadata, never original Store authority.
fn local_product_bounded_home() -> String? raise ClientStop {
  let maximum = 4096 * 3 + 3
  let bytes = Bytes::make(maximum, 0)
  let length = command_bounded_home_ffi(bytes, maximum)
  if length == -1 {
    return None
  }
  if length < 0 || length > maximum {
    stop("LocalProductHomeUnavailable")
  }
  Some(@utf8.decode_lossy(bytes[0:length]))
}
