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
  if max_bytes <= 0L {
    return Err(InvalidLimit)
  }
  let root = match @filesystem.open_root(root_path) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let generation = match root.inspect_generation(name) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Missing)
    Err(issue) => return Err(Filesystem(issue))
  }
  if generation.size < 0L || generation.size > max_bytes {
    return Err(CapacityExceeded)
  }
  let reader = match root.open_reader(name, generation) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let bytes : Array[Byte] = []
  let mut done = false
  while !done {
    let chunk = match reader.next(65536) {
      Ok(value) => value
      Err(issue) =>
        return match reader.close() {
          Ok(_) => Err(Filesystem(issue))
          Err(cleanup) => Err(Cleanup(issue, cleanup))
        }
    }
    for byte in chunk.bytes {
      bytes.push(byte)
    }
    done = chunk.eof
  }
  match reader.finish() {
    Ok(_) => ()
    Err(issue) =>
      return match reader.close() {
        Ok(_) => Err(Filesystem(issue))
        Err(cleanup) => Err(Cleanup(issue, cleanup))
      }
  }
  let text = @utf8.decode(Bytes::from_array(bytes)) catch {
    _ => return Err(InvalidUtf8)
  }
  Ok(if trim_newline { trim_terminal_newline(text) } else { text })
}
