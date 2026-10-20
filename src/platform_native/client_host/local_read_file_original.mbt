///|
fn local_read_file_unsigned_identity(value : String) -> Bool {
  if value.is_empty() ||
    value.length() > 20 ||
    (value.length() > 1 && value[0] == '0') {
    return false
  }
  for unit in value.code_units() {
    if unit < 48 || unit > 57 {
      return false
    }
  }
  value.length() < 20 ||
  @canonical_value.compare_utf16(value, "18446744073709551615") <= 0
}

///|
fn local_read_file_name(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 4096 &&
  value != "." &&
  value != ".." &&
  !value.contains("/") &&
  !value.contains("\\") &&
  !value.contains("\u{0000}")
}

///|
fn local_read_file_location(
  path : String,
  parent : String,
  name : String,
) -> Bool {
  if path.length() > 4096 ||
    !parent.has_prefix("/") ||
    parent.contains("\\") ||
    parent.contains("\u{0000}") ||
    !local_read_file_name(name) ||
    path != (if parent == "/" { "/" + name } else { parent + "/" + name }) {
    return false
  }
  if parent != "/" {
    if parent.has_suffix("/") || parent.contains("//") {
      return false
    }
    for part in parent.split("/") {
      if part == "." || part == ".." {
        return false
      }
    }
  }
  true
}

///|
// Inverse of the private evidence DATA only. In particular, this function
// never opens a pathname or restores live Writer/Root custody from an inode.
fn read_local_file_destination_original(
  fields : @decode.ObjectView,
) -> Result[NativeLocalReadFileOriginal, NativeClientRunJournalIssue] {
  guard epoch_text(fields, "destination_path") is Some(path) &&
    epoch_text(fields, "destination_name") is Some(name) &&
    epoch_text(fields, "destination_staging_name") is Some(staging_name) &&
    epoch_text(fields, "destination_parent_device") is Some(parent_device) &&
    epoch_text(fields, "destination_parent_inode") is Some(parent_inode) &&
    epoch_text(fields, "destination_writer_device") is Some(writer_device) &&
    epoch_text(fields, "destination_writer_inode") is Some(writer_inode) &&
    local_read_file_name(name) &&
    local_read_file_name(staging_name) &&
    name != staging_name &&
    path.has_suffix("/" + name) else {
    return Err(CustodyLost)
  }
  let prefix = path[:path.length() - name.length() - 1].to_owned()
  let parent = if prefix.is_empty() { "/" } else { prefix }
  if !local_read_file_location(path, parent, name) {
    return Err(CustodyLost)
  }
  for value in [parent_device, parent_inode, writer_device, writer_inode] {
    if !local_read_file_unsigned_identity(value) {
      return Err(CustodyLost)
    }
  }
  Ok({
    path,
    name,
    staging_name,
    parent_device,
    parent_inode,
    writer_device,
    writer_inode,
  })
}
