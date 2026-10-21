///|
/// Physical assembly of an explicitly selected Local Host. This retains the
/// existing filesystem lock and custody; it is not a dispatch permit or a new
/// execution Owner. Final journal adoption is required before protected work.
struct NativeLocalAdoptionSession {
  parent : @filesystem.Root
  root : @filesystem.Root
  source_root : @filesystem.Root
  source_ownership : @filesystem.NativeFileOwnership
  lock : @filesystem.Lock
  source_name : String
  source_generation : @filesystem.NativeFileGeneration
  source_body : Bytes
  configuration : @authorization.AdmittedAccountConfiguration
  settings : NativeLocalConfigurationSelection
  existing_only : Bool
  // Shared across aliases: only the actual exclusive creation may consume it.
  initial_signing_eligible : Ref[Bool]
  initial_signing_failure : Ref[NativeLocalInitialSigningFailure?]
  root_ownership : @filesystem.NativeFileOwnership
  state_path : String
  intent_body : Bytes
  intent_generation : @filesystem.NativeFileGeneration
  intent_cid : String
  mut closed : Bool
  mut close_pending : Bool
  mut read_cleanup : NativeLocalAdoptionIssue?
  mut lock_close_attempted : Bool
  // Only the existing-only custodied journal entrance installs this carrier.
  // All aliases must retire that same partial open before releasing its lock.
  mut journal_open_failure : NativeLocalJournalOpenFailure?
}

///|
pub(all) enum NativeLocalAdoptionIssue {
  InvalidInput
  ConfigurationLimit
  Configuration(@authorization.ConfigurationIssue)
  ForeignAccount
  UninstalledBootstrapProfile
  CustodyLost
  SourceChanged
  AmbiguousInitialization
  Closed
  Encoding
  Crypto(@crypto.NativeSignatureIssue)
  Filesystem(@filesystem.NativeFilesystemIssue)
  ReadAcquisitionFailure(@filesystem.NativeReaderOpenFailure)
  ReadPending(@filesystem.Reader, @filesystem.NativeFilesystemIssue)
  WritePending(@filesystem.Writer, @filesystem.NativeFilesystemIssue)
  Physical(@sqlite.NativeSqliteIssue)
  Epoch(NativeClientEpochIssue)
  Journal(NativeClientRunJournalIssue)
  Fenced
  TransactionUnknown
  DatabasePending(@sqlite.Database, NativeLocalAdoptionIssue)
  Inspection(NativeClientStateInspectionIssue)
  InstallationReadTransactionFailure(
    NativeLocalAdoptionIssue,
    NativeClientRunJournalIssue
  )
  OriginalResources(@arena.InstalledArenaLocalHostResourcesIssue)
  OriginalResourceScopePending
  OriginalResourceLeave(
    NativeLocalAdoptionIssue?,
    @arena.InstalledArenaLocalHostResourcesIssue
  )
  InspectionCleanup(@journal.NativeRemoteJournalIssue)
  InspectionPending(
    NativeLocalAdoptionIssue?,
    NativeLocalAdoptionIssue,
    @journal.CoordinatorInitializationCleanup
  )
}

///|
fn local_adoption_record(
  fields : Array[(String, String)],
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  @host.client_local_original_record_body(fields).map_err(_ => Encoding)
}

///|
fn local_adoption_fields(
  body : Bytes,
  keys : Array[String],
) -> Result[Array[String], NativeLocalAdoptionIssue] {
  @host.client_local_original_record_fields(body, keys).map_err(issue => {
    match issue {
      @host.Encoding => Encoding
      @host.InvalidOriginal | @host.ConfigurationLimit => CustodyLost
    }
  })
}

///|
fn local_adoption_digest(
  crypto : @crypto.Library,
  body : Bytes,
) -> Result[String, NativeLocalAdoptionIssue] {
  native_timing_count(26)
  let hasher = match crypto.sha256_hasher() {
    Ok(value) => value
    Err(issue) => return Err(Crypto(issue))
  }
  match hasher.update(body) {
    Ok(_) => ()
    Err(issue) => return Err(Crypto(issue))
  }
  hasher
  .finish_hex()
  .map(value => "sha256:" + value)
  .map_err(issue => Crypto(issue))
}

///|
fn local_adoption_read(
  root : @filesystem.Root,
  name : String,
  max_bytes : Int64,
) -> Result[(Bytes, @filesystem.NativeFileGeneration), NativeLocalAdoptionIssue] {
  let generation = match root.inspect_generation(name) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(Filesystem(issue))
  }
  if generation.size < 0L || generation.size > max_bytes {
    return Err(ConfigurationLimit)
  }
  let reader = match
    local_adoption_reader_result(
      root.open_reader_with_custody(name, generation),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Reserve a finite destination from the admitted original size before copying.
  let body : FixedArray[Byte] = FixedArray::make(generation.size.to_int(), 0)
  let mut offset = 0
  let mut failure : @filesystem.NativeFilesystemIssue? = None
  while offset < body.length() {
    match reader.next(65536) {
      Err(issue) => {
        failure = Some(issue)
        break
      }
      Ok(chunk) => {
        if chunk.bytes.is_empty() ||
          chunk.bytes.length() > body.length() - offset {
          failure = Some(@filesystem.GenerationMismatch)
          break
        }
        body.blit_from_bytes(offset, chunk.bytes, 0, chunk.bytes.length())
        offset += chunk.bytes.length()
      }
    }
  }
  if failure is None {
    match reader.finish() {
      Ok(_) => ()
      Err(issue) => failure = Some(issue)
    }
  }
  match reader.close() {
    Ok(_) => ()
    Err(issue) => return Err(ReadPending(reader, issue))
  }
  match failure {
    Some(issue) => Err(Filesystem(issue))
    None => Ok((Bytes::from_array(body), generation))
  }
}

///|
/// Preserve the filesystem Owner's same rejected constructor and primary
/// reason. The caller retains this carrier even if no descriptor was acquired;
/// only its original retry_cleanup can acknowledge pending Reader retirement.
fn local_adoption_reader_result(
  result : Result[@filesystem.Reader, @filesystem.NativeReaderOpenFailure],
) -> Result[@filesystem.Reader, NativeLocalAdoptionIssue] {
  result.map_err(failure => ReadAcquisitionFailure(failure))
}

///|
fn local_adoption_write(
  root : @filesystem.Root,
  name : String,
  body : Bytes,
) -> Result[@filesystem.NativeFileGeneration, NativeLocalAdoptionIssue] {
  let writer = match
    root.create_writer(name + ".stage", body.length().to_int64()) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  match writer.append(body) {
    Ok(_) => ()
    Err(issue) => return Err(WritePending(writer, issue))
  }
  match writer.seal(name) {
    Ok(value) => Ok(value)
    Err(issue) => Err(WritePending(writer, issue))
  }
}

///|
fn local_adoption_name(name : String) -> Bool {
  !name.is_empty() &&
  name.length() <= 128 &&
  name != "." &&
  name != ".." &&
  !name.contains("/") &&
  !name.contains("\\") &&
  !name.contains("\u{0000}")
}

///|
/// Begin or inspect the original one-time intent. An existing directory with
/// missing proof is never initialized, even when all its files are absent.
/// Selected account bytes are admitted before any Host-state mutation.
pub fn begin_native_local_host_adoption(
  parent_path : String,
  state_name : String,
  source_path : String,
  source_name : String,
  account_id : String,
  crypto : @crypto.Library,
  configuration_files? : Array[String] = [],
  managed_root_path? : String? = None,
  existing_only? : Bool = false,
) -> Result[NativeLocalAdoptionSession, NativeLocalAdoptionIssue] {
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
  )
}

///|
fn NativeLocalAdoptionSession::check_original(
  self : NativeLocalAdoptionSession,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.read_cleanup is Some(issue) {
    return Err(issue)
  }
  if self.initial_signing_failure.val is Some(failure) {
    return Err(failure.issue())
  }
  self
  .check_original_after_read_custody()
  .map_err(issue => self.retain_read_issue(issue))
}

///|
fn NativeLocalAdoptionSession::check_original_after_read_custody(
  self : NativeLocalAdoptionSession,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.closed {
    return Err(Closed)
  }
  // Existing diagnostic slot: one attempted source validation, not a cheap
  // lifetime check, cache hit or completed authorization decision.
  native_timing_count(37)
  guard self.parent.private_ownership() is Ok(_) &&
    self.root.private_ownership() is Ok(current) &&
    current == self.root_ownership &&
    self.source_root.private_ownership() is Ok(current_source) &&
    current_source == self.source_ownership &&
    self.root.verify_generation("initialization.json", self.intent_generation) else {
    return Err(CustodyLost)
  }
  let (intent, _) = match
    local_adoption_read(self.root, "initialization.json", 8192L) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if intent != self.intent_body ||
    !self.source_root.verify_generation(
      self.source_name,
      self.source_generation,
    ) {
    return Err(SourceChanged)
  }
  let (source, _) = match
    local_adoption_read(self.source_root, self.source_name, 1048576L) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if source != self.source_body {
    return Err(SourceChanged)
  }
  self.settings.check_source(self.source_root)
}

///|
/// Copy only under the persisted original intent. Existing content without its
/// exact creation witness stays ambiguous and cannot be overwritten or adopted.
pub fn NativeLocalAdoptionSession::stage_configuration(
  self : NativeLocalAdoptionSession,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match self.check_original() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.stage_configuration_after_original()
}

///|
// Only the same synchronous Owner path may enter immediately after its actual
// check_original. Public staging still checks that original itself. Keep the
// final original check after account/custody I/O; no Allow or file fact is cached.
fn NativeLocalAdoptionSession::stage_configuration_after_original(
  self : NativeLocalAdoptionSession,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.read_cleanup is Some(issue) {
    return Err(issue)
  }
  if self.initial_signing_failure.val is Some(failure) {
    return Err(failure.issue())
  }
  self
  .stage_configuration_after_read_custody()
  .map_err(issue => self.retain_read_issue(issue))
}

///|
fn NativeLocalAdoptionSession::stage_configuration_after_read_custody(
  self : NativeLocalAdoptionSession,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  let existing = match self.root.inspect_generation("account.json") {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let keys = ["device", "inode", "intent_cid", "size", "version"]
  let generation = match existing {
    None if self.existing_only => return Err(CustodyLost)
    None => {
      // An initialized or possibly initialized Host must never regenerate an
      // account file, even if both its content and creation witness disappeared.
      for
        name in [
          "client.sqlite3", "journal-custody.json", "journal-initializing.json",
        ] {
        match self.root.inspect_generation(name) {
          Ok(None) => ()
          Ok(Some(_)) => return Err(CustodyLost)
          Err(issue) => return Err(Filesystem(issue))
        }
      }
      match self.root.inspect_generation("configuration-custody.json") {
        Ok(None) => ()
        Ok(Some(_)) => return Err(CustodyLost)
        Err(issue) => return Err(Filesystem(issue))
      }
      let generation = match
        local_adoption_write(self.root, "account.json", self.source_body) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let body = match
        @host.client_local_configuration_custody_record(
          self.intent_cid,
          (generation.device, generation.inode, generation.size),
        ).map_err(_ => NativeLocalAdoptionIssue::Encoding) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match
        local_adoption_write(self.root, "configuration-custody.json", body) {
        Ok(_) => generation
        Err(issue) => return Err(issue)
      }
    }
    Some(generation) => {
      let (body, _) = match
        local_adoption_read(self.root, "configuration-custody.json", 8192L) {
        Ok(value) => value
        Err(CustodyLost) => return Err(AmbiguousInitialization)
        Err(issue) => return Err(issue)
      }
      let fields = match local_adoption_fields(body, keys) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if fields !=
        [
          generation.device.to_string(),
          generation.inode.to_string(),
          self.intent_cid,
          generation.size.to_string(),
          "actql-native-local-configuration-custody/0.1",
        ] {
        return Err(CustodyLost)
      }
      generation
    }
  }
  let (body, observed) = match
    local_adoption_read(self.root, "account.json", 1048576L) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if body != self.source_body || observed != generation {
    return Err(SourceChanged)
  }
  // Staging is not final journal adoption and grants no Source/Effect authority.
  self.check_original()
}

///|
pub fn NativeLocalAdoptionSession::intent_cid(
  self : NativeLocalAdoptionSession,
) -> String {
  self.intent_cid
}

///|
pub fn NativeLocalAdoptionSession::configuration_cid(
  self : NativeLocalAdoptionSession,
) -> String {
  self.configuration.configuration_cid()
}

///|
pub fn NativeLocalAdoptionSession::close(
  self : NativeLocalAdoptionSession,
) -> Bool {
  // A current callback may expose only false, so its actual read carrier must
  // stay here. Fence new work before cleanup; do not return the adoption lock
  // while a rejected Reader still owns its original cleanup responsibility.
  self.closed = true
  if self.journal_open_failure is Some(original) {
    return original.retry_cleanup() is Ok(_)
  }
  if self.initial_signing_failure.val is Some(failure) &&
    failure.retry_cleanup() is Err(_) {
    self.close_pending = true
    return false
  }
  if self.retry_read_cleanup() is Err(_) {
    self.close_pending = true
    return false
  }
  if self.lock_close_attempted {
    return !self.close_pending
  }
  // Fence reuse before releasing the exclusive physical claim, including a
  // failed/unknown close. A closed descriptor must never authorize another copy.
  self.lock_close_attempted = true
  self.close_pending = !self.lock.close()
  !self.close_pending
}

///|
fn NativeLocalAdoptionSession::retain_read_issue(
  self : NativeLocalAdoptionSession,
  issue : NativeLocalAdoptionIssue,
) -> NativeLocalAdoptionIssue {
  match issue {
    ReadAcquisitionFailure(_) | ReadPending(_, _) =>
      match self.read_cleanup {
        Some(original) => original
        None => {
          self.read_cleanup = Some(issue)
          issue
        }
      }
    _ => issue
  }
}

///|
/// Cleanup only: no read replay, replacement Reader or lock reacquisition.
fn NativeLocalAdoptionSession::retry_read_cleanup(
  self : NativeLocalAdoptionSession,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  guard self.read_cleanup is Some(original) else { return Ok(()) }
  let cleaned = match original {
    ReadAcquisitionFailure(failure) => failure.retry_cleanup()
    ReadPending(reader, _) => reader.close()
    _ => return Err(original)
  }
  match cleaned {
    Err(_) => Err(original)
    Ok(_) => {
      self.read_cleanup = None
      Ok(())
    }
  }
}
