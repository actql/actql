///|
type Root

///|
type Writer

///|
pub fn open_root(_path : String) -> Result[Root, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Root::create_writer(
  _self : Root,
  staging_name : String,
  max_bytes : Int64,
) -> Result[Writer, NativeFilesystemIssue] {
  ignore(staging_name)
  ignore(max_bytes)
  Err(UnsupportedTarget)
}

///|
pub fn Writer::append(
  _self : Writer,
  chunk : Bytes,
) -> Result[Unit, NativeFilesystemIssue] {
  ignore(chunk)
  Err(UnsupportedTarget)
}

///|
pub fn Writer::seal(
  _self : Writer,
  final_name : String,
) -> Result[NativeFileGeneration, NativeFilesystemIssue] {
  ignore(final_name)
  Err(UnsupportedTarget)
}

///|
pub fn Writer::cancel(_self : Writer) -> Result[Unit, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Writer::written(_self : Writer) -> Int64 {
  0L
}

///|
pub fn Writer::is_sealed(_self : Writer) -> Bool {
  false
}

///|
pub fn Writer::cleanup_pending(_self : Writer) -> Bool {
  false
}

///|
pub fn Root::verify_generation(
  _self : Root,
  name : String,
  generation : NativeFileGeneration,
) -> Bool {
  ignore(name)
  ignore(generation)
  false
}

///|
#warnings("-unused_value")
fn retain_native_import() -> Unit {
  ignore(@utf8.encode(""))
}
