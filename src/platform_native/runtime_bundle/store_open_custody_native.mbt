///|
/// Failed preparation owns the original physical handles, never another Store
/// or a replacement catalog/holding. Only Native constructs this opaque value.
struct NativeRuntimeBundleStoreOpenFailure {
  original_issue : NativeRuntimeBundleStoreIssue
  mut root : @filesystem.Root?
  mut failed_root : @filesystem.NativeRootOpenFailure?
  mut lock : @filesystem.Lock?
  mut failed_lock : @filesystem.NativeLockOpenFailure?
  mut database : @sqlite.Database?
  mut failed_database : @sqlite.NativeSqliteOpenFailure?
}

///|
pub fn NativeRuntimeBundleStoreOpenFailure::issue(
  self : NativeRuntimeBundleStoreOpenFailure,
) -> NativeRuntimeBundleStoreIssue {
  self.original_issue
}

///|
/// Reverse preparation order, same nominal Owners. A failed ACK preserves
/// this handle and every outer handle; no catalog read, reopen, hold release,
/// reservation return or durable record deletion occurs here.
pub fn NativeRuntimeBundleStoreOpenFailure::retry_cleanup(
  self : NativeRuntimeBundleStoreOpenFailure,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
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
fn bundle_store_open_failure(
  original_issue : NativeRuntimeBundleStoreIssue,
  root? : @filesystem.Root? = None,
  failed_root? : @filesystem.NativeRootOpenFailure? = None,
  lock? : @filesystem.Lock? = None,
  failed_lock? : @filesystem.NativeLockOpenFailure? = None,
  database? : @sqlite.Database? = None,
  failed_database? : @sqlite.NativeSqliteOpenFailure? = None,
) -> NativeRuntimeBundleStoreOpenFailure {
  {
    original_issue,
    root,
    failed_root,
    lock,
    failed_lock,
    database,
    failed_database,
  }
}

///|
/// Validate/configure exactly as the existing constructor. A new catalog is
/// initialized only by its original CAS; failed cleanup never initializes it.
pub fn open_runtime_bundle_store_with_custody(
  sqlite_library : @sqlite.Library,
  signature_library : @signature.Library,
  root_path : String,
  authorities : Array[NativeRuntimeBundleAuthority],
  target_triple : String,
  capacity_bytes : Int64,
  max_bundles : Int,
  max_owners : Int,
  max_record_bytes : Int64,
) -> Result[NativeRuntimeBundleStore, NativeRuntimeBundleStoreOpenError] {
  open_runtime_bundle_store_with_authorities_and_custody(
    sqlite_library, signature_library, root_path, authorities, authorities, target_triple,
    capacity_bytes, max_bundles, max_owners, max_record_bytes,
  )
}

///|
/// Exact verification/copy custody already retained by this Store. Never
/// reopen after a failed close or discard a rejected Reader before its ACK.
/// Copy Readers retire before the original Writer; cancel/sync failures keep
/// that Writer and the outer DB/Lock/Root alive without releasing copy bytes.
fn close_bundle_component_reader(
  store : NativeRuntimeBundleStore,
  original_reader? : @filesystem.Reader? = None,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  if original_reader is Some(same) {
    // Successful verification keeps its live reader locally until this close.
    // Only a failed close leaves this exact reference in the Store.
    if store.component_reader is Some(prior) && !physical_equal(prior, same) {
      return Err(CleanupPending)
    }
    store.component_reader = Some(same)
  }
  if store.component_hasher is Some(original) {
    match original.close_checked() {
      Ok(_) => store.component_hasher = None
      Err(issue) => return Err(Signature(issue))
    }
  }
  if store.component_open_failure is Some(original) {
    match original.retry_cleanup() {
      Ok(_) => store.component_open_failure = None
      Err(issue) => return Err(Filesystem(issue))
    }
  }
  if store.component_reader is Some(original) {
    match original.close() {
      Ok(_) => store.component_reader = None
      Err(issue) => return Err(Filesystem(issue))
    }
  }
  if store.component_writer_open_failure is Some(original) {
    match original.retry_cleanup() {
      Ok(_) => store.component_writer_open_failure = None
      Err(issue) => return Err(Filesystem(issue))
    }
  }
  if store.component_writer is Some(original) {
    match original.cancel() {
      Ok(_) => store.component_writer = None
      Err(issue) => return Err(Filesystem(issue))
    }
  }
  Ok(())
}

///|
/// Retain before fallible cleanup, never replace an earlier copy's original.
/// This retires physical I/O only; the existing durable copy intent/reservation
/// remains until its separate original recovery and catalog CAS confirm it.
fn cancel_bundle_component_writer(
  store : NativeRuntimeBundleStore,
  original : @filesystem.Writer,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  if store.component_writer is Some(prior) && !physical_equal(prior, original) {
    return Err(CleanupPending)
  }
  store.component_writer = Some(original)
  close_bundle_component_reader(store)
}
