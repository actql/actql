///|
/// Physical failures from reading one exact immutable file generation. The
/// caller owns the semantic interpretation of the returned UTF-8 text.
pub(all) enum NativeBoundedTextIssue {
  InvalidLimit
  Missing
  CapacityExceeded
  Filesystem(@filesystem.NativeFilesystemIssue)
  Cleanup(@filesystem.NativeFilesystemIssue, @filesystem.NativeFilesystemIssue)
  InvalidUtf8
}

///|
/// A failed bounded read and, when close was not acknowledged, its original
/// Reader. This is custody of the existing filesystem Owner, not a replacement
/// read operation. The original issue remains available after cleanup.
struct NativeBoundedTextFailure {
  original_issue : NativeBoundedTextIssue
  mut reader : @filesystem.Reader?
}

///|
pub fn NativeBoundedTextFailure::issue(
  self : NativeBoundedTextFailure,
) -> NativeBoundedTextIssue {
  self.original_issue
}

///|
/// Re-observes close on the same Reader; an unconfirmed close does not reopen
/// or re-read the file. Only acknowledged close drops this retained reference.
/// The caller still owns retirement of its buffers and capacity reservation.
pub fn NativeBoundedTextFailure::retry_cleanup(
  self : NativeBoundedTextFailure,
) -> Result[Unit, @filesystem.NativeFilesystemIssue] {
  guard self.reader is Some(reader) else { return Ok(()) }
  match reader.close() {
    Ok(_) => {
      self.reader = None
      Ok(())
    }
    Err(issue) => Err(issue)
  }
}

///|
fn bounded_text_failure(
  issue : NativeBoundedTextIssue,
) -> NativeBoundedTextFailure {
  { original_issue: issue, reader: None, }
}

///|
fn close_failed_bounded_reader(
  reader : @filesystem.Reader,
  issue : @filesystem.NativeFilesystemIssue,
) -> NativeBoundedTextFailure {
  match reader.close() {
    Ok(_) => bounded_text_failure(Filesystem(issue))
    Err(cleanup) =>
      { original_issue: Cleanup(issue, cleanup), reader: Some(reader), }
  }
}

///|
fn trim_terminal_newline(value : String) -> String {
  let without_newline = match value.strip_suffix("\n") {
    Some(text) => text.to_owned()
    None => value
  }
  match without_newline.strip_suffix("\r") {
    Some(text) => text.to_owned()
    None => without_newline
  }
}

///|
/// Reads one exact generation through bounded chunks. Size is checked before
/// allocation, and a failed read retains its close failure as a separate
/// physical fact instead of treating callback return as reader stop.
pub fn read_bounded_text_file(
  root_path : String,
  name : String,
  max_bytes : Int64,
  trim_newline? : Bool = false,
) -> Result[String, NativeBoundedTextIssue] {
  match
    read_bounded_text_file_with_custody(
      root_path,
      name,
      max_bytes,
      trim_newline~,
    ) {
    Ok(text) => Ok(text)
    Err(failure) => Err(failure.issue())
  }
}

///|
/// The same bounded read algorithm, retaining the original Reader on cleanup
/// failure so a funded caller can keep its operation pending. Selection, UTF-8,
/// generation and chunk/byte limits are identical to the issue-only entry.
pub fn read_bounded_text_file_with_custody(
  root_path : String,
  name : String,
  max_bytes : Int64,
  trim_newline? : Bool = false,
) -> Result[String, NativeBoundedTextFailure] {
  if max_bytes <= 0L {
    return Err(bounded_text_failure(InvalidLimit))
  }
  let root = match @filesystem.open_root(root_path) {
    Ok(value) => value
    Err(issue) => return Err(bounded_text_failure(Filesystem(issue)))
  }
  let generation = match root.inspect_generation(name) {
    Ok(Some(value)) => value
    Ok(None) => return Err(bounded_text_failure(Missing))
    Err(issue) => return Err(bounded_text_failure(Filesystem(issue)))
  }
  if generation.size < 0L || generation.size > max_bytes {
    return Err(bounded_text_failure(CapacityExceeded))
  }
  let reader = match root.open_reader(name, generation) {
    Ok(value) => value
    Err(issue) => return Err(bounded_text_failure(Filesystem(issue)))
  }
  let bytes : Array[Byte] = []
  let mut done = false
  while !done {
    let chunk = match reader.next(65536) {
      Ok(value) => value
      Err(issue) => return Err(close_failed_bounded_reader(reader, issue))
    }
    for byte in chunk.bytes {
      bytes.push(byte)
    }
    done = chunk.eof
  }
  match reader.finish() {
    Ok(_) => ()
    Err(issue) => return Err(close_failed_bounded_reader(reader, issue))
  }
  let text = @utf8.decode(Bytes::from_array(bytes)) catch {
    _ => return Err(bounded_text_failure(InvalidUtf8))
  }
  Ok(if trim_newline { trim_terminal_newline(text) } else { text })
}
