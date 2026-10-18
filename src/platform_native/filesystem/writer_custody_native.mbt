///|
#borrow(writer)
extern "C" fn writer_close_retaining_files_ffi(writer : Writer) -> Int = "actql_native_filesystem_writer_close_retaining_files"

///|
/// Preserve partial names even on finalization. Ok acknowledges only this
/// original FD and directory sync, never complete contents or namespace cleanup.
/// Write/seal are fenced; explicit cancellation is a separate original operation.
pub fn Writer::close_retaining_files(
  self : Writer,
) -> Result[Unit, NativeFilesystemIssue] {
  if writer_close_retaining_files_ffi(self) == 0 {
    Ok(())
  } else {
    Err(Cleanup(writer_message(self)))
  }
}

///|
/// Same exclusive constructor, retaining its actual object on failure. The
/// primary issue and any later close refusal are independent observations.
pub fn Root::create_writer_with_custody(
  self : Root,
  staging_name : String,
  max_bytes : Int64,
) -> Result[Writer, NativeWriterOpenFailure] {
  if !valid_object_name(staging_name) {
    return Err({ original_issue: InvalidName, writer: None, })
  }
  if max_bytes < 0L {
    return Err({ original_issue: InvalidLimit, writer: None, })
  }
  let encoded = @utf8.encode(staging_name)
  let writer = create_writer_ffi(self, encoded, encoded.length(), max_bytes)
  if writer_ready_ffi(writer) {
    return Ok(writer)
  }
  let issue = if writer_conflict_ffi(writer) {
    Conflict
  } else {
    WriterCreate(writer_message(writer))
  }
  Err({ original_issue: issue, writer: Some(writer), })
}
