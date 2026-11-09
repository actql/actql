///|
// The existing Adoption Owner retains the actual operator file independently
// of the Product's copy. This view issues no key, Account decision or grant.
struct NativeLocalOperatorHostOriginal {
  current : Ref[Bool]
  root : @filesystem.Root
  ownership : @filesystem.NativeFileOwnership
  observation : @filesystem.NativeFileObservation
  generation : @filesystem.NativeFileGeneration
  body : Bytes
}

///|
// Publish this original on the command before opening its first Root. Every
// failed constructor and staged Writer stays here until its own close replies.
struct NativeLocalOperatorHostCapture {
  base_path : String
  directories : Array[String]
  name : String
  create_default : Bool
  root_opening : NativeLocalAdoptionRootOpening
  current : Ref[Bool]
  roots : Array[@filesystem.Root]
  custody : NativeLocalAdoptionOpenFailure
  mut writer : @filesystem.Writer?
  mut writer_failure : @filesystem.NativeWriterOpenFailure?
  mut original : NativeLocalOperatorHostOriginal?
  mut attempted : Bool
  mut issue : NativeLocalAdoptionIssue?
  mut closing : Bool
  mut closed : Bool
}

///|
fn prepare_local_operator_host_capture(
  base_path : String,
  directories : Array[String],
  name : String,
  create_default : Bool,
  root_opening : NativeLocalAdoptionRootOpening,
) -> Result[NativeLocalOperatorHostCapture, NativeLocalAdoptionIssue] {
  if !base_path.has_prefix("/") ||
    base_path.length() > 4096 ||
    directories.length() > 2 ||
    !local_adoption_name(name) ||
    directories.any(name => !local_adoption_name(name)) {
    return Err(InvalidInput)
  }
  Ok({
    base_path,
    directories: directories.copy(),
    name,
    create_default,
    root_opening,
    current: { val: false, },
    roots: [],
    custody: new_local_adoption_open_failure(),
    writer: None,
    writer_failure: None,
    original: None,
    attempted: false,
    issue: None,
    closing: false,
    closed: false,
  })
}

///|
/// The caller already holds the SAME original consuming Read. Only explicit
/// initialization can create an absent default file; restore never repairs it.
pub fn prepare_native_local_operator_host_capture_in_current_read_context(
  base_path : String,
  directories : Array[String],
  name : String,
  create_default : Bool,
  diagnostic_ceiling : Int,
) -> Result[NativeLocalOperatorHostCapture, NativeLocalAdoptionIssue] {
  prepare_local_operator_host_capture(
    base_path,
    directories,
    name,
    create_default,
    CurrentOriginalReadRoots(diagnostic_ceiling),
  )
}

///|
fn NativeLocalOperatorHostCapture::open_original(
  self : NativeLocalOperatorHostCapture,
) -> Result[NativeLocalOperatorHostOriginal, NativeLocalAdoptionIssue] {
  let root = match self.root_opening {
    LegacyPrivateRoots => @filesystem.open_root_with_custody(self.base_path)
    CurrentOriginalReadRoots(ceiling) =>
      @filesystem.open_root_in_current_read_context_with_custody(
        self.base_path,
        ceiling,
      )
  }
  let mut root = match root {
    Ok(root) => root
    Err(failure) => {
      self.custody.root_acquisition = Some(failure)
      return Err(Filesystem(failure.issue()))
    }
  }
  self.roots.push(root)
  for name in self.directories {
    match root.bootstrap_parent_ownership() {
      Ok(_) => ()
      Err(issue) => return Err(Filesystem(issue))
    }
    match root.inspect_directory(name) {
      Ok(Some(_)) => ()
      Ok(None) if self.create_default => {
        match root.create_directory(name) {
          Ok(_) => ()
          Err(issue) => return Err(Filesystem(issue))
        }
        match root.sync_directory() {
          Ok(_) => ()
          Err(issue) => return Err(Filesystem(issue))
        }
      }
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(Filesystem(issue))
    }
    root = match root.open_child_with_custody(name) {
      Ok(child) => child
      Err(failure) => {
        self.custody.root_acquisition = Some(failure)
        return Err(Filesystem(failure.issue()))
      }
    }
    self.roots.push(root)
  }
  let ownership = match root.bootstrap_parent_ownership() {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  match root.inspect_generation(self.name) {
    Ok(Some(_)) => ()
    Ok(None) if self.create_default => {
      // Exclusive seal never replaces an existing operator file. In particular
      // a concurrent named-signer file cannot turn into an implicit default.
      let body = b"{\"version\":\"actql-host/0.1\"}\n"
      let writer = match
        root.create_writer_with_custody(
          self.name + ".stage",
          body.length().to_int64(),
        ) {
        Ok(writer) => writer
        Err(failure) => {
          self.writer_failure = Some(failure)
          return Err(Filesystem(failure.issue()))
        }
      }
      self.writer = Some(writer)
      match writer.append(body) {
        Ok(_) => ()
        Err(issue) => return Err(Filesystem(issue))
      }
      match writer.seal(self.name) {
        Ok(_) => ()
        Err(issue) => return Err(Filesystem(issue))
      }
      match writer.close_retaining_files() {
        Ok(_) => self.writer = None
        Err(issue) => return Err(Filesystem(issue))
      }
    }
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(Filesystem(issue))
  }
  let observation = match root.observe_file(self.name) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let (body, generation) = match local_adoption_read(root, self.name, 65536L) {
    Ok(value) => value
    Err(issue) => {
      self.custody.original_issue = issue
      return Err(issue)
    }
  }
  match observation.check_current() {
    Ok(_) => ()
    Err(issue) => return Err(Filesystem(issue))
  }
  guard observation.generation() is Ok(selected) && selected == generation else {
    return Err(SourceChanged)
  }
  self.current.val = true
  Ok({ current: self.current, root, ownership, observation, generation, body, })
}

///|
pub fn NativeLocalOperatorHostCapture::open(
  self : NativeLocalOperatorHostCapture,
) -> Result[NativeLocalOperatorHostOriginal, NativeLocalAdoptionIssue] {
  if self.closing || self.closed {
    return Err(Closed)
  }
  if !self.attempted {
    self.attempted = true
    match self.open_original() {
      Ok(original) => self.original = Some(original)
      Err(issue) => self.issue = Some(issue)
    }
  }
  if self.issue is Some(issue) {
    return Err(issue)
  }
  match self.original {
    Some(original) => Ok(original)
    None => Err(CustodyLost)
  }
}

///|
/// Recheck the original namespace/file only; no decode, key use or authority.
pub fn NativeLocalOperatorHostOriginal::check_current(
  self : NativeLocalOperatorHostOriginal,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if !self.current.val {
    return Err(Closed)
  }
  guard self.root.bootstrap_parent_ownership() is Ok(current) &&
    current == self.ownership else {
    return Err(CustodyLost)
  }
  self.observation.check_current().map_err(issue => Filesystem(issue))
}

///|
pub fn NativeLocalOperatorHostOriginal::original_wire(
  self : NativeLocalOperatorHostOriginal,
) -> Result[String, NativeLocalAdoptionIssue] {
  match self.check_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok(@utf8.decode(self.body)) catch {
    _ => Err(Encoding)
  }
}

///|
pub fn NativeLocalOperatorHostCapture::close(
  self : NativeLocalOperatorHostCapture,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  self.closing = true
  self.current.val = false
  if self.closed {
    return Ok(())
  }
  match self.custody.retry_cleanup() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if self.writer_failure is Some(failure) {
    match failure.retry_cleanup() {
      Ok(_) => self.writer_failure = None
      Err(issue) => return Err(Filesystem(issue))
    }
  }
  if self.writer is Some(writer) {
    let closed = if writer.is_sealed() {
      writer.close_retaining_files()
    } else {
      writer.cancel()
    }
    match closed {
      Ok(_) => self.writer = None
      Err(issue) => return Err(Filesystem(issue))
    }
  }
  while !self.roots.is_empty() {
    let root = self.roots[self.roots.length() - 1]
    match root.close() {
      Ok(_) => ignore(self.roots.pop())
      Err(issue) => return Err(Filesystem(issue))
    }
  }
  self.original = None
  self.closed = true
  Ok(())
}
