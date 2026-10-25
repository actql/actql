///|
type Root

///|
type Lock

///|
type Writer

///|
type Reader

///|
pub fn Root::close(_self : Root) -> Result[Unit, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn open_root(
  _path : String,
  diagnostic_ceiling? : Int? = None,
) -> Result[Root, NativeFilesystemIssue] {
  if diagnostic_ceiling is Some(limit) && limit <= 0 {
    return Err(InvalidLimit)
  }
  Err(UnsupportedTarget)
}

///|
pub fn open_private_root(
  _path : String,
  diagnostic_ceiling? : Int? = None,
) -> Result[Root, NativeFilesystemIssue] {
  if diagnostic_ceiling is Some(limit) && limit <= 0 {
    return Err(InvalidLimit)
  }
  Err(UnsupportedTarget)
}

///|
pub fn open_private_root_with_custody(
  _path : String,
  diagnostic_ceiling? : Int? = None,
) -> Result[Root, NativeRootOpenFailure] {
  if diagnostic_ceiling is Some(limit) && limit <= 0 {
    return Err({ original_issue: InvalidLimit, root: None, })
  }
  Err({ original_issue: UnsupportedTarget, root: None, })
}

///|
pub fn Root::private_ownership(
  _self : Root,
) -> Result[NativeFileOwnership, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Root::bootstrap_parent_ownership(
  _self : Root,
) -> Result[NativeFileOwnership, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Root::acquire_lock(
  _self : Root,
  _name : String,
) -> Result[Lock, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Lock::close(_self : Lock) -> Bool {
  false
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
pub fn Writer::adopt_name(
  _self : Writer,
  _target : Root,
  _name : String,
) -> Result[Unit, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Root::create_directory(
  _self : Root,
  _name : String,
) -> Result[NativeFileOwnership, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Root::inspect_directory(
  _self : Root,
  _name : String,
) -> Result[NativeFileOwnership?, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Root::remove_directory(
  _self : Root,
  _name : String,
  _identity : NativeFileOwnership,
) -> Result[Bool, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Root::open_child(
  _self : Root,
  _name : String,
) -> Result[Root, NativeFilesystemIssue] {
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
pub fn Writer::ownership(_self : Writer) -> NativeFileOwnership {
  { device: 0UL, inode: 0UL, }
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
pub fn Root::inspect_generation(
  _self : Root,
  _name : String,
) -> Result[NativeFileGeneration?, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Root::sync_directory(
  _self : Root,
) -> Result[Unit, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Root::reclaim_generation(
  _self : Root,
  name : String,
  generation : NativeFileGeneration,
) -> Result[Unit, NativeFilesystemIssue] {
  ignore(name)
  ignore(generation)
  Err(UnsupportedTarget)
}

///|
pub fn Root::open_reader(
  _self : Root,
  name : String,
  generation : NativeFileGeneration,
) -> Result[Reader, NativeFilesystemIssue] {
  ignore(name)
  ignore(generation)
  Err(UnsupportedTarget)
}

///|
pub fn Root::open_reader_with_custody(
  _self : Root,
  _name : String,
  _generation : NativeFileGeneration,
) -> Result[Reader, NativeReaderOpenFailure] {
  Err(reader_open_failure(UnsupportedTarget))
}

///|
pub fn Reader::next(
  _self : Reader,
  max_bytes : Int,
) -> Result[NativeFileChunk, NativeFilesystemIssue] {
  ignore(max_bytes)
  Err(UnsupportedTarget)
}

///|
pub fn Reader::finish(_self : Reader) -> Result[Unit, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Reader::close(_self : Reader) -> Result[Unit, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
#warnings("-unused_value")
fn retain_native_import() -> Unit {
  ignore(@utf8.encode(""))
}

///|
pub fn open_root_with_custody(
  _path : String,
  diagnostic_ceiling? : Int? = None,
) -> Result[Root, NativeRootOpenFailure] {
  if diagnostic_ceiling is Some(limit) && limit <= 0 {
    return Err({ original_issue: InvalidLimit, root: None, })
  }
  Err({ original_issue: UnsupportedTarget, root: None, })
}

///|
pub fn Root::acquire_lock_with_custody(
  _self : Root,
  _name : String,
) -> Result[Lock, NativeLockOpenFailure] {
  Err({ original_issue: UnsupportedTarget, lock: None, })
}

///|
pub fn Lock::close_checked(_self : Lock) -> Result[Unit, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}
