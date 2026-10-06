///|
/// Physical storage for one exact task output. The producer's canonical
/// stream already computes its logical CID; writing those same bytes does not
/// hash them a second time. A fresh reader verifies the complete stored bytes
/// before its result can be admitted as a new consumer input.
struct NativeRetainedTaskFile {
  root : @filesystem.Root
  writer : @filesystem.Writer?
  name : String
  mut generation : @filesystem.NativeFileGeneration?
  mut cid : String?
  mut released : Bool
  usable : Ref[Bool]
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
  usable : Ref[Bool]
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
    writer: Some(writer),
    name: "output-" + occurrence,
    generation: None,
    cid: None,
    released: false,
    usable: Ref(true),
    readers: Ref(0),
    opened_readers: [],
  })
}

///|
/// Re-adopt one exact sealed file after its previous physical owner stopped.
/// The trusted caller must retain the saved generation and original content
/// CID under its existing custody and exclusive holder boundary. This checks
/// physical identity only; it grants no Run, Source, borrow or start authority.
/// It creates no writer, replacement file or capacity reservation. Complete
/// content still needs the existing reader's finish before input admission.
pub fn restore_native_retained_task_file(
  root_path : String,
  occurrence : String,
  generation : @filesystem.NativeFileGeneration,
  cid : String,
  max_bytes : Int64,
) -> Result[NativeRetainedTaskFile, NativeRetainedTaskFileIssue] {
  if max_bytes < 0L || generation.size < 0L || generation.size > max_bytes {
    return Err(InvalidLimit)
  }
  if !valid_cid(cid) {
    return Err(ContentMismatch)
  }
  let root = match @filesystem.open_root(root_path) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let name = "output-" + occurrence
  if !root.verify_generation(name, generation) {
    return Err(Filesystem(@filesystem.GenerationMismatch))
  }
  Ok({
    root,
    writer: None,
    name,
    generation: Some(generation),
    cid: Some(cid),
    released: false,
    usable: Ref(true),
    readers: Ref(0),
    opened_readers: [],
  })
}

///|
pub fn NativeRetainedTaskFile::append(
  self : NativeRetainedTaskFile,
  batch : String,
) -> Result[Unit, NativeRetainedTaskFileIssue] {
  if self.generation is Some(_) || self.released || !self.usable.val {
    return Err(InvalidState)
  }
  guard self.writer is Some(writer) else { return Err(InvalidState) }
  writer.append(@utf8.encode(batch)).map_err(issue => Filesystem(issue))
}

///|
/// Seal only after the complete producer stream has returned its identity.
/// The bytes written are exactly its drained batches and terminal tail.
pub fn NativeRetainedTaskFile::seal(
  self : NativeRetainedTaskFile,
  cid : String,
  bytes : Int,
) -> Result[Unit, NativeRetainedTaskFileIssue] {
  if self.released || self.generation is Some(_) || !self.usable.val {
    return Err(InvalidState)
  }
  guard self.writer is Some(writer) else { return Err(InvalidState) }
  if bytes < 0 || writer.written() != bytes.to_int64() || !valid_cid(cid) {
    return Err(ContentMismatch)
  }
  let generation = match writer.seal(self.name) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  self.generation = Some(generation)
  self.cid = Some(cid)
  Ok(())
}

///|
pub fn NativeRetainedTaskFile::available(self : NativeRetainedTaskFile) -> Bool {
  if self.released || !self.usable.val {
    return false
  }
  guard self.generation is Some(generation) else { return false }
  self.root.verify_generation(self.name, generation)
}

///|
/// Revoke new and existing reader authority when the Run stops accepting
/// work. This never declares physical cleanup complete; release still owns
/// the writer, links, reader handles, and directory synchronization.
pub fn NativeRetainedTaskFile::stop_use(self : NativeRetainedTaskFile) -> Unit {
  self.usable.val = false
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
/// Return the exact producer identity and durable byte count recorded at
/// seal. This does not rescan or rehash the file; availability still checks
/// the generation and any later integrity failure revokes further use.
pub fn NativeRetainedTaskFile::sealed_content(
  self : NativeRetainedTaskFile,
) -> (String, Int64)? {
  guard self.available() &&
    self.cid is Some(cid) &&
    self.generation is Some(generation) else {
    return None
  }
  Some((cid, generation.size))
}

///|
/// Physical custody needed for restoration, distinct from the content CID.
/// The caller persists it with the original task responsibility; a filename
/// alone must never authorize adopting or reclaiming a replacement file.
pub fn NativeRetainedTaskFile::sealed_generation(
  self : NativeRetainedTaskFile,
) -> @filesystem.NativeFileGeneration? {
  if self.available() {
    self.generation
  } else {
    None
  }
}

///|
/// One availability check for the exact physical snapshot persisted alongside
/// the original task observation. The caller still owns journal durability.
pub fn NativeRetainedTaskFile::sealed_custody(
  self : NativeRetainedTaskFile,
) -> (String, @filesystem.NativeFileGeneration, String)? {
  if self.available() &&
    self.generation is Some(generation) &&
    self.cid is Some(cid) {
    Some((self.name[7:].to_owned(), generation, cid))
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
    usable: self.usable,
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
  if self.closed || self.eof || !self.usable.val {
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
  if self.closed || !self.eof || !self.usable.val {
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
    self.usable.val = false
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
  let cleanup = match self.writer {
    Some(writer) => writer.cancel()
    None => {
      guard self.generation is Some(generation) else {
        return Err(InvalidState)
      }
      self.root.reclaim_generation(self.name, generation)
    }
  }
  match cleanup {
    Ok(_) => ()
    Err(issue) => return Err(Filesystem(issue))
  }
  self.released = true
  Ok(())
}
