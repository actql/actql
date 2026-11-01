///|
priv suberror CommandStop {
  CommandStop(String)
}

///|
fn[T] stop(message : String) -> T raise CommandStop {
  raise CommandStop(message)
}

///|
priv type BundleEntryOriginal

///|
extern "C" fn capture_bundle_entry_ffi() -> BundleEntryOriginal = "actql_bundle_capture_initial_entry"

///|
#borrow(original)
extern "C" fn bundle_entry_current_ffi(original : BundleEntryOriginal) -> Int = "actql_bundle_initial_entry_current"

///|
#borrow(original)
extern "C" fn bundle_entry_pin_ffi(
  original : BundleEntryOriginal,
  kind : Int,
) -> Bytes = "actql_bundle_initial_entry_pin"

///|
#borrow(original)
extern "C" fn bundle_entry_quantity_ffi(
  original : BundleEntryOriginal,
  kind : Int,
) -> Int64 = "actql_bundle_initial_entry_quantity"

///|
#borrow(original)
extern "C" fn retire_bundle_entry_ffi(original : BundleEntryOriginal) -> Int = "actql_bundle_retire_initial_entry"

///|
extern "C" fn bundle_control_diagnostic_ffi(stage : Int) -> Unit = "actql_bundle_initial_control_diagnostic"

///|
#borrow(message)
extern "C" fn bundle_command_failure_ffi(message : Bytes, length : Int) -> Unit = "actql_bundle_command_failure"

///|
extern "C" fn bundle_control_exit_failure_ffi() -> Unit = "actql_bundle_initial_control_exit_failure"

///|
/// The real captured command entry is the bootstrap's original anchor. All
/// partial acquisitions remain on this carrier before their status is read.
/// This private installation slice grants no Run, VM, Site or read authority.
struct BundleInitialControl {
  original : BundleEntryOriginal
  mut host : @bootstrap.NativeHostBootstrap[BundleEntryOriginal]?
  mut scope : @bootstrap.NativeBootstrapBorrow[BundleEntryOriginal]?
  mut scope_entered : Bool
  mut region : @bootstrap.NativeBackedExecutionRegion[
    BundleEntryOriginal,
    BundleEntryOriginal,
  ]?
  mut loan : @bootstrap.NativeBackedExecutionLoan[
    BundleEntryOriginal,
    BundleEntryOriginal,
  ]?
  mut view : @bootstrap.NativeBackedExecutionView[
    BundleEntryOriginal,
    BundleEntryOriginal,
  ]?
  mut domain : @bootstrap.NativeBackedExecutionDomain[
    BundleEntryOriginal,
    BundleEntryOriginal,
  ]?
  mut read_entered : Bool
  mut managed_payload_bytes : Int64
  mut sqlite_heap_bytes : Int64
  mut crypto_heap_bytes : Int64
  mut diagnostic_bytes : Int
  mut sqlite : @sqlite.Library?
  mut failed_sqlite : @sqlite.NativeSqliteLibraryLoadFailure?
  mut crypto_component : @signature.OriginalCryptoComponent?
  mut crypto : @signature.Library?
  mut store : @runtime_bundle.NativeRuntimeBundleStore?
  mut failed_store : @runtime_bundle.NativeRuntimeBundleStoreOpenFailure?
  mut retired : Bool
}

///|
fn capture_bundle_initial_control() -> BundleInitialControl {
  {
    original: capture_bundle_entry_ffi(),
    host: None,
    scope: None,
    scope_entered: false,
    region: None,
    loan: None,
    view: None,
    domain: None,
    read_entered: false,
    managed_payload_bytes: 0L,
    sqlite_heap_bytes: 0L,
    crypto_heap_bytes: 0L,
    diagnostic_bytes: 0,
    sqlite: None,
    failed_sqlite: None,
    crypto_component: None,
    crypto: None,
    store: None,
    failed_store: None,
    retired: false,
  }
}

///|
fn BundleInitialControl::require_current(
  self : BundleInitialControl,
) -> Unit raise CommandStop {
  if self.retired || bundle_entry_current_ffi(self.original) != 1 {
    stop("original installed command entry unavailable")
  }
}

///|
fn BundleInitialControl::acquire(
  self : BundleInitialControl,
) -> Unit raise CommandStop {
  self.require_current()
  let source_bytes = bundle_entry_pin_ffi(self.original, 0)
  let recipe = bundle_entry_pin_ffi(self.original, 1)
  if source_bytes.length() != 40 || recipe.length() != 32 {
    stop("installed command recipe unavailable")
  }
  let source = @utf8.decode(source_bytes) catch {
    _ => stop("installed command source unavailable")
  }
  let quantity = (kind : Int) => bundle_entry_quantity_ffi(self.original, kind)
  let generation = quantity(0)
  let capacity = quantity(1)
  let control_envelope = quantity(2)
  let limits : @resources.LedgerLimits = {
    planning_work: quantity(3).to_int(),
    attempts: quantity(4).to_int(),
    holdings: quantity(5).to_int(),
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: capacity,
  }
  let supplier = @bootstrap.prepare_installed_arena_supplier(
    self.original,
    source,
    recipe,
    generation,
    capacity,
    limits,
    control_envelope,
  ).bundle_initial_require("installed command supplier refused")
  let acquisition = supplier
    .acquire(self.original)
    .bundle_initial_require("installed command acquisition refused")
  match acquisition {
    Acquired(host) => self.host = Some(host)
    Pending(host, _) => {
      self.host = Some(host)
      stop("installed command acquisition pending")
    }
  }
  guard self.host is Some(host) else { stop("original bootstrap missing") }
  host
  .claim(self.original, source, recipe, generation)
  .bundle_initial_require("installed command claim refused")
  let scope = host
    .borrow_backing(self.original)
    .bundle_initial_require("installed command borrow refused")
  self.scope = Some(scope)
  host
  .enter_borrow_scope(self.original, scope)
  .bundle_initial_require("installed command scope refused")
  self.scope_entered = true
  // This is the SAME already-reserved arena's actual remaining capacity,
  // including its charged control layout, not a second numerical grant.
  let available = host
    .initial_payload_capacity(self.original)
    .bundle_initial_require("installed command original capacity unavailable")
  self.managed_payload_bytes = quantity(6)
  self.sqlite_heap_bytes = quantity(7)
  self.crypto_heap_bytes = quantity(8)
  let diagnostic = quantity(9)
  if self.managed_payload_bytes <= 0L ||
    self.sqlite_heap_bytes < 4096L ||
    self.crypto_heap_bytes <= 0L ||
    diagnostic <= 0L ||
    diagnostic > 2147483647L {
    stop("installed component selection unavailable")
  }
  self.diagnostic_bytes = diagnostic.to_int()
  // SQLite and Crypto allocate through the SAME entered Read's lease.
  // Quote their complete overlap with managed command values in ONE domain;
  // free bytes in the outer parent cannot back an inner allocation.
  if self.managed_payload_bytes >= available ||
    self.sqlite_heap_bytes >= available - self.managed_payload_bytes ||
    self.crypto_heap_bytes >=
    available - self.managed_payload_bytes - self.sqlite_heap_bytes {
    stop("installed component extents exceed original backing")
  }
  let read_payload_bytes = self.managed_payload_bytes +
    self.sqlite_heap_bytes +
    self.crypto_heap_bytes
  let domain_bytes = bundle_managed_domain_bytes(read_payload_bytes)
  if domain_bytes > available {
    stop("installed component layout exceeds original backing")
  }
  let allocation = host
    .allocate_in_process_domain(self.original, domain_bytes)
    .bundle_initial_require("installed command domain allocation refused")
  let region = host
    .issue_backed_region(self.original, allocation)
    .bundle_initial_require("installed command region refused")
  self.region = Some(region)
  let child_limits : @resources.LedgerLimits = {
    planning_work: 16,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: domain_bytes,
  }
  let acquired_loan = host
    .lend_backed_region_in_process(
      self.original,
      region,
      scope,
      self.original,
      {
        offset: 0L,
        length: domain_bytes,
        payload_offset: 0L,
        payload_length: domain_bytes,
      },
      @resources.ExclusiveWrite,
      child_limits,
      0L,
      0L,
    )
    .bundle_initial_require("installed command loan refused")
  match acquired_loan {
    Lent(loan) => self.loan = Some(loan)
    Pending(loan, _) => {
      self.loan = Some(loan)
      stop("installed command loan pending")
    }
  }
  guard self.loan is Some(loan) else { stop("original command loan missing") }
  match
    host
    .view_backed_region_in_process(self.original, loan, self.original)
    .bundle_initial_require("installed command view refused") {
    Mapped(view) => self.view = Some(view)
    PendingView(view, _) => {
      self.view = Some(view)
      stop("installed command view pending")
    }
  }
  guard self.view is Some(view) else { stop("original command view missing") }
  match
    host
    .acquire_backed_domain(self.original, view, self.original)
    .bundle_initial_require("installed command domain refused") {
    DomainReady(domain) => self.domain = Some(domain)
    DomainPending(domain, _) => {
      self.domain = Some(domain)
      stop("installed command domain pending")
    }
  }
  guard self.domain is Some(domain) else {
    stop("original command domain missing")
  }
  host
  .transfer_backed_domain(self.original, domain, self.original)
  .bundle_initial_require("installed command transfer refused")
  // The existing provider refuses entry into a different domain while the
  // parent arena is entered. Return only that scope, retaining its same loan.
  host
  .leave_borrow_scope(self.original, scope)
  .bundle_initial_require("installed command parent scope leave pending")
  self.scope_entered = false
  // Read construction is attempted once on the same retained domain. A failed
  // physical or accounting step keeps that carrier for child-first cleanup.
  host
  .prepare_backed_read_context(
    self.original,
    domain,
    self.original,
    execution_ceiling=read_payload_bytes,
  )
  .bundle_initial_require("installed command read context refused")
}

///|
fn BundleInitialControl::enter(
  self : BundleInitialControl,
) -> Unit raise CommandStop {
  self.require_current()
  guard self.host is Some(host) && self.domain is Some(domain) else {
    stop("original command backing missing")
  }
  host
  .enter_backed_read_context(self.original, domain, self.original)
  .bundle_initial_require("installed command read entry refused")
  self.read_entered = true
}

///|
/// Call only after all managed parser/command aliases unwind. A failure keeps
/// the exact outstanding stage; no process exit or logical close is an ACK.
fn BundleInitialControl::close(self : BundleInitialControl) -> Bool {
  if self.retired {
    return true
  }
  // Actual Store/Library partials still require the entered original Read.
  // Never leave its parent domain merely because command execution returned.
  if self.store is Some(_) ||
    self.failed_store is Some(_) ||
    self.sqlite is Some(_) ||
    self.failed_sqlite is Some(_) ||
    self.crypto is Some(_) ||
    self.crypto_component is Some(_) {
    return false
  }
  if self.host is Some(host) {
    if self.domain is Some(domain) {
      if self.read_entered {
        if host.leave_backed_read_context(self.original, domain, self.original)
          is Err(_) {
          return false
        }
        self.read_entered = false
      }
      // The same domain Owner knows whether read_use was published, including
      // a failed preparation. It closes that original Read when present; an
      // attempted Bool cannot invent a missing reader or replace its cleanup.
      if host.close_backed_domain(self.original, domain, self.original)
        is Err(_) {
        return false
      }
      self.domain = None
    }
    if self.scope is Some(scope) {
      if self.scope_entered {
        if host.leave_borrow_scope(self.original, scope) is Err(_) {
          return false
        }
        self.scope_entered = false
      }
    }
    if self.view is Some(view) {
      if host.close_backed_view(self.original, view, self.original) is Err(_) {
        return false
      }
      self.view = None
    }
    if self.loan is Some(loan) {
      if host.settle_backed_region_after_owner_ack(
          self.original,
          loan,
          self.original,
          None,
        )
        is Err(_) {
        return false
      }
      self.loan = None
    }
    if self.region is Some(region) {
      if !(host.close_backed_region(self.original, region) is Ok(true)) {
        return false
      }
      self.region = None
    }
    if self.scope is Some(scope) {
      if host.return_borrow(self.original, scope) is Err(_) {
        return false
      }
      self.scope = None
    }
    if host.try_close(self.original) is Err(_) {
      return false
    }
    self.host = None
  }
  if retire_bundle_entry_ffi(self.original) != 1 {
    return false
  }
  self.retired = true
  true
}

///|
fn[T, E] Result::bundle_initial_require(
  self : Result[T, E],
  message : String,
) -> T raise CommandStop {
  match self {
    Ok(value) => value
    Err(_) => stop(message)
  }
}

///|
fn bundle_managed_domain_bytes(payload : Int64) -> Int64 raise CommandStop {
  let mut bytes = payload
  for index = 0; index < 8; index = index + 1 {
    let necessary = @bootstrap.execution_domain_necessary_bytes(bytes, payload)
    if necessary <= 0L {
      stop("installed command provider layout unavailable")
    }
    if necessary <= bytes {
      return bytes
    }
    bytes = necessary
  }
  stop("installed command provider layout did not converge")
}

///|
/// Child cleanup executes while the SAME original Read is still entered. Each
/// receiver remains on this carrier before any fallible close. Failed ACKs keep
/// all outer obligations; they do not permit replacement or parent retirement.
fn BundleInitialControl::close_children(self : BundleInitialControl) -> Bool {
  if self.failed_store is Some(original) {
    if original.retry_cleanup() is Err(_) {
      return false
    }
    self.failed_store = None
  }
  if self.store is Some(original) {
    if original.close() is Err(_) {
      return false
    }
    self.store = None
  }
  if self.crypto is Some(original) {
    if original.close_checked() is Err(_) {
      return false
    }
    self.crypto = None
  }
  if self.crypto_component is Some(original) {
    if original.close_checked() is Err(_) {
      return false
    }
    self.crypto_component = None
  }
  if self.failed_sqlite is Some(original) {
    if original.retry_cleanup() is Err(_) {
      return false
    }
    self.failed_sqlite = None
  }
  if self.sqlite is Some(original) {
    if original.close_checked() is Err(_) {
      return false
    }
    self.sqlite = None
  }
  true
}

///|
fn BundleInitialControl::load_sqlite(
  self : BundleInitialControl,
  path : String,
) -> Result[@sqlite.Library, String] {
  if self.sqlite is Some(_) || self.failed_sqlite is Some(_) {
    return Err("original SQLite acquisition already attempted")
  }
  match
    @sqlite.load_current_component_with_custody(
      path,
      self.sqlite_heap_bytes,
      self.diagnostic_bytes,
    ) {
    Ok(original) => {
      self.sqlite = Some(original)
      Ok(original)
    }
    Err(RefusedBeforeAcquisition(_)) =>
      Err("SQLite component acquisition refused")
    Err(CleanupRequired(original)) => {
      self.failed_sqlite = Some(original)
      Err("SQLite component acquisition cleanup pending")
    }
  }
}

///|
fn BundleInitialControl::load_crypto(
  self : BundleInitialControl,
  path : String,
) -> Result[@signature.Library, String] {
  if self.crypto is Some(_) || self.crypto_component is Some(_) {
    return Err("original Crypto acquisition already attempted")
  }
  let component = match
    @signature.load_current_crypto_component(
      path,
      self.crypto_heap_bytes,
      self.diagnostic_bytes,
    ) {
    Ok(ReadyCryptoComponent(original)) => {
      self.crypto_component = Some(original)
      original
    }
    Ok(PendingCryptoComponent(original, _)) => {
      self.crypto_component = Some(original)
      return Err("Crypto component acquisition cleanup pending")
    }
    Err(_) => return Err("Crypto component acquisition refused")
  }
  match component.new_library() {
    Ok(ReadyCryptoLibrary(original)) => {
      self.crypto = Some(original)
      Ok(original)
    }
    Ok(PendingCryptoLibrary(original, _)) => {
      self.crypto = Some(original)
      Err("Crypto Library acquisition cleanup pending")
    }
    Err(_) => Err("Crypto Library acquisition refused")
  }
}
