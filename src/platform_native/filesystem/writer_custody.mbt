///|
/// Original rejected Writer, not write authority. Cleanup only retires its FD;
/// partial names and the caller's unresolved initialization remain retained.
struct NativeWriterOpenFailure {
  original_issue : NativeFilesystemIssue
  mut writer : Writer?
}

///|
pub fn NativeWriterOpenFailure::issue(
  self : NativeWriterOpenFailure,
) -> NativeFilesystemIssue {
  self.original_issue
}

///|
pub fn NativeWriterOpenFailure::retry_cleanup(
  self : NativeWriterOpenFailure,
) -> Result[Unit, NativeFilesystemIssue] {
  guard self.writer is Some(writer) else { return Ok(()) }
  match writer.close_retaining_files() {
    Err(issue) => Err(issue)
    Ok(_) => {
      self.writer = None
      Ok(())
    }
  }
}
