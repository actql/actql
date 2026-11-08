///|
priv type NativeObservedFileStat

///|
/// Actual current file facts owned by the same Root, never restored from a
/// public generation/CID. This is not private-key installation custody or a
/// complete named-namespace/package/authority witness.
struct NativeFileObservation {
  root : Root
  name : String
  stat : NativeObservedFileStat
}

///|
#borrow(writer, root, name, stat, lock)
extern "C" fn replace_observed_file_ffi(
  writer : Writer,
  root : Root,
  name : Bytes,
  length : Int,
  stat : NativeObservedFileStat,
  lock : Lock,
) -> Int = "actql_native_filesystem_replace_observed_file"

///|
/// Replace the SAME observed ordinary file under its already held same-Root
/// `<name>.actql-write.lock` original. This is physical I/O, not approval or a
/// dispatch claim. The caller must enter its original durable claim before
/// calling. An attempt is
/// never replayed, including after an ambiguous sync failure; cleanup only
/// retires the original staging writer and never removes the replaced target.
pub fn Writer::replace_observed_file(
  self : Writer,
  original : NativeFileObservation,
  lock : Lock,
) -> Result[NativeFileGeneration, NativeFilesystemIssue] {
  let name = @utf8.encode(original.name)
  match
    replace_observed_file_ffi(
      self,
      original.root,
      name,
      name.length(),
      original.stat,
      lock,
    ) {
    0 =>
      Ok({
        device: writer_device_ffi(self),
        inode: writer_inode_ffi(self),
        size: writer_written_ffi(self),
      })
    2 => Err(GenerationMismatch)
    3 => Err(WriterClosed)
    _ => Err(Write(writer_message(self)))
  }
}

///|
#borrow(root, name)
extern "C" fn observe_file_ffi(
  root : Root,
  name : Bytes,
  length : Int,
) -> NativeObservedFileStat = "actql_native_filesystem_observe_file"

///|
#borrow(stat)
extern "C" fn observed_file_kind_ffi(stat : NativeObservedFileStat) -> Int = "actql_native_filesystem_observed_file_kind"

///|
#borrow(stat)
extern "C" fn observed_file_device_ffi(stat : NativeObservedFileStat) -> UInt64 = "actql_native_filesystem_observed_file_device"

///|
#borrow(stat)
extern "C" fn observed_file_inode_ffi(stat : NativeObservedFileStat) -> UInt64 = "actql_native_filesystem_observed_file_inode"

///|
#borrow(stat)
extern "C" fn observed_file_size_ffi(stat : NativeObservedFileStat) -> Int64 = "actql_native_filesystem_observed_file_size"

///|
#borrow(stat)
extern "C" fn observed_file_mode_ffi(stat : NativeObservedFileStat) -> Int = "actql_native_filesystem_observed_file_mode"

///|
#borrow(root, name, stat)
extern "C" fn observed_file_current_ffi(
  root : Root,
  name : Bytes,
  length : Int,
  stat : NativeObservedFileStat,
) -> Int = "actql_native_filesystem_observed_file_current"

///|
#borrow(root, reader, stat)
extern "C" fn observed_file_reader_ffi(
  root : Root,
  reader : Reader,
  stat : NativeObservedFileStat,
) -> Bool = "actql_native_filesystem_observed_file_reader"

///|
fn observed_file_issue(root : Root, kind : Int) -> NativeFilesystemIssue {
  match kind {
    1 => GenerationMismatch
    3 => Cleanup(decode_diagnostic_message(root_error_ffi(root)))
    _ => Read(decode_diagnostic_message(root_error_ffi(root)))
  }
}

///|
pub fn Root::observe_file(
  self : Root,
  name : String,
) -> Result[NativeFileObservation, NativeFilesystemIssue] {
  if !valid_object_name(name) {
    return Err(InvalidName)
  }
  let bytes = @utf8.encode(name)
  let stat = observe_file_ffi(self, bytes, bytes.length())
  let kind = observed_file_kind_ffi(stat)
  if kind == 0 {
    Ok({ root: self, name, stat, })
  } else {
    Err(observed_file_issue(self, kind))
  }
}

///|
pub fn NativeFileObservation::generation(
  self : NativeFileObservation,
) -> Result[NativeFileGeneration, NativeFilesystemIssue] {
  Ok({
    device: observed_file_device_ffi(self.stat),
    inode: observed_file_inode_ffi(self.stat),
    size: observed_file_size_ffi(self.stat),
  })
}

///|
/// Exact permission/special mode bits observed, not permission to use the file.
pub fn NativeFileObservation::mode(
  self : NativeFileObservation,
) -> Result[Int, NativeFilesystemIssue] {
  Ok(observed_file_mode_ffi(self.stat))
}

///|
pub fn NativeFileObservation::check_current(
  self : NativeFileObservation,
) -> Result[Unit, NativeFilesystemIssue] {
  let name = @utf8.encode(self.name)
  let kind = observed_file_current_ffi(
    self.root,
    name,
    name.length(),
    self.stat,
  )
  if kind == 0 {
    Ok(())
  } else {
    Err(observed_file_issue(self.root, kind))
  }
}

///|
/// Open through the existing Reader constructor, then compare the actual opened
/// file to the same full original stat. A rejected Reader keeps its own cleanup
/// carrier, including a missing close acknowledgement.
pub fn NativeFileObservation::open_reader_with_custody(
  self : NativeFileObservation,
) -> Result[Reader, NativeReaderOpenFailure] {
  if self.check_current() is Err(issue) {
    return Err(reader_open_failure(issue))
  }
  let generation = match self.generation() {
    Ok(value) => value
    Err(issue) => return Err(reader_open_failure(issue))
  }
  match self.root.open_reader_with_custody(self.name, generation) {
    Err(failure) => Err(failure)
    Ok(reader) => {
      let matches = observed_file_reader_ffi(self.root, reader, self.stat)
      let issue = match self.check_current() {
        Err(issue) => Some(issue)
        Ok(_) => if matches { None } else { Some(GenerationMismatch) }
      }
      match issue {
        None => Ok(reader)
        Some(issue) => {
          let failure = reader_open_failure(issue)
          if reader.close() is Err(_) {
            failure.reader = Some(reader)
          }
          Err(failure)
        }
      }
    }
  }
}

///|
/// Compare the same reader after bounded consumption, before its finish/close.
pub fn NativeFileObservation::check_reader(
  self : NativeFileObservation,
  reader : Reader,
) -> Result[Unit, NativeFilesystemIssue] {
  if self.check_current() is Err(issue) {
    return Err(issue)
  }
  if observed_file_reader_ffi(self.root, reader, self.stat) {
    Ok(())
  } else {
    Err(GenerationMismatch)
  }
}

///|
/// Private command-loader observation. It carries existing Root/stat aliases,
/// not an initial operational original or permission to call the loader.
type NativeObservedComponentMember

///|
#borrow(root, stat, name, source, manifest, digest)
extern "C" fn observed_component_member_ffi(
  root : Root,
  stat : NativeObservedFileStat,
  name : Bytes,
  length : Int,
  kind : Int,
  source : Bytes,
  manifest : Bytes,
  digest : Bytes,
) -> NativeObservedComponentMember = "actql_native_filesystem_observed_component_member"

///|
/// Internal Runtime assembly only: the caller has already checked the complete
/// Reader digest against the admitted member. This projection supplies physical
/// file correspondence; the trusted entry must independently admit its original
/// initial envelope before any selected load.
pub fn NativeFileObservation::command_component_member(
  self : NativeFileObservation,
  kind : Int,
  source : String,
  manifest : String,
  digest : String,
) -> Result[NativeObservedComponentMember, NativeFilesystemIssue] {
  match self.check_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let name = @utf8.encode(self.name)
  Ok(
    observed_component_member_ffi(
      self.root,
      self.stat,
      name,
      name.length(),
      kind,
      @utf8.encode(source),
      @utf8.encode(manifest),
      @utf8.encode(digest),
    ),
  )
}
