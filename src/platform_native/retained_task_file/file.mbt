///|
/// Physical storage for one exact task output. The producer's canonical
/// stream already computes its logical CID; writing those same bytes does not
/// hash them a second time. A fresh reader verifies the complete stored bytes
/// before its result can be admitted as a new consumer input.
struct NativeRetainedTaskFile {
  root : @filesystem.Root
  writer : @filesystem.Writer
  name : String
  mut generation : @filesystem.NativeFileGeneration?
  mut cid : String?
  mut released : Bool
  readers : Ref[Int]
  opened_readers : Array[NativeRetainedTaskReader]
}

///|
struct NativeRetainedTaskReader {
  reader : @filesystem.Reader
  hash : @sha256.Hasher
  cid : String
  mut eof : Bool
  mut closed : Bool
  readers : Ref[Int]
}

///|
pub(all) enum NativeRetainedTaskFileIssue {
  InvalidLimit
  InvalidState
  ContentMismatch
  Filesystem(@filesystem.NativeFilesystemIssue)
  Hash(@sha256.HashFailure)
}

///|
fn valid_cid(value : String) -> Bool {
  if !value.has_prefix("sha256:") || value.length() != 71 {
    return false
  }
  for index in 7..<71 {
    let character = value[index]
    if !((character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f')) {
      return false
    }
  }
  true
}

///|
/// The caller supplies a private Run root and an exact task occurrence name.
/// Exclusive creation prevents another writer from adopting the same name.
pub fn begin_native_retained_task_file(
  root_path : String,
  occurrence : String,
  max_bytes : Int64,
) -> Result[NativeRetainedTaskFile, NativeRetainedTaskFileIssue] {
  if max_bytes < 0L {
    return Err(InvalidLimit)
  }
  let root = match @filesystem.open_root(root_path) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let writer = match root.create_writer("stage-" + occurrence, max_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  Ok({
    root,
    writer,
    name: "output-" + occurrence,
    generation: None,
    cid: None,
    released: false,
    readers: Ref(0),
    opened_readers: [],
  })
}

///|
pub fn NativeRetainedTaskFile::append(
  self : NativeRetainedTaskFile,
  batch : String,
) -> Result[Unit, NativeRetainedTaskFileIssue] {
  if self.generation is Some(_) || self.released {
    return Err(InvalidState)
  }
  self.writer.append(@utf8.encode(batch)).map_err(issue => Filesystem(issue))
}

///|
/// Seal only after the complete producer stream has returned its identity.
/// The bytes written are exactly its drained batches and terminal tail.
pub fn NativeRetainedTaskFile::seal(
  self : NativeRetainedTaskFile,
  cid : String,
  bytes : Int,
) -> Result[Unit, NativeRetainedTaskFileIssue] {
  if self.released || self.generation is Some(_) {
    return Err(InvalidState)
  }
  if bytes < 0 || self.writer.written() != bytes.to_int64() || !valid_cid(cid) {
    return Err(ContentMismatch)
  }
  let generation = match self.writer.seal(self.name) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  self.generation = Some(generation)
  self.cid = Some(cid)
  Ok(())
}

///|
pub fn NativeRetainedTaskFile::available(self : NativeRetainedTaskFile) -> Bool {
  if self.released {
    return false
  }
  guard self.generation is Some(generation) else { return false }
  self.root.verify_generation(self.name, generation)
}

///|
pub fn NativeRetainedTaskFile::stored_bytes(
  self : NativeRetainedTaskFile,
) -> Int64? {
  if self.available() {
    self.generation.map(value => value.size)
  } else {
    None
  }
}

///|
/// The common execution may return reserved holding capacity only after this
/// owner confirms removal and directory durability.
pub fn NativeRetainedTaskFile::release_confirmed(
  self : NativeRetainedTaskFile,
) -> Bool {
  self.released
}

///|
pub fn NativeRetainedTaskFile::open_reader(
  self : NativeRetainedTaskFile,
) -> Result[NativeRetainedTaskReader, NativeRetainedTaskFileIssue] {
  if !self.available() {
    return Err(InvalidState)
  }
  guard self.generation is Some(generation) && self.cid is Some(cid) else {
    return Err(InvalidState)
  }
  let reader = match self.root.open_reader(self.name, generation) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  self.readers.val += 1
  let opened = {
    reader,
    hash: @sha256.hasher(),
    cid,
    eof: false,
    closed: false,
    readers: self.readers,
  }
  self.opened_readers.push(opened)
  Ok(opened)
}

///|
/// Called only after the execution owner has stopped accepting reader work.
/// Failed closes retain their exact reader handles for a later cleanup retry.
pub fn NativeRetainedTaskFile::reclaim_readers(
  self : NativeRetainedTaskFile,
) -> Result[Unit, NativeRetainedTaskFileIssue] {
  let mut first : NativeRetainedTaskFileIssue? = None
  for reader in self.opened_readers {
    if !reader.closed {
      match reader.close() {
        Ok(_) => ()
        Err(issue) => if first is None { first = Some(issue) }
      }
    }
  }
  match first {
    Some(issue) => Err(issue)
    None => Ok(())
  }
}

///|
/// Returned chunks remain provisional until finish confirms complete content.
pub fn NativeRetainedTaskReader::next(
  self : NativeRetainedTaskReader,
  max_bytes : Int,
) -> Result[@filesystem.NativeFileChunk, NativeRetainedTaskFileIssue] {
  if self.closed || self.eof {
    return Err(InvalidState)
  }
  let chunk = match self.reader.next(max_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  @sha256.update(self.hash, chunk.bytes) catch {
    issue => return Err(Hash(issue))
  }
  self.eof = chunk.eof
  Ok(chunk)
}

///|
pub fn NativeRetainedTaskReader::finish(
  self : NativeRetainedTaskReader,
) -> Result[Unit, NativeRetainedTaskFileIssue] {
  if self.closed || !self.eof {
    return Err(InvalidState)
  }
  match self.reader.finish() {
    Err(issue) => return Err(Filesystem(issue))
    Ok(_) => ()
  }
  let digest = try "sha256:" + @sha256.finish_hex(self.hash) catch {
    issue => return Err(Hash(issue))
  }
  if digest != self.cid {
    return Err(ContentMismatch)
  }
  match self.reader.close() {
    Ok(_) => ()
    Err(issue) => return Err(Filesystem(issue))
  }
  self.closed = true
  self.readers.val -= 1
  Ok(())
}

///|
pub fn NativeRetainedTaskReader::close(
  self : NativeRetainedTaskReader,
) -> Result[Unit, NativeRetainedTaskFileIssue] {
  if self.closed {
    return Ok(())
  }
  match self.reader.close() {
    Ok(_) => ()
    Err(issue) => return Err(Filesystem(issue))
  }
  self.closed = true
  self.readers.val -= 1
  Ok(())
}

///|
/// Retry this on cleanup failure. The exact writer owns both provisional and
/// sealed links, including the case where seal failed after creating a link.
pub fn NativeRetainedTaskFile::release(
  self : NativeRetainedTaskFile,
) -> Result[Unit, NativeRetainedTaskFileIssue] {
  if self.released {
    return Ok(())
  }
  if self.readers.val != 0 {
    return Err(InvalidState)
  }
  match self.writer.cancel() {
    Ok(_) => ()
    Err(issue) => return Err(Filesystem(issue))
  }
  self.released = true
  Ok(())
}
