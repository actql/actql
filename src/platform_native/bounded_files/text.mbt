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
  PreparationUnavailable
}

///|
/// A failed bounded read and, when close was not acknowledged, its original
/// Reader/directory. This is custody of the existing filesystem Owners, not a replacement
/// read operation. The original issue remains available after cleanup.
struct NativeBoundedTextFailure {
  original_issue : NativeBoundedTextIssue
  mut reader : @filesystem.Reader?
  mut rejected_reader : @filesystem.NativeReaderOpenFailure?
  mut root : @filesystem.Root?
  mut rejected_root : @filesystem.NativeRootOpenFailure?
  original_root_cleanup_issue : @filesystem.NativeFilesystemIssue?
}

///|
/// Separate directory cleanup evidence; never a replacement for the original
/// read/refusal or a claim that a child Reader has stopped.
pub fn NativeBoundedTextFailure::root_cleanup_issue(
  self : NativeBoundedTextFailure,
) -> @filesystem.NativeFilesystemIssue? {
  self.original_root_cleanup_issue
}

///|
pub fn NativeBoundedTextFailure::issue(
  self : NativeBoundedTextFailure,
) -> NativeBoundedTextIssue {
  self.original_issue
}

///|
/// Re-observes close on the same Reader; an unconfirmed close does not reopen
/// or re-read the file. Only acknowledged close drops each retained reference.
/// The caller still owns retirement of its buffers and capacity reservation.
pub fn NativeBoundedTextFailure::retry_cleanup(
  self : NativeBoundedTextFailure,
) -> Result[Unit, @filesystem.NativeFilesystemIssue] {
  let mut first_issue : @filesystem.NativeFilesystemIssue? = None
  if self.reader is Some(reader) {
    match reader.close() {
      Ok(_) => self.reader = None
      Err(issue) => return Err(issue)
    }
  }
  if self.rejected_reader is Some(rejected) {
    match rejected.retry_cleanup() {
      Ok(_) => self.rejected_reader = None
      Err(issue) => return Err(issue)
    }
  }
  if self.root is Some(root) {
    match root.close() {
      Ok(_) => self.root = None
      Err(issue) => if first_issue is None { first_issue = Some(issue) }
    }
  }
  if self.rejected_root is Some(rejected) {
    match rejected.retry_cleanup() {
      Ok(_) => self.rejected_root = None
      Err(issue) => if first_issue is None { first_issue = Some(issue) }
    }
  }
  match first_issue {
    Some(issue) => Err(issue)
    None => Ok(())
  }
}

///|
fn bounded_text_failure(
  issue : NativeBoundedTextIssue,
) -> NativeBoundedTextFailure {
  {
    original_issue: issue,
    reader: None,
    rejected_reader: None,
    root: None,
    rejected_root: None,
    original_root_cleanup_issue: None,
  }
}

///|
fn close_bounded_root_after_failure(
  root : @filesystem.Root,
  failure : NativeBoundedTextFailure,
) -> NativeBoundedTextFailure {
  match root.close() {
    Ok(_) => failure
    Err(issue) =>
      {
        original_issue: failure.original_issue,
        reader: failure.reader,
        rejected_reader: failure.rejected_reader,
        root: Some(root),
        rejected_root: failure.rejected_root,
        original_root_cleanup_issue: Some(issue),
      }
  }
}

///|
fn close_failed_bounded_reader(
  root : @filesystem.Root,
  reader : @filesystem.Reader,
  issue : @filesystem.NativeFilesystemIssue,
) -> NativeBoundedTextFailure {
  match reader.close() {
    Ok(_) =>
      close_bounded_root_after_failure(
        root,
        bounded_text_failure(Filesystem(issue)),
      )
    Err(cleanup) =>
      {
        // Keep the original parent until this Reader's own retirement is ACKed.
        // Parent close does not prove child stop and cannot retire its references.
        original_issue: Cleanup(issue, cleanup),
        reader: Some(reader),
        rejected_reader: None,
        root: Some(root),
        rejected_root: None,
        original_root_cleanup_issue: None,
      }
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
  diagnostic_ceiling? : Int? = None,
) -> Result[String, NativeBoundedTextIssue] {
  match
    read_bounded_text_file_with_custody(
      root_path,
      name,
      max_bytes,
      trim_newline~,
      diagnostic_ceiling~,
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
  diagnostic_ceiling? : Int? = None,
) -> Result[String, NativeBoundedTextFailure] {
  read_bounded_text_file_selected(
    root_path, name, max_bytes, trim_newline, diagnostic_ceiling, false, false,
  )
}

///|
/// Requires the caller's existing Native Domain scope around the whole call,
/// including input encoding, buffers, UTF-8 and result/failure construction.
/// Current Core/read permission is checked by that caller, not by this physical
/// context. No context, grant, profile or fallback Root is issued here.
pub fn read_bounded_text_file_in_current_read_context_with_custody(
  root_path : String,
  name : String,
  max_bytes : Int64,
  diagnostic_ceiling : Int,
  trim_newline? : Bool = false,
) -> Result[String, NativeBoundedTextFailure] {
  read_bounded_text_file_selected(
    root_path,
    name,
    max_bytes,
    trim_newline,
    Some(diagnostic_ceiling),
    true,
    false,
  )
}

///|
/// Read one ordinary basename under the same original Root/Reader and bounded
/// UTF-8 algorithm. The caller splits a selected path before this operation;
/// separators, traversal and NUL remain invalid. No internal object-name
/// grammar, physical permission or replacement input is inferred.
pub fn read_bounded_ordinary_text_file_with_custody(
  root_path : String,
  name : String,
  max_bytes : Int64,
  trim_newline? : Bool = false,
  diagnostic_ceiling? : Int? = None,
) -> Result[String, NativeBoundedTextFailure] {
  read_bounded_text_file_selected(
    root_path, name, max_bytes, trim_newline, diagnostic_ceiling, false, true,
  )
}

///|
/// The entered Read variant retains the same failed constructor/Reader/Root
/// until their actual child-first cleanup. This does not acquire a scope or
/// widen the caller's original input, work or diagnostic ceiling.
pub fn read_bounded_ordinary_text_file_in_current_read_context_with_custody(
  root_path : String,
  name : String,
  max_bytes : Int64,
  diagnostic_ceiling : Int,
  trim_newline? : Bool = false,
) -> Result[String, NativeBoundedTextFailure] {
  read_bounded_text_file_selected(
    root_path,
    name,
    max_bytes,
    trim_newline,
    Some(diagnostic_ceiling),
    true,
    true,
  )
}

///|
fn read_bounded_text_file_selected(
  root_path : String,
  name : String,
  max_bytes : Int64,
  trim_newline : Bool,
  diagnostic_ceiling : Int?,
  scoped : Bool,
  ordinary_name : Bool,
  prepare_payload? : ((Int64) -> Bool)? = None,
) -> Result[String, NativeBoundedTextFailure] {
  if max_bytes <= 0L || (diagnostic_ceiling is Some(limit) && limit <= 0) {
    return Err(bounded_text_failure(InvalidLimit))
  }
  let root = match
    (if scoped {
      @filesystem.open_root_in_current_read_context_with_custody(
        root_path,
        diagnostic_ceiling.unwrap_or(0),
      )
    } else {
      @filesystem.open_root_with_custody(root_path, diagnostic_ceiling~)
    }) {
    Ok(value) => value
    Err(rejected) => {
      let failure = bounded_text_failure(Filesystem(rejected.issue()))
      // Keep the original constructor object until that same Owner observes
      // its cleanup. An unready Root may still retain physical allocation
      // context; a failed open is not acknowledgement of its retirement.
      failure.rejected_root = Some(rejected)
      return Err(failure)
    }
  }
  let generation = match
    (if ordinary_name {
      root.inspect_file_generation(name)
    } else {
      root.inspect_generation(name)
    }) {
    Ok(Some(value)) => value
    Ok(None) =>
      return Err(
        close_bounded_root_after_failure(root, bounded_text_failure(Missing)),
      )
    Err(issue) =>
      return Err(
        close_bounded_root_after_failure(
          root,
          bounded_text_failure(Filesystem(issue)),
        ),
      )
  }
  if generation.size < 0L || generation.size > max_bytes {
    return Err(
      close_bounded_root_after_failure(
        root,
        bounded_text_failure(CapacityExceeded),
      ),
    )
  }
  if prepare_payload is Some(prepare) && !prepare(generation.size) {
    return Err(
      close_bounded_root_after_failure(
        root,
        bounded_text_failure(PreparationUnavailable),
      ),
    )
  }
  let reader = match
    (if ordinary_name {
      root.open_file_reader_with_custody(name, generation)
    } else {
      root.open_reader_with_custody(name, generation)
    }) {
    Ok(value) => value
    Err(rejected) => {
      let failure : NativeBoundedTextFailure = {
        original_issue: Filesystem(rejected.issue()),
        reader: None,
        rejected_reader: Some(rejected),
        root: Some(root),
        rejected_root: None,
        original_root_cleanup_issue: None,
      }
      // The rejected Reader's original Owner decides its cleanup before any
      // parent close. Even a failed constructor is not a child retirement ACK.
      return Err(failure)
    }
  }
  let bytes : Array[Byte] = []
  let mut done = false
  while !done {
    let chunk = match reader.next(65536) {
      Ok(value) => value
      Err(issue) => return Err(close_failed_bounded_reader(root, reader, issue))
    }
    for byte in chunk.bytes {
      bytes.push(byte)
    }
    done = chunk.eof
  }
  match reader.finish() {
    Ok(_) => ()
    Err(issue) => return Err(close_failed_bounded_reader(root, reader, issue))
  }
  match root.close() {
    Ok(_) => ()
    Err(issue) =>
      return Err({
        original_issue: Filesystem(issue),
        reader: None,
        rejected_reader: None,
        root: Some(root),
        rejected_root: None,
        original_root_cleanup_issue: Some(issue),
      })
  }
  let text = @utf8.decode(Bytes::from_array(bytes)) catch {
    _ => return Err(bounded_text_failure(InvalidUtf8))
  }
  Ok(if trim_newline { trim_terminal_newline(text) } else { text })
}

///|
/// Same ordinary original-generation read. The trusted already-entered caller
/// backs the observed payload BEFORE the Reader/buffers/UTF8 constructors.
/// This callback issues no permission, context, file identity or cleanup ACK;
/// refusal keeps the original Root's actual cleanup custody. The signed Int
/// ceiling is the existing byte/String representation, not a Host allowance.
pub fn read_observed_ordinary_text_file_in_current_read_context_with_custody(
  root_path : String,
  name : String,
  diagnostic_ceiling : Int,
  prepare_payload : (Int64) -> Bool,
) -> Result[String, NativeBoundedTextFailure] {
  read_bounded_text_file_selected(
    root_path,
    name,
    2147483518L,
    false,
    Some(diagnostic_ceiling),
    true,
    true,
    prepare_payload=Some(prepare_payload),
  )
}
