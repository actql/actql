///|
type Library

///|
type Database

///|
#borrow(path)
extern "C" fn load_library_ffi(
  path : Bytes,
  length : Int,
  diagnostic_ceiling : Int,
) -> Library = "actql_native_sqlite_load_library"

///|
extern "C" fn selected_current_scope_ffi() -> Bool = "actql_native_sqlite_selected_current_scope"

///|
#borrow(path)
extern "C" fn load_current_component_ffi(
  path : Bytes,
  length : Int,
  diagnostic_ceiling : Int,
  heap_bytes : Int64,
) -> Library = "actql_native_sqlite_load_current_component"

///|
#borrow(library)
extern "C" fn library_acquired_ffi(library : Library) -> Bool = "actql_native_sqlite_library_acquired"

///|
#borrow(library)
extern "C" fn library_close_checked_ffi(library : Library) -> Bool = "actql_native_sqlite_library_close_checked"

///|
#borrow(library)
extern "C" fn library_ready_ffi(library : Library) -> Bool = "actql_native_sqlite_library_ready"

///|
#borrow(library)
extern "C" fn library_error_ffi(library : Library) -> Bytes = "actql_native_sqlite_library_error"

///|
#borrow(library)
extern "C" fn library_version_ffi(library : Library) -> Bytes = "actql_native_sqlite_library_version"

///|
#borrow(library)
extern "C" fn library_diagnostic_ceiling_ffi(library : Library) -> Int = "actql_native_sqlite_library_diagnostic_ceiling"

///|
#borrow(database)
extern "C" fn database_diagnostic_ceiling_ffi(database : Database) -> Int = "actql_native_sqlite_database_diagnostic_ceiling"

///|
#borrow(database)
extern "C" fn database_current_component_matches_heap_ffi(
  database : Database,
  expected_heap_bytes : Int64,
) -> Bool = "actql_native_sqlite_database_current_component_matches_heap"

///|
#borrow(library, path)
extern "C" fn open_database_ffi(
  library : Library,
  path : Bytes,
  length : Int,
  max_body_bytes : Int64,
) -> Database = "actql_native_sqlite_open_database"

///|
#borrow(library, path)
extern "C" fn open_existing_database_ffi(
  library : Library,
  path : Bytes,
  length : Int,
  max_body_bytes : Int64,
) -> Database = "actql_native_sqlite_open_existing_database"

///|
#borrow(library, path)
extern "C" fn initialize_owned_database_ffi(
  library : Library,
  path : Bytes,
  length : Int,
  device : UInt64,
  inode : UInt64,
  max_body_bytes : Int64,
) -> Database = "actql_native_sqlite_initialize_owned_database"

///|
#borrow(library, path)
extern "C" fn open_existing_journal_database_ffi(
  library : Library,
  path : Bytes,
  length : Int,
  max_body_bytes : Int64,
) -> Database = "actql_native_sqlite_open_existing_journal_database"

///|
#borrow(library, path)
extern "C" fn initialize_owned_journal_database_ffi(
  library : Library,
  path : Bytes,
  length : Int,
  device : UInt64,
  inode : UInt64,
  max_body_bytes : Int64,
) -> Database = "actql_native_sqlite_initialize_owned_journal_database"

///|
#borrow(library, path)
extern "C" fn open_inspection_database_ffi(
  library : Library,
  path : Bytes,
  length : Int,
  max_body_bytes : Int64,
) -> Database = "actql_native_sqlite_open_inspection_database"

///|
#borrow(library, path)
extern "C" fn open_journal_inspection_database_ffi(
  library : Library,
  path : Bytes,
  length : Int,
  max_body_bytes : Int64,
) -> Database = "actql_native_sqlite_open_journal_inspection_database"

///|
#borrow(database)
extern "C" fn close_checked_ffi(database : Database) -> Bool = "actql_native_sqlite_close_checked"

///|
#borrow(database)
extern "C" fn inspection_schema_ffi(database : Database) -> Bool = "actql_native_sqlite_inspection_schema"

///|
#borrow(database)
extern "C" fn database_ready_ffi(database : Database) -> Bool = "actql_native_sqlite_database_ready"

///|
#borrow(database)
extern "C" fn database_error_ffi(database : Database) -> Bytes = "actql_native_sqlite_database_error"

///|
#borrow(database, scope, key)
extern "C" fn database_read_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
) -> Int = "actql_native_sqlite_database_read"

///|
#borrow(database, scope, key)
extern "C" fn database_read_header_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
) -> Int = "actql_native_sqlite_database_read_header"

///|
#borrow(database)
extern "C" fn database_result_header_body_bytes_ffi(
  database : Database,
) -> Int64 = "actql_native_sqlite_database_result_header_body_bytes"

///|
#borrow(database, scope, key)
extern "C" fn database_read_with_body_limit_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
  max_body_bytes : Int64,
) -> Int = "actql_native_sqlite_database_read_with_body_limit"

///|
#borrow(database, scope, after_key)
extern "C" fn database_scan_after_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  after_key : Bytes,
  after_key_length : Int,
) -> Int = "actql_native_sqlite_database_scan_after"

///|
#borrow(database, scope, after_key)
extern "C" fn database_scan_after_with_body_limit_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  after_key : Bytes,
  after_key_length : Int,
  max_body_bytes : Int64,
) -> Int = "actql_native_sqlite_database_scan_after_with_body_limit"

///|
#borrow(database, scope, key, body)
extern "C" fn database_insert_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
  body : Bytes,
  body_length : Int,
) -> Int = "actql_native_sqlite_database_insert"

///|
#borrow(database, scope, key, body)
extern "C" fn database_compare_exchange_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
  expected_revision : Int64,
  body : Bytes,
  body_length : Int,
) -> Int = "actql_native_sqlite_database_compare_exchange"

///|
#borrow(database, scope, key, body)
extern "C" fn database_remove_exact_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
  expected_revision : Int64,
  body : Bytes,
  body_length : Int,
) -> Int = "actql_native_sqlite_database_remove_exact"

///|
#borrow(database)
extern "C" fn database_begin_deferred_ffi(database : Database) -> Int = "actql_native_sqlite_database_begin_deferred"

///|
#borrow(database)
extern "C" fn database_begin_immediate_ffi(database : Database) -> Int = "actql_native_sqlite_database_begin_immediate"

///|
#borrow(database)
extern "C" fn database_transaction_state_ffi(database : Database) -> Int = "actql_native_sqlite_database_transaction_state"

///|
#borrow(database)
extern "C" fn database_commit_ffi(database : Database) -> Int = "actql_native_sqlite_database_commit"

///|
#borrow(database)
extern "C" fn database_rollback_ffi(database : Database) -> Int = "actql_native_sqlite_database_rollback"

///|
#borrow(database)
extern "C" fn database_fence_transactions_ffi(database : Database) -> Unit = "actql_native_sqlite_database_fence_transactions"

///|
#borrow(database)
extern "C" fn database_transaction_fenced_ffi(database : Database) -> Bool = "actql_native_sqlite_database_transaction_fenced"

///|
#borrow(database, scope, key)
extern "C" fn database_reserve_capacity_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
  reserved_bytes : Int64,
  reserved_objects : Int64,
  max_bytes : Int64,
  max_objects : Int64,
  caller_transaction : Int,
) -> Int = "actql_native_sqlite_database_reserve_capacity"

///|
#borrow(database, scope, key)
extern "C" fn database_release_capacity_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
  reserved_bytes : Int64,
  reserved_objects : Int64,
) -> Int = "actql_native_sqlite_database_release_capacity"

///|
#borrow(database, scope, key)
extern "C" fn database_release_capacity_in_transaction_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
  reserved_bytes : Int64,
  reserved_objects : Int64,
) -> Int = "actql_native_sqlite_database_release_capacity_in_transaction"

///|
#borrow(database, scope, key)
extern "C" fn database_claim_ordinal_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
  max_claims : Int64,
) -> Int = "actql_native_sqlite_database_claim_ordinal"

///|
#borrow(database, scope, key)
extern "C" fn database_claim_ordinal_in_transaction_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
  max_claims : Int64,
) -> Int = "actql_native_sqlite_database_claim_ordinal_in_transaction"

///|
#borrow(database, scope, key)
extern "C" fn database_lookup_claim_ordinal_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
) -> Int = "actql_native_sqlite_database_lookup_claim_ordinal"

///|
#borrow(database, scope, key)
extern "C" fn database_read_capacity_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
  key : Bytes,
  key_length : Int,
) -> Int = "actql_native_sqlite_database_read_capacity"

///|
#borrow(database)
extern "C" fn database_usage_ffi(database : Database) -> Int = "actql_native_sqlite_database_usage"

///|
#borrow(database)
extern "C" fn database_result_record_count_ffi(database : Database) -> Int64 = "actql_native_sqlite_database_result_record_count"

///|
#borrow(database)
extern "C" fn database_result_record_body_bytes_ffi(
  database : Database,
) -> Int64 = "actql_native_sqlite_database_result_record_body_bytes"

///|
#borrow(database)
extern "C" fn database_result_reservation_count_ffi(
  database : Database,
) -> Int64 = "actql_native_sqlite_database_result_reservation_count"

///|
#borrow(database, scope)
extern "C" fn database_capacity_usage_ffi(
  database : Database,
  scope : Bytes,
  scope_length : Int,
) -> Int = "actql_native_sqlite_database_capacity_usage"

///|
#borrow(database)
extern "C" fn database_result_capacity_bytes_ffi(database : Database) -> Int64 = "actql_native_sqlite_database_result_capacity_bytes"

///|
#borrow(database)
extern "C" fn database_result_capacity_objects_ffi(
  database : Database,
) -> Int64 = "actql_native_sqlite_database_result_capacity_objects"

///|
#borrow(database)
extern "C" fn database_result_revision_ffi(database : Database) -> Int64 = "actql_native_sqlite_database_result_revision"

///|
#borrow(database)
extern "C" fn database_result_body_ffi(database : Database) -> Bytes = "actql_native_sqlite_database_result_body"

///|
#borrow(database)
extern "C" fn database_result_key_ffi(database : Database) -> Bytes = "actql_native_sqlite_database_result_key"

///|
#borrow(database)
extern "C" fn close_database_ffi(database : Database) -> Unit = "actql_native_sqlite_close_database"

///|
fn decode_message(bytes : Bytes) -> String {
  @utf8.decode_lossy(bytes)
}

///|
fn decode_diagnostic(bytes : Bytes) -> String {
  if bytes.is_empty() {
    "SQLite diagnostic detail omitted"
  } else {
    @utf8.decode_lossy(bytes)
  }
}

///|
fn valid_name(bytes : Bytes) -> Bool {
  bytes.length() > 0 && bytes.length() <= 512
}

///|
fn operation_issue(database : Database, code : Int) -> NativeSqliteIssue {
  match code {
    1 => NotFound
    2 => Collision
    3 => Busy
    4 => BodyTooLarge
    5 => DatabaseClosed
    6 => CapacityExceeded
    _ => Physical(decode_diagnostic(database_error_ffi(database)))
  }
}

///|
/// Select only from trusted installer configuration bound to its source/ABI.
/// This physical diagnostic bound issues no authority or capacity reservation.
/// Omission preserves legacy behavior and does not establish a funded profile.
pub fn load_library(
  path : String,
  diagnostic_ceiling? : Int? = None,
) -> Result[Library, NativeSqliteIssue] {
  if diagnostic_ceiling is Some(value) && value <= 0 {
    return Err(InvalidLimit)
  }
  let encoded = @utf8.encode(path)
  let library = load_library_ffi(
    encoded,
    encoded.length(),
    diagnostic_ceiling.unwrap_or(0),
  )
  if library_ready_ffi(library) {
    Ok(library)
  } else {
    Err(LibraryLoad(decode_diagnostic(library_error_ffi(library))))
  }
}

///|
/// Private physical entry for the trusted installed Library caller. The caller
/// has already verified its owned component/source/recipe and nominal Host /
/// Store / epoch / current plus the original funded read-domain scope. A path,
/// heap size or successful load does not establish any of those conditions.
/// Refuse a missing selected scope before allocating the UTF-8 path copy.
pub fn load_current_component_with_custody(
  path : String,
  heap_bytes : Int64,
  diagnostic_ceiling : Int,
) -> Result[Library, NativeSqliteLibraryLoadError] {
  if heap_bytes < 4096L || heap_bytes > 2147483647L || diagnostic_ceiling <= 0 {
    return Err(RefusedBeforeAcquisition(InvalidLimit))
  }
  if path.is_empty() ||
    path.length() > 4096 ||
    !path.has_prefix("/") ||
    path.contains("\u{0}") {
    return Err(RefusedBeforeAcquisition(InvalidName))
  }
  if !selected_current_scope_ffi() {
    return Err(
      RefusedBeforeAcquisition(
        Physical("original SQLite read domain unavailable"),
      ),
    )
  }
  let encoded = @utf8.encode(path)
  if encoded.length() > 4096 {
    return Err(RefusedBeforeAcquisition(InvalidName))
  }
  let library = load_current_component_ffi(
    encoded,
    encoded.length(),
    diagnostic_ceiling,
    heap_bytes,
  )
  if !library_acquired_ffi(library) {
    return Err(
      RefusedBeforeAcquisition(
        Physical("original SQLite Library acquisition unavailable"),
      ),
    )
  }
  if library_ready_ffi(library) {
    Ok(library)
  } else {
    Err(
      CleanupRequired({
        original_issue: LibraryLoad(
          decode_diagnostic(library_error_ffi(library)),
        ),
        library: Some(library),
      }),
    )
  }
}

///|
/// Selected component only. Preserve the original current domain until this
/// Library's own cleanup ACK; this does not close managed aliases or the domain.
pub fn Library::close_checked(
  self : Library,
) -> Result[Unit, NativeSqliteIssue] {
  if library_close_checked_ffi(self) {
    Ok(())
  } else {
    Err(Physical("original SQLite Library cleanup pending"))
  }
}

///|
pub fn Library::version(self : Library) -> String {
  decode_message(library_version_ffi(self))
}

///|
/// Immutable metadata of this original physical Library, not a current,
/// reservation or read grant. None preserves legacy unbounded/unavailable
/// diagnostics; it must not be converted to a zero-byte funded bound. Closing
/// does not reissue or change the original selection.
pub fn Library::diagnostic_ceiling(self : Library) -> Int? {
  let original = library_diagnostic_ceiling_ffi(self)
  if original > 0 {
    Some(original)
  } else {
    None
  }
}

///|
/// This Database retained its own original Library selection at creation.
/// Projection performs no SQL, reconfiguration or current check; it issues no
/// capacity. Callers still require the existing current and scoped read Owners.
pub fn Database::diagnostic_ceiling(self : Database) -> Int? {
  let original = database_diagnostic_ceiling_ffi(self)
  if original > 0 {
    Some(original)
  } else {
    None
  }
}

///|
/// Match this Database's original successful component heap selection under
/// its still-open Library and same physical process/read context. The expected
/// quantity comes from the trusted installer's original selection; do not infer
/// it from a row limit, diagnostic ceiling or current arena size. This performs
/// no SQL or managed allocation and proves neither permission, available
/// capacity, whole-Host funding nor cleanup acknowledgement. Callers still
/// validate the original Host/component/source/recipe and current authority
/// before and after use; matching a quantity is not Library identity.
pub fn Database::current_component_matches_heap(
  self : Database,
  expected_heap_bytes : Int64,
) -> Bool {
  database_current_component_matches_heap_ffi(self, expected_heap_bytes)
}

///|
pub fn Library::open_database(
  self : Library,
  path : String,
  max_body_bytes : Int64,
) -> Result[Database, NativeSqliteIssue] {
  if max_body_bytes < 0L {
    return Err(InvalidLimit)
  }
  let encoded = @utf8.encode(path)
  let database = open_database_ffi(
    self,
    encoded,
    encoded.length(),
    max_body_bytes,
  )
  if database_ready_ffi(database) {
    Ok(database)
  } else {
    Err(DatabaseOpen(decode_diagnostic(database_error_ffi(database))))
  }
}

///|
fn sqlite_open_result_with_custody(
  database : Database,
) -> Result[Database, NativeSqliteOpenFailure] {
  if database_ready_ffi(database) {
    Ok(database)
  } else {
    Err({
      original_issue: DatabaseOpen(
        decode_diagnostic(database_error_ffi(database)),
      ),
      database: Some(database),
    })
  }
}

///|
/// Same open/schema policy as open_database, with original failure custody for
/// callers that must retain cleanup responsibility before returning capacity.
pub fn Library::open_database_with_custody(
  self : Library,
  path : String,
  max_body_bytes : Int64,
) -> Result[Database, NativeSqliteOpenFailure] {
  if max_body_bytes < 0L {
    return Err({ original_issue: InvalidLimit, database: None, })
  }
  let encoded = @utf8.encode(path)
  sqlite_open_result_with_custody(
    open_database_ffi(self, encoded, encoded.length(), max_body_bytes),
  )
}

///|
/// Open a retained journal without creation or schema repair. The caller must
/// first admit its original format/custody and contain the absolute path under
/// its pinned managed Root; this physical operation issues no authority.
pub fn Library::open_existing_database(
  self : Library,
  path : String,
  max_body_bytes : Int64,
) -> Result[Database, NativeSqliteIssue] {
  if max_body_bytes < 0L {
    return Err(InvalidLimit)
  }
  let encoded = @utf8.encode(path)
  let database = open_existing_database_ffi(
    self,
    encoded,
    encoded.length(),
    max_body_bytes,
  )
  if database_ready_ffi(database) {
    Ok(database)
  } else {
    Err(DatabaseOpen(decode_diagnostic(database_error_ffi(database))))
  }
}

///|
/// Never creates or repairs an original database. An unconfirmed failed-open
/// close remains in the same carrier, not a fresh-open or retry permission.
pub fn Library::open_existing_database_with_custody(
  self : Library,
  path : String,
  max_body_bytes : Int64,
) -> Result[Database, NativeSqliteOpenFailure] {
  if max_body_bytes < 0L {
    return Err({ original_issue: InvalidLimit, database: None, })
  }
  let encoded = @utf8.encode(path)
  sqlite_open_result_with_custody(
    open_existing_database_ffi(self, encoded, encoded.length(), max_body_bytes),
  )
}

///|
/// Selected original adoption Journal only. Its caller retains the same
/// Session/Lock and resource supplier. This restriction supplies neither.
/// The matching component must confirm actual heap-backed exclusive WAL;
/// generic existing-only opens retain their previous behavior.
pub fn Library::open_existing_journal_database_with_custody(
  self : Library,
  path : String,
  max_body_bytes : Int64,
) -> Result[Database, NativeSqliteOpenFailure] {
  if max_body_bytes < 0L {
    return Err({ original_issue: InvalidLimit, database: None, })
  }
  let encoded = @utf8.encode(path)
  sqlite_open_result_with_custody(
    open_existing_journal_database_ffi(
      self,
      encoded,
      encoded.length(),
      max_body_bytes,
    ),
  )
}

///|
/// Same Journal restriction for the exact exclusively created empty file.
/// Failed selection retains original open/cleanup custody without NORMAL,
/// stock-library, missing-file or schema-repair fallback.
pub fn Library::initialize_owned_journal_database_with_custody(
  self : Library,
  path : String,
  ownership : @filesystem.NativeFileOwnership,
  max_body_bytes : Int64,
) -> Result[Database, NativeSqliteOpenFailure] {
  if max_body_bytes < 0L {
    return Err({ original_issue: InvalidLimit, database: None, })
  }
  let encoded = @utf8.encode(path)
  sqlite_open_result_with_custody(
    initialize_owned_journal_database_ffi(
      self,
      encoded,
      encoded.length(),
      ownership.device,
      ownership.inode,
      max_body_bytes,
    ),
  )
}

///|
/// Initialize only the exact exclusively created empty file. This never opens
/// with CREATE and never repairs a previously initialized database. Ownership
/// alone is not authorization; a trusted Host must bind its original durable
/// initialization intent before calling this physical boundary.
pub fn Library::initialize_owned_database(
  self : Library,
  path : String,
  ownership : @filesystem.NativeFileOwnership,
  max_body_bytes : Int64,
) -> Result[Database, NativeSqliteIssue] {
  if max_body_bytes < 0L {
    return Err(InvalidLimit)
  }
  let encoded = @utf8.encode(path)
  let database = initialize_owned_database_ffi(
    self,
    encoded,
    encoded.length(),
    ownership.device,
    ownership.inode,
    max_body_bytes,
  )
  if database_ready_ffi(database) {
    Ok(database)
  } else {
    Err(DatabaseOpen(decode_diagnostic(database_error_ffi(database))))
  }
}

///|
/// The same exclusive-file initialization with original failed-open custody.
/// It neither creates a missing file nor repairs a retained schema. A caller
/// must keep its original durable initialization intent and file Owner.
pub fn Library::initialize_owned_database_with_custody(
  self : Library,
  path : String,
  ownership : @filesystem.NativeFileOwnership,
  max_body_bytes : Int64,
) -> Result[Database, NativeSqliteOpenFailure] {
  if max_body_bytes < 0L {
    return Err({ original_issue: InvalidLimit, database: None, })
  }
  let encoded = @utf8.encode(path)
  sqlite_open_result_with_custody(
    initialize_owned_database_ffi(
      self,
      encoded,
      encoded.length(),
      ownership.device,
      ownership.inode,
      max_body_bytes,
    ),
  )
}

///|
pub fn Database::read(
  self : Database,
  scope : String,
  key : String,
) -> Result[NativeJournalValue, NativeSqliteIssue] {
  let scope_bytes = @utf8.encode(scope)
  let key_bytes = @utf8.encode(key)
  if !valid_name(scope_bytes) || !valid_name(key_bytes) {
    return Err(InvalidName)
  }
  let code = database_read_ffi(
    self,
    scope_bytes,
    scope_bytes.length(),
    key_bytes,
    key_bytes.length(),
  )
  if code == 0 {
    Ok({
      revision: database_result_revision_ffi(self),
      body: database_result_body_ffi(self),
    })
  } else {
    Err(operation_issue(self, code))
  }
}

///|
/// Observe revision and byte length without allocating a copy of the body.
/// Original row validation/bound remain; missing and SQL failure are distinct.
pub fn Database::read_header(
  self : Database,
  scope : String,
  key : String,
) -> Result[NativeJournalHeader, NativeSqliteIssue] {
  let scope_bytes = @utf8.encode(scope)
  let key_bytes = @utf8.encode(key)
  if !valid_name(scope_bytes) || !valid_name(key_bytes) {
    return Err(InvalidName)
  }
  let code = database_read_header_ffi(
    self,
    scope_bytes,
    scope_bytes.length(),
    key_bytes,
    key_bytes.length(),
  )
  if code == 0 {
    Ok({
      revision: database_result_revision_ffi(self),
      body_bytes: database_result_header_body_bytes_ffi(self),
    })
  } else {
    Err(operation_issue(self, code))
  }
}

///|
/// Apply an additional body ceiling before the C readback and MoonBytes copies.
/// The database's original body bound and validation still apply. This neither
/// reserves backing nor authorizes access; SQLite row/statement/cache backing
/// must be accounted for independently by the caller's existing resource Owner.
pub fn Database::read_with_body_limit(
  self : Database,
  scope : String,
  key : String,
  max_body_bytes : Int64,
) -> Result[NativeJournalValue, NativeSqliteIssue] {
  if max_body_bytes < 0L {
    return Err(InvalidLimit)
  }
  let scope_bytes = @utf8.encode(scope)
  let key_bytes = @utf8.encode(key)
  if !valid_name(scope_bytes) || !valid_name(key_bytes) {
    return Err(InvalidName)
  }
  let code = database_read_with_body_limit_ffi(
    self,
    scope_bytes,
    scope_bytes.length(),
    key_bytes,
    key_bytes.length(),
    max_body_bytes,
  )
  if code == 0 {
    Ok({
      revision: database_result_revision_ffi(self),
      body: database_result_body_ffi(self),
    })
  } else {
    Err(operation_issue(self, code))
  }
}

///|
/// Open only an isolated inspection copy. The caller always receives the
/// cleanup owner, including when SQLite open failed; inspect status before use.
pub fn Library::open_inspection_database(
  self : Library,
  path : String,
  max_body_bytes : Int64,
) -> Database {
  let bytes = @utf8.encode(path)
  open_inspection_database_ffi(self, bytes, bytes.length(), max_body_bytes)
}

///|
/// Only the original Journal inspection Owner's unique copied DB/WAL and
/// owned empty SHM. The copy remains read-only and WAL-visible; status checks
/// the matching component's actual private-index path. This supplies neither
/// copy ownership nor resources, and never changes generic inspection.
pub fn Library::open_journal_inspection_database(
  self : Library,
  path : String,
  max_body_bytes : Int64,
) -> Database {
  let bytes = @utf8.encode(path)
  open_journal_inspection_database_ffi(
    self,
    bytes,
    bytes.length(),
    max_body_bytes,
  )
}

///|
pub fn Database::inspection_status(
  self : Database,
) -> Result[Unit, NativeSqliteIssue] {
  if database_ready_ffi(self) && inspection_schema_ffi(self) {
    Ok(())
  } else {
    Err(DatabaseOpen(decode_diagnostic(database_error_ffi(self))))
  }
}

///|
/// Failure leaves the physical owner intact. A retry never reopens SQLite or
/// repeats inspection/initialization; success is idempotent.
pub fn Database::close_checked(
  self : Database,
) -> Result[Unit, NativeSqliteIssue] {
  if close_checked_ffi(self) {
    Ok(())
  } else {
    Err(Physical(decode_diagnostic(database_error_ffi(self))))
  }
}

///|
/// Returns the next record in binary key order without materializing the
/// remaining namespace. An empty cursor starts at the first record.
pub fn Database::scan_after(
  self : Database,
  scope : String,
  after_key : String,
) -> Result[NativeJournalEntry, NativeSqliteIssue] {
  let scope_bytes = @utf8.encode(scope)
  let after_key_bytes = @utf8.encode(after_key)
  if !valid_name(scope_bytes) || after_key_bytes.length() > 512 {
    return Err(InvalidName)
  }
  let code = database_scan_after_ffi(
    self,
    scope_bytes,
    scope_bytes.length(),
    after_key_bytes,
    after_key_bytes.length(),
  )
  if code != 0 {
    return Err(operation_issue(self, code))
  }
  let key = @utf8.decode(database_result_key_ffi(self)) catch {
    _ => return Err(Physical("invalid stored journal key"))
  }
  Ok({
    key,
    revision: database_result_revision_ffi(self),
    body: database_result_body_ffi(self),
  })
}

///|
/// Apply an additional body ceiling before the C readback and MoonBytes copies.
/// The database's original body bound and validation still apply. This neither
/// reserves backing nor authorizes access; SQLite row/statement/cache backing
/// must be accounted for independently by the caller's existing resource Owner.
pub fn Database::scan_after_with_body_limit(
  self : Database,
  scope : String,
  after_key : String,
  max_body_bytes : Int64,
) -> Result[NativeJournalEntry, NativeSqliteIssue] {
  if max_body_bytes < 0L {
    return Err(InvalidLimit)
  }
  let scope_bytes = @utf8.encode(scope)
  let after_key_bytes = @utf8.encode(after_key)
  if !valid_name(scope_bytes) || after_key_bytes.length() > 512 {
    return Err(InvalidName)
  }
  let code = database_scan_after_with_body_limit_ffi(
    self,
    scope_bytes,
    scope_bytes.length(),
    after_key_bytes,
    after_key_bytes.length(),
    max_body_bytes,
  )
  if code != 0 {
    return Err(operation_issue(self, code))
  }
  let key = @utf8.decode(database_result_key_ffi(self)) catch {
    _ => return Err(Physical("invalid stored journal key"))
  }
  Ok({
    key,
    revision: database_result_revision_ffi(self),
    body: database_result_body_ffi(self),
  })
}

///|
pub fn Database::insert(
  self : Database,
  scope : String,
  key : String,
  body : Bytes,
) -> Result[Int64, NativeSqliteIssue] {
  let scope_bytes = @utf8.encode(scope)
  let key_bytes = @utf8.encode(key)
  if !valid_name(scope_bytes) || !valid_name(key_bytes) {
    return Err(InvalidName)
  }
  let code = database_insert_ffi(
    self,
    scope_bytes,
    scope_bytes.length(),
    key_bytes,
    key_bytes.length(),
    body,
    body.length(),
  )
  if code == 0 {
    Ok(database_result_revision_ffi(self))
  } else {
    Err(operation_issue(self, code))
  }
}

///|
pub fn Database::compare_exchange(
  self : Database,
  scope : String,
  key : String,
  expected_revision : Int64,
  body : Bytes,
) -> Result[Int64, NativeSqliteIssue] {
  let scope_bytes = @utf8.encode(scope)
  let key_bytes = @utf8.encode(key)
  if !valid_name(scope_bytes) || !valid_name(key_bytes) {
    return Err(InvalidName)
  }
  if expected_revision < 0L {
    return Err(Collision)
  }
  let code = database_compare_exchange_ffi(
    self,
    scope_bytes,
    scope_bytes.length(),
    key_bytes,
    key_bytes.length(),
    expected_revision,
    body,
    body.length(),
  )
  if code == 0 {
    Ok(database_result_revision_ffi(self))
  } else {
    Err(operation_issue(self, code))
  }
}

///|
/// Remove one exact original row inside an already-open, unfenced transaction.
/// This confirms neither transaction commit nor any other physical cleanup.
pub fn Database::remove_exact(
  self : Database,
  scope : String,
  key : String,
  expected_revision : Int64,
  expected_body : Bytes,
) -> Result[Unit, NativeSqliteIssue] {
  let scope_bytes = @utf8.encode(scope)
  let key_bytes = @utf8.encode(key)
  if !valid_name(scope_bytes) || !valid_name(key_bytes) {
    return Err(InvalidName)
  }
  if expected_revision < 0L {
    return Err(Collision)
  }
  let code = database_remove_exact_ffi(
    self,
    scope_bytes,
    scope_bytes.length(),
    key_bytes,
    key_bytes.length(),
    expected_revision,
    expected_body,
    expected_body.length(),
  )
  if code == 0 {
    Ok(())
  } else {
    Err(operation_issue(self, code))
  }
}

///|
/// Start a deferred physical snapshot on this same connection, without a
/// write or COMMIT. The caller must explicitly stop the original transaction.
pub fn Database::begin_deferred(
  self : Database,
) -> Result[Unit, NativeSqliteIssue] {
  let code = database_begin_deferred_ffi(self)
  if code == 0 {
    Ok(())
  } else {
    Err(operation_issue(self, code))
  }
}

///|
/// Begin one physical SQLite transaction for an adapter operation that must
/// install several already prepared records atomically.
pub fn Database::begin_immediate(
  self : Database,
) -> Result[Unit, NativeSqliteIssue] {
  let code = database_begin_immediate_ffi(self)
  if code == 0 {
    Ok(())
  } else {
    Err(operation_issue(self, code))
  }
}

///|
/// Commit the current physical transaction. Application state must still be
/// committed separately by the portable owner after this succeeds.
pub fn Database::commit(self : Database) -> Result[Unit, NativeSqliteIssue] {
  let code = database_commit_ffi(self)
  if code == 0 {
    Ok(())
  } else {
    Err(operation_issue(self, code))
  }
}

///|
/// Share an adapter's uncertain transaction outcome with other adapters on
/// this same physical handle. This does not classify the durable outcome or
/// authorize a replacement connection. There is no in-place fence reset.
pub fn Database::fence_transactions(self : Database) -> Unit {
  database_fence_transactions_ffi(self)
}

///|
pub fn Database::transaction_fenced(self : Database) -> Bool {
  database_transaction_fenced_ffi(self)
}

///|
pub fn Database::transaction_state(
  self : Database,
) -> Result[NativeSqliteTransactionState, NativeSqliteIssue] {
  match database_transaction_state_ffi(self) {
    0 => Ok(NoActiveSqliteTransaction)
    1 => Ok(ActiveSqliteTransaction)
    _ => Err(DatabaseClosed)
  }
}

///|
/// Roll back the current physical transaction after a failed adapter step.
pub fn Database::rollback(self : Database) -> Result[Unit, NativeSqliteIssue] {
  let code = database_rollback_ffi(self)
  if code == 0 {
    Ok(())
  } else {
    Err(operation_issue(self, code))
  }
}

///|
/// Atomically installs one exact reservation when both scope limits permit it.
/// Repeating the same key and quantities is idempotent and returns false.
pub fn Database::reserve_capacity(
  self : Database,
  scope : String,
  key : String,
  reserved_bytes : Int64,
  reserved_objects : Int64,
  max_bytes : Int64,
  max_objects : Int64,
) -> Result[Bool, NativeSqliteIssue] {
  self.reserve_capacity_transaction(
    scope, key, reserved_bytes, reserved_objects, max_bytes, max_objects, false,
  )
}

///|
/// Add an exact reservation to the caller's active transaction. This operation
/// never commits or rolls back; the caller must finish or retain that obligation.
/// Calling it outside a transaction is refused before any reservation is added.
pub fn Database::reserve_capacity_in_transaction(
  self : Database,
  scope : String,
  key : String,
  reserved_bytes : Int64,
  reserved_objects : Int64,
  max_bytes : Int64,
  max_objects : Int64,
) -> Result[Bool, NativeSqliteIssue] {
  self.reserve_capacity_transaction(
    scope, key, reserved_bytes, reserved_objects, max_bytes, max_objects, true,
  )
}

///|
fn Database::reserve_capacity_transaction(
  self : Database,
  scope : String,
  key : String,
  reserved_bytes : Int64,
  reserved_objects : Int64,
  max_bytes : Int64,
  max_objects : Int64,
  caller_transaction : Bool,
) -> Result[Bool, NativeSqliteIssue] {
  let scope_bytes = @utf8.encode(scope)
  let key_bytes = @utf8.encode(key)
  if !valid_name(scope_bytes) || !valid_name(key_bytes) {
    return Err(InvalidName)
  }
  if reserved_bytes < 0L ||
    reserved_objects < 0L ||
    max_bytes < 0L ||
    max_objects < 0L {
    return Err(InvalidLimit)
  }
  match
    database_reserve_capacity_ffi(
      self,
      scope_bytes,
      scope_bytes.length(),
      key_bytes,
      key_bytes.length(),
      reserved_bytes,
      reserved_objects,
      max_bytes,
      max_objects,
      if caller_transaction {
        1
      } else {
        0
      },
    ) {
    0 => Ok(true)
    7 => Ok(false)
    code => Err(operation_issue(self, code))
  }
}

///|
/// Atomically releases only the exact reservation. A missing reservation is
/// idempotent and returns false; a mismatched reservation is a collision.
pub fn Database::release_capacity(
  self : Database,
  scope : String,
  key : String,
  reserved_bytes : Int64,
  reserved_objects : Int64,
) -> Result[Bool, NativeSqliteIssue] {
  self.release_capacity_transaction(
    scope, key, reserved_bytes, reserved_objects, false,
  )
}

///|
/// Release the exact original reservation in the caller's active transaction.
/// Never commits, rolls back or supplies a physical cleanup/admission ACK.
pub fn Database::release_capacity_in_transaction(
  self : Database,
  scope : String,
  key : String,
  reserved_bytes : Int64,
  reserved_objects : Int64,
) -> Result[Bool, NativeSqliteIssue] {
  self.release_capacity_transaction(
    scope, key, reserved_bytes, reserved_objects, true,
  )
}

///|
fn Database::release_capacity_transaction(
  self : Database,
  scope : String,
  key : String,
  reserved_bytes : Int64,
  reserved_objects : Int64,
  caller_transaction : Bool,
) -> Result[Bool, NativeSqliteIssue] {
  let scope_bytes = @utf8.encode(scope)
  let key_bytes = @utf8.encode(key)
  if !valid_name(scope_bytes) || !valid_name(key_bytes) {
    return Err(InvalidName)
  }
  if reserved_bytes < 0L || reserved_objects < 0L {
    return Err(InvalidLimit)
  }
  let release = if caller_transaction {
    database_release_capacity_in_transaction_ffi
  } else {
    database_release_capacity_ffi
  }
  match
    release(
      self,
      scope_bytes,
      scope_bytes.length(),
      key_bytes,
      key_bytes.length(),
      reserved_bytes,
      reserved_objects,
    ) {
    0 => Ok(true)
    7 => Ok(false)
    code => Err(operation_issue(self, code))
  }
}

///|
/// Atomically assigns a stable one-based ordinal under a bounded namespace.
/// Repeating the same key returns its original ordinal without consuming a
/// second claim.
pub fn Database::claim_ordinal(
  self : Database,
  scope : String,
  key : String,
  max_claims : Int64,
) -> Result[Int64, NativeSqliteIssue] {
  self
  .claim_ordinal_action(scope, key, max_claims)
  .map(action => {
    match action {
      Fresh(ordinal) | Retained(ordinal) => ordinal
    }
  })
}

///|
/// Read an already stored claim without assigning an ordinal, reserving
/// capacity or changing the caller's transaction. Absence is not evidence of
/// nonexecution or permission to claim again. The caller separately checks the
/// original grant/use binding, current authority, expiry and cleanup custody.
pub fn Database::lookup_claim_ordinal(
  self : Database,
  scope : String,
  key : String,
) -> Result[Int64?, NativeSqliteIssue] {
  let scope_bytes = @utf8.encode(scope)
  let key_bytes = @utf8.encode(key)
  if !valid_name(scope_bytes) || !valid_name(key_bytes) {
    return Err(InvalidName)
  }
  match
    database_lookup_claim_ordinal_ffi(
      self,
      scope_bytes,
      scope_bytes.length(),
      key_bytes,
      key_bytes.length(),
    ) {
    0 => {
      let ordinal = database_result_revision_ffi(self)
      if ordinal <= 0L {
        Err(Physical("invalid original claim ordinal"))
      } else {
        Ok(Some(ordinal))
      }
    }
    1 => Ok(None)
    code => Err(operation_issue(self, code))
  }
}

///|
/// Preserve the existing transaction's new/original result. A retained claim
/// must not be promoted to a fresh send when its separate use record is lost.
pub fn Database::claim_ordinal_action(
  self : Database,
  scope : String,
  key : String,
  max_claims : Int64,
) -> Result[NativeOrdinalClaim, NativeSqliteIssue] {
  self.claim_ordinal_owned(scope, key, max_claims, false)
}

///|
/// Assign or observe the same bounded ordinal inside the caller's active TX.
/// Does not begin, commit or roll back that TX, including on refusal. The caller
/// must atomically persist its original use and retain uncertain commit custody.
/// No transaction/fenced handle refuses; this is storage, not use permission.
pub fn Database::claim_ordinal_action_in_transaction(
  self : Database,
  scope : String,
  key : String,
  max_claims : Int64,
) -> Result[NativeOrdinalClaim, NativeSqliteIssue] {
  self.claim_ordinal_owned(scope, key, max_claims, true)
}

///|
fn Database::claim_ordinal_owned(
  self : Database,
  scope : String,
  key : String,
  max_claims : Int64,
  caller_transaction : Bool,
) -> Result[NativeOrdinalClaim, NativeSqliteIssue] {
  let scope_bytes = @utf8.encode(scope)
  let key_bytes = @utf8.encode(key)
  if !valid_name(scope_bytes) || !valid_name(key_bytes) {
    return Err(InvalidName)
  }
  if max_claims <= 0L {
    return Err(InvalidLimit)
  }
  let code = if caller_transaction {
    database_claim_ordinal_in_transaction_ffi(
      self,
      scope_bytes,
      scope_bytes.length(),
      key_bytes,
      key_bytes.length(),
      max_claims,
    )
  } else {
    database_claim_ordinal_ffi(
      self,
      scope_bytes,
      scope_bytes.length(),
      key_bytes,
      key_bytes.length(),
      max_claims,
    )
  }
  match code {
    0 => {
      let ordinal = database_result_revision_ffi(self)
      if ordinal <= 0L {
        Err(Physical("invalid bounded claim ordinal"))
      } else {
        Ok(Fresh(ordinal))
      }
    }
    7 => {
      let ordinal = database_result_revision_ffi(self)
      if ordinal <= 0L {
        Err(Physical("invalid retained claim ordinal"))
      } else {
        Ok(Retained(ordinal))
      }
    }
    code => Err(operation_issue(self, code))
  }
}

///|
/// Lookup only: neither a missing reservation nor its retained amounts permit
/// another reserve, physical launch, release or mutation.
pub fn Database::read_capacity(
  self : Database,
  scope : String,
  key : String,
) -> Result[NativeCapacityUsage, NativeSqliteIssue] {
  let scope_bytes = @utf8.encode(scope)
  let key_bytes = @utf8.encode(key)
  if !valid_name(scope_bytes) || !valid_name(key_bytes) {
    return Err(InvalidName)
  }
  let code = database_read_capacity_ffi(
    self,
    scope_bytes,
    scope_bytes.length(),
    key_bytes,
    key_bytes.length(),
  )
  if code == 0 {
    Ok({
      reserved_bytes: database_result_capacity_bytes_ffi(self),
      reserved_objects: database_result_capacity_objects_ffi(self),
    })
  } else {
    Err(operation_issue(self, code))
  }
}

///|
/// Physical totals only, in the same connection's current SQLite view. A
/// caller-owned transaction may include uncommitted rows; this is no durable
/// publication fact and never completes the caller's transaction.
pub fn Database::database_usage(
  self : Database,
) -> Result[NativeDatabaseUsage, NativeSqliteIssue] {
  let code = database_usage_ffi(self)
  if code == 0 {
    Ok({
      record_count: database_result_record_count_ffi(self),
      body_bytes: database_result_record_body_bytes_ffi(self),
      reservation_count: database_result_reservation_count_ffi(self),
    })
  } else {
    Err(operation_issue(self, code))
  }
}

///|
pub fn Database::capacity_usage(
  self : Database,
  scope : String,
) -> Result[NativeCapacityUsage, NativeSqliteIssue] {
  let scope_bytes = @utf8.encode(scope)
  if !valid_name(scope_bytes) {
    return Err(InvalidName)
  }
  let code = database_capacity_usage_ffi(
    self,
    scope_bytes,
    scope_bytes.length(),
  )
  if code == 0 {
    Ok({
      reserved_bytes: database_result_capacity_bytes_ffi(self),
      reserved_objects: database_result_capacity_objects_ffi(self),
    })
  } else {
    Err(operation_issue(self, code))
  }
}

///|
pub fn Database::close(self : Database) -> Unit {
  close_database_ffi(self)
}
