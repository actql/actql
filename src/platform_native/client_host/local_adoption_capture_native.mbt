///|
/// Immutable selection DATA only. Preparation snapshots configuration_files;
/// neither these paths nor the snapshot admit a Host or physical resource.
pub(all) struct NativeLocalExistingAdoptionInput {
  parent_path : String
  state_name : String
  source_path : String
  source_name : String
  account_id : String
  configuration_files : Array[String]
  managed_root_path : String?
}

///|
/// Physical operation identity, independent of opening/current/cleanup outcome.
pub(all) enum NativeLocalAdoptionCaptureOperation {
  OpenCapturedAdoption
  ObserveCapturedAdoption
  CloseCapturedAdoption
} derive(Eq)

///|
priv enum NativeLocalAdoptionCaptureOpening {
  AdoptionNotAttempted
  AdoptionOpenUnconfirmed
  AdoptionAcquired(NativeLocalAdoptionSession)
  AdoptionRefused
}

///|
pub(all) enum NativeLocalAdoptionCaptureIssue {
  AdoptionNotOpened
  AdoptionOpeningUnconfirmed
  AdoptionCaptureClosed
  AdoptionJournalAlreadyCaptured
  AdoptionOriginal(NativeLocalAdoptionIssue)
  AdoptionJournal(NativeLocalJournalCaptureIssue)
}

///|
/// The trusted caller retains this holder and its actual outer read/loan BEFORE
/// open. It owns operational use of returned Session/inner-capture aliases.
/// Preparation performs no I/O and supplies no capacity or current authority.
struct NativeLocalAdoptionCapture {
  input : NativeLocalExistingAdoptionInput
  crypto : @crypto.Library
  root_opening : NativeLocalAdoptionRootOpening
  existing_only : Bool
  original : NativeLocalAdoptionOpenFailure
  mut opening : NativeLocalAdoptionCaptureOpening
  mut journal : NativeLocalJournalCapture?
  mut closing : Bool
  mut cleanup_acknowledged : Bool
}

///|
struct NativeLocalAdoptionCaptureReply {
  operation : NativeLocalAdoptionCaptureOperation
  capture : NativeLocalAdoptionCapture
  issue : NativeLocalAdoptionCaptureIssue?
}

///|
fn prepare_local_existing_adoption_capture(
  input : NativeLocalExistingAdoptionInput,
  crypto : @crypto.Library,
  root_opening : NativeLocalAdoptionRootOpening,
  existing_only? : Bool = true,
) -> Result[NativeLocalAdoptionCapture, NativeLocalAdoptionIssue] {
  // Reuse the existing configuration limit before copying caller-owned DATA.
  // Selection, ordering and all physical validation remain in Adoption itself.
  if input.configuration_files.length() > 11 ||
    (
      input.configuration_files.length() == 11 &&
      !input.configuration_files.contains("host.json")
    ) {
    return Err(ConfigurationLimit)
  }
  let snapshot = {
    ..input,
    configuration_files: input.configuration_files.copy(),
  }
  Ok({
    input: snapshot,
    crypto,
    root_opening,
    existing_only,
    original: new_local_adoption_open_failure(),
    opening: AdoptionNotAttempted,
    journal: None,
    closing: false,
    cleanup_acknowledged: false,
  })
}

///|
/// Existing legacy constructor selection only; never a scoped-open fallback.
pub fn prepare_native_local_existing_adoption_capture(
  input : NativeLocalExistingAdoptionInput,
  crypto : @crypto.Library,
) -> Result[NativeLocalAdoptionCapture, NativeLocalAdoptionIssue] {
  prepare_local_existing_adoption_capture(input, crypto, LegacyPrivateRoots)
}

///|
/// Consume an already entered original read scope, without manufacturing it.
/// Missing scope refuses at the existing physical entrance; it cannot choose
/// the legacy constructor or initialize a missing Host instead.
pub fn prepare_native_local_existing_adoption_capture_in_current_read_context(
  input : NativeLocalExistingAdoptionInput,
  crypto : @crypto.Library,
  diagnostic_ceiling : Int,
) -> Result[NativeLocalAdoptionCapture, NativeLocalAdoptionIssue] {
  prepare_local_existing_adoption_capture(
    input,
    crypto,
    CurrentOriginalReadRoots(diagnostic_ceiling),
  )
}

///|
/// Explicit trusted installer only. This retains the same original constructor
/// before its first attempt. The original intent, marker and Account admission
/// still decide initialization; a path or a scope never authorizes repair.
pub fn prepare_native_local_initial_adoption_capture_in_current_read_context(
  input : NativeLocalExistingAdoptionInput,
  crypto : @crypto.Library,
  diagnostic_ceiling : Int,
) -> Result[NativeLocalAdoptionCapture, NativeLocalAdoptionIssue] {
  prepare_local_existing_adoption_capture(
    input,
    crypto,
    CurrentOriginalReadRoots(diagnostic_ceiling),
    existing_only=false,
  )
}

///|
fn NativeLocalAdoptionCapture::reply(
  self : NativeLocalAdoptionCapture,
  operation : NativeLocalAdoptionCaptureOperation,
  issue : NativeLocalAdoptionCaptureIssue?,
) -> NativeLocalAdoptionCaptureReply {
  { operation, capture: self, issue, }
}

///|
/// Publish unconfirmed entry before any acquisition. The preallocated original
/// receives partial Roots/Readers/Lock, and the actual outcome is retained before
/// reply allocation. An interruption cannot authorize another physical attempt.
pub fn NativeLocalAdoptionCapture::open(
  self : NativeLocalAdoptionCapture,
  product? : NativeLocalProductConfigurationCapture? = None,
) -> NativeLocalAdoptionCaptureReply {
  if self.closing {
    return self.reply(OpenCapturedAdoption, Some(AdoptionCaptureClosed))
  }
  if self.opening is AdoptionNotAttempted {
    self.opening = AdoptionOpenUnconfirmed
    // The caller already retains this actual Product before this synchronous
    // borrow. It is not reopened, copied or replaced by a profile descriptor.
    let product_original = match product {
      Some(capture) if !capture.closing &&
        !capture.operation_failed &&
        capture.opening is ProductAcquired(original) => Some(original)
      None => None
      _ => {
        self.original.original_issue = UninstalledBootstrapProfile
        self.opening = AdoptionRefused
        return self.reply(
          OpenCapturedAdoption,
          Some(AdoptionOriginal(UninstalledBootstrapProfile)),
        )
      }
    }
    self.opening = match
      begin_native_local_host_adoption_original(
        self.input.parent_path,
        self.input.state_name,
        self.input.source_path,
        self.input.source_name,
        self.input.account_id,
        self.crypto,
        configuration_files=self.input.configuration_files,
        managed_root_path=self.input.managed_root_path,
        existing_only=self.existing_only,
        custody=Some(self.original),
        root_opening=self.root_opening,
        product_original~,
      ) {
      Ok(session) => AdoptionAcquired(session)
      Err(issue) => {
        self.original.original_issue = issue
        AdoptionRefused
      }
    }
  }
  self.reply(
    OpenCapturedAdoption,
    match self.opening {
      AdoptionNotAttempted => Some(AdoptionNotOpened)
      AdoptionOpenUnconfirmed => Some(AdoptionOpeningUnconfirmed)
      AdoptionRefused => Some(AdoptionOriginal(self.original.issue()))
      AdoptionAcquired(_) => None
    },
  )
}

///|
/// Bind the same acquired Session to its existing journal capture once, and
/// retain that capture before returning it. Re-entry cannot replace its selected
/// Libraries/options. A lost return is recovered through original_journal().
pub fn NativeLocalAdoptionCapture::capture_journal(
  self : NativeLocalAdoptionCapture,
  library : @sqlite.Library,
  ttl_ms : Double,
  max_records : Int,
  max_snapshot_bytes : Int64,
) -> Result[NativeLocalJournalCapture, NativeLocalAdoptionCaptureIssue] {
  let session = match self.journal_capture_session() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let journal = prepare_native_local_journal_capture(
    session,
    library,
    self.crypto,
    ttl_ms,
    max_records,
    max_snapshot_bytes,
  )
  self.journal = Some(journal)
  Ok(journal)
}

///|
// Both entrances retain the original child before returning it. Parent aliases
// then close/observe that same child, never the Session around a still-open DB.
fn NativeLocalAdoptionCapture::journal_capture_session(
  self : NativeLocalAdoptionCapture,
) -> Result[NativeLocalAdoptionSession, NativeLocalAdoptionCaptureIssue] {
  if self.closing {
    return Err(AdoptionCaptureClosed)
  }
  if self.journal is Some(_) {
    return Err(AdoptionJournalAlreadyCaptured)
  }
  match self.opening {
    AdoptionNotAttempted => return Err(AdoptionNotOpened)
    AdoptionOpenUnconfirmed => return Err(AdoptionOpeningUnconfirmed)
    AdoptionRefused => return Err(AdoptionOriginal(self.original.issue()))
    AdoptionAcquired(session) => Ok(session)
  }
}

///|
/// Bind the already acquired Session to the same claimed resource pair once.
/// Uses this original capture's Crypto and retains the Journal before exposing
/// it. No caller Library, second claim or replacement child is selected.
pub fn NativeLocalAdoptionCapture::capture_journal_with_original_resources(
  self : NativeLocalAdoptionCapture,
  host : @arena.InstalledArenaHost,
  resources : @arena.InstalledArenaLocalHostResources,
  read : @arena.InstalledArenaOriginalRead,
  ttl_ms : Double,
  max_records : Int,
  max_snapshot_bytes : Int64,
) -> Result[NativeLocalJournalCapture, NativeLocalAdoptionCaptureIssue] {
  self.capture_original_journal_resources(
    host,
    resources,
    read,
    ttl_ms,
    max_records,
    max_snapshot_bytes,
    false,
    None,
  )
}

///|
/// The finite Native command-preparation operational selection only. The
/// original acquired Session/Lock, same claimed pair and current checks remain
/// mandatory. It neither selects a generic SQLite mode nor issues authority.
pub fn NativeLocalAdoptionCapture::capture_command_journal_with_original_resources(
  self : NativeLocalAdoptionCapture,
  host : @arena.InstalledArenaHost,
  resources : @arena.InstalledArenaLocalHostResources,
  read : @arena.InstalledArenaOriginalRead,
  ttl_ms : Double,
  max_records : Int,
  max_snapshot_bytes : Int64,
) -> Result[NativeLocalJournalCapture, NativeLocalAdoptionCaptureIssue] {
  self.capture_original_journal_resources(
    host,
    resources,
    read,
    ttl_ms,
    max_records,
    max_snapshot_bytes,
    true,
    None,
  )
}

///|
fn NativeLocalAdoptionCapture::capture_original_journal_resources(
  self : NativeLocalAdoptionCapture,
  host : @arena.InstalledArenaHost,
  resources : @arena.InstalledArenaLocalHostResources,
  read : @arena.InstalledArenaOriginalRead,
  ttl_ms : Double,
  max_records : Int,
  max_snapshot_bytes : Int64,
  command_preparation_journal : Bool,
  initial_signing : (
    NativeLocalInitialSigningMaterial,
    @host.ClientLocalSigningBootstrapPolicy,
  )?,
) -> Result[NativeLocalJournalCapture, NativeLocalAdoptionCaptureIssue] {
  let session = match self.journal_capture_session() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let prepared = prepare_native_local_journal_capture_with_original_resources(
    session,
    host,
    resources,
    read,
    self.crypto,
    ttl_ms,
    max_records,
    max_snapshot_bytes,
  )
  let journal = { ..prepared, command_preparation_journal, initial_signing, }
  self.journal = Some(journal)
  Ok(journal)
}

///|
/// Retain the actual first-initialization material in this same child before
/// returning it. The Journal's original durable marker still decides whether
/// initialization is permitted; this entrance cannot replace retained state.
pub fn NativeLocalAdoptionCapture::capture_initial_journal_with_original_resources(
  self : NativeLocalAdoptionCapture,
  host : @arena.InstalledArenaHost,
  resources : @arena.InstalledArenaLocalHostResources,
  read : @arena.InstalledArenaOriginalRead,
  material : NativeLocalInitialSigningMaterial,
  policy : @host.ClientLocalSigningBootstrapPolicy,
  ttl_ms : Double,
  max_records : Int,
  max_snapshot_bytes : Int64,
) -> Result[NativeLocalJournalCapture, NativeLocalAdoptionCaptureIssue] {
  self.capture_original_journal_resources(
    host,
    resources,
    read,
    ttl_ms,
    max_records,
    max_snapshot_bytes,
    false,
    Some((material, policy)),
  )
}

///|
/// The same explicit initialization materials and durable marker rules as the
/// original entrance, with the command-only Journal operational selection.
pub fn NativeLocalAdoptionCapture::capture_initial_command_journal_with_original_resources(
  self : NativeLocalAdoptionCapture,
  host : @arena.InstalledArenaHost,
  resources : @arena.InstalledArenaLocalHostResources,
  read : @arena.InstalledArenaOriginalRead,
  material : NativeLocalInitialSigningMaterial,
  policy : @host.ClientLocalSigningBootstrapPolicy,
  ttl_ms : Double,
  max_records : Int,
  max_snapshot_bytes : Int64,
) -> Result[NativeLocalJournalCapture, NativeLocalAdoptionCaptureIssue] {
  self.capture_original_journal_resources(
    host,
    resources,
    read,
    ttl_ms,
    max_records,
    max_snapshot_bytes,
    true,
    Some((material, policy)),
  )
}

///|
/// Observe the original physical current fence, never cached acquisition. Once
/// handed to the journal, its whole binding check owns current observation.
pub fn NativeLocalAdoptionCapture::check_current(
  self : NativeLocalAdoptionCapture,
) -> NativeLocalAdoptionCaptureReply {
  if self.closing {
    return self.reply(ObserveCapturedAdoption, Some(AdoptionCaptureClosed))
  }
  if self.journal is Some(journal) {
    return self.reply(
      ObserveCapturedAdoption,
      journal.check_current().issue().map(issue => AdoptionJournal(issue)),
    )
  }
  self.reply(
    ObserveCapturedAdoption,
    match self.opening {
      AdoptionNotAttempted => Some(AdoptionNotOpened)
      AdoptionOpenUnconfirmed => Some(AdoptionOpeningUnconfirmed)
      AdoptionRefused => Some(AdoptionOriginal(self.original.issue()))
      AdoptionAcquired(session) =>
        match session.check_original() {
          Ok(_) => None
          Err(issue) => Some(AdoptionOriginal(issue))
        }
    },
  )
}

///|
/// Close the retained inner journal first, including its failed/unknown close.
/// With no journal, retire the original Session or partial acquisition only.
/// An unconfirmed open cannot ACK cleanup even if its known fields are empty.
/// Outer read/provider/escaped aliases require separate actual acknowledgements.
pub fn NativeLocalAdoptionCapture::close(
  self : NativeLocalAdoptionCapture,
) -> NativeLocalAdoptionCaptureReply {
  self.closing = true
  if self.cleanup_acknowledged {
    return self.reply(CloseCapturedAdoption, None)
  }
  if self.opening is AdoptionOpenUnconfirmed {
    return self.reply(CloseCapturedAdoption, Some(AdoptionOpeningUnconfirmed))
  }
  if self.journal is Some(journal) {
    let reply = journal.close()
    guard journal.descriptor_cleanup_acknowledged() else {
      return self.reply(
        CloseCapturedAdoption,
        Some(
          AdoptionJournal(reply.issue().unwrap_or(JournalOpeningUnconfirmed)),
        ),
      )
    }
    self.cleanup_acknowledged = true
    return self.reply(CloseCapturedAdoption, None)
  }
  let result = match self.opening {
    AdoptionNotAttempted => Ok(())
    AdoptionOpenUnconfirmed =>
      return self.reply(CloseCapturedAdoption, Some(AdoptionOpeningUnconfirmed))
    AdoptionRefused => self.original.retry_cleanup()
    AdoptionAcquired(session) =>
      if session.close() {
        close_local_session_owned_root_descriptors(session)
      } else {
        Err(CustodyLost)
      }
  }
  self.reply(
    CloseCapturedAdoption,
    match result {
      Ok(_) => {
        self.cleanup_acknowledged = true
        None
      }
      Err(issue) => Some(AdoptionOriginal(issue))
    },
  )
}

///|
/// Retained references only. These getters issue no current/use permission.
pub fn NativeLocalAdoptionCapture::original_session(
  self : NativeLocalAdoptionCapture,
) -> NativeLocalAdoptionSession? {
  match self.opening {
    AdoptionAcquired(session) => Some(session)
    _ => None
  }
}

///|
pub fn NativeLocalAdoptionCapture::original_failure(
  self : NativeLocalAdoptionCapture,
) -> NativeLocalAdoptionOpenFailure? {
  if self.opening is AdoptionRefused {
    Some(self.original)
  } else {
    None
  }
}

///|
pub fn NativeLocalAdoptionCapture::original_journal(
  self : NativeLocalAdoptionCapture,
) -> NativeLocalJournalCapture? {
  self.journal
}

///|
pub fn NativeLocalAdoptionCapture::descriptor_cleanup_acknowledged(
  self : NativeLocalAdoptionCapture,
) -> Bool {
  self.cleanup_acknowledged
}

///|
pub fn NativeLocalAdoptionCaptureReply::issue(
  self : NativeLocalAdoptionCaptureReply,
) -> NativeLocalAdoptionCaptureIssue? {
  self.issue
}

///|
pub fn NativeLocalAdoptionCaptureReply::original_capture(
  self : NativeLocalAdoptionCaptureReply,
) -> NativeLocalAdoptionCapture {
  self.capture
}

///|
pub fn NativeLocalAdoptionCaptureReply::operation_tag(
  self : NativeLocalAdoptionCaptureReply,
) -> Int {
  match self.operation {
    OpenCapturedAdoption => 1
    ObserveCapturedAdoption => 2
    CloseCapturedAdoption => 3
  }
}

///|
pub fn NativeLocalAdoptionCaptureReply::issue_family(
  self : NativeLocalAdoptionCaptureReply,
) -> Int {
  match self.issue {
    None => 0
    Some(AdoptionNotOpened) => 1
    Some(AdoptionOpeningUnconfirmed) => 2
    Some(AdoptionCaptureClosed) => 3
    Some(AdoptionOriginal(_)) => 4
    Some(AdoptionJournalAlreadyCaptured) => 5
    Some(AdoptionJournal(_)) => 6
  }
}
