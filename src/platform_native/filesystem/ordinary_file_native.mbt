///|
// An ordinary path's basename, not an internal Store object identifier. Keep
// exact Unicode and whitespace; the actual filesystem decides its name limit.
// Traversal, separators and NUL cannot name one child of this original Root.
fn valid_file_component(name : String) -> Bool {
  if name.is_empty() || name == "." || name == ".." {
    return false
  }
  for character in name.iter() {
    if character == '/' || character.to_int() == 0 {
      return false
    }
  }
  true
}

///|
/// Seal to one ordinary basename through the same exclusive link, original
/// generation and pending-cleanup path. This never replaces an existing name.
pub fn Writer::seal_file(
  self : Writer,
  name : String,
) -> Result[NativeFileGeneration, NativeFilesystemIssue] {
  if !valid_file_component(name) {
    return Err(InvalidName)
  }
  self.seal_named_file(name)
}

///|
pub fn Root::inspect_file_generation(
  self : Root,
  name : String,
) -> Result[NativeFileGeneration?, NativeFilesystemIssue] {
  if !valid_file_component(name) {
    return Err(InvalidName)
  }
  self.inspect_named_file_generation(name)
}

///|
pub fn Root::verify_file_generation(
  self : Root,
  name : String,
  generation : NativeFileGeneration,
) -> Bool {
  if !valid_file_component(name) {
    return false
  }
  self.verify_named_file_generation(name, generation)
}

///|
/// The same exact generation and entered-read constructor. Failed acquisition
/// retains its original Reader and cleanup issue; the name issues no authority.
pub fn Root::open_file_reader_with_custody(
  self : Root,
  name : String,
  generation : NativeFileGeneration,
) -> Result[Reader, NativeReaderOpenFailure] {
  if !valid_file_component(name) {
    return Err(reader_open_failure(InvalidName))
  }
  self.open_named_file_reader_with_custody(name, generation)
}
