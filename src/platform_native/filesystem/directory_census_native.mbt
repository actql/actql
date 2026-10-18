///|
#borrow(root, frame)
extern "C" fn directory_census_ffi(
  root : Root,
  frame : Bytes,
  length : Int,
  count : Int,
) -> Int = "actql_native_filesystem_directory_census"

///|
#borrow(root, frame)
extern "C" fn command_directory_census_ffi(
  root : Root,
  frame : Bytes,
  length : Int,
  count : Int,
) -> Int = "actql_native_filesystem_command_directory_census"

///|
// Census-only directory spelling required by the selected npm scope route.
// It does not change Writer/Reader/Store object names or select a package.
fn valid_census_member_name(entry : NativeDirectoryMember) -> Bool {
  valid_object_name(entry.name) ||
  (entry.kind == Directory && entry.name == "@actql")
}

///|
/// Compare a bounded expected set against this same opened Root. Unknown names
/// are not accumulated. This does not verify the Root's named namespace, file
/// modes/bytes/hashes or provide a complete-product witness or permission.
/// Entries use the formal inventory's ASCII name order, not Core shortlex.
/// The caller must retain the same Root on cleanup error until its actual ACK.
pub fn Root::check_directory_members(
  self : Root,
  expected : Array[NativeDirectoryMember],
  command_preparation? : Bool = false,
) -> Result[Unit, NativeFilesystemIssue] {
  // Existing product inventory intake ceilings only; not workspace funding.
  if expected.length() > (8192 - 5) / 5 {
    return Err(CapacityExceeded)
  }
  let mut size = 0
  for entry in expected {
    if !valid_census_member_name(entry) {
      return Err(InvalidName)
    }
    if size > 65536 - entry.name.length() - 2 {
      return Err(CapacityExceeded)
    }
    size += entry.name.length() + 2
  }
  let frame : Array[Byte] = []
  for entry in expected {
    frame.push(
      match entry.kind {
        File => b'f'
        Directory => b'd'
      },
    )
    for byte in @utf8.encode(entry.name) {
      frame.push(byte)
    }
    frame.push(b'\x00')
  }
  let bytes = Bytes::from_array(frame)
  let observed = if command_preparation {
    command_directory_census_ffi(self, bytes, bytes.length(), expected.length())
  } else {
    directory_census_ffi(self, bytes, bytes.length(), expected.length())
  }
  match observed {
    0 => Ok(())
    1 => Err(GenerationMismatch)
    2 => Err(CapacityExceeded)
    3 => Err(Cleanup(decode_diagnostic_message(root_error_ffi(self))))
    4 => Err(InvalidName)
    _ => Err(Read(decode_diagnostic_message(root_error_ffi(self))))
  }
}
