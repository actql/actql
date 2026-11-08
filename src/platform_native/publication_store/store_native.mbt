///|
struct Store {
  root : @filesystem.Root
  lock : @filesystem.Lock
  database : @sqlite.Database
  operation_original : @sqlite.NativeStoreOperationOriginal?
  mut operation_body_active : Bool
  mut operation_return_pending : Bool
  mut operation_return_primary : NativePublicationStoreIssue?
  // The exact acquired child stays here until the original return and that
  // child's cleanup are confirmed. A reader count cannot replace its custody.
  mut pending_result_delivery : ResultDelivery?
  authority_cid : String
  journal_identity : @filesystem.NativeFileOwnership
  capacity_bytes : Int64
  max_objects : Int64
  max_record_bytes : Int
  active_writers : Map[String, Bool]
  pending_writers : Map[String, PendingPayloadCleanup]
  // Exact ownership acquired but not yet confirmed in the durable allocation
  // record. Capacity stays with this Store until persistence and reclaim finish.
  pending_allocations : Map[String, RecordedAllocation]
  active_readers : Map[String, Int]
  mut closed : Bool
  // Existing close responsibility; no new I/O is admitted after retirement starts.
  mut retiring : Bool
  // Acceptance evidence only: called at the steps of a payload allocation.
  mut allocation_observer : ((String) -> Unit)?
  // Whitebox fault injection at fallible allocation preparation boundaries.
  allocation_failure : Ref[((String) -> NativePublicationStoreIssue?)?]
}

///|
/// Original failed preparation with the same existing physical Owners. No
/// wire, persistence, reservation, authority or substitute Store is issued.
struct NativePublicationStoreOpenFailure {
  original_issue : NativePublicationStoreIssue
  mut operation_original : @sqlite.NativeStoreOperationOriginal?
  mut operation_database_alias : @sqlite.Database?
  mut operation_return_pending : Bool
  mut operation_children_closed : Bool
  mut root : @filesystem.Root?
  mut failed_root : @filesystem.NativeRootOpenFailure?
  mut lock : @filesystem.Lock?
  mut failed_lock : @filesystem.NativeLockOpenFailure?
  mut database : @sqlite.Database?
  mut failed_database : @sqlite.NativeSqliteOpenFailure?
  // Missing original constructor custody remains pending. Its primary issue
  // retains the original diagnostic; this marker cannot acknowledge cleanup.
  cleanup_gap : Unit?
}

///|
pub fn NativePublicationStoreOpenFailure::issue(
  self : NativePublicationStoreOpenFailure,
) -> NativePublicationStoreIssue {
  self.original_issue
}

///|
/// Re-observe only the original handles, in reverse preparation order. No
/// reopen/schema repair and no capacity return are performed here. Missing
/// opaque constructor custody remains pending, not a fabricated empty ACK.
fn NativePublicationStoreOpenFailure::retry_cleanup_in_scope(
  self : NativePublicationStoreOpenFailure,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.failed_database is Some(original) {
    match original.retry_cleanup() {
      Ok(_) => self.failed_database = None
      Err(issue) => return Err(Database(issue))
    }
  }
  if self.database is Some(original) {
    match original.close_checked() {
      Ok(_) => self.database = None
      Err(issue) => return Err(Database(issue))
    }
  }
  if self.failed_lock is Some(original) {
    match original.retry_cleanup() {
      Ok(_) => self.failed_lock = None
      Err(issue) => return Err(Filesystem(issue))
    }
  }
  if self.lock is Some(original) {
    match original.close_checked() {
      Ok(_) => self.lock = None
      Err(issue) => return Err(Filesystem(issue))
    }
  }
  if self.cleanup_gap is Some(_) {
    return Err(CleanupPending)
  }
  if self.failed_root is Some(original) {
    match original.retry_cleanup() {
      Ok(_) => self.failed_root = None
      Err(issue) => return Err(Filesystem(issue))
    }
  }
  if self.root is Some(original) {
    match original.close() {
      Ok(_) => self.root = None
      Err(issue) => return Err(Filesystem(issue))
    }
  }
  Ok(())
}

///|
fn store_open_failure(
  original_issue : NativePublicationStoreIssue,
  operation_original? : @sqlite.NativeStoreOperationOriginal? = None,
  operation_return_pending? : Bool = false,
  root? : @filesystem.Root? = None,
  failed_root? : @filesystem.NativeRootOpenFailure? = None,
  lock? : @filesystem.Lock? = None,
  failed_lock? : @filesystem.NativeLockOpenFailure? = None,
  database? : @sqlite.Database? = None,
  failed_database? : @sqlite.NativeSqliteOpenFailure? = None,
  cleanup_gap? : Unit? = None,
) -> NativePublicationStoreOpenFailure {
  {
    original_issue,
    operation_original,
    operation_database_alias: None,
    operation_return_pending,
    operation_children_closed: false,
    root,
    failed_root,
    lock,
    failed_lock,
    database,
    failed_database,
    cleanup_gap,
  }
}

///|
/// A failed open keeps the same routing carrier as well as every physical
/// child. Scope cleanup cannot acknowledge any of those children in advance.
pub fn NativePublicationStoreOpenFailure::retry_cleanup(
  self : NativePublicationStoreOpenFailure,
) -> Result[Unit, NativePublicationStoreIssue] {
  guard self.operation_original is Some(original) else {
    return self.retry_cleanup_in_scope()
  }
  if self.operation_return_pending {
    match original.leave_store() {
      Ok(_) => {
        self.operation_return_pending = false
        self.operation_database_alias = None
        if self.operation_children_closed {
          self.operation_original = None
          return Ok(())
        }
      }
      Err(issue) =>
        if self.operation_children_closed {
          return Err(OperationRouting(Some(self.original_issue), issue))
        }
    }
  }
  // Retain the actual DATA shell separately before physical cleanup can clear
  // its constructor field. Last-alias retirement follows confirmed return.
  if self.operation_database_alias is None {
    self.operation_database_alias = match self.database {
      Some(database) => Some(database)
      None =>
        match self.failed_database {
          Some(failure) =>
            match failure.borrow_original_database_cleanup(original) {
              Ok(database) => database
              Err(issue) => return Err(Database(issue))
            }
          None => None
        }
    }
  }
  match original.enter_cleanup() {
    Err(issue) => return Err(Database(issue))
    Ok(_) => ()
  }
  let result = self.retry_cleanup_in_scope()
  self.operation_children_closed = result is Ok(_)
  self.operation_return_pending = true
  let after = original.leave_store()
  match after {
    Err(issue) =>
      Err(
        OperationRouting(
          match result {
            Ok(_) => None
            Err(primary) => Some(primary)
          },
          issue,
        ),
      )
    Ok(_) => {
      self.operation_return_pending = false
      self.operation_database_alias = None
      if result is Ok(_) {
        self.operation_original = None
      }
      result
    }
  }
}

///|
/// The closure is package-private and comes only from the existing typed
/// Store methods. It neither supplies an original nor grants a new operation.
fn[T] Store::with_original_read(
  self : Store,
  cleanup_work : Bool,
  final_close : Bool,
  call : () -> Result[T, NativePublicationStoreIssue],
) -> Result[T, NativePublicationStoreIssue] {
  guard self.operation_original is Some(original) else { return call() }
  if self.operation_body_active || self.operation_return_pending {
    return Err(CleanupPending)
  }
  if !cleanup_work && self.pending_result_delivery is Some(_) {
    return Err(CleanupPending)
  }
  let before = if final_close {
    original.enter_cleanup()
  } else if cleanup_work {
    original.enter_cleanup_work()
  } else {
    original.enter_store()
  }
  match before {
    Err(issue) => return Err(Database(issue))
    Ok(_) => ()
  }
  self.operation_body_active = true
  let result = call()
  self.operation_body_active = false
  self.complete_original_return(original, result)
}

///|
fn[T] Store::complete_original_return(
  self : Store,
  original : @sqlite.NativeStoreOperationOriginal,
  result : Result[T, NativePublicationStoreIssue],
  prior_primary? : NativePublicationStoreIssue? = None,
) -> Result[T, NativePublicationStoreIssue] {
  // Register this duty before invoking a callback that can fail or reenter.
  // Physical child close alone does not acknowledge the original return.
  self.operation_return_pending = true
  self.operation_return_primary = match result {
    Ok(_) => prior_primary
    Err(primary) => Some(primary)
  }
  match original.leave_store() {
    Err(issue) => Err(OperationRouting(self.operation_return_primary, issue))
    Ok(_) => {
      self.operation_return_pending = false
      self.operation_return_primary = None
      result
    }
  }
}

///|
/// Reconcile only this Store's outstanding original return. No Store body,
/// SQL, child close or acquisition is replayed. False means no pending duty;
/// only the original coordinator's successful return clears the mirror.
pub fn Store::reconcile_original_return(
  self : Store,
) -> Result[Bool, NativePublicationStoreIssue] {
  if self.operation_body_active {
    return Err(CleanupPending)
  }
  if !self.operation_return_pending {
    return Ok(false)
  }
  guard self.operation_original is Some(original) else {
    return Err(CleanupPending)
  }
  let prior = self.operation_return_primary
  // Keep the mirror latched and deny reentry throughout both callbacks.
  self.operation_body_active = true
  let returned = match original.leave_store() {
    Ok(_) => Ok(())
    Err(_) =>
      // A failed normal return can only recover through the existing same
      // original cleanup entry. Its success alone is not a return ACK.
      match original.enter_cleanup() {
        Err(issue) => Err(issue)
        Ok(_) => original.leave_store()
      }
  }
  self.operation_body_active = false
  match returned {
    Err(issue) => Err(OperationRouting(prior, issue))
    Ok(_) => {
      self.operation_return_pending = false
      // Retain the original primary observation; this ACK cannot clear the
      // underlying operation failure or restore normal dispatch.
      Ok(true)
    }
  }
}

///|
/// Close only a Result child whose successful acquisition could not be
/// returned. The same Store retains it before the fallible return; no new
/// delivery, Reader, attempt or SQL acquisition is issued by this method.
pub fn Store::retry_pending_result_delivery_cleanup(
  self : Store,
) -> Result[Bool, NativePublicationStoreIssue] {
  match self.reconcile_original_return() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard self.pending_result_delivery is Some(original) else { return Ok(false) }
  match original.close() {
    Err(issue) => Err(issue)
    Ok(_) => {
      self.pending_result_delivery = None
      Ok(true)
    }
  }
}

///|
/// The fixed Native coordinator supplies this original before any Root or DB
/// work. Absence is never projected into the generic unscoped open entrance.
pub fn open_original_local_store_with_custody(
  library : @sqlite.Library,
  original : @sqlite.NativeStoreOperationOriginal,
  root_path : String,
  authority_cid : String,
  capacity_bytes : Int64,
  max_objects : Int64,
  max_record_bytes : Int64,
  existing? : Bool = false,
  diagnostic_ceiling? : Int? = None,
) -> Result[Store, NativePublicationStoreOpenError] {
  if capacity_bytes < 0L ||
    max_objects < 1L ||
    max_record_bytes < 1L ||
    max_record_bytes > 2147483647L {
    return Err(RefusedBeforeAcquisition(InvalidConfiguration))
  }
  match original.enter_store() {
    Err(issue) =>
      return Err(
        CleanupRequired(
          store_open_failure(Database(issue), operation_original=Some(original)),
        ),
      )
    Ok(_) => ()
  }
  let result = open_store_owned_with_custody(
    library,
    root_path,
    authority_cid,
    capacity_bytes,
    max_objects,
    max_record_bytes,
    existing,
    diagnostic_ceiling~,
    local_facility=true,
    operation_original=Some(original),
  )
  // Every failed constructor is retained before attempting the return scope.
  if result is Err(CleanupRequired(failure)) {
    failure.operation_original = Some(original)
  }
  match original.leave_store() {
    Ok(_) => result
    Err(issue) => {
      let failure = match result {
        Ok(store) =>
          store_open_failure(
            OperationRouting(None, issue),
            operation_original=Some(original),
            operation_return_pending=true,
            root=Some(store.root),
            lock=Some(store.lock),
            database=Some(store.database),
          )
        Err(RefusedBeforeAcquisition(primary)) =>
          store_open_failure(
            OperationRouting(Some(primary), issue),
            operation_original=Some(original),
            operation_return_pending=true,
          )
        Err(CleanupRequired(failure)) =>
          // Preserve the original primary, plus this separate return failure.
          store_open_failure(
            OperationRouting(Some(failure.issue()), issue),
            operation_original=Some(original),
            operation_return_pending=true,
            root=failure.root,
            failed_root=failure.failed_root,
            lock=failure.lock,
            failed_lock=failure.failed_lock,
            database=failure.database,
            failed_database=failure.failed_database,
            cleanup_gap=failure.cleanup_gap,
          )
      }
      Err(CleanupRequired(failure))
    }
  }
}

///|
fn require_store_open(
  store : Store,
) -> Result[Unit, NativePublicationStoreIssue] {
  if store.closed {
    Err(Closed)
  } else if store.retiring {
    Err(CleanupPending)
  } else {
    Ok(())
  }
}

///|
/// Acceptance evidence only: `observer` is called with `"allocated"` once the
/// private staging file exists and before its ownership is durable, and with
/// `"owned"` once the ownership is durable and before the file gets its
/// public name. Effect Source custody also emits `effect-custody-before-intent`,
/// `effect-custody-intent-saved` and `effect-custody-before-terminal` around its
/// metadata persistence boundaries. These are observation seams, not state proof.
pub fn Store::observe_allocation(
  self : Store,
  observer : (String) -> Unit,
) -> Unit {
  self.allocation_observer = Some(observer)
}

///|
fn observe(store : Store, step : String) -> Unit {
  match store.allocation_observer {
    Some(observer) => observer(step)
    None => ()
  }
}

///|
fn[T] allocation_prepare(
  store : Store,
  step : String,
  operation : () -> Result[T, NativePublicationStoreIssue],
) -> Result[T, NativePublicationStoreIssue] {
  match require_store_open(store) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if store.allocation_failure.val is Some(inject) && inject(step) is Some(issue) {
    return Err(issue)
  }
  // The existing observation seam can retire this same Store. Its callback
  // grants no permission to start I/O after returning.
  match require_store_open(store) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  operation()
}

///|
// The filesystem creation primitive retains the acquired identity even when
// its directory sync reports failure. Borrow that exact acquisition result;
// inspecting a name after an error would not prove this Store created it.
#borrow(root)
extern "C" fn allocation_device_ffi(root : @filesystem.Root) -> UInt64 = "actql_native_filesystem_root_result_device"

///|
#borrow(root)
extern "C" fn allocation_inode_ffi(root : @filesystem.Root) -> UInt64 = "actql_native_filesystem_root_result_inode"

///|
#borrow(root)
extern "C" fn allocation_acquired_ffi(root : @filesystem.Root) -> Int = "actql_native_filesystem_root_result_directory_acquired"

///|
/// The name of the private allocation area a payload is first created in.
/// The area is a directory this Store creates exclusively; its recorded
/// identity, not its name, is what proves that what is inside was created by
/// this allocation.
fn allocation_name(
  request : @payload.PublicationPayloadRequest,
  ordinal : Int64,
) -> String {
  @payload.prepare_publication_payload_allocation_name(request, ordinal)
}

///|
/// The file name inside an allocation area.
const ALLOCATION_FILE : String = @payload.PUBLICATION_PAYLOAD_ALLOCATION_FILE

///|
/// What the Store recorded about a request's allocation area: its name and,
/// once the area existed, its identity. A name without an identity gives no
/// authority over anything found at that name.
priv struct RecordedAllocation {
  name : String
  identity : @filesystem.NativeFileOwnership?
}

///|
fn allocation_body(allocation : RecordedAllocation) -> Bytes {
  @payload.encode_publication_payload_allocation(
    allocation.name,
    allocation.identity.map(identity => {
      device: identity.device,
      inode: identity.inode,
    }),
  )
}

///|
/// The allocation recorded for a request, if any. A recorded body that is
/// not an allocation of this request is a collision, never a name to touch.
fn recorded_allocation(
  store : Store,
  request : @payload.PublicationPayloadRequest,
) -> Result[RecordedAllocation?, NativePublicationStoreIssue] {
  match
    store.database.read(
      @payload.publication_payload_allocation_namespace(),
      record_key(request),
    ) {
    Ok(value) =>
      match @payload.admit_publication_payload_allocation(request, value.body) {
        Err(_) => Err(StateCollision)
        Ok(allocation) =>
          Ok(
            Some({
              name: @payload.publication_payload_allocation_name(allocation),
              identity: @payload.publication_payload_allocation_ownership(
                allocation,
              ).map(identity => {
                device: identity.device,
                inode: identity.inode,
              }),
            }),
          )
      }
    Err(@sqlite.NotFound) => Ok(None)
    Err(issue) => Err(Database(issue))
  }
}

///|
/// The ordinal of the next allocation for a request: one more than the last
/// recorded one, so every allocation of a key has its own area, and a name
/// that could not be created is never tried again.
fn next_allocation_ordinal(
  store : Store,
  request : @payload.PublicationPayloadRequest,
) -> Result[Int64, NativePublicationStoreIssue] {
  match recorded_allocation(store, request) {
    Ok(None) => Ok(1L)
    Ok(Some(allocation)) =>
      match
        @payload.next_publication_payload_allocation_ordinal(
          request,
          allocation.name,
        ) {
        Ok(ordinal) => Ok(ordinal)
        Err(_) => Err(StateCollision)
      }
    Err(issue) => Err(issue)
  }
}

///|
/// Record a request's allocation durably: first its name, before the area
/// exists; then, once the area was created exclusively, its identity.
fn record_allocation(
  store : Store,
  key : String,
  allocation : RecordedAllocation,
  cleanup_owned? : Bool = false,
) -> Result[Unit, NativePublicationStoreIssue] {
  let body = allocation_body(allocation)
  let inserted = if cleanup_owned {
    insert_owned_cleanup_record(
      store,
      @payload.publication_payload_allocation_namespace(),
      key,
      body,
    )
  } else {
    store.database.insert(
      @payload.publication_payload_allocation_namespace(),
      key,
      body,
    )
  }
  match inserted {
    Ok(_) => return Ok(())
    Err(@sqlite.Collision) => ()
    Err(issue) => return Err(Database(issue))
  }
  let current = match
    store.database.read(
      @payload.publication_payload_allocation_namespace(),
      key,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  match
    store.database.compare_exchange(
      @payload.publication_payload_allocation_namespace(),
      key,
      current.revision,
      body,
    ) {
    Ok(_) => Ok(())
    Err(issue) => Err(Database(issue))
  }
}

///|
/// Called only by the existing ownership-checked cleanup paths. It records an
/// already retained identity/tombstone; it cannot create a fresh reservation.
fn insert_owned_cleanup_record(
  store : Store,
  table : String,
  key : String,
  body : Bytes,
) -> Result[Int64, @sqlite.NativeSqliteIssue] {
  match store.operation_original {
    Some(original) =>
      store.database.insert_original_store_cleanup(original, table, key, body)
    None => store.database.insert(table, key, body)
  }
}

///|
/// The allocation area of a request when, and only when, the Store proved it
/// created it: the recorded identity matches the directory found at the
/// name. Anything inside was created by this allocation, since the area was
/// empty when it was created and only this Store creates names in it.
priv struct OwnedAllocation {
  name : String
  identity : @filesystem.NativeFileOwnership
  area : @filesystem.Root
  file : @filesystem.NativeFileGeneration?
}

///|
fn owned_allocation(
  store : Store,
  request : @payload.PublicationPayloadRequest,
) -> Result[OwnedAllocation?, NativePublicationStoreIssue] {
  guard recorded_allocation(store, request)
    is Ok(Some({ name, identity: Some(identity), })) else {
    return match recorded_allocation(store, request) {
      Err(issue) => Err(issue)
      _ => Ok(None)
    }
  }
  let actual = match store.root.inspect_directory(name) {
    Ok(Some(value)) => value
    Ok(None) => return Ok(None)
    Err(@filesystem.GenerationMismatch) => return Ok(None)
    Err(issue) => return Err(Filesystem(issue))
  }
  if actual.device != identity.device || actual.inode != identity.inode {
    return Ok(None)
  }
  let area = match store.root.open_child(name) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let file = match area.inspect_generation(ALLOCATION_FILE) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  Ok(Some({ name, identity, area, file, }))
}

///|
// An intent without acquired ownership cannot distinguish a directory made
// by a dead process from a foreign entry. Absence can be synchronized and
// reclaimed; presence requires reconciliation, never name-only deletion.
fn allocation_owner_unknown(
  store : Store,
  request : @payload.PublicationPayloadRequest,
) -> Result[Bool, NativePublicationStoreIssue] {
  match recorded_allocation(store, request) {
    Ok(Some({ name, identity: None, })) =>
      match store.root.inspect_directory(name) {
        Ok(None) => Ok(false)
        Ok(Some(_)) | Err(@filesystem.GenerationMismatch) => Ok(true)
        Err(issue) => Err(Filesystem(issue))
      }
    Ok(_) => Ok(false)
    Err(issue) => Err(issue)
  }
}

///|
/// Reclaim what an owned allocation area holds: the file, only when it is
/// the recorded generation or no generation was recorded yet, then the
/// area itself once empty.
fn reclaim_owned_allocation(
  store : Store,
  record : @payload.PublicationPayloadRecord,
  allocation : OwnedAllocation,
) -> Result[Unit, NativePublicationStoreIssue] {
  match allocation.file {
    Some(generation) => {
      match @payload.publication_payload_record_ownership(record) {
        Some(owner) =>
          if !allocation_matches(generation, owner) {
            return Err(Filesystem(@filesystem.GenerationMismatch))
          }
        None => ()
      }
      match
        filesystem(
          allocation.area.reclaim_generation(ALLOCATION_FILE, generation),
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    None => ()
  }
  match
    filesystem(
      store.root.remove_directory(allocation.name, allocation.identity),
    ) {
    Ok(true) => Ok(())
    Ok(false) => Err(CleanupPending)
    Err(issue) => Err(issue)
  }
}

///|
#borrow(path)
extern "C" fn store_format_ffi(
  path : Bytes,
  length : Int,
  establish : Int,
) -> Int = "actql_native_publication_store_format"

///|
fn admit_store_format(
  root_path : String,
  establish : Bool,
  existing_only? : Bool = false,
) -> Result[Unit, NativePublicationStoreIssue] {
  let path = @utf8.encode(root_path)
  match
    store_format_ffi(
      path,
      path.length(),
      if existing_only {
        -1
      } else if establish {
        1
      } else {
        0
      },
    ) {
    0 => Ok(())
    1 => Err(LegacyStoreFormat(root_path))
    2 => Err(UnknownStoreFormat(root_path))
    _ => Err(StoreFormatIo(root_path))
  }
}

///|
priv struct PendingPayloadCleanup {
  physical : @filesystem.Writer
  mut stopped : Bool
}

///|
struct PayloadWriter {
  store : Store
  record : @payload.PublicationPayloadRecord
  physical : @filesystem.Writer
  hash : @sha.Hasher
  mut sealed_generation : @payload.PublicationPayloadGeneration?
  mut sealed_digest : String
  mut closed : Bool
}

///|
/// Exact recovery owner for one payload request whose writer could not be
/// returned or cancelled durably. It never scans or reclaims another active
/// payload occurrence.
struct PayloadCleanupOwner {
  store : Store
  request : @payload.PublicationPayloadRequest
  mut complete : Bool
}

///|
struct PayloadReader {
  store : Store
  material_generation_cid : String
  physical : @filesystem.Reader
  hash : @sha.Hasher
  expected_digest : String
  mut closed : Bool
}

///|
struct PayloadDelivery {
  reader : PayloadReader
  frames : @publication.DurableResultRowFrames
  serializer : @publication.ResultDeliverySerializer
  input_chunk_bytes : Int
  expected_rows : Int64
  max_delivery_bytes : Int64
  hash : @sha.Hasher
  mut queued_rows : Array[String]
  mut queued_index : Int
  mut pending : Bytes
  mut pending_offset : Int
  mut source_eof : Bool
  mut input_finished : Bool
  mut serializer_finished : Bool
  mut terminal : Bool
  mut produced_bytes : Int64
  mut emitted_bytes : Int64
  mut emitted_rows : Int64
  mut delivery_digest : String?
  mut closed : Bool
}

///|
struct ConfirmedPayloadDelivery {
  source : PayloadDelivery
  progress : @publication.DeliverySinkProgress
  mut closed : Bool
}

///|
struct ResultDelivery {
  store : Store
  source : ConfirmedPayloadDelivery
  index : @publication.PublicationContract
  manifest : @publication.PublicationContract
  grant : @publication.PublicationContract
  retention : @publication.PublicationContract
  result_name : String
  attempt : @publication.PublicationContract
  streaming : @publication.PublicationContract
  mut record_revision : Int64
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  mut source_summary : NativePublicationDeliverySummary?
  mut failure_confirmed : Int64?
  mut terminal_observed_at : String
  mut succeeded : NativeResultDeliverySuccess?
  mut closed : Bool
}

///|
fn[T] protocol(
  result : Result[T, @payload.PublicationPayloadIssue],
) -> Result[T, NativePublicationStoreIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(Protocol(issue))
  }
}

///|
fn[T] database(
  result : Result[T, @sqlite.NativeSqliteIssue],
) -> Result[T, NativePublicationStoreIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(Database(issue))
  }
}

///|
fn[T] filesystem(
  result : Result[T, @filesystem.NativeFilesystemIssue],
) -> Result[T, NativePublicationStoreIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(Filesystem(issue))
  }
}

///|
pub fn open_store(
  library : @sqlite.Library,
  root_path : String,
  authority_cid : String,
  capacity_bytes : Int64,
  max_objects : Int64,
  max_record_bytes : Int64,
) -> Result[Store, NativePublicationStoreIssue] {
  open_store_owned(
    library, root_path, authority_cid, capacity_bytes, max_objects, max_record_bytes,
    false,
  )
}

///|
/// Restore an existing physical Store without format or database initialization.
/// This is not evidence of original Run binding or current authority: the Host
/// must still verify those with the retained journal and Store custody location.
/// Missing, empty or divergent originals refuse; no fresh custody is substituted.
pub fn open_existing_store(
  library : @sqlite.Library,
  root_path : String,
  authority_cid : String,
  capacity_bytes : Int64,
  max_objects : Int64,
  max_record_bytes : Int64,
) -> Result[Store, NativePublicationStoreIssue] {
  open_store_owned(
    library, root_path, authority_cid, capacity_bytes, max_objects, max_record_bytes,
    true,
  )
}

///|
fn open_store_owned(
  library : @sqlite.Library,
  root_path : String,
  authority_cid : String,
  capacity_bytes : Int64,
  max_objects : Int64,
  max_record_bytes : Int64,
  existing_only : Bool,
) -> Result[Store, NativePublicationStoreIssue] {
  match
    open_store_owned_with_custody(
      library, root_path, authority_cid, capacity_bytes, max_objects, max_record_bytes,
      existing_only,
    ) {
    Ok(value) => Ok(value)
    Err(RefusedBeforeAcquisition(issue)) => Err(issue)
    Err(CleanupRequired(failure)) => {
      // Legacy issue-only entrance has no failure-custody return port. It is
      // not a funded fallback; new bounded callers select the explicit API.
      ignore(failure.retry_cleanup())
      Err(failure.issue())
    }
  }
}

///|
pub fn open_store_with_custody(
  library : @sqlite.Library,
  root_path : String,
  authority_cid : String,
  capacity_bytes : Int64,
  max_objects : Int64,
  max_record_bytes : Int64,
  diagnostic_ceiling? : Int? = None,
) -> Result[Store, NativePublicationStoreOpenError] {
  open_store_owned_with_custody(
    library,
    root_path,
    authority_cid,
    capacity_bytes,
    max_objects,
    max_record_bytes,
    false,
    diagnostic_ceiling~,
  )
}

///|
pub fn open_existing_store_with_custody(
  library : @sqlite.Library,
  root_path : String,
  authority_cid : String,
  capacity_bytes : Int64,
  max_objects : Int64,
  max_record_bytes : Int64,
  diagnostic_ceiling? : Int? = None,
) -> Result[Store, NativePublicationStoreOpenError] {
  open_store_owned_with_custody(
    library,
    root_path,
    authority_cid,
    capacity_bytes,
    max_objects,
    max_record_bytes,
    true,
    diagnostic_ceiling~,
  )
}

///|
/// Trusted selected Native Local consumer only. Selection is a physical
/// restriction, not authority or an allocation grant. The complete same-Host
/// phase/heap/FD overlap must precede this call and remain through cleanup.
pub fn open_local_store_with_custody(
  library : @sqlite.Library,
  root_path : String,
  authority_cid : String,
  capacity_bytes : Int64,
  max_objects : Int64,
  max_record_bytes : Int64,
  diagnostic_ceiling? : Int? = None,
) -> Result[Store, NativePublicationStoreOpenError] {
  open_store_owned_with_custody(
    library,
    root_path,
    authority_cid,
    capacity_bytes,
    max_objects,
    max_record_bytes,
    false,
    diagnostic_ceiling~,
    local_facility=true,
  )
}

///|
pub fn open_existing_local_store_with_custody(
  library : @sqlite.Library,
  root_path : String,
  authority_cid : String,
  capacity_bytes : Int64,
  max_objects : Int64,
  max_record_bytes : Int64,
  diagnostic_ceiling? : Int? = None,
) -> Result[Store, NativePublicationStoreOpenError] {
  open_store_owned_with_custody(
    library,
    root_path,
    authority_cid,
    capacity_bytes,
    max_objects,
    max_record_bytes,
    true,
    diagnostic_ceiling~,
    local_facility=true,
  )
}

///|
fn open_store_owned_with_custody(
  library : @sqlite.Library,
  root_path : String,
  authority_cid : String,
  capacity_bytes : Int64,
  max_objects : Int64,
  max_record_bytes : Int64,
  existing_only : Bool,
  diagnostic_ceiling? : Int? = None,
  local_facility? : Bool = false,
  operation_original? : @sqlite.NativeStoreOperationOriginal? = None,
) -> Result[Store, NativePublicationStoreOpenError] {
  if capacity_bytes < 0L ||
    max_objects < 1L ||
    max_record_bytes < 1L ||
    max_record_bytes > 2147483647L {
    return Err(RefusedBeforeAcquisition(InvalidConfiguration))
  }
  if diagnostic_ceiling is Some(value) && value <= 0 {
    return Err(RefusedBeforeAcquisition(Filesystem(@filesystem.InvalidLimit)))
  }
  let root = match
    @filesystem.open_root_with_custody(root_path, diagnostic_ceiling~) {
    Ok(value) => value
    Err(failure) =>
      return Err(
        CleanupRequired(
          store_open_failure(
            Filesystem(failure.issue()),
            failed_root=Some(failure),
          ),
        ),
      )
  }
  match admit_store_format(root_path, false, existing_only~) {
    Ok(_) => ()
    Err(issue) =>
      return Err(CleanupRequired(store_open_failure(issue, root=Some(root))))
  }
  let lock = match root.acquire_lock_with_custody(".actql-publication.lock") {
    Ok(value) => value
    Err(failure) =>
      return Err(
        CleanupRequired(
          store_open_failure(
            Filesystem(failure.issue()),
            root=Some(root),
            failed_lock=Some(failure),
          ),
        ),
      )
  }
  match admit_store_format(root_path, true, existing_only~) {
    Ok(_) => ()
    Err(issue) =>
      return Err(
        CleanupRequired(
          store_open_failure(issue, root=Some(root), lock=Some(lock)),
        ),
      )
  }
  let journal_path = root_path + "/.actql-publication.sqlite3"
  let selected = if operation_original is Some(original) {
    library.open_original_local_store_database_with_custody(
      original,
      journal_path,
      max_record_bytes,
      existing=existing_only,
    )
  } else if local_facility {
    if existing_only {
      library.open_existing_local_store_database_with_custody(
        journal_path, max_record_bytes,
      )
    } else {
      library.open_local_store_database_with_custody(
        journal_path, max_record_bytes,
      )
    }
  } else if existing_only {
    library.open_existing_database_with_custody(journal_path, max_record_bytes)
  } else {
    library.open_database_with_custody(journal_path, max_record_bytes)
  }
  let database = match selected {
    Ok(value) => value
    Err(failure) =>
      return Err(
        CleanupRequired(
          store_open_failure(
            Database(failure.issue()),
            root=Some(root),
            lock=Some(lock),
            failed_database=Some(failure),
          ),
        ),
      )
  }
  let journal_identity : @filesystem.NativeFileOwnership = match
    root.inspect_generation(".actql-publication.sqlite3") {
    Ok(Some(value)) => { device: value.device, inode: value.inode, }
    other => {
      let issue = match other {
        Err(issue) => Filesystem(issue)
        _ => StateCollision
      }
      return Err(
        CleanupRequired(
          store_open_failure(
            issue,
            root=Some(root),
            lock=Some(lock),
            database=Some(database),
          ),
        ),
      )
    }
  }
  Ok({
    root,
    lock,
    database,
    operation_original,
    operation_body_active: false,
    operation_return_pending: false,
    operation_return_primary: None,
    pending_result_delivery: None,
    authority_cid,
    journal_identity,
    capacity_bytes,
    max_objects,
    max_record_bytes: max_record_bytes.to_int(),
    active_writers: Map([]),
    pending_writers: Map([]),
    pending_allocations: Map([]),
    active_readers: Map([]),
    closed: false,
    retiring: false,
    allocation_observer: None,
    allocation_failure: Ref(None),
  })
}

///|
fn record_key(request : @payload.PublicationPayloadRequest) -> String {
  @payload.publication_payload_material_identity(request)
}

///|
fn load_record(
  store : Store,
  key : String,
) -> Result[@payload.PublicationPayloadRecord, NativePublicationStoreIssue] {
  let value = match store.database.read("publication_payload", key) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  let durable = match
    @payload.admit_durable_publication_payload_record(value.body) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  if @payload.durable_publication_payload_record_material_identity(durable) !=
    key ||
    @payload.durable_publication_payload_record_revision(durable).to_int64() !=
    value.revision {
    return Err(StateCollision)
  }
  protocol(@payload.restore_durable_publication_payload_record(durable))
}

///|
fn persist_transition(
  store : Store,
  transition : @payload.PublicationPayloadTransition,
) -> Result[@payload.PublicationPayloadRecord, NativePublicationStoreIssue] {
  let record = match
    protocol(@payload.publication_payload_transition_durable_json(transition)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let expected = @payload.publication_payload_transition_expected_revision(
    transition,
  ).to_int64()
  let key = @payload.publication_payload_transition_material_identity(
    transition,
  )
  let bytes = @utf8.encode(record)
  let durable = match
    store.database.compare_exchange("publication_payload", key, expected, bytes) {
    Ok(revision) => revision == expected + 1L
    Err(@sqlite.Collision) =>
      match store.database.read("publication_payload", key) {
        Ok(value) => value.revision == expected + 1L && value.body == bytes
        Err(issue) => return Err(Database(issue))
      }
    Err(issue) => return Err(Database(issue))
  }
  if !durable {
    return Err(StateCollision)
  }
  protocol(@payload.commit_publication_payload_transition(transition, true))
}

///|
fn filesystem_generation(
  generation : @payload.PublicationPayloadGeneration,
) -> @filesystem.NativeFileGeneration {
  { device: generation.device, inode: generation.inode, size: generation.size, }
}

///|
fn payload_generation(
  generation : @filesystem.NativeFileGeneration,
) -> @payload.PublicationPayloadGeneration {
  { device: generation.device, inode: generation.inode, size: generation.size, }
}

///|
fn payload_ownership(
  ownership : @filesystem.NativeFileOwnership,
) -> @payload.PublicationPayloadOwnership {
  { device: ownership.device, inode: ownership.inode, }
}

///|
fn allocation_matches(
  generation : @filesystem.NativeFileGeneration,
  ownership : @payload.PublicationPayloadOwnership,
) -> Bool {
  generation.device == ownership.device && generation.inode == ownership.inode
}

///|
fn discovered_generations(
  store : Store,
  request : @payload.PublicationPayloadRequest,
) -> Result[
  (
    @filesystem.NativeFileGeneration?,
    @filesystem.NativeFileGeneration?,
    OwnedAllocation?,
  ),
  NativePublicationStoreIssue,
] {
  // The allocation area, when the Store proved it created it.
  let allocation = match owned_allocation(store, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let staging = match
    store.root.inspect_generation(
      @payload.publication_payload_staging_name(request),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let committed = match
    store.root.inspect_generation(
      @payload.publication_payload_object_name(request),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  Ok((staging, committed, allocation))
}

///|
fn reclaimable_generation(
  record : @payload.PublicationPayloadRecord,
  actual : @filesystem.NativeFileGeneration,
  committed_name : Bool,
) -> Result[Bool, NativePublicationStoreIssue] {
  // A record without durable ownership never reached a public name: the
  // file is created under the private allocation name and linked to its
  // public name only after the ownership is durable. A file found at a
  // public name is then foreign and is left alone.
  guard @payload.publication_payload_record_ownership(record) is Some(owner) else {
    return Ok(false)
  }
  if !allocation_matches(actual, owner) {
    // The owned generation is known: another generation at the public
    // staging name is a foreign file (the owned one never got that name, or
    // lost it), and at the committed name it is foreign as long as nothing
    // was committed. Both are left alone.
    return if !committed_name ||
      @payload.publication_payload_record_generation(record) is None {
      Ok(false)
    } else {
      Err(Filesystem(@filesystem.GenerationMismatch))
    }
  }
  if @payload.publication_payload_record_generation(record) is Some(expected) &&
    filesystem_generation(expected) != actual {
    return Err(Filesystem(@filesystem.GenerationMismatch))
  }
  Ok(true)
}

///|
fn reclaim_record_internal(
  store : Store,
  record : @payload.PublicationPayloadRecord,
  known_unallocated : Bool,
  pending_owner : Bool,
) -> Result[Unit, NativePublicationStoreIssue] {
  let request = @payload.publication_payload_record_request(record)
  let key = record_key(request)
  if store.active_writers.contains(key) {
    return Err(CleanupPending)
  }
  if !pending_owner && store.pending_writers.contains(key) {
    return Err(CleanupPending)
  }
  if store.active_readers.get(key).unwrap_or(0) != 0 {
    return Err(ReaderBusy)
  }
  if store.pending_allocations.get(key) is Some(allocation) {
    if known_unallocated {
      return Err(StateCollision)
    }
    // A failed ownership write does not discard the identity returned by
    // exclusive creation. Make that exact identity durable before recovery
    // proceeds; failure keeps both this owner and its reservation.
    match
      allocation_prepare(store, "identity", fn() {
        record_allocation(store, key, allocation, cleanup_owned=true)
      }) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let state = @payload.publication_payload_record_state(record)
  if state == @payload.Reclaimed {
    match
      database(
        store.database.release_capacity(
          "publication_payload",
          key,
          @payload.publication_payload_request_max_bytes(request),
          1L,
        ),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    return Ok(())
  }
  let found = match discovered_generations(store, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut reclaim_staging = false
  let mut reclaim_committed = false
  let mut reclaim_allocation = false
  if !known_unallocated {
    if found.0 is Some(value) {
      reclaim_staging = match reclaimable_generation(record, value, false) {
        Ok(result) => result
        Err(issue) => return Err(issue)
      }
    }
    if found.1 is Some(value) {
      reclaim_committed = match reclaimable_generation(record, value, true) {
        Ok(result) => result
        Err(issue) => return Err(issue)
      }
    }
    reclaim_allocation = found.2 is Some(_)
  } else if @payload.publication_payload_record_ownership(record) is Some(_) ||
    @payload.publication_payload_record_generation(record) is Some(_) {
    return Err(StateCollision)
  }
  if state != @payload.Reclaiming {
    let transition = match
      protocol(@payload.prepare_publication_payload_reclaiming(record)) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match persist_transition(store, transition) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  } else if !known_unallocated {
    if found.0 is Some(value) {
      reclaim_staging = match reclaimable_generation(record, value, false) {
        Ok(result) => result
        Err(issue) => return Err(issue)
      }
    }
    if found.1 is Some(value) {
      reclaim_committed = match reclaimable_generation(record, value, true) {
        Ok(result) => result
        Err(issue) => return Err(issue)
      }
    }
    reclaim_allocation = found.2 is Some(_)
  }
  if !known_unallocated {
    match allocation_owner_unknown(store, request) {
      Ok(true) => return Err(RecoveryRequired)
      Ok(false) => ()
      Err(issue) => return Err(issue)
    }
  }
  if !known_unallocated {
    if reclaim_allocation && found.2 is Some(allocation) {
      match reclaim_owned_allocation(store, record, allocation) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    if reclaim_staging && found.0 is Some(generation) {
      match
        filesystem(
          store.root.reclaim_generation(
            @payload.publication_payload_staging_name(request),
            generation,
          ),
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    if reclaim_committed && found.1 is Some(generation) {
      match
        filesystem(
          store.root.reclaim_generation(
            @payload.publication_payload_object_name(request),
            generation,
          ),
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
  }
  // A prior reclaim attempt can unlink the last visible name and then fail
  // while synchronizing the directory. Absence on retry is not durable proof
  // of deletion, so confirm the directory before releasing capacity or
  // persisting Reclaimed even when no generation name remains.
  match filesystem(store.root.sync_directory()) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    database(
      store.database.release_capacity(
        "publication_payload",
        key,
        @payload.publication_payload_request_max_bytes(request),
        1L,
      ),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let transition = match
    protocol(@payload.prepare_publication_payload_reclaimed(record)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match persist_transition(store, transition) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  ignore(store.pending_allocations.remove(key))
  Ok(())
}

///|
fn reclaim_record(
  store : Store,
  record : @payload.PublicationPayloadRecord,
) -> Result[Unit, NativePublicationStoreIssue] {
  reclaim_record_internal(store, record, false, false)
}

///|
fn reclaim_unallocated_record(
  store : Store,
  record : @payload.PublicationPayloadRecord,
) -> Result[Unit, NativePublicationStoreIssue] {
  reclaim_record_internal(store, record, true, false)
}

///|
fn cleanup_after_begin_failure(
  store : Store,
  record : @payload.PublicationPayloadRecord,
) -> Bool {
  reclaim_unallocated_record(store, record) is Ok(_)
}

///|
fn retain_pending_writer(
  store : Store,
  record : @payload.PublicationPayloadRecord,
  physical : @filesystem.Writer,
  stopped : Bool,
) -> Result[Unit, NativePublicationStoreIssue] {
  let key = record_key(@payload.publication_payload_record_request(record))
  if store.pending_writers.contains(key) {
    return Err(StateCollision)
  }
  ignore(store.active_writers.remove(key))
  store.pending_writers[key] = { physical, stopped, }
  Ok(())
}

///|
fn retry_pending_writer(
  store : Store,
  key : String,
) -> Result[Bool, NativePublicationStoreIssue] {
  guard store.pending_writers.get(key) is Some(pending) else {
    return Ok(false)
  }
  if !pending.stopped {
    match filesystem(pending.physical.cancel()) {
      Ok(_) => pending.stopped = true
      Err(issue) => return Err(issue)
    }
  }
  ignore(store.pending_writers.remove(key))
  let current = match load_record(store, key) {
    Ok(value) => value
    Err(issue) => {
      store.pending_writers[key] = pending
      return Err(issue)
    }
  }
  match reclaim_record_internal(store, current, false, true) {
    Ok(_) => Ok(true)
    Err(issue) => {
      store.pending_writers[key] = pending
      Err(issue)
    }
  }
}

///|
/// Acquire the cleanup responsibility retained by one exact payload request.
/// The caller must use this only after an operation reports that cleanup is
/// pending; ordinary admission rejection grants no recovery authority.
pub fn Store::acquire_payload_cleanup(
  self : Store,
  request : @payload.PublicationPayloadRequest,
) -> Result[PayloadCleanupOwner, NativePublicationStoreIssue] {
  self.with_original_read(true, false, fn() {
    self.acquire_payload_cleanup_in_scope(request)
  })
}

///|
fn Store::acquire_payload_cleanup_in_scope(
  self : Store,
  request : @payload.PublicationPayloadRequest,
) -> Result[PayloadCleanupOwner, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  if @payload.publication_payload_request_store_authority(request) !=
    self.authority_cid {
    return Err(StateCollision)
  }
  let key = record_key(request)
  let current = match load_record(self, key) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @payload.publication_payload_request_identity(
      @payload.publication_payload_record_request(current),
    ) !=
    @payload.publication_payload_request_identity(request) {
    return Err(StateCollision)
  }
  Ok({ store: self, request, complete: false, })
}

///|
pub fn PayloadCleanupOwner::pending(self : PayloadCleanupOwner) -> Bool {
  !self.complete
}

///|
/// Retry only the exact pending writer or durable payload record fixed when
/// this owner was acquired.
pub fn PayloadCleanupOwner::retry(
  self : PayloadCleanupOwner,
) -> Result[Bool, NativePublicationStoreIssue] {
  self.store.with_original_read(true, false, fn() { self.retry_in_scope() })
}

///|
fn PayloadCleanupOwner::retry_in_scope(
  self : PayloadCleanupOwner,
) -> Result[Bool, NativePublicationStoreIssue] {
  if self.complete {
    return Ok(false)
  }
  match require_store_open(self.store) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let key = record_key(self.request)
  if self.store.pending_writers.contains(key) {
    match retry_pending_writer(self.store, key) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  } else {
    let current = match load_record(self.store, key) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match reclaim_record(self.store, current) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  self.complete = true
  Ok(true)
}

///|
pub fn Store::begin_payload(
  self : Store,
  request : @payload.PublicationPayloadRequest,
) -> Result[PayloadWriter, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.begin_payload_in_scope(request)
  })
}

///|
fn Store::begin_payload_in_scope(
  self : Store,
  request : @payload.PublicationPayloadRequest,
) -> Result[PayloadWriter, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  if @payload.publication_payload_request_store_authority(request) !=
    self.authority_cid {
    return Err(StateCollision)
  }
  let key = record_key(request)
  if self.active_writers.contains(key) {
    return Err(RecoveryRequired)
  }
  let record = @payload.prepare_publication_payload_record(request)
  let initial = match
    protocol(@payload.publication_payload_record_durable_json(record)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    self.database.insert("publication_payload", key, @utf8.encode(initial)) {
    Ok(revision) => if revision != 0L { return Err(StateCollision) }
    Err(@sqlite.Collision) => {
      let existing = match load_record(self, key) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if @payload.publication_payload_request_identity(
          @payload.publication_payload_record_request(existing),
        ) !=
        @payload.publication_payload_request_identity(request) {
        return Err(StateCollision)
      }
      return if @payload.publication_payload_record_state(existing) ==
        @payload.Sealed {
        Err(ExistingPayload)
      } else {
        Err(RecoveryRequired)
      }
    }
    Err(issue) => return Err(Database(issue))
  }
  match
    self.database.reserve_capacity(
      "publication_payload",
      key,
      @payload.publication_payload_request_max_bytes(request),
      1L,
      self.capacity_bytes,
      self.max_objects,
    ) {
    Ok(_) => ()
    Err(issue) => {
      if !cleanup_after_begin_failure(self, record) {
        return Err(CleanupPending)
      }
      return Err(Database(issue))
    }
  }
  let reserved = match
    protocol(@payload.prepare_publication_payload_reserved(record)) {
    Ok(transition) =>
      match persist_transition(self, transition) {
        Ok(value) => value
        Err(issue) => {
          if !cleanup_after_begin_failure(self, record) {
            return Err(CleanupPending)
          }
          return Err(issue)
        }
      }
    Err(issue) => return Err(issue)
  }
  let writing = match
    protocol(@payload.prepare_publication_payload_writing(reserved)) {
    Ok(transition) =>
      match persist_transition(self, transition) {
        Ok(value) => value
        Err(issue) => {
          if !cleanup_after_begin_failure(self, record) {
            return Err(CleanupPending)
          }
          return Err(issue)
        }
      }
    Err(issue) => return Err(issue)
  }
  // Record the allocation intent before creation; the name alone never
  // authorizes deleting an entry found there.
  let ordinal = match next_allocation_ordinal(self, request) {
    Ok(value) => value
    Err(issue) => {
      if !cleanup_after_begin_failure(self, writing) {
        return Err(CleanupPending)
      }
      return Err(issue)
    }
  }
  let name = allocation_name(request, ordinal)
  match record_allocation(self, key, { name, identity: None, }) {
    Ok(_) => ()
    Err(issue) => {
      if !cleanup_after_begin_failure(self, writing) {
        return Err(CleanupPending)
      }
      return Err(issue)
    }
  }
  observe(self, "allocation-recorded")
  // The allocation area is created exclusively; a name already taken is a
  // conflict and nothing there is touched. Its identity is recorded before
  // anything is created inside it, so a file found there later is this
  // allocation's by that identity, never by the name.
  let identity = match self.root.create_directory(name) {
    Ok(value) => value
    Err(issue) => {
      let acquired = allocation_acquired_ffi(self.root)
      if acquired != 0 {
        if acquired == 2 {
          self.pending_allocations[key] = {
            name,
            identity: Some({
              device: allocation_device_ffi(self.root),
              inode: allocation_inode_ffi(self.root),
            }),
          }
        }
        if reclaim_record(self, writing) is Err(_) {
          return Err(CleanupPending)
        }
        return Err(Filesystem(issue))
      }
      if !cleanup_after_begin_failure(self, writing) {
        return Err(CleanupPending)
      }
      return Err(Filesystem(issue))
    }
  }
  let allocation = { name, identity: Some(identity), }
  self.pending_allocations[key] = allocation
  observe(self, "allocation-created")
  match
    allocation_prepare(self, "identity", fn() {
      record_allocation(self, key, allocation)
    }) {
    Ok(_) => ignore(self.pending_allocations.remove(key))
    Err(issue) => {
      if reclaim_record(self, writing) is Err(_) {
        return Err(CleanupPending)
      }
      return Err(issue)
    }
  }
  let area = match
    allocation_prepare(self, "open", fn() {
      filesystem(self.root.open_child(name))
    }) {
    Ok(value) => value
    Err(issue) => {
      if reclaim_record(self, writing) is Err(_) {
        return Err(CleanupPending)
      }
      return Err(issue)
    }
  }
  let physical = match
    allocation_prepare(self, "writer", fn() {
      filesystem(
        area.create_writer(
          ALLOCATION_FILE,
          @payload.publication_payload_request_max_bytes(request),
        ),
      )
    }) {
    Ok(value) => value
    Err(issue) => {
      if reclaim_record(self, writing) is Err(_) {
        return Err(CleanupPending)
      }
      return Err(issue)
    }
  }
  observe(self, "allocated")
  let owned = match
    protocol(
      @payload.prepare_publication_payload_owned(
        writing,
        payload_ownership(physical.ownership()),
      ),
    ) {
    Ok(transition) =>
      match persist_transition(self, transition) {
        Ok(value) => value
        Err(issue) => {
          let stopped = physical.cancel() is Ok(_)
          let current = load_record(self, key).unwrap_or(writing)
          if stopped && reclaim_record(self, current) is Ok(_) {
            return Err(issue)
          }
          match retain_pending_writer(self, current, physical, stopped) {
            Ok(_) => return Err(CleanupPending)
            Err(_) => return Err(CleanupPending)
          }
        }
      }
    Err(issue) => {
      let stopped = physical.cancel() is Ok(_)
      if stopped && reclaim_record(self, writing) is Ok(_) {
        return Err(issue)
      }
      match retain_pending_writer(self, writing, physical, stopped) {
        Ok(_) => return Err(CleanupPending)
        Err(_) => return Err(CleanupPending)
      }
    }
  }
  observe(self, "owned")
  // Only now does the file get its public staging name, exclusively: a
  // foreign file there is a conflict, is never replaced, and this owned
  // allocation is reclaimed by its record.
  match
    physical.adopt_name(
      self.root,
      @payload.publication_payload_staging_name(request),
    ) {
    Ok(_) =>
      // The area is empty now; if it cannot go yet, recovery removes it by
      // its identity later.
      ignore(self.root.remove_directory(name, identity))
    Err(issue) => {
      let stopped = physical.cancel() is Ok(_)
      let current = load_record(self, key).unwrap_or(owned)
      if stopped && reclaim_record(self, current) is Ok(_) {
        return Err(Filesystem(issue))
      }
      match retain_pending_writer(self, current, physical, stopped) {
        Ok(_) => return Err(CleanupPending)
        Err(_) => return Err(CleanupPending)
      }
    }
  }
  self.active_writers[key] = true
  Ok({
    store: self,
    record: owned,
    physical,
    hash: @sha.hasher(),
    sealed_generation: None,
    sealed_digest: "",
    closed: false,
  })
}

///|
pub fn PayloadWriter::append(
  self : PayloadWriter,
  chunk : Bytes,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.store.with_original_read(false, false, fn() {
    self.append_in_scope(chunk)
  })
}

///|
fn PayloadWriter::append_in_scope(
  self : PayloadWriter,
  chunk : Bytes,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  match filesystem(self.physical.append(chunk)) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  @sha.update(self.hash, chunk) catch {
    _ => return Err(StateCollision)
  }
  Ok(())
}

///|
fn payload_info(
  record : @payload.PublicationPayloadRecord,
) -> Result[NativePublicationPayloadInfo, NativePublicationStoreIssue] {
  let request = @payload.publication_payload_record_request(record)
  let generation = match
    @payload.publication_payload_record_generation(record) {
    Some(value) => filesystem_generation(value)
    None => return Err(StateCollision)
  }
  Ok({
    material_generation_cid: @payload.publication_payload_material_identity(
      request,
    ),
    publication_attempt_cid: @payload.publication_payload_request_attempt(
      request,
    ),
    result_definition_cid: @payload.publication_payload_request_result_definition(
      request,
    ),
    logical_relation_cid: @payload.publication_payload_request_logical_relation(
      request,
    ),
    result_schema_cid: @payload.publication_payload_request_schema(request),
    ordering_evidence_cid: @payload.publication_payload_request_ordering_evidence(
      request,
    ),
    durable_codec_cid: @payload.publication_payload_request_codec(request),
    row_count: @payload.publication_payload_request_row_count(request),
    physical_digest: @payload.publication_payload_record_digest(record),
    object_name: @payload.publication_payload_object_name(request),
    generation,
  })
}

///|
pub fn PayloadWriter::seal(
  self : PayloadWriter,
) -> Result[NativePublicationPayloadInfo, NativePublicationStoreIssue] {
  self.store.with_original_read(false, false, fn() { self.seal_in_scope() })
}

///|
fn PayloadWriter::seal_in_scope(
  self : PayloadWriter,
) -> Result[NativePublicationPayloadInfo, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.sealed_generation is None {
    let request = @payload.publication_payload_record_request(self.record)
    let physical = match
      filesystem(
        self.physical.seal(@payload.publication_payload_object_name(request)),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let digest = @sha.finish_hex(self.hash) catch {
      _ => return Err(StateCollision)
    }
    self.sealed_generation = Some(payload_generation(physical))
    self.sealed_digest = "sha256:" + digest
  }
  let generation = self.sealed_generation.unwrap()
  let transition = match
    protocol(
      @payload.prepare_publication_payload_sealed(
        self.record,
        generation,
        self.sealed_digest,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let record = match persist_transition(self.store, transition) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let key = record_key(@payload.publication_payload_record_request(record))
  ignore(self.store.active_writers.remove(key))
  self.closed = true
  payload_info(record)
}

///|
pub fn PayloadWriter::cancel(
  self : PayloadWriter,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.store.with_original_read(true, false, fn() { self.cancel_in_scope() })
}

///|
fn PayloadWriter::cancel_in_scope(
  self : PayloadWriter,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Ok(())
  }
  match filesystem(self.physical.cancel()) {
    Ok(_) => ()
    Err(issue) => {
      match
        retain_pending_writer(self.store, self.record, self.physical, false) {
        Ok(_) => self.closed = true
        Err(_) => ()
      }
      return Err(issue)
    }
  }
  let key = record_key(@payload.publication_payload_record_request(self.record))
  ignore(self.store.active_writers.remove(key))
  match reclaim_record(self.store, self.record) {
    Ok(_) => {
      self.closed = true
      Ok(())
    }
    Err(issue) => {
      match
        retain_pending_writer(self.store, self.record, self.physical, true) {
        Ok(_) => self.closed = true
        Err(_) => self.store.active_writers[key] = true
      }
      Err(issue)
    }
  }
}

///|
pub fn Store::inspect_payload(
  self : Store,
  material_generation_cid : String,
) -> Result[NativePublicationPayloadInfo, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.inspect_payload_in_scope(material_generation_cid)
  })
}

///|
fn Store::inspect_payload_in_scope(
  self : Store,
  material_generation_cid : String,
) -> Result[NativePublicationPayloadInfo, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  let record = match load_record(self, material_generation_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @payload.publication_payload_record_state(record) != @payload.Sealed {
    return Err(RecoveryRequired)
  }
  let info = match payload_info(record) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !self.root.verify_generation(info.object_name, info.generation) {
    return Err(Filesystem(@filesystem.GenerationMismatch))
  }
  Ok(info)
}

///|
/// Reconcile one exact payload request without creating a second writer.
/// Absence is distinct from an unresolved or conflicting durable occurrence.
pub fn Store::reconcile_payload(
  self : Store,
  request : @payload.PublicationPayloadRequest,
) -> Result[NativePublicationPayloadInfo?, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.reconcile_payload_in_scope(request)
  })
}

///|
fn Store::reconcile_payload_in_scope(
  self : Store,
  request : @payload.PublicationPayloadRequest,
) -> Result[NativePublicationPayloadInfo?, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  if @payload.publication_payload_request_store_authority(request) !=
    self.authority_cid {
    return Err(StateCollision)
  }
  let key = record_key(request)
  let record = match load_record(self, key) {
    Ok(value) => value
    Err(Database(@sqlite.NotFound)) => return Ok(None)
    Err(issue) => return Err(issue)
  }
  if @payload.publication_payload_request_identity(
      @payload.publication_payload_record_request(record),
    ) !=
    @payload.publication_payload_request_identity(request) {
    return Err(StateCollision)
  }
  if @payload.publication_payload_record_state(record) != @payload.Sealed {
    return Err(RecoveryRequired)
  }
  let info = match payload_info(record) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !self.root.verify_generation(info.object_name, info.generation) {
    return Err(Filesystem(@filesystem.GenerationMismatch))
  }
  Ok(Some(info))
}

///|
pub fn Store::open_payload_reader(
  self : Store,
  material_generation_cid : String,
) -> Result[PayloadReader, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.open_payload_reader_in_scope(material_generation_cid)
  })
}

///|
fn Store::open_payload_reader_in_scope(
  self : Store,
  material_generation_cid : String,
) -> Result[PayloadReader, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let info = match self.inspect_payload_in_scope(material_generation_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let physical = match
    filesystem(self.root.open_reader(info.object_name, info.generation)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.active_readers[material_generation_cid] = self.active_readers
    .get(material_generation_cid)
    .unwrap_or(0) +
    1
  Ok({
    store: self,
    material_generation_cid,
    physical,
    hash: @sha.hasher(),
    expected_digest: info.physical_digest,
    closed: false,
  })
}

///|
pub fn PayloadReader::next(
  self : PayloadReader,
  max_bytes : Int,
) -> Result[@filesystem.NativeFileChunk, NativePublicationStoreIssue] {
  self.store.with_original_read(false, false, fn() {
    self.next_in_scope(max_bytes)
  })
}

///|
fn PayloadReader::next_in_scope(
  self : PayloadReader,
  max_bytes : Int,
) -> Result[@filesystem.NativeFileChunk, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  let chunk = match filesystem(self.physical.next(max_bytes)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @sha.update(self.hash, chunk.bytes) catch {
    _ => return Err(StateCollision)
  }
  Ok(chunk)
}

///|
fn PayloadReader::release_pin(self : PayloadReader) -> Unit {
  let count = self.store.active_readers
    .get(self.material_generation_cid)
    .unwrap_or(0)
  if count <= 1 {
    ignore(self.store.active_readers.remove(self.material_generation_cid))
  } else {
    self.store.active_readers[self.material_generation_cid] = count - 1
  }
  self.closed = true
}

///|
pub fn PayloadReader::finish(
  self : PayloadReader,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.store.with_original_read(false, false, fn() { self.finish_in_scope() })
}

///|
fn PayloadReader::finish_in_scope(
  self : PayloadReader,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  match filesystem(self.physical.finish()) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let actual = "sha256:" +
    (@sha.finish_hex(self.hash) catch { _ => return Err(StateCollision) })
  self.release_pin()
  if actual != self.expected_digest {
    Err(DigestMismatch)
  } else {
    Ok(())
  }
}

///|
pub fn PayloadReader::close(
  self : PayloadReader,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.store.with_original_read(true, false, fn() { self.close_in_scope() })
}

///|
fn PayloadReader::close_in_scope(
  self : PayloadReader,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Ok(())
  }
  match filesystem(self.physical.close()) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.release_pin()
  Ok(())
}

///|
fn delivery(
  result : Result[String, @publication.DeliverySerializationIssue],
) -> Result[String, NativePublicationStoreIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(Delivery(issue))
  }
}

///|
fn[T] sink_progress(
  result : Result[T, @publication.DeliverySinkProgressIssue],
) -> Result[T, NativePublicationStoreIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(SinkProgress(issue))
  }
}

///|
fn[T] delivery_issuance(
  result : Result[T, @publication.DeliveryIssuanceIssue],
) -> Result[T, NativePublicationStoreIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(DeliveryIssuance(issue))
  }
}

///|
fn put_publication_contract(
  store : Store,
  contract : @publication.PublicationContract,
) -> Result[Unit, NativePublicationStoreIssue] {
  let identity = @publication.publication_contract_identity(contract)
  let body = @utf8.encode(@publication.publication_contract_json(contract))
  match store.database.insert("publication_contract", identity, body) {
    Ok(_) => Ok(())
    Err(@sqlite.Collision) => {
      let existing = match
        store.database.read("publication_contract", identity) {
        Ok(value) => value
        Err(issue) => return Err(Database(issue))
      }
      if existing.body == body {
        Ok(())
      } else {
        Err(StateCollision)
      }
    }
    Err(issue) => Err(Database(issue))
  }
}

///|
fn load_publication_contract(
  store : Store,
  name : String,
  identity : String,
) -> Result[@publication.PublicationContract, NativePublicationStoreIssue] {
  let stored = match store.database.read("publication_contract", identity) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  let wire = @utf8.decode(stored.body) catch { _ => return Err(StateCollision) }
  let contract = match
    @publication.admit_publication_contract(
      name,
      wire,
      store.max_record_bytes,
      store.max_record_bytes,
      64,
    ) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  if @publication.publication_contract_identity(contract) != identity {
    return Err(StateCollision)
  }
  Ok(contract)
}

///|
/// Load and re-admit one exact publication contract from durable storage.
/// Callers must separately establish authority for the requested identity.
pub fn Store::read_publication_contract(
  self : Store,
  name : String,
  identity : String,
) -> Result[@publication.PublicationContract, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.read_publication_contract_in_scope(name, identity)
  })
}

///|
fn Store::read_publication_contract_in_scope(
  self : Store,
  name : String,
  identity : String,
) -> Result[@publication.PublicationContract, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  load_publication_contract(self, name, identity)
}

///|
fn put_result_schema(
  store : Store,
  result_schema_cid : String,
  result_schema_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, NativePublicationStoreIssue] {
  match
    delivery_issuance(
      @publication.validate_result_schema_wire(
        result_schema_cid, result_schema_wire, max_wire_bytes, max_nodes, max_depth,
      ),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let body = @utf8.encode(result_schema_wire)
  match store.database.insert("result_schema", result_schema_cid, body) {
    Ok(_) => Ok(())
    Err(@sqlite.Collision) => {
      let existing = match
        store.database.read("result_schema", result_schema_cid) {
        Ok(value) => value
        Err(issue) => return Err(Database(issue))
      }
      if existing.body == body {
        Ok(())
      } else {
        Err(StateCollision)
      }
    }
    Err(issue) => Err(Database(issue))
  }
}

///|
/// Load and revalidate the canonical schema retained for a committed Result.
pub fn Store::read_result_schema(
  self : Store,
  result_schema_cid : String,
) -> Result[String, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.read_result_schema_in_scope(result_schema_cid)
  })
}

///|
fn Store::read_result_schema_in_scope(
  self : Store,
  result_schema_cid : String,
) -> Result[String, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  let stored = match self.database.read("result_schema", result_schema_cid) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  let wire = @utf8.decode(stored.body) catch { _ => return Err(StateCollision) }
  match
    delivery_issuance(
      @publication.validate_result_schema_wire(
        result_schema_cid,
        wire,
        self.max_record_bytes,
        self.max_record_bytes,
        64,
      ),
    ) {
    Ok(_) => Ok(wire)
    Err(_) => Err(StateCollision)
  }
}

///|
fn publication_commit(
  result : Result[Unit, @publication.PublicationCommitIssue],
) -> Result[Unit, NativePublicationStoreIssue] {
  match result {
    Ok(_) => Ok(())
    Err(issue) => Err(PublicationCommit(issue))
  }
}

///|
fn publication_commit_key(
  result : Result[String, @publication.PublicationCommitIssuanceIssue],
) -> Result[String, NativePublicationStoreIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(PublicationCommitIssuance(issue))
  }
}

///|
/// Persist a monotonic observation for one admitted clock contract. A process
/// restart or concurrent observer cannot move the durable lower bound back.
pub fn Store::observe_trusted_clock(
  self : Store,
  clock_contract_cid : String,
  observed_at : String,
) -> Result[String, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.observe_trusted_clock_in_scope(clock_contract_cid, observed_at)
  })
}

///|
fn Store::observe_trusted_clock_in_scope(
  self : Store,
  clock_contract_cid : String,
  observed_at : String,
) -> Result[String, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  if !@publication.trusted_clock_not_before(None, observed_at) {
    return Err(ClockRegression)
  }
  let body = @utf8.encode(observed_at)
  for retry = 0; retry < 16; retry = retry + 1 {
    let current = match
      self.database.read("trusted_clock", clock_contract_cid) {
      Ok(value) => Some(value)
      Err(@sqlite.NotFound) => None
      Err(issue) => return Err(Database(issue))
    }
    match current {
      None =>
        match self.database.insert("trusted_clock", clock_contract_cid, body) {
          Ok(_) => return Ok(observed_at)
          Err(@sqlite.Collision) => continue
          Err(issue) => return Err(Database(issue))
        }
      Some(value) => {
        let previous = @utf8.decode(value.body) catch {
          _ => return Err(StateCollision)
        }
        if !@publication.trusted_clock_not_before(Some(previous), observed_at) {
          return Err(ClockRegression)
        }
        if previous == observed_at {
          return Ok(observed_at)
        }
        match
          self.database.compare_exchange(
            "trusted_clock",
            clock_contract_cid,
            value.revision,
            body,
          ) {
          Ok(_) => return Ok(observed_at)
          Err(@sqlite.Collision) => continue
          Err(issue) => return Err(Database(issue))
        }
      }
    }
  }
  Err(Database(@sqlite.Busy))
}

///|
/// Make one fully validated Run-bound publication visible. Semantic contracts
/// are durable before the single scoped index row is installed. An exact
/// retry returns the existing commit; a different publication for the same
/// scoped Run is a conflict.
pub fn Store::commit_publication(
  self : Store,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  derivations : Array[@publication.PublicationContract],
  orderings : Array[@publication.PublicationContract],
  retentions : Array[@publication.PublicationContract],
  bindings : Array[@publication.PublicationContract],
  binding_schema_wires : Array[String],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  index : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  capture? : @local.ClientProgramCapture? = None,
) -> Result[NativePublicationCommit, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.commit_publication_in_scope(
      run_definition,
      invocation,
      definitions,
      artifacts,
      derivations,
      orderings,
      retentions,
      bindings,
      binding_schema_wires,
      manifest,
      receipt,
      captured_run,
      request,
      attempt,
      index,
      max_wire_bytes,
      max_nodes,
      max_depth,
      capture~,
    )
  })
}

///|
fn Store::commit_publication_in_scope(
  self : Store,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  derivations : Array[@publication.PublicationContract],
  orderings : Array[@publication.PublicationContract],
  retentions : Array[@publication.PublicationContract],
  bindings : Array[@publication.PublicationContract],
  binding_schema_wires : Array[String],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  index : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  capture? : @local.ClientProgramCapture? = None,
) -> Result[NativePublicationCommit, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  if bindings.length() != binding_schema_wires.length() {
    return Err(InvalidConfiguration)
  }
  let checked = match capture {
    Some(original) =>
      @local.check_program_commit_validation(
        original, run_definition, invocation, definitions, artifacts, derivations,
        orderings, retentions, bindings, manifest, receipt, captured_run, request,
        attempt, index,
      ).map_err(issue => {
        NativePublicationStoreIssue::PublicationPreparation(issue)
      })
    None =>
      publication_commit(
        @publication.validate_effect_free_publication_commit_with_result_evidence(
          run_definition, invocation, definitions, artifacts, derivations, orderings,
          retentions, bindings, manifest, receipt, captured_run, request, attempt,
          index, max_wire_bytes, max_nodes, max_depth,
        ),
      )
  }
  match checked {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    self.observe_publication_payload_facts_in_scope(
      bindings, binding_schema_wires, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let key = match
    publication_commit_key(
      @publication.publication_index_storage_key(
        index, max_wire_bytes, max_nodes, max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let contracts : Array[@publication.PublicationContract] = [
    run_definition, invocation, manifest, receipt, captured_run, request, attempt,
  ]
  for
    values in [
      definitions, artifacts, derivations, orderings, retentions, bindings,
    ] {
    for contract in values {
      contracts.push(contract)
    }
  }
  contracts.push(index)
  for contract in contracts {
    match put_publication_contract(self, contract) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  for binding_index, binding in bindings {
    let projected = match
      delivery_issuance(
        @publication.project_durable_result_binding_read(binding),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match
      put_result_schema(
        self,
        projected.result_schema_cid,
        binding_schema_wires[binding_index],
        max_wire_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let identity = @publication.publication_contract_identity(index)
  let body = @utf8.encode(identity)
  match self.database.insert("public_index", key, body) {
    Ok(_) =>
      Ok({
        public_index_entry_cid: identity,
        committed: true,
        idempotent: false,
      })
    Err(@sqlite.Collision) => {
      let existing = match self.database.read("public_index", key) {
        Ok(value) => value
        Err(issue) => return Err(Database(issue))
      }
      if existing.body != body {
        return Err(PublicationCommitConflict)
      }
      Ok({
        public_index_entry_cid: identity,
        committed: false,
        idempotent: true,
      })
    }
    Err(issue) => Err(Database(issue))
  }
}

///|
/// Resolve one durably committed index after the caller has separately
/// authorized the scoped lookup. SQLite FULL durability makes a returned row
/// the confirmed commit boundary rather than a process-local observation.
pub fn Store::inspect_committed_publication(
  self : Store,
  namespace_id : String,
  authority_scope_cid : String,
  run_definition_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.PublicationContract?, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.inspect_committed_publication_in_scope(
      namespace_id, authority_scope_cid, run_definition_cid, max_wire_bytes, max_nodes,
      max_depth,
    )
  })
}

///|
fn Store::inspect_committed_publication_in_scope(
  self : Store,
  namespace_id : String,
  authority_scope_cid : String,
  run_definition_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.PublicationContract?, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  let key = match
    publication_commit_key(
      @publication.publication_index_scope_storage_key(
        namespace_id, authority_scope_cid, run_definition_cid, max_wire_bytes, max_nodes,
        max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let stored = match self.database.read("public_index", key) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Ok(None)
    Err(issue) => return Err(Database(issue))
  }
  let identity = @utf8.decode(stored.body) catch {
    _ => return Err(StateCollision)
  }
  let index = match
    load_publication_contract(self, "public_index_entry", identity) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let actual_key = match
    publication_commit_key(
      @publication.publication_index_storage_key(
        index, max_wire_bytes, max_nodes, max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if actual_key != key {
    return Err(StateCollision)
  }
  Ok(Some(index))
}

///|
/// Resolve one authorized Result name through the durable public index. The
/// portable publication owner selects and validates the exact binding; this
/// adapter only retrieves the indexed bodies.
pub fn Store::resolve_committed_result(
  self : Store,
  namespace_id : String,
  authority_scope_cid : String,
  run_definition_cid : String,
  result_name : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[NativeCommittedResult?, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.resolve_committed_result_in_scope(
      namespace_id, authority_scope_cid, run_definition_cid, result_name, max_wire_bytes,
      max_nodes, max_depth,
    )
  })
}

///|
fn Store::resolve_committed_result_in_scope(
  self : Store,
  namespace_id : String,
  authority_scope_cid : String,
  run_definition_cid : String,
  result_name : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[NativeCommittedResult?, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let index = match
    self.inspect_committed_publication_in_scope(
      namespace_id, authority_scope_cid, run_definition_cid, max_wire_bytes, max_nodes,
      max_depth,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Ok(None)
    Err(issue) => return Err(issue)
  }
  let index_read = match
    delivery_issuance(@publication.project_public_index_read(index)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let manifest = match
    load_publication_contract(
      self,
      "result_manifest",
      index_read.result_manifest_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let bindings : Array[@publication.PublicationContract] = []
  for identity in index_read.durable_result_binding_cids {
    let binding = match
      load_publication_contract(self, "durable_result_binding", identity) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    bindings.push(binding)
  }
  let read = match
    delivery_issuance(
      @publication.project_committed_result_read(
        index, manifest, result_name, bindings,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let retention = match
    load_publication_contract(
      self,
      "result_retention_policy",
      read.effective_retention_policy_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut selected_binding : @publication.PublicationContract? = None
  for candidate in bindings {
    if @publication.publication_contract_identity(candidate) ==
      read.durable_result_binding_cid {
      selected_binding = Some(candidate)
    }
  }
  guard selected_binding is Some(binding) else { return Err(StateCollision) }
  Ok(
    Some({
      public_index_entry: index,
      result_manifest: manifest,
      retention,
      binding,
      read,
    }),
  )
}

///|
fn require_committed_publication(
  store : Store,
  index : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, NativePublicationStoreIssue] {
  let key = match
    publication_commit_key(
      @publication.publication_index_storage_key(
        index, max_wire_bytes, max_nodes, max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let installed = match store.database.read("public_index", key) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Err(DeliveryAttemptUnresolved)
    Err(issue) => return Err(Database(issue))
  }
  let expected = @utf8.encode(@publication.publication_contract_identity(index))
  if installed.body != expected {
    return Err(PublicationCommitConflict)
  }
  Ok(())
}

///|
fn delivery_attempt_key(attempt_id : String) -> String {
  @sha.hex(@sha.digest(@utf8.encode(attempt_id)))
}

///|
fn claim_result_read_grant_use(
  store : Store,
  grant : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Bool, NativePublicationStoreIssue] {
  let scope = "result_read_grant_usage"
  let key = @publication.publication_contract_identity(grant)
  for _ in 0..<32 {
    let existing = match store.database.read(scope, key) {
      Ok(value) => Some(value)
      Err(@sqlite.NotFound) => None
      Err(@sqlite.Busy) => continue
      Err(issue) => return Err(Database(issue))
    }
    let existing_wire = match existing {
      Some(value) =>
        Some(@utf8.decode(value.body) catch { _ => return Err(StateCollision) })
      None => None
    }
    let claim = match
      @publication.prepare_delivery_grant_usage_claim(
        grant, existing_wire, attempt, max_wire_bytes, max_nodes, max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(DeliveryGrantUsage(issue))
    }
    if !@publication.delivery_grant_usage_claim_is_new(claim) {
      return Ok(false)
    }
    let body = @utf8.encode(@publication.delivery_grant_usage_claim_wire(claim))
    let committed = match existing {
      Some(value) =>
        store.database.compare_exchange(scope, key, value.revision, body)
      None => store.database.insert(scope, key, body)
    }
    match committed {
      Ok(_) => return Ok(true)
      Err(@sqlite.Collision) | Err(@sqlite.Busy) => continue
      Err(issue) => return Err(Database(issue))
    }
  }
  Err(Database(@sqlite.Busy))
}

///|
fn claim_delivery_attempt(
  store : Store,
  attempt_id : String,
  attempt : @publication.PublicationContract,
) -> Result[Unit, NativePublicationStoreIssue] {
  let identity = @publication.publication_contract_identity(attempt)
  match
    store.database.insert(
      "delivery_attempt",
      delivery_attempt_key(attempt_id),
      @utf8.encode(identity),
    ) {
    Ok(_) => Ok(())
    Err(@sqlite.Collision) => {
      let existing = match
        store.database.read(
          "delivery_attempt",
          delivery_attempt_key(attempt_id),
        ) {
        Ok(value) => value
        Err(issue) => return Err(Database(issue))
      }
      if existing.body == @utf8.encode(identity) {
        Err(ExistingDeliveryAttempt)
      } else {
        Err(StateCollision)
      }
    }
    Err(issue) => Err(Database(issue))
  }
}

///|
fn append_initial_delivery_record(
  store : Store,
  attempt : @publication.PublicationContract,
  record : @publication.PublicationContract,
) -> Result[Int64, NativePublicationStoreIssue] {
  match put_publication_contract(store, record) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let key = @publication.publication_contract_identity(attempt)
  let body = @utf8.encode(@publication.publication_contract_json(record))
  match store.database.insert("delivery_record_head", key, body) {
    Ok(revision) => Ok(revision)
    Err(@sqlite.Collision) => Err(DeliveryAttemptUnresolved)
    Err(issue) => Err(Database(issue))
  }
}

///|
fn append_next_delivery_record(
  store : Store,
  attempt : @publication.PublicationContract,
  expected_revision : Int64,
  record : @publication.PublicationContract,
) -> Result[Int64, NativePublicationStoreIssue] {
  match put_publication_contract(store, record) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let key = @publication.publication_contract_identity(attempt)
  let body = @utf8.encode(@publication.publication_contract_json(record))
  match
    store.database.compare_exchange(
      "delivery_record_head", key, expected_revision, body,
    ) {
    Ok(revision) => Ok(revision)
    Err(@sqlite.Collision) => {
      let existing = match store.database.read("delivery_record_head", key) {
        Ok(value) => value
        Err(issue) => return Err(Database(issue))
      }
      if existing.body == body {
        Ok(existing.revision)
      } else {
        Err(StateCollision)
      }
    }
    Err(issue) => Err(Database(issue))
  }
}

///|
fn queue_delivery_output(
  stream : PayloadDelivery,
  output : String,
) -> Result[Unit, NativePublicationStoreIssue] {
  let bytes = @utf8.encode(output)
  let size = bytes.length().to_int64()
  if size > stream.max_delivery_bytes - stream.produced_bytes {
    return Err(DeliveryLimit)
  }
  stream.produced_bytes += size
  stream.pending = bytes
  stream.pending_offset = 0
  Ok(())
}

///|
pub fn Store::open_payload_delivery(
  self : Store,
  material_generation_cid : String,
  format : String,
  schema_wire : String,
  fields : Array[String],
  input_chunk_bytes : Int,
  max_row_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_delivery_bytes : Int64,
) -> Result[PayloadDelivery, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.open_payload_delivery_in_scope(
      material_generation_cid, format, schema_wire, fields, input_chunk_bytes, max_row_bytes,
      max_nodes, max_depth, max_delivery_bytes,
    )
  })
}

///|
fn Store::open_payload_delivery_in_scope(
  self : Store,
  material_generation_cid : String,
  format : String,
  schema_wire : String,
  fields : Array[String],
  input_chunk_bytes : Int,
  max_row_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_delivery_bytes : Int64,
) -> Result[PayloadDelivery, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if input_chunk_bytes < 1 ||
    input_chunk_bytes > 16777216 ||
    max_row_bytes < 1 ||
    max_row_bytes > 16777216 ||
    max_delivery_bytes < 0L {
    return Err(InvalidConfiguration)
  }
  let info = match self.inspect_payload_in_scope(material_generation_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if info.generation.size < 0L ||
    info.generation.size > 2147483647L ||
    info.row_count < 0L ||
    info.row_count > 2147483647L {
    return Err(InvalidConfiguration)
  }
  let serializer = match
    @publication.prepare_result_delivery_serializer(
      format, schema_wire, fields, max_row_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Delivery(issue))
  }
  let frames = match
    @publication.prepare_durable_result_row_frames(
      info.generation.size.to_int(),
      info.row_count.to_int(),
      max_row_bytes,
      max_depth,
      input_chunk_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(RowFrame(issue))
  }
  let prefix = match delivery(@publication.begin_result_delivery(serializer)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let prefix_bytes = @utf8.encode(prefix)
  if prefix_bytes.length().to_int64() > max_delivery_bytes {
    return Err(DeliveryLimit)
  }
  let reader = match
    self.open_payload_reader_in_scope(material_generation_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    reader,
    frames,
    serializer,
    input_chunk_bytes,
    expected_rows: info.row_count,
    max_delivery_bytes,
    hash: @sha.hasher(),
    queued_rows: [],
    queued_index: 0,
    pending: prefix_bytes,
    pending_offset: 0,
    source_eof: false,
    input_finished: false,
    serializer_finished: false,
    terminal: false,
    produced_bytes: prefix_bytes.length().to_int64(),
    emitted_bytes: 0L,
    emitted_rows: 0L,
    delivery_digest: None,
    closed: false,
  })
}

///|
/// Open a delivery that keeps Store reads separate from sink confirmation.
/// `next` exposes at most one bounded chunk. The caller must confirm that
/// exact chunk before requesting another one, and must explicitly confirm the
/// sink's successful end even when the representation is empty.
pub fn Store::open_confirmed_payload_delivery(
  self : Store,
  material_generation_cid : String,
  format : String,
  schema_wire : String,
  fields : Array[String],
  input_chunk_bytes : Int,
  max_row_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_delivery_bytes : Int64,
) -> Result[ConfirmedPayloadDelivery, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.open_confirmed_payload_delivery_in_scope(
      material_generation_cid, format, schema_wire, fields, input_chunk_bytes, max_row_bytes,
      max_nodes, max_depth, max_delivery_bytes,
    )
  })
}

///|
fn Store::open_confirmed_payload_delivery_in_scope(
  self : Store,
  material_generation_cid : String,
  format : String,
  schema_wire : String,
  fields : Array[String],
  input_chunk_bytes : Int,
  max_row_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_delivery_bytes : Int64,
) -> Result[ConfirmedPayloadDelivery, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let source = match
    self.open_payload_delivery_in_scope(
      material_generation_cid, format, schema_wire, fields, input_chunk_bytes, max_row_bytes,
      max_nodes, max_depth, max_delivery_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let progress = match
    sink_progress(
      @publication.prepare_delivery_sink_progress(max_delivery_bytes),
    ) {
    Ok(value) => value
    Err(issue) => {
      ignore(source.close())
      return Err(issue)
    }
  }
  Ok({ source, progress, closed: false, })
}

///|
fn fill_delivery_pending(
  stream : PayloadDelivery,
) -> Result[Unit, NativePublicationStoreIssue] {
  while stream.pending_offset == stream.pending.length() && !stream.terminal {
    stream.pending = b""
    stream.pending_offset = 0
    if stream.queued_index < stream.queued_rows.length() {
      let row = stream.queued_rows[stream.queued_index]
      stream.queued_index += 1
      let output = match
        delivery(@publication.next_result_delivery_row(stream.serializer, row)) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      stream.emitted_rows += 1L
      match queue_delivery_output(stream, output) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      continue
    }
    stream.queued_rows = []
    stream.queued_index = 0
    if stream.source_eof {
      if !stream.input_finished {
        let summary = match
          @publication.finish_durable_result_row_frames(stream.frames) {
          Ok(value) => value
          Err(issue) => return Err(RowFrame(issue))
        }
        match stream.reader.finish_in_scope() {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        if summary.rows.to_int64() != stream.expected_rows ||
          stream.emitted_rows != stream.expected_rows {
          return Err(DeliveryIncomplete)
        }
        stream.input_finished = true
      }
      if !stream.serializer_finished {
        let suffix = match
          delivery(@publication.finish_result_delivery(stream.serializer)) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        stream.serializer_finished = true
        match queue_delivery_output(stream, suffix) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        if stream.pending.length() == 0 {
          stream.terminal = true
        }
        continue
      }
      stream.terminal = true
      continue
    }
    let physical = match stream.reader.next_in_scope(stream.input_chunk_bytes) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let rows = match
      @publication.feed_durable_result_row_frames(stream.frames, physical.bytes) {
      Ok(value) => value
      Err(issue) => return Err(RowFrame(issue))
    }
    stream.queued_rows = rows
    stream.source_eof = physical.eof
  }
  Ok(())
}

///|
pub fn PayloadDelivery::next(
  self : PayloadDelivery,
  max_bytes : Int,
) -> Result[NativePublicationDeliveryChunk, NativePublicationStoreIssue] {
  self.reader.store.with_original_read(false, false, fn() {
    self.next_in_scope(max_bytes)
  })
}

///|
fn PayloadDelivery::next_in_scope(
  self : PayloadDelivery,
  max_bytes : Int,
) -> Result[NativePublicationDeliveryChunk, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if max_bytes < 1 || max_bytes > 16777216 {
    return Err(InvalidConfiguration)
  }
  match fill_delivery_pending(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if self.pending_offset == self.pending.length() {
    return Ok({ bytes: b"", eof: self.terminal, })
  }
  let end = Int::min(self.pending.length(), self.pending_offset + max_bytes)
  let bytes = self.pending[self.pending_offset:end].to_owned()
  self.pending_offset = end
  self.emitted_bytes += bytes.length().to_int64()
  @sha.update(self.hash, bytes) catch {
    _ => return Err(StateCollision)
  }
  if self.serializer_finished && self.pending_offset == self.pending.length() {
    self.terminal = true
  }
  Ok({ bytes, eof: self.terminal, })
}

///|
pub fn PayloadDelivery::finish(
  self : PayloadDelivery,
) -> Result[NativePublicationDeliverySummary, NativePublicationStoreIssue] {
  self.reader.store.with_original_read(false, false, fn() {
    self.finish_in_scope()
  })
}

///|
fn PayloadDelivery::finish_in_scope(
  self : PayloadDelivery,
) -> Result[NativePublicationDeliverySummary, NativePublicationStoreIssue] {
  if self.closed ||
    !self.terminal ||
    self.pending_offset != self.pending.length() ||
    self.emitted_bytes != self.produced_bytes {
    return Err(DeliveryIncomplete)
  }
  let digest = match self.delivery_digest {
    Some(value) => value
    None => {
      let value = "sha256:" +
        (@sha.finish_hex(self.hash) catch { _ => return Err(StateCollision) })
      self.delivery_digest = Some(value)
      value
    }
  }
  self.closed = true
  Ok({
    bytes: self.emitted_bytes,
    rows: self.emitted_rows,
    delivery_digest: digest,
  })
}

///|
pub fn PayloadDelivery::close(
  self : PayloadDelivery,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.reader.store.with_original_read(true, false, fn() {
    self.close_in_scope()
  })
}

///|
fn PayloadDelivery::close_in_scope(
  self : PayloadDelivery,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Ok(())
  }
  if !self.input_finished {
    match self.reader.close_in_scope() {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    @publication.cancel_durable_result_row_frames(self.frames)
  }
  self.closed = true
  Ok(())
}

///|
pub fn ConfirmedPayloadDelivery::next(
  self : ConfirmedPayloadDelivery,
  max_bytes : Int,
) -> Result[NativePublicationDeliveryChunk, NativePublicationStoreIssue] {
  self.source.reader.store.with_original_read(false, false, fn() {
    self.next_in_scope(max_bytes)
  })
}

///|
fn ConfirmedPayloadDelivery::next_in_scope(
  self : ConfirmedPayloadDelivery,
  max_bytes : Int,
) -> Result[NativePublicationDeliveryChunk, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  match sink_progress(self.progress.prepare_next()) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let chunk = match self.source.next_in_scope(max_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match sink_progress(self.progress.offer(chunk.bytes, chunk.eof)) {
    Ok(_) => Ok(chunk)
    Err(issue) => Err(issue)
  }
}

///|
pub fn ConfirmedPayloadDelivery::confirm_chunk(
  self : ConfirmedPayloadDelivery,
) -> Result[Int64, NativePublicationStoreIssue] {
  self.source.reader.store.with_original_read(false, false, fn() {
    self.confirm_chunk_in_scope()
  })
}

///|
fn ConfirmedPayloadDelivery::confirm_chunk_in_scope(
  self : ConfirmedPayloadDelivery,
) -> Result[Int64, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  sink_progress(self.progress.confirm_chunk())
}

///|
pub fn ConfirmedPayloadDelivery::fail_chunk(
  self : ConfirmedPayloadDelivery,
  confirmed_prefix_bytes : Int,
) -> Result[Int64, NativePublicationStoreIssue] {
  self.source.reader.store.with_original_read(true, false, fn() {
    self.fail_chunk_in_scope(confirmed_prefix_bytes)
  })
}

///|
fn ConfirmedPayloadDelivery::fail_chunk_in_scope(
  self : ConfirmedPayloadDelivery,
  confirmed_prefix_bytes : Int,
) -> Result[Int64, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  let confirmed = match
    sink_progress(self.progress.fail_chunk(confirmed_prefix_bytes)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match self.source.close_in_scope() {
    Ok(_) => {
      self.closed = true
      Ok(confirmed)
    }
    Err(issue) => Err(issue)
  }
}

///|
pub fn ConfirmedPayloadDelivery::fail(
  self : ConfirmedPayloadDelivery,
) -> Result[Int64, NativePublicationStoreIssue] {
  self.source.reader.store.with_original_read(true, false, fn() {
    self.fail_in_scope()
  })
}

///|
fn ConfirmedPayloadDelivery::fail_in_scope(
  self : ConfirmedPayloadDelivery,
) -> Result[Int64, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  let confirmed = match sink_progress(self.progress.fail()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match self.source.close_in_scope() {
    Ok(_) => {
      self.closed = true
      Ok(confirmed)
    }
    Err(issue) => Err(issue)
  }
}

///|
pub fn ConfirmedPayloadDelivery::confirm_sink_finished(
  self : ConfirmedPayloadDelivery,
) -> Result[NativePublicationDeliverySummary, NativePublicationStoreIssue] {
  self.source.reader.store.with_original_read(false, false, fn() {
    self.confirm_sink_finished_in_scope()
  })
}

///|
fn ConfirmedPayloadDelivery::confirm_sink_finished_in_scope(
  self : ConfirmedPayloadDelivery,
) -> Result[NativePublicationDeliverySummary, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  let source = match self.source.finish_in_scope() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let confirmed = match sink_progress(self.progress.confirm_finished()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if source.bytes != confirmed.confirmed_bytes ||
    source.delivery_digest != confirmed.delivered_sha256 {
    return Err(StateCollision)
  }
  self.closed = true
  Ok(source)
}

///|
pub fn ConfirmedPayloadDelivery::close(
  self : ConfirmedPayloadDelivery,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.source.reader.store.with_original_read(true, false, fn() {
    self.close_in_scope()
  })
}

///|
fn ConfirmedPayloadDelivery::close_in_scope(
  self : ConfirmedPayloadDelivery,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Ok(())
  }
  match self.source.close_in_scope() {
    Ok(_) => {
      self.closed = true
      Ok(())
    }
    Err(issue) => Err(issue)
  }
}

///|
/// Begin one formally admitted Result delivery. The immutable attempt and its
/// initial streaming record are durable before any payload byte is exposed.
pub fn Store::begin_result_delivery(
  self : Store,
  index : @publication.PublicationContract,
  manifest : @publication.PublicationContract,
  grant : @publication.PublicationContract,
  retention : @publication.PublicationContract,
  binding : @publication.PublicationContract,
  material_generation_cid : String,
  result_name : String,
  format : String,
  attempt_id : String,
  requested_at : String,
  schema_wire : String,
  fields : Array[String],
  input_chunk_bytes : Int,
  max_row_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_delivery_bytes : Int64,
) -> Result[ResultDelivery, NativePublicationStoreIssue] {
  self
  .with_original_read(false, false, fn() {
    let acquired = self.begin_result_delivery_in_scope(
      index, manifest, grant, retention, binding, material_generation_cid, result_name,
      format, attempt_id, requested_at, schema_wire, fields, input_chunk_bytes, max_row_bytes,
      max_wire_bytes, max_nodes, max_depth, max_delivery_bytes,
    )
    if acquired is Ok(original) {
      // Publish child custody before with_original_read invokes leave_store.
      // A failed return must not drop the only owning Reader/Delivery handle.
      self.pending_result_delivery = Some(original)
    }
    acquired
  })
  .map(original => {
    // Only a confirmed original return exposes this same acquired child.
    self.pending_result_delivery = None
    original
  })
}

///|
fn Store::begin_result_delivery_in_scope(
  self : Store,
  index : @publication.PublicationContract,
  manifest : @publication.PublicationContract,
  grant : @publication.PublicationContract,
  retention : @publication.PublicationContract,
  binding : @publication.PublicationContract,
  material_generation_cid : String,
  result_name : String,
  format : String,
  attempt_id : String,
  requested_at : String,
  schema_wire : String,
  fields : Array[String],
  input_chunk_bytes : Int,
  max_row_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_delivery_bytes : Int64,
) -> Result[ResultDelivery, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if self.closed || max_delivery_bytes < 0L || max_delivery_bytes > 2147483647L {
    return Err(InvalidConfiguration)
  }
  match
    require_committed_publication(
      self, index, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !@publication.result_read_grant_valid_at(grant, requested_at) ||
    !@publication.result_read_grant_allows_bytes(
      grant,
      max_delivery_bytes.to_int(),
    ) {
    return Err(DeliveryLimit)
  }
  let availability = match
    delivery_issuance(
      @publication.result_read_availability(
        manifest, result_name, retention, requested_at,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if availability != "available" {
    return Err(DeliveryLimit)
  }
  let attempt = match
    delivery_issuance(
      @publication.issue_delivery_attempt(
        index, manifest, grant, result_name, format, attempt_id, requested_at, max_wire_bytes,
        max_nodes, max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let info = match self.inspect_payload_in_scope(material_generation_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !info.physical_digest.has_prefix("sha256:") {
    return Err(DigestMismatch)
  }
  let facts : @publication.DeliveryPayloadFacts = {
    store_authority_cid: self.authority_cid,
    material_generation_cid,
    logical_result_cid: info.logical_relation_cid,
    result_schema_cid: info.result_schema_cid,
    ordering_evidence_cid: info.ordering_evidence_cid,
    codec_contract_cid: info.durable_codec_cid,
    result_fields: fields.copy(),
    result_schema_wire: schema_wire,
    row_count: info.row_count,
    byte_count: info.generation.size,
    physical_sha256: info.physical_digest[7:].to_owned(),
  }
  match
    delivery_issuance(
      @publication.validate_delivery_payload_binding(
        index, manifest, attempt, binding, facts, max_wire_bytes, max_nodes, max_depth,
      ),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  for contract in [index, manifest, grant, retention, binding, attempt] {
    match put_publication_contract(self, contract) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  match
    claim_result_read_grant_use(
      self, grant, attempt, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match claim_delivery_attempt(self, attempt_id, attempt) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let streaming = match
    delivery_issuance(
      @publication.issue_delivery_record(
        attempt,
        None,
        "streaming",
        0,
        "exact",
        None,
        None,
        None,
        None,
        requested_at,
        [],
        max_wire_bytes,
        max_nodes,
        max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let record_revision = match
    append_initial_delivery_record(self, attempt, streaming) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let source = match
    self.open_confirmed_payload_delivery_in_scope(
      material_generation_cid, format, schema_wire, fields, input_chunk_bytes, max_row_bytes,
      max_nodes, max_depth, max_delivery_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    store: self,
    source,
    index,
    manifest,
    grant,
    retention,
    result_name,
    attempt,
    streaming,
    record_revision,
    max_wire_bytes,
    max_nodes,
    max_depth,
    source_summary: None,
    failure_confirmed: None,
    terminal_observed_at: "",
    succeeded: None,
    closed: false,
  })
}

///|
pub fn ResultDelivery::attempt_cid(self : ResultDelivery) -> String {
  @publication.publication_contract_identity(self.attempt)
}

///|
pub fn ResultDelivery::next(
  self : ResultDelivery,
  max_bytes : Int,
  observed_at : String,
) -> Result[NativePublicationDeliveryChunk, NativePublicationStoreIssue] {
  self.store.with_original_read(false, false, fn() {
    self.next_in_scope(max_bytes, observed_at)
  })
}

///|
fn ResultDelivery::next_in_scope(
  self : ResultDelivery,
  max_bytes : Int,
  observed_at : String,
) -> Result[NativePublicationDeliveryChunk, NativePublicationStoreIssue] {
  if self.closed || self.succeeded is Some(_) {
    return Err(Closed)
  }
  if !@publication.result_read_grant_valid_at(self.grant, observed_at) {
    return Err(DeliveryLimit)
  }
  let availability = match
    delivery_issuance(
      @publication.result_read_availability(
        self.manifest,
        self.result_name,
        self.retention,
        observed_at,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if availability != "available" {
    return Err(DeliveryLimit)
  }
  self.source.next_in_scope(max_bytes)
}

///|
pub fn ResultDelivery::confirm_chunk(
  self : ResultDelivery,
) -> Result[Int64, NativePublicationStoreIssue] {
  self.store.with_original_read(false, false, fn() {
    self.confirm_chunk_in_scope()
  })
}

///|
fn ResultDelivery::confirm_chunk_in_scope(
  self : ResultDelivery,
) -> Result[Int64, NativePublicationStoreIssue] {
  if self.closed || self.succeeded is Some(_) {
    return Err(Closed)
  }
  self.source.confirm_chunk_in_scope()
}

///|
pub fn ResultDelivery::confirm_sink_finished(
  self : ResultDelivery,
  observed_at : String,
) -> Result[NativeResultDeliverySuccess, NativePublicationStoreIssue] {
  self.store.with_original_read(false, false, fn() {
    self.confirm_sink_finished_in_scope(observed_at)
  })
}

///|
fn ResultDelivery::confirm_sink_finished_in_scope(
  self : ResultDelivery,
  observed_at : String,
) -> Result[NativeResultDeliverySuccess, NativePublicationStoreIssue] {
  match self.succeeded {
    Some(value) => return Ok(value)
    None => ()
  }
  if self.closed {
    return Err(Closed)
  }
  match require_store_open(self.store) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !@publication.result_read_grant_valid_at(self.grant, observed_at) {
    return Err(DeliveryLimit)
  }
  let availability = match
    delivery_issuance(
      @publication.result_read_availability(
        self.manifest,
        self.result_name,
        self.retention,
        observed_at,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if availability != "available" {
    return Err(DeliveryLimit)
  }
  let summary = match self.source_summary {
    Some(value) => value
    None => {
      let value = match self.source.confirm_sink_finished_in_scope() {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.source_summary = Some(value)
      value
    }
  }
  if !@publication.result_read_grant_allows_bytes(
      self.grant,
      summary.bytes.to_int(),
    ) {
    return Err(DeliveryLimit)
  }
  if self.terminal_observed_at.is_empty() {
    self.terminal_observed_at = observed_at
  }
  if !summary.delivery_digest.has_prefix("sha256:") {
    return Err(DigestMismatch)
  }
  let delivered_sha256 = summary.delivery_digest[7:].to_owned()
  let receipt = match
    delivery_issuance(
      @publication.issue_result_delivery_receipt(
        self.index,
        self.manifest,
        self.grant,
        self.attempt,
        summary.bytes.to_int(),
        delivered_sha256,
        self.max_wire_bytes,
        self.max_nodes,
        self.max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match put_publication_contract(self.store, receipt) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let succeeded = match
    delivery_issuance(
      @publication.issue_delivery_record(
        self.attempt,
        Some(self.streaming),
        "succeeded",
        summary.bytes.to_int(),
        "exact",
        None,
        Some(delivered_sha256),
        Some(receipt),
        None,
        self.terminal_observed_at,
        [],
        self.max_wire_bytes,
        self.max_nodes,
        self.max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.record_revision = match
    append_next_delivery_record(
      self.store,
      self.attempt,
      self.record_revision,
      succeeded,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    delivery_issuance(
      @publication.validate_delivery_success_evidence(
        self.attempt,
        receipt,
        succeeded,
      ),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let result : NativeResultDeliverySuccess = {
    delivery_attempt_cid: @publication.publication_contract_identity(
      self.attempt,
    ),
    delivery_record_cid: @publication.publication_contract_identity(succeeded),
    result_delivery_receipt_cid: @publication.publication_contract_identity(
      receipt,
    ),
    confirmed_bytes: summary.bytes,
    delivered_sha256,
  }
  self.succeeded = Some(result)
  self.closed = true
  Ok(result)
}

///|
/// Terminate a failed or cancelled attempt after reporting the sink-confirmed
/// prefix of the one outstanding chunk, if any. The payload reader is stopped
/// before the terminal record is committed, while a durability failure keeps
/// this session retryable without reading or sending more payload.
pub fn ResultDelivery::terminate(
  self : ResultDelivery,
  confirmed_prefix_bytes : Int?,
  cancellation_observed : Bool,
  exposure : String,
  possible_unconfirmed_max_bytes : Int?,
  failure_cid : String?,
  observed_at : String,
) -> Result[NativeResultDeliveryFailure, NativePublicationStoreIssue] {
  self.store.with_original_read(false, false, fn() {
    self.terminate_in_scope(
      confirmed_prefix_bytes, cancellation_observed, exposure, possible_unconfirmed_max_bytes,
      failure_cid, observed_at,
    )
  })
}

///|
fn ResultDelivery::terminate_in_scope(
  self : ResultDelivery,
  confirmed_prefix_bytes : Int?,
  cancellation_observed : Bool,
  exposure : String,
  possible_unconfirmed_max_bytes : Int?,
  failure_cid : String?,
  observed_at : String,
) -> Result[NativeResultDeliveryFailure, NativePublicationStoreIssue] {
  if self.succeeded is Some(_) || self.closed {
    return Err(Closed)
  }
  match require_store_open(self.store) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let confirmed = match self.failure_confirmed {
    Some(value) => value
    None => {
      let value = match confirmed_prefix_bytes {
        Some(prefix) =>
          match self.source.fail_chunk_in_scope(prefix) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
        None =>
          match self.source.fail_in_scope() {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
      }
      self.failure_confirmed = Some(value)
      value
    }
  }
  if confirmed > 2147483647L {
    return Err(InvalidConfiguration)
  }
  if self.terminal_observed_at.is_empty() {
    self.terminal_observed_at = observed_at
  }
  let action = @publication.prepare_delivery_failure_terminal(
    cancellation_observed,
  )
  let state = @publication.delivery_failure_terminal_state(action)
  let terminal = match
    delivery_issuance(
      @publication.issue_delivery_record(
        self.attempt,
        Some(self.streaming),
        state,
        confirmed.to_int(),
        exposure,
        possible_unconfirmed_max_bytes,
        None,
        None,
        failure_cid,
        self.terminal_observed_at,
        [],
        self.max_wire_bytes,
        self.max_nodes,
        self.max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.record_revision = match
    append_next_delivery_record(
      self.store,
      self.attempt,
      self.record_revision,
      terminal,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.closed = true
  Ok({
    delivery_attempt_cid: @publication.publication_contract_identity(
      self.attempt,
    ),
    delivery_record_cid: @publication.publication_contract_identity(terminal),
    confirmed_bytes: confirmed,
    state,
  })
}

///|
pub fn ResultDelivery::close(
  self : ResultDelivery,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.store.with_original_read(true, false, fn() { self.close_in_scope() })
}

///|
fn ResultDelivery::close_in_scope(
  self : ResultDelivery,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Ok(())
  }
  match self.source.close_in_scope() {
    Ok(_) => {
      self.closed = true
      Ok(())
    }
    Err(issue) => Err(issue)
  }
}

///|
fn read_result_delivery_attempt(
  store : Store,
  attempt_id : String,
) -> Result[@publication.PublicationContract?, NativePublicationStoreIssue] {
  let mapped = match
    store.database.read("delivery_attempt", delivery_attempt_key(attempt_id)) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Ok(None)
    Err(issue) => return Err(Database(issue))
  }
  let attempt_cid = @utf8.decode(mapped.body) catch {
    _ => return Err(StateCollision)
  }
  load_publication_contract(store, "delivery_attempt", attempt_cid).map(value => {
    Some(value)
  })
}

///|
fn read_result_delivery_records(
  store : Store,
  attempt : @publication.PublicationContract,
) -> Result[
  (@publication.PublicationContract?, @publication.PublicationContract?),
  NativePublicationStoreIssue,
] {
  let attempt_cid = @publication.publication_contract_identity(attempt)
  let head = match store.database.read("delivery_record_head", attempt_cid) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Ok((None, None))
    Err(issue) => return Err(Database(issue))
  }
  let wire = @utf8.decode(head.body) catch { _ => return Err(StateCollision) }
  let record = match
    @publication.admit_publication_contract(
      "delivery_record",
      wire,
      store.max_record_bytes,
      store.max_record_bytes,
      64,
    ) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  let projection = match
    delivery_issuance(@publication.project_delivery_record(record)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if projection.delivery_attempt_cid != attempt_cid {
    return Err(StateCollision)
  }
  let receipt = match projection.result_delivery_receipt_cid {
    Some(cid) => {
      let receipt = match
        load_publication_contract(store, "result_delivery_receipt", cid) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match
        delivery_issuance(
          @publication.validate_delivery_success_evidence(
            attempt, receipt, record,
          ),
        ) {
        Ok(_) => Some(receipt)
        Err(issue) => return Err(issue)
      }
    }
    None => None
  }
  Ok((Some(record), receipt))
}

///|
/// Metadata only, under the caller's separately established current authority.
/// Missing attempt mapping and retained attempt without a record are distinct.
/// Expired/deleted payload is never opened, and no grant use is claimed here.
/// These immutable references and a latest record are not an atomic snapshot.
pub fn Store::lookup_result_delivery(
  self : Store,
  scope : @publication.DeliveryAttemptLookupScope,
) -> Result[NativeResultDeliveryLookup?, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.lookup_result_delivery_in_scope(scope)
  })
}

///|
fn Store::lookup_result_delivery_in_scope(
  self : Store,
  scope : @publication.DeliveryAttemptLookupScope,
) -> Result[NativeResultDeliveryLookup?, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  let attempt = match read_result_delivery_attempt(self, scope.attempt_id) {
    Ok(Some(value)) => value
    Ok(None) => return Ok(None)
    Err(issue) => return Err(issue)
  }
  let grant_cid = match
    delivery_issuance(@publication.delivery_attempt_read_grant_cid(attempt)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let grant = match
    load_publication_contract(self, "result_read_grant", grant_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    delivery_issuance(
      @publication.delivery_attempt_lookup_matches_scope(attempt, grant, scope),
    ) {
    Ok(true) => ()
    Ok(false) => return Ok(None)
    Err(issue) => return Err(issue)
  }
  let (record, receipt) = match read_result_delivery_records(self, attempt) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(Some({ attempt, record, host_release_receipt: receipt, }))
}

///|
/// Reconcile the latest durable terminal or unresolved fact for one delivery
/// occurrence after a process restart. This does not authorize a new delivery
/// or imply that its source material remains available.
pub fn Store::inspect_result_delivery(
  self : Store,
  attempt_id : String,
) -> Result[NativeResultDeliveryStatus, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.inspect_result_delivery_in_scope(attempt_id)
  })
}

///|
fn Store::inspect_result_delivery_in_scope(
  self : Store,
  attempt_id : String,
) -> Result[NativeResultDeliveryStatus, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  let attempt = match read_result_delivery_attempt(self, attempt_id) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Database(@sqlite.NotFound))
    Err(issue) => return Err(issue)
  }
  let (record, _) = match read_result_delivery_records(self, attempt) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard record is Some(record) else { return Err(Database(@sqlite.NotFound)) }
  let projection = match
    delivery_issuance(@publication.project_delivery_record(record)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    delivery_attempt_cid: @publication.publication_contract_identity(attempt),
    delivery_record_cid: @publication.publication_contract_identity(record),
    state: projection.state,
    confirmed_bytes: projection.confirmed_byte_count,
    delivered_sha256: projection.delivered_sha256,
    result_delivery_receipt_cid: projection.result_delivery_receipt_cid,
  })
}

///|
pub fn Store::reclaim_payload(
  self : Store,
  material_generation_cid : String,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.with_original_read(true, false, fn() {
    self.reclaim_payload_in_scope(material_generation_cid)
  })
}

///|
fn Store::reclaim_payload_in_scope(
  self : Store,
  material_generation_cid : String,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  let record = match load_record(self, material_generation_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  reclaim_record(self, record)
}

///|
pub fn Store::recover(
  self : Store,
) -> Result[NativePublicationRecovery, NativePublicationStoreIssue] {
  self.with_original_read(true, false, fn() { self.recover_in_scope() })
}

///|
fn Store::recover_in_scope(
  self : Store,
) -> Result[NativePublicationRecovery, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  if !self.active_writers.is_empty() || !self.active_readers.is_empty() {
    return Err(CleanupPending)
  }
  let pending = self.pending_writers.keys().to_array()
  for key in pending {
    match retry_pending_writer(self, key) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let mut cursor = ""
  let mut retained = match recover_captured_content_records(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut reclaimed = 0
  while true {
    let entry = match self.database.scan_after("publication_payload", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Database(issue))
    }
    cursor = entry.key
    let durable = match
      @payload.admit_durable_publication_payload_record(entry.body) {
      Ok(value) => value
      Err(issue) => return Err(Protocol(issue))
    }
    if @payload.durable_publication_payload_record_material_identity(durable) !=
      entry.key ||
      @payload.durable_publication_payload_record_revision(durable).to_int64() !=
      entry.revision {
      return Err(StateCollision)
    }
    let record = match
      protocol(@payload.restore_durable_publication_payload_record(durable)) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match @payload.publication_payload_record_state(record) {
      @payload.Sealed => {
        match self.inspect_payload_in_scope(entry.key) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        retained += 1
      }
      @payload.Reclaimed =>
        match
          database(
            self.database.release_capacity(
              "publication_payload",
              entry.key,
              @payload.publication_payload_request_max_bytes(
                @payload.publication_payload_record_request(record),
              ),
              1L,
            ),
          ) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      _ => {
        match reclaim_record(self, record) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        reclaimed += 1
      }
    }
  }
  Ok({ retained, reclaimed, })
}

///|
pub fn Store::capacity_usage(
  self : Store,
) -> Result[@sqlite.NativeCapacityUsage, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() { self.capacity_usage_in_scope() })
}

///|
fn Store::capacity_usage_in_scope(
  self : Store,
) -> Result[@sqlite.NativeCapacityUsage, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  database(self.database.capacity_usage("publication_payload"))
}

///|
pub fn Store::close(self : Store) -> Result[Bool, NativePublicationStoreIssue] {
  if self.pending_result_delivery is Some(_) {
    // The retained child has its own close/return ACK before parent cleanup.
    return Err(CleanupPending)
  }
  if self.operation_body_active {
    return Err(CleanupPending)
  }
  if self.operation_return_pending {
    guard self.operation_original is Some(original) else {
      return Err(CleanupPending)
    }
    // Retry only this same return. No Store body, SQL, open or replacement is
    // replayed while its acknowledgement remains uncertain.
    match original.leave_store() {
      Err(issue) => {
        if self.closed {
          return Err(OperationRouting(self.operation_return_primary, issue))
        }
        // A failed NORMAL return cannot pass C's ordinary leave fence. Only
        // the existing same-original tag4 recovery can acknowledge that old
        // flight and establish cleanup Read; it never resumes business.
        let prior = self.operation_return_primary
        match original.enter_cleanup() {
          Err(cleanup) => return Err(OperationRouting(prior, cleanup))
          Ok(_) => ()
        }
        self.operation_body_active = true
        let result = self
          .close_in_scope()
          .map_err(cleanup => OperationCleanup(prior, cleanup))
        self.operation_body_active = false
        return self.complete_original_return(
          original,
          result,
          prior_primary=prior,
        )
      }
      Ok(_) => {
        self.operation_return_pending = false
        self.operation_return_primary = None
        if self.closed {
          return Ok(true)
        }
      }
    }
  }
  // A rejected close must not spend the original Read while an existing
  // writer or reader still needs that same normal operation to finish.
  if self.closed {
    return Ok(false)
  }
  if !self.active_writers.is_empty() || !self.active_readers.is_empty() {
    return Err(CleanupPending)
  }
  self.with_original_read(true, true, fn() { self.close_in_scope() })
}

///|
fn Store::close_in_scope(
  self : Store,
) -> Result[Bool, NativePublicationStoreIssue] {
  if self.closed {
    return Ok(false)
  }
  if !self.active_writers.is_empty() || !self.active_readers.is_empty() {
    return Err(CleanupPending)
  }
  if !self.retiring {
    match self.recover_in_scope() {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    self.retiring = true
  }
  // Each original Owner is idempotent after its own ACK. On a later failure,
  // keep this Store and skip recovery/new I/O against an already closed DB.
  match self.database.close_checked() {
    Ok(_) => ()
    Err(issue) => return Err(Database(issue))
  }
  match self.lock.close_checked() {
    Ok(_) => ()
    Err(issue) => return Err(Filesystem(issue))
  }
  match self.root.close() {
    Ok(_) => ()
    Err(issue) => return Err(Filesystem(issue))
  }
  self.closed = true
  Ok(true)
}

///|
/// The existing physical journal's identity, not a read/write grant. Retain it
/// with the original Run so a same-authority empty replacement Store cannot
/// turn lost publication history into proof of non-publication. File length is
/// excluded; the journal grows without replacing its original ownership.
pub fn Store::custody_location(
  self : Store,
) -> Result[(String, UInt64, UInt64), NativePublicationStoreIssue] {
  Ok(
    (
      self.authority_cid,
      self.journal_identity.device,
      self.journal_identity.inode,
    ),
  )
}

///|
/// Retained immutable DATA may be reused only within the caller's existing
/// validated operation. This checks the actual Store and idle Database route;
/// it grants no authority, enters no scope and acknowledges no child or return.
/// Active payload readers retain their own separate custody and may stay live.
pub fn Store::retained_data_current(
  self : Store,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring ||
    self.operation_body_active ||
    self.operation_return_pending ||
    self.pending_result_delivery is Some(_) {
    return Err(CleanupPending)
  }
  match self.database.retained_data_current() {
    Ok(_) => Ok(())
    Err(issue) => Err(Database(issue))
  }
}

///|
/// Same original association only. This metadata supplies no current scope,
/// authority, physical grant or ACK; the consumer retains its original fences.
pub fn Store::matches_original_operation(
  self : Store,
  original : @sqlite.NativeStoreOperationOriginal,
) -> Bool {
  match self.operation_original {
    Some(owned) =>
      physical_equal(owned, original) &&
      self.database.matches_original_store_operation(original)
    None => false
  }
}
