///|
pub fn Writer::seal_file(
  _self : Writer,
  _name : String,
) -> Result[NativeFileGeneration, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Root::inspect_file_generation(
  _self : Root,
  _name : String,
) -> Result[NativeFileGeneration?, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Root::verify_file_generation(
  _self : Root,
  _name : String,
  _generation : NativeFileGeneration,
) -> Bool {
  false
}

///|
pub fn Root::open_file_reader_with_custody(
  _self : Root,
  _name : String,
  _generation : NativeFileGeneration,
) -> Result[Reader, NativeReaderOpenFailure] {
  Err(reader_open_failure(UnsupportedTarget))
}
