///|
/// Physical operation results only, not another Run or journal state machine.
pub(all) enum NativeLocalJournalCaptureOperation {
  OpenCapturedJournal
  ObserveCapturedJournal
  CloseCapturedJournal
} derive(Eq)

///|
priv enum NativeLocalJournalCaptureOpening {
  JournalNotAttempted
  JournalOpenUnconfirmed
  JournalAcquired(NativeLocalHostConnection)
  JournalRefused(NativeLocalJournalOpenFailure)
}

///|
pub(all) enum NativeLocalJournalCaptureIssue {
  JournalNotOpened
  JournalOpeningUnconfirmed
  JournalCaptureClosed
  JournalAdoption(NativeLocalAdoptionIssue)
}

///|
/// Private installed caller transport of its original Session and Libraries.
/// Preparation performs no I/O and supplies no read capacity or authority. The
/// caller transfers operational use of that same Session; it must retain and
/// fence escaped aliases, the provider and its original read/loan separately.
struct NativeLocalJournalCapture {
  session : NativeLocalAdoptionSession
  library : @sqlite.Library?
  original_resources : NativeLocalJournalOriginalResources?
  command_preparation_journal : Bool
  initial_signing : (
    NativeLocalInitialSigningMaterial,
    @host.ClientLocalSigningBootstrapPolicy,
  )?
  mut read_callback_active : Bool
  mut read_facts_valid : Bool
  mut read_material : @host.ClientLocalAdoptedHostMaterial[
    @sqlite.Database,
    NativeLocalAdoptionIssue,
  ]?
  read_scopes : Array[(String, String, String)]
  read_decisions : Array[
    (@authorization.AccessTuple, @authorization.AccountOutcome),
  ]
  read_bindings : Array[(NativeLocalReadPolicyBinding, Int64)]
  read_committed_results : Array[NativeLocalCommittedResultObservation]
  read_preimages : Array[NativeLocalReadPreimageObservation]
  read_evidence : Array[NativeLocalReadEvidenceObservation]
  mut read_operation_issue : NativeLocalAdoptionIssue?
  mut opening_database : @sqlite.Database?
  mut opening_physical_failure : @sqlite.NativeSqliteOpenFailure?
  mut opening_inspection : @journal.CoordinatorInitializationCleanup?
  crypto : @crypto.Library
  ttl_ms : Double
  max_records : Int
  max_snapshot_bytes : Int64
  max_retained_intent_bytes : Int64
  mut opening : NativeLocalJournalCaptureOpening
  mut closing : Bool
  mut cleanup_acknowledged : Bool
}

///|
struct NativeLocalJournalCaptureReply {
  operation : NativeLocalJournalCaptureOperation
  capture : NativeLocalJournalCapture
  issue : NativeLocalJournalCaptureIssue?
}

///|
/// Retain this capture in the caller's original out-slot BEFORE calling open.
/// Neither valid options nor a successful preparation adopts a Host, Library,
/// current policy, initial signing original or numerical resource profile.
/// max_retained_intent_bytes selects cumulative fresh intent storage; it is
/// carried into this same Journal and never reserves the future policy as RAM.
pub fn prepare_native_local_journal_capture(
  session : NativeLocalAdoptionSession,
  library : @sqlite.Library,
  crypto : @crypto.Library,
  ttl_ms : Double,
  max_records : Int,
  max_snapshot_bytes : Int64,
  max_retained_intent_bytes? : Int64 = 67108864L,
) -> NativeLocalJournalCapture {
  {
    session,
    library: Some(library),
    original_resources: None,
    command_preparation_journal: false,
    initial_signing: None,
    read_callback_active: false,
    read_facts_valid: false,
    read_material: None,
    read_scopes: [],
    read_decisions: [],
    read_bindings: [],
    read_committed_results: [],
    read_preimages: [],
    read_evidence: [],
    read_operation_issue: None,
    opening_database: None,
    opening_physical_failure: None,
    opening_inspection: None,
    crypto,
    ttl_ms,
    max_records,
    max_snapshot_bytes,
    max_retained_intent_bytes,
    opening: JournalNotAttempted,
    closing: false,
    cleanup_acknowledged: false,
  }
}

///|
fn NativeLocalJournalCapture::reply(
  self : NativeLocalJournalCapture,
  operation : NativeLocalJournalCaptureOperation,
  issue : NativeLocalJournalCaptureIssue?,
) -> NativeLocalJournalCaptureReply {
  { operation, capture: self, issue, }
}

///|
/// One physical attempt. Publish the original unconfirmed state before entry;
/// an interrupted call cannot turn into an unattempted open or a replacement.
/// The actual Host/failure is retained before allocating its result reply.
pub fn NativeLocalJournalCapture::open(
  self : NativeLocalJournalCapture,
) -> NativeLocalJournalCaptureReply {
  native_timing_begin(15)
  defer native_timing_end(15)
  if self.closing {
    return self.reply(OpenCapturedJournal, Some(JournalCaptureClosed))
  }
  match self.opening {
    JournalNotAttempted => {
      self.opening = JournalOpenUnconfirmed
      let opened = match self.original_resources {
        None =>
          self.session.open_existing_journal_with_custody(
            self.library.unwrap(),
            self.crypto,
            self.ttl_ms,
            self.max_records,
            self.max_snapshot_bytes,
            max_retained_intent_bytes=self.max_retained_intent_bytes,
          )
        Some(original) => self.open_original_journal(original)
      }
      self.opening = match opened {
        Ok(host) => JournalAcquired(host)
        Err(original) => JournalRefused(original)
      }
      // The acquired Host or Session-owned failure now retains the same DB.
      // Clear this temporary alias only after publishing that original state.
      self.opening_database = None
      self.opening_physical_failure = None
      self.opening_inspection = None
    }
    _ => ()
  }
  let issue = match self.opening {
    JournalAcquired(_) => None
    JournalRefused(original) => Some(JournalAdoption(original.issue()))
    JournalOpenUnconfirmed => Some(JournalOpeningUnconfirmed)
    JournalNotAttempted => Some(JournalNotOpened)
  }
  self.reply(OpenCapturedJournal, issue)
}

///|
/// Cached open success is not current authority. Use the original Host's whole
/// binding fence; a failed/unconfirmed open never obtains a usable Host here.
pub fn NativeLocalJournalCapture::check_current(
  self : NativeLocalJournalCapture,
) -> NativeLocalJournalCaptureReply {
  let issue = if self.closing {
    Some(JournalCaptureClosed)
  } else if self.read_operation_issue is Some(original) {
    // A failed preparation exchange is cleanup-only. A later observation may
    // not erase that first failure by attempting the protected fence again.
    Some(JournalAdoption(original))
  } else {
    match self.opening {
      JournalNotAttempted => Some(JournalNotOpened)
      JournalOpenUnconfirmed => Some(JournalOpeningUnconfirmed)
      JournalRefused(original) => Some(JournalAdoption(original.issue()))
      JournalAcquired(host) => {
        let current = match self.original_resources {
          None => host.check_binding()
          Some(_) =>
            if self.read_callback_active &&
              self.original_resources is Some(original) &&
              original.active_phase is Some(@arena.HostRead) {
              self.check_current_in_original_read()
            } else {
              self.check_current_between_original_phases()
            }
        }
        match current {
          Ok(_) => None
          Err(issue) => Some(JournalAdoption(issue))
        }
      }
    }
  }
  self.reply(ObserveCapturedJournal, issue)
}

///|
/// Same original descriptor cleanup only, including before any SQL attempt.
/// A missing outcome is not cleanup success. The immutable opening refusal
/// stays reachable independently of a later cleanup error or acknowledgement.
/// Escaped data/provider/domain/workspace retirement is the outer caller's ACK.
pub fn NativeLocalJournalCapture::close(
  self : NativeLocalJournalCapture,
) -> NativeLocalJournalCaptureReply {
  self.closing = true
  if self.cleanup_acknowledged {
    return self.reply(CloseCapturedJournal, None)
  }
  let result = match self.opening {
    JournalOpenUnconfirmed =>
      return self.reply(CloseCapturedJournal, Some(JournalOpeningUnconfirmed))
    JournalRefused(original) => original.retry_cleanup()
    JournalAcquired(host) =>
      match self.original_resources {
        None => host.close_owned_root_descriptors()
        Some(original) => original.close_journal(host)
      }
    JournalNotAttempted =>
      match self.original_resources {
        None =>
          if self.session.close() {
            close_local_session_owned_root_descriptors(self.session)
          } else {
            Err(CustodyLost)
          }
        Some(original) => original.close_unopened_session(self.session)
      }
  }
  let issue = match result {
    Ok(_) => {
      self.cleanup_acknowledged = true
      None
    }
    Err(issue) => Some(JournalAdoption(issue))
  }
  self.reply(CloseCapturedJournal, issue)
}

///|
pub fn NativeLocalJournalCapture::original_session(
  self : NativeLocalJournalCapture,
) -> NativeLocalAdoptionSession {
  self.session
}

///|
/// A retained reference, never proof of currentness or permission to use it.
pub fn NativeLocalJournalCapture::original_host(
  self : NativeLocalJournalCapture,
) -> NativeLocalHostConnection? {
  match self.opening {
    JournalAcquired(host) => Some(host)
    _ => None
  }
}

///|
pub fn NativeLocalJournalCapture::original_failure(
  self : NativeLocalJournalCapture,
) -> NativeLocalJournalOpenFailure? {
  match self.opening {
    JournalRefused(original) => Some(original)
    _ => None
  }
}

///|
pub fn NativeLocalJournalCapture::descriptor_cleanup_acknowledged(
  self : NativeLocalJournalCapture,
) -> Bool {
  self.cleanup_acknowledged
}

///|
/// The original outcome is independent of the current/cleanup operation.
/// No transport code renders, replaces or authorizes from its diagnostic.
pub fn NativeLocalJournalCapture::original_issue_family(
  self : NativeLocalJournalCapture,
) -> Int {
  match self.opening {
    JournalNotAttempted | JournalAcquired(_) => 0
    JournalOpenUnconfirmed => 2
    JournalRefused(_) => 4
  }
}

///|
pub fn NativeLocalJournalCaptureReply::original_capture(
  self : NativeLocalJournalCaptureReply,
) -> NativeLocalJournalCapture {
  self.capture
}

///|
pub fn NativeLocalJournalCaptureReply::operation_tag(
  self : NativeLocalJournalCaptureReply,
) -> Int {
  match self.operation {
    OpenCapturedJournal => 1
    ObserveCapturedJournal => 2
    CloseCapturedJournal => 3
  }
}

///|
pub fn NativeLocalJournalCaptureReply::issue_family(
  self : NativeLocalJournalCaptureReply,
) -> Int {
  match self.issue {
    None => 0
    Some(JournalNotOpened) => 1
    Some(JournalOpeningUnconfirmed) => 2
    Some(JournalCaptureClosed) => 3
    Some(JournalAdoption(_)) => 4
  }
}

///|
/// Preserve the original typed cause without rendering paths or secret inputs.
pub fn NativeLocalJournalCaptureReply::issue(
  self : NativeLocalJournalCaptureReply,
) -> NativeLocalJournalCaptureIssue? {
  self.issue
}
