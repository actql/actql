///|
// One file destination retained by the existing read binding. Construction
// is private: pathname DATA cannot reconstruct a Root, Writer or their ACKs.
// The binding must retain this record before its first fallible acquisition.
priv struct NativeLocalReadFileDestination {
  path : String
  parent : String
  name : String
  staging_name : String
  max_bytes : Int
  mut root : @filesystem.Root?
  mut root_failure : @filesystem.NativeRootOpenFailure?
  mut parent_observation : @filesystem.NativeDirectoryObservation?
  mut parent_identity : @filesystem.NativeFileOwnership?
  mut writer : @filesystem.Writer?
  mut writer_failure : @filesystem.NativeWriterOpenFailure?
  mut reader : @filesystem.Reader?
  mut reader_failure : @filesystem.NativeReaderOpenFailure?
  mut generation : @filesystem.NativeFileGeneration?
  mut primary : @filesystem.NativeFilesystemIssue?
  mut write_attempted : Bool
  mut finish_attempted : Bool
  mut sink_installed : Bool
  mut closing : Bool
  mut closed : Bool
}

///|
fn local_read_file_destination(
  path : String,
  parent : String,
  name : String,
  staging_name : String,
  max_bytes : Int,
) -> NativeLocalReadFileDestination {
  {
    path,
    parent,
    name,
    staging_name,
    max_bytes,
    root: None,
    root_failure: None,
    parent_observation: None,
    parent_identity: None,
    writer: None,
    writer_failure: None,
    reader: None,
    reader_failure: None,
    generation: None,
    primary: None,
    write_attempted: false,
    finish_attempted: false,
    sink_installed: false,
    closing: false,
    closed: false,
  }
}

///|
fn NativeLocalReadFileDestination::remember(
  self : NativeLocalReadFileDestination,
  issue : @filesystem.NativeFilesystemIssue,
) -> @filesystem.NativeFilesystemIssue {
  if self.primary is None {
    self.primary = Some(issue)
  }
  issue
}

///|
// Opening a parent is separate from creating output. The caller can therefore
// inspect the original delivery history before any new Writer is created.
fn NativeLocalReadFileDestination::open_parent(
  self : NativeLocalReadFileDestination,
) -> Result[Unit, @filesystem.NativeFilesystemIssue] {
  if self.closing ||
    self.closed ||
    self.root is Some(_) ||
    self.root_failure is Some(_) ||
    self.primary is Some(_) {
    return Err(@filesystem.WriterClosed)
  }
  let root = match @filesystem.open_root_with_custody(self.parent) {
    Ok(value) => value
    Err(original) => {
      self.root_failure = Some(original)
      return Err(self.remember(original.issue()))
    }
  }
  self.root = Some(root)
  let observation = match root.observe_directory() {
    Ok(value) => value
    Err(issue) => return Err(self.remember(issue))
  }
  self.parent_observation = Some(observation)
  let identity = match observation.identity() {
    Ok(value) => value
    Err(issue) => return Err(self.remember(issue))
  }
  self.parent_identity = Some(identity)
  Ok(())
}

///|
fn NativeLocalReadFileDestination::create_writer(
  self : NativeLocalReadFileDestination,
) -> Result[Unit, @filesystem.NativeFilesystemIssue] {
  guard !self.closing &&
    !self.closed &&
    self.primary is None &&
    self.writer is None &&
    self.writer_failure is None &&
    self.root is Some(root) &&
    self.parent_observation is Some(observation) else {
    return Err(@filesystem.WriterClosed)
  }
  match observation.check_current() {
    Ok(_) => ()
    Err(issue) => return Err(self.remember(issue))
  }
  match root.inspect_file_generation(self.name) {
    Ok(None) => ()
    Ok(Some(_)) => return Err(self.remember(@filesystem.Conflict))
    Err(issue) => return Err(self.remember(issue))
  }
  let writer = match
    root.create_writer_with_custody(
      self.staging_name,
      self.max_bytes.to_int64(),
    ) {
    Ok(value) => value
    Err(original) => {
      self.writer_failure = Some(original)
      return Err(self.remember(original.issue()))
    }
  }
  // Retain the same exclusive original before a later currentness check.
  self.writer = Some(writer)
  self.check_current().map_err(issue => self.remember(issue))
}

///|
fn NativeLocalReadFileDestination::check_current(
  self : NativeLocalReadFileDestination,
) -> Result[Unit, @filesystem.NativeFilesystemIssue] {
  guard !self.closing &&
    !self.closed &&
    self.root is Some(root) &&
    self.writer is Some(writer) &&
    self.parent_identity is Some(identity) &&
    self.parent_observation is Some(observation) else {
    return Err(@filesystem.WriterClosed)
  }
  match observation.identity() {
    Ok(actual) if actual == identity => ()
    Ok(_) => return Err(@filesystem.GenerationMismatch)
    Err(issue) => return Err(issue)
  }
  let (name, generation) = match self.generation {
    Some(value) => (self.name, value)
    None => {
      let ownership = writer.ownership()
      (
        self.staging_name,
        {
          device: ownership.device,
          inode: ownership.inode,
          size: writer.written(),
        },
      )
    }
  }
  if root.verify_file_generation(name, generation) {
    Ok(())
  } else {
    Err(@filesystem.GenerationMismatch)
  }
}

///|
fn NativeLocalReadFileDestination::original_data(
  self : NativeLocalReadFileDestination,
) -> Result[NativeLocalReadFileOriginal, @filesystem.NativeFilesystemIssue] {
  match self.check_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard self.parent_identity is Some(parent) && self.writer is Some(writer) else {
    return Err(@filesystem.WriterClosed)
  }
  let identity = writer.ownership()
  Ok({
    path: self.path,
    name: self.name,
    staging_name: self.staging_name,
    parent_device: parent.device.to_string(),
    parent_inode: parent.inode.to_string(),
    writer_device: identity.device.to_string(),
    writer_inode: identity.inode.to_string(),
  })
}

///|
fn NativeLocalReadFileDestination::append(
  self : NativeLocalReadFileDestination,
  bytes : Bytes,
) -> @result_access.NativeResultSinkWrite {
  if self.finish_attempted || self.primary is Some(_) {
    return @result_access.SinkChunkFailed(0, 0)
  }
  match self.check_current() {
    Ok(_) => ()
    Err(issue) => {
      ignore(self.remember(issue))
      return @result_access.SinkChunkFailed(0, 0)
    }
  }
  guard self.writer is Some(writer) else {
    return @result_access.SinkChunkFailed(0, 0)
  }
  let before = writer.written()
  self.write_attempted = true
  match writer.append(bytes) {
    Ok(_) => @result_access.SinkChunkConfirmed
    Err(issue) => {
      ignore(self.remember(issue))
      // The existing Writer accounts for every successful write prefix, even
      // when a later write fails. Do not repeat that chunk or infer its ACK.
      let prefix = writer.written() - before
      if prefix < 0L || prefix > bytes.length().to_int64() {
        @result_access.SinkChunkFailed(0, bytes.length())
      } else {
        @result_access.SinkChunkFailed(prefix.to_int(), 0)
      }
    }
  }
}

///|
fn NativeLocalReadFileDestination::finish(
  self : NativeLocalReadFileDestination,
) -> Bool {
  if self.finish_attempted || self.primary is Some(_) {
    return false
  }
  self.finish_attempted = true
  match self.check_current() {
    Ok(_) => ()
    Err(issue) => {
      ignore(self.remember(issue))
      return false
    }
  }
  guard self.writer is Some(writer) else { return false }
  match writer.seal_file(self.name) {
    Ok(generation) => self.generation = Some(generation)
    Err(issue) => {
      ignore(self.remember(issue))
      return false
    }
  }
  match self.check_current() {
    Ok(_) => true
    Err(issue) => {
      ignore(self.remember(issue))
      false
    }
  }
}

///|
// A payload/finish attempt retains its actual names for inspection. Before
// either attempt, the same empty private staging file can be cancelled through
// its original Writer. Neither path resends bytes, retries a consumed FD or
// certifies a delivery receipt. Parent retirement follows the child's ACK.
fn NativeLocalReadFileDestination::close(
  self : NativeLocalReadFileDestination,
) -> Result[Unit, @filesystem.NativeFilesystemIssue] {
  if self.closed {
    return Ok(())
  }
  self.closing = true
  if self.reader_failure is Some(original) {
    match original.retry_cleanup() {
      Ok(_) => self.reader_failure = None
      Err(issue) => return Err(issue)
    }
  }
  if self.reader is Some(reader) {
    match reader.close() {
      Ok(_) => self.reader = None
      Err(issue) => return Err(issue)
    }
  }
  if self.writer_failure is Some(original) {
    match original.retry_cleanup() {
      Ok(_) => self.writer_failure = None
      Err(issue) => return Err(issue)
    }
  }
  if self.writer is Some(writer) {
    let closed = if self.write_attempted || self.finish_attempted {
      writer.close_retaining_files()
    } else {
      writer.cancel()
    }
    match closed {
      Ok(_) => self.writer = None
      Err(issue) => return Err(issue)
    }
  }
  if self.root_failure is Some(original) {
    match original.retry_cleanup() {
      Ok(_) => self.root_failure = None
      Err(issue) => return Err(issue)
    }
  }
  if self.root is Some(root) {
    match root.close() {
      Ok(_) => self.root = None
      Err(issue) => return Err(issue)
    }
  }
  self.parent_observation = None
  self.closed = true
  Ok(())
}

///|
// Re-observe the actual completed file. Saved identity DATA never reconstitutes
// a Writer or permits another append; a failed read retains its original child.
fn NativeLocalReadFileDestination::verify_completed(
  self : NativeLocalReadFileDestination,
  saved : NativeLocalReadFileOriginal,
) -> Result[(Int64, String), @filesystem.NativeFilesystemIssue] {
  guard !self.closing &&
    !self.closed &&
    self.primary is None &&
    self.reader is None &&
    self.reader_failure is None &&
    self.path == saved.path &&
    self.name == saved.name &&
    self.root is Some(root) &&
    self.parent_observation is Some(observation) else {
    return Err(@filesystem.GenerationMismatch)
  }
  let parent = match observation.identity() {
    Ok(value) => value
    Err(issue) => return Err(self.remember(issue))
  }
  if parent.device.to_string() != saved.parent_device ||
    parent.inode.to_string() != saved.parent_inode {
    return Err(self.remember(@filesystem.GenerationMismatch))
  }
  let generation = match root.inspect_file_generation(self.name) {
    Ok(Some(value)) if value.size >= 0L &&
      value.size <= self.max_bytes.to_int64() &&
      value.device.to_string() == saved.writer_device &&
      value.inode.to_string() == saved.writer_inode => value
    Ok(_) => return Err(self.remember(@filesystem.GenerationMismatch))
    Err(issue) => return Err(self.remember(issue))
  }
  let reader = match root.open_file_reader_with_custody(self.name, generation) {
    Ok(value) => value
    Err(original) => {
      self.reader_failure = Some(original)
      return Err(self.remember(original.issue()))
    }
  }
  self.reader = Some(reader)
  let digest = @sha.hasher()
  let mut count = 0L
  let mut complete = false
  for _ in 0..<(generation.size + 1L).to_int() {
    let chunk = match reader.next(16384) {
      Ok(value) => value
      Err(issue) => return Err(self.remember(issue))
    }
    if chunk.bytes.length().to_int64() > generation.size - count ||
      (chunk.bytes.is_empty() && !chunk.eof) {
      return Err(self.remember(@filesystem.GenerationMismatch))
    }
    @sha.update(digest, chunk.bytes) catch {
      _ => return Err(self.remember(@filesystem.GenerationMismatch))
    }
    count += chunk.bytes.length().to_int64()
    if chunk.eof {
      complete = true
      break
    }
  }
  if !complete ||
    count != generation.size ||
    reader.finish() is Err(_) ||
    !root.verify_file_generation(self.name, generation) ||
    !(observation.identity() is Ok(actual) && actual == parent) {
    return Err(self.remember(@filesystem.GenerationMismatch))
  }
  let hash = @sha.finish_hex(digest) catch {
    _ => return Err(self.remember(@filesystem.GenerationMismatch))
  }
  match reader.close() {
    Ok(_) => self.reader = None
    Err(issue) => return Err(self.remember(issue))
  }
  Ok((count, hash))
}
