///|
/// Private constructor projection, never authority or a serialized pointer.
type ScopedReadAcquisition

///|
extern "C" fn current_read_available_ffi() -> Bool = "actql_native_filesystem_current_read_available"

///|
#borrow(root)
extern "C" fn root_is_scoped_ffi(root : Root) -> Bool = "actql_native_filesystem_root_is_scoped"

///|
#borrow(root)
extern "C" fn root_read_available_ffi(root : Root) -> Bool = "actql_native_filesystem_root_read_available"

///|
#borrow(reader)
extern "C" fn reader_read_available_ffi(reader : Reader) -> Bool = "actql_native_filesystem_reader_read_available"

///|
#borrow(path)
extern "C" fn acquire_current_root_ffi(
  path : Bytes,
  length : Int,
  diagnostic_ceiling : Int,
) -> ScopedReadAcquisition = "actql_native_filesystem_acquire_current_root"

///|
#borrow(root, name)
extern "C" fn acquire_scoped_reader_ffi(
  root : Root,
  name : Bytes,
  length : Int,
  device : UInt64,
  inode : UInt64,
  size : Int64,
) -> ScopedReadAcquisition = "actql_native_filesystem_acquire_scoped_reader"

///|
#borrow(result)
extern "C" fn acquisition_status_ffi(result : ScopedReadAcquisition) -> Int = "actql_native_filesystem_acquisition_status"

///|
#borrow(result)
extern "C" fn acquisition_has_original_ffi(
  result : ScopedReadAcquisition,
) -> Bool = "actql_native_filesystem_acquisition_has_original"

///|
#borrow(result)
extern "C" fn acquisition_root_ffi(result : ScopedReadAcquisition) -> Root = "actql_native_filesystem_acquisition_root"

///|
#borrow(result)
extern "C" fn acquisition_reader_ffi(result : ScopedReadAcquisition) -> Reader = "actql_native_filesystem_acquisition_reader"

///|
fn scoped_read_refusal(
  status : Int,
  reader? : Bool = false,
) -> NativeFilesystemIssue {
  if status == -4 {
    CapacityExceeded
  } else if reader {
    Read("Current read scope was refused")
  } else {
    RootOpen("Current read scope was refused")
  }
}

///|
/// The caller must enter its original Native Domain before this whole managed
/// call, and revalidate Core/current permission independently. This entrance
/// never creates a read context or adopts a profile. Stock/missing scope refuses
/// before encoding or Root acquisition; a rejected Root retains original custody.
pub fn open_root_in_current_read_context_with_custody(
  path : String,
  diagnostic_ceiling : Int,
) -> Result[Root, NativeRootOpenFailure] {
  if diagnostic_ceiling <= 0 {
    return Err({ original_issue: InvalidLimit, root: None, })
  }
  if !current_read_available_ffi() {
    return Err({ original_issue: scoped_read_refusal(-1), root: None, })
  }
  let encoded = @utf8.encode(path)
  let result = acquire_current_root_ffi(
    encoded,
    encoded.length(),
    diagnostic_ceiling,
  )
  let status = acquisition_status_ffi(result)
  guard acquisition_has_original_ffi(result) else {
    return Err({ original_issue: scoped_read_refusal(status), root: None, })
  }
  let root = acquisition_root_ffi(result)
  if status != 0 {
    Err({ original_issue: scoped_read_refusal(status), root: Some(root), })
  } else if root_ready_ffi(root) {
    Ok(root)
  } else {
    Err({
      original_issue: RootOpen(decode_diagnostic_message(root_error_ffi(root))),
      root: Some(root),
    })
  }
}

///|
fn open_scoped_reader_with_custody(
  root : Root,
  encoded : Bytes,
  generation : NativeFileGeneration,
) -> Result[Reader, NativeReaderOpenFailure] {
  let result = acquire_scoped_reader_ffi(
    root,
    encoded,
    encoded.length(),
    generation.device,
    generation.inode,
    generation.size,
  )
  let status = acquisition_status_ffi(result)
  guard acquisition_has_original_ffi(result) else {
    return Err(reader_open_failure(scoped_read_refusal(status, reader=true)))
  }
  let reader = acquisition_reader_ffi(result)
  if status != 0 {
    return Err({
      original_issue: scoped_read_refusal(status, reader=true),
      reader: Some(reader),
    })
  }
  if reader_ready_ffi(reader) {
    Ok(reader)
  } else {
    let message = decode_diagnostic_message(reader_open_error_ffi(reader))
    let issue = reader_open_issue(
      reader_open_kind(reader_open_kind_ffi(reader)),
      message,
    )
    let retained = match reader.close() {
      Ok(_) => None
      Err(_) => Some(reader)
    }
    Err({ original_issue: issue, reader: retained, })
  }
}
