///|
pub fn Writer::close_retaining_files(
  _self : Writer,
) -> Result[Unit, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Root::create_writer_with_custody(
  _self : Root,
  _staging_name : String,
  _max_bytes : Int64,
) -> Result[Writer, NativeWriterOpenFailure] {
  Err({ original_issue: UnsupportedTarget, writer: None, })
}
