///|
/// Original partial acquisition in the existing Adoption Owner. This carries
/// cleanup only, never a usable Host, replacement acquisition or admission.
struct NativeLocalAdoptionOpenFailure {
  mut original_issue : NativeLocalAdoptionIssue
  mut source_root : @filesystem.Root?
  mut parent : @filesystem.Root?
  mut root : @filesystem.Root?
  mut managed : @filesystem.Root?
  mut lock : @filesystem.Lock?
  mut root_acquisition : @filesystem.NativeRootOpenFailure?
  mut lock_acquisition : @filesystem.NativeLockOpenFailure?
  mut original_read_cleaned : Bool
}

///|
pub fn NativeLocalAdoptionOpenFailure::issue(
  self : NativeLocalAdoptionOpenFailure,
) -> NativeLocalAdoptionIssue {
  self.original_issue
}

///|
/// Retire only the original acquired objects. In particular, retain the actual
/// lock until all original Reader/Root closes acknowledge; an Unknown cannot
/// release it and authorize a new process against an incompletely retired open.
/// The original refusal remains available after cleanup and is never retried.
pub fn NativeLocalAdoptionOpenFailure::retry_cleanup(
  self : NativeLocalAdoptionOpenFailure,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if !self.original_read_cleaned {
    let closed = match self.original_issue {
      ReadAcquisitionFailure(failure) => failure.retry_cleanup()
      ReadPending(reader, _) => reader.close()
      WritePending(writer, _) => writer.cancel()
      _ => Ok(())
    }
    match closed {
      Err(issue) => return Err(Filesystem(issue))
      Ok(_) => self.original_read_cleaned = true
    }
  }
  if self.root_acquisition is Some(failure) {
    match failure.retry_cleanup() {
      Err(issue) => return Err(Filesystem(issue))
      Ok(_) => self.root_acquisition = None
    }
  }
  if self.lock_acquisition is Some(failure) {
    match failure.retry_cleanup() {
      Err(issue) => return Err(Filesystem(issue))
      Ok(_) => self.lock_acquisition = None
    }
  }
  if self.root is Some(root) {
    match root.close() {
      Err(issue) => return Err(Filesystem(issue))
      Ok(_) => self.root = None
    }
  }
  if self.managed is Some(managed) {
    match managed.close() {
      Err(issue) => return Err(Filesystem(issue))
      Ok(_) => self.managed = None
    }
  }
  if self.parent is Some(parent) {
    match parent.close() {
      Err(issue) => return Err(Filesystem(issue))
      Ok(_) => self.parent = None
    }
  }
  if self.source_root is Some(source) {
    match source.close() {
      Err(issue) => return Err(Filesystem(issue))
      Ok(_) => self.source_root = None
    }
  }
  if self.lock is Some(lock) {
    match lock.close_checked() {
      Err(issue) => return Err(Filesystem(issue))
      Ok(_) => self.lock = None
    }
  }
  Ok(())
}

///|
// Allocate the original partial-acquisition carrier before entering any I/O.
fn new_local_adoption_open_failure() -> NativeLocalAdoptionOpenFailure {
  {
    original_issue: InvalidInput,
    source_root: None,
    parent: None,
    root: None,
    managed: None,
    lock: None,
    root_acquisition: None,
    lock_acquisition: None,
    original_read_cleaned: false,
  }
}

///|
// Shared original constructor and partial-acquisition custody. Public existing
// entrances keep existing_only=true; the explicit installer may select false.
// Scope selection never supplies initialization or signing authority.
fn begin_native_local_host_adoption_with_original_root_custody(
  parent_path : String,
  state_name : String,
  source_path : String,
  source_name : String,
  account_id : String,
  crypto : @crypto.Library,
  root_opening : NativeLocalAdoptionRootOpening,
  existing_only? : Bool = true,
  configuration_files? : Array[String] = [],
  managed_root_path? : String? = None,
) -> Result[NativeLocalAdoptionSession, NativeLocalAdoptionOpenFailure] {
  let custody = new_local_adoption_open_failure()
  match
    begin_native_local_host_adoption_original(
      parent_path,
      state_name,
      source_path,
      source_name,
      account_id,
      crypto,
      configuration_files~,
      managed_root_path~,
      existing_only~,
      custody=Some(custody),
      root_opening~,
    ) {
    Ok(original) => Ok(original)
    Err(issue) => {
      custody.original_issue = issue
      Err(custody)
    }
  }
}

///|
fn local_adoption_open_private_root(
  path : String,
  custody : NativeLocalAdoptionOpenFailure?,
  root_opening? : NativeLocalAdoptionRootOpening = LegacyPrivateRoots,
) -> Result[@filesystem.Root, NativeLocalAdoptionIssue] {
  if root_opening is CurrentOriginalReadRoots(diagnostic_ceiling) {
    guard custody is Some(original) else { return Err(InvalidInput) }
    return @filesystem.open_private_root_in_current_read_context_with_custody(
      path, diagnostic_ceiling,
    ).map_err(failure => {
      original.root_acquisition = Some(failure)
      Filesystem(failure.issue())
    })
  }
  match custody {
    None =>
      @filesystem.open_private_root(path).map_err(issue => Filesystem(issue))
    Some(original) =>
      @filesystem.open_private_root_with_custody(path).map_err(failure => {
        original.root_acquisition = Some(failure)
        Filesystem(failure.issue())
      })
  }
}

///|
fn local_adoption_acquire_lock(
  parent : @filesystem.Root,
  custody : NativeLocalAdoptionOpenFailure?,
) -> Result[@filesystem.Lock, NativeLocalAdoptionIssue] {
  match custody {
    None =>
      parent
      .acquire_lock("local-adoption.lock")
      .map_err(issue => Filesystem(issue))
    Some(original) =>
      parent
      .acquire_lock_with_custody("local-adoption.lock")
      .map_err(failure => {
        original.lock_acquisition = Some(failure)
        Filesystem(failure.issue())
      })
  }
}

///|
fn local_adoption_open_child(
  parent : @filesystem.Root,
  state_name : String,
  custody : NativeLocalAdoptionOpenFailure?,
) -> Result[@filesystem.Root, NativeLocalAdoptionIssue] {
  match custody {
    None => parent.open_child(state_name).map_err(issue => Filesystem(issue))
    Some(original) =>
      parent
      .open_child_with_custody(state_name)
      .map_err(failure => {
        original.root_acquisition = Some(failure)
        Filesystem(failure.issue())
      })
  }
}
