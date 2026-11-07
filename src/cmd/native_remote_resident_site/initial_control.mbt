///|
priv type ResidentEntryOriginal

///|
extern "C" fn capture_resident_entry_ffi() -> ResidentEntryOriginal = "actql_resident_capture_initial_entry"

///|
#borrow(original)
extern "C" fn resident_entry_current_ffi(
  original : ResidentEntryOriginal,
) -> Int = "actql_resident_initial_entry_current"

///|
#borrow(original)
extern "C" fn resident_entry_pin_ffi(
  original : ResidentEntryOriginal,
  kind : Int,
) -> Bytes = "actql_resident_initial_entry_pin"

///|
#borrow(original)
extern "C" fn resident_entry_quantity_ffi(
  original : ResidentEntryOriginal,
  kind : Int,
) -> Int64 = "actql_resident_initial_entry_quantity"

///|
#borrow(original)
extern "C" fn retire_resident_entry_ffi(
  original : ResidentEntryOriginal,
) -> Int = "actql_resident_retire_initial_entry"

///|
extern "C" fn resident_control_diagnostic_ffi(stage : Int) -> Unit = "actql_resident_initial_control_diagnostic"

///|
/// Closed acquire/enter literals select fixed diagnostics before the Read is
/// entered. Never encode or print the message here. Unknown failures retain
/// stage 1; stages 2 and 3 still describe the original cleanup boundaries.
fn resident_initial_failure_stage(message : String) -> Int {
  match message {
    "original installed command entry unavailable" => 101
    "installed command recipe unavailable" => 102
    "installed command source unavailable" => 103
    "installed command supplier refused" => 104
    "installed command acquisition refused" => 105
    "installed command acquisition pending" => 106
    "original bootstrap missing" => 107
    "installed command claim refused" => 108
    "installed command borrow refused" => 109
    "installed command scope refused" => 110
    "installed command original capacity unavailable" => 111
    "installed component selection exceeds original backing" => 112
    "installed managed extent unavailable" => 113
    "installed managed layout unavailable" => 114
    "installed components exhaust original Read payload" => 115
    "installed command domain allocation refused" => 116
    "installed command region refused" => 117
    "installed command loan refused" => 118
    "installed command loan pending" => 119
    "original command loan missing" => 120
    "installed command view refused" => 121
    "installed command view pending" => 122
    "original command view missing" => 123
    "installed command domain refused" => 124
    "installed command domain pending" => 125
    "original command domain missing" => 126
    "installed command transfer refused" => 127
    "installed command parent scope leave pending" => 128
    "installed command read context refused" => 129
    "original command backing missing" => 130
    "installed command read entry refused" => 131
    "installed command Read control refused" => 132
    "installed command control entry refused" => 133
    "installed command control leave pending" => 134
    "installed command working supplier refused" => 135
    _ => 1
  }
}

///|
#borrow(message)
extern "C" fn resident_command_failure_ffi(
  message : Bytes,
  length : Int,
) -> Unit = "actql_resident_command_failure"

///|
extern "C" fn resident_control_exit_failure_ffi() -> Unit = "actql_resident_initial_control_exit_failure"

///|
#borrow(original)
extern "C" fn resident_controller_retired_ffi(
  original : ResidentEntryOriginal,
) -> Int = "actql_resident_controller_retired"

///|
/// The real captured command entry is the bootstrap's original anchor. All
/// partial acquisitions remain on this carrier before their status is read.
/// This private installation slice grants no Run, VM, Site or read authority.
struct ResidentInitialControl {
  original : ResidentEntryOriginal
  mut host : @bootstrap.NativeHostBootstrap[ResidentEntryOriginal]?
  mut scope : @bootstrap.NativeBootstrapBorrow[ResidentEntryOriginal]?
  mut scope_entered : Bool
  mut region : @bootstrap.NativeBackedExecutionRegion[
    ResidentEntryOriginal,
    ResidentEntryOriginal,
  ]?
  mut loan : @bootstrap.NativeBackedExecutionLoan[
    ResidentEntryOriginal,
    ResidentEntryOriginal,
  ]?
  mut view : @bootstrap.NativeBackedExecutionView[
    ResidentEntryOriginal,
    ResidentEntryOriginal,
  ]?
  mut domain : @bootstrap.NativeBackedExecutionDomain[
    ResidentEntryOriginal,
    ResidentEntryOriginal,
  ]?
  mut control_entered : Bool
  mut read_entered : Bool
  mut read_payload_bytes : Int64
  mut sqlite_heap_bytes : Int64
  mut crypto_heap_bytes : Int64
  mut diagnostic_bytes : Int
  mut sqlite_path : String?
  mut sqlite : @sqlite.Library?
  mut failed_sqlite : @sqlite.NativeSqliteLibraryLoadFailure?
  mut crypto_path : String?
  mut crypto_component : @signature.OriginalCryptoComponent?
  mut crypto : @signature.Library?
  mut http_path : String?
  mut http_library : @http.Library?
  mut failed_http_library : @http.NativeHttpLibraryLoadFailure?
  mut http_client_attempted : Bool
  mut http_client : @http.Client?
  mut failed_http_client : @http.NativeHttpClientCreateFailure?
  // Retirement only forbids further loads. It is not a cleanup ACK.
  mut libraries_retiring : Bool
  // Select the controller's terminal report only after its normal return.
  // This marker is not cleanup evidence; close() still checks every Owner.
  mut controller_returned : Bool
  mut retired : Bool
}

///|
fn capture_resident_initial_control() -> ResidentInitialControl {
  {
    original: capture_resident_entry_ffi(),
    host: None,
    scope: None,
    scope_entered: false,
    region: None,
    loan: None,
    view: None,
    domain: None,
    control_entered: false,
    read_entered: false,
    read_payload_bytes: 0L,
    sqlite_heap_bytes: 0L,
    crypto_heap_bytes: 0L,
    diagnostic_bytes: 0,
    sqlite_path: None,
    sqlite: None,
    failed_sqlite: None,
    crypto_path: None,
    crypto_component: None,
    crypto: None,
    http_path: None,
    http_library: None,
    failed_http_library: None,
    http_client_attempted: false,
    http_client: None,
    failed_http_client: None,
    libraries_retiring: false,
    controller_returned: false,
    retired: false,
  }
}

///|
fn ResidentInitialControl::require_current(
  self : ResidentInitialControl,
) -> Unit raise CommandStop {
  if self.retired || resident_entry_current_ffi(self.original) != 1 {
    stop("original installed command entry unavailable")
  }
}

///|
fn ResidentInitialControl::acquire(
  self : ResidentInitialControl,
) -> Unit raise CommandStop {
  self.require_current()
  let source_bytes = resident_entry_pin_ffi(self.original, 0)
  let recipe = resident_entry_pin_ffi(self.original, 1)
  if source_bytes.length() != 40 || recipe.length() != 32 {
    stop("installed command recipe unavailable")
  }
  let source = @utf8.decode(source_bytes) catch {
    _ => stop("installed command source unavailable")
  }
  let quantity = (kind : Int) => {
    resident_entry_quantity_ffi(self.original, kind)
  }
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
  ).resident_initial_require("installed command supplier refused")
  let acquisition = supplier
    .acquire(self.original)
    .resident_initial_require("installed command acquisition refused")
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
  .resident_initial_require("installed command claim refused")
  let scope = host
    .borrow_backing(self.original)
    .resident_initial_require("installed command borrow refused")
  self.scope = Some(scope)
  host
  .enter_borrow_scope(self.original, scope)
  .resident_initial_require("installed command scope refused")
  self.scope_entered = true
  // The fixed Read/control basis is charged before this same Host selects
  // its payload. Domain bytes cannot consume bookkeeping still owed later.
  host
  .prepare_backed_read_control(self.original, scope)
  .resident_initial_require("installed command Read control refused")
  if !host.enter_backed_read_control(self.original, scope) {
    stop("installed command control entry refused")
  }
  self.control_entered = true
  // This is the SAME already-reserved arena's actual remaining capacity,
  // including its charged control layout, not a second numerical grant.
  let available = host
    .initial_payload_capacity(self.original)
    .resident_initial_require("installed command original capacity unavailable")
  self.sqlite_heap_bytes = quantity(6)
  self.crypto_heap_bytes = quantity(7)
  let diagnostic = quantity(8)
  if self.sqlite_heap_bytes < 4096L ||
    self.crypto_heap_bytes <= 0L ||
    diagnostic <= 0L ||
    diagnostic > 2147483647L ||
    self.sqlite_heap_bytes >= available ||
    self.crypto_heap_bytes >= available - self.sqlite_heap_bytes {
    stop("installed component selection exceeds original backing")
  }
  self.diagnostic_bytes = diagnostic.to_int()
  // The component heaps allocate through the SAME current Read/lease, not
  // a spare outer arena. Its one payload ceiling includes BOTH heaps plus
  // managed values. Derive the coexisting total from the original provider's
  // actual control/context layout; the installed arena is unchanged.
  let domain_bytes = available
  self.read_payload_bytes = resident_read_payload_bytes(domain_bytes)
  if self.sqlite_heap_bytes >= self.read_payload_bytes ||
    self.crypto_heap_bytes >= self.read_payload_bytes - self.sqlite_heap_bytes {
    stop("installed components exhaust original Read payload")
  }
  let allocation = host
    .allocate_in_process_domain(self.original, domain_bytes)
    .resident_initial_require("installed command domain allocation refused")
  let region = host
    .issue_backed_region(self.original, allocation)
    .resident_initial_require("installed command region refused")
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
    .resident_initial_require("installed command loan refused")
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
    .resident_initial_require("installed command view refused") {
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
    .resident_initial_require("installed command domain refused") {
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
  .resident_initial_require("installed command transfer refused")
  host
  .leave_backed_read_control(self.original, scope)
  .resident_initial_require("installed command control leave pending")
  self.control_entered = false
  // The existing provider refuses entry into a different domain while the
  // parent arena is entered. Return only that scope, retaining its same loan.
  host
  .leave_borrow_scope(self.original, scope)
  .resident_initial_require("installed command parent scope leave pending")
  self.scope_entered = false
  host
  .prepare_backed_domain_growth(self.original, domain, self.original)
  .resident_initial_require("installed command working supplier refused")
  // Read construction is attempted once on the same retained domain. A failed
  // physical or accounting step keeps that carrier for child-first cleanup.
  host
  .prepare_backed_read_context(
    self.original,
    domain,
    self.original,
    execution_ceiling=self.read_payload_bytes,
  )
  .resident_initial_require("installed command read context refused")
}

///|
fn ResidentInitialControl::enter(
  self : ResidentInitialControl,
) -> Unit raise CommandStop {
  self.require_current()
  guard self.host is Some(host) && self.domain is Some(domain) else {
    stop("original command backing missing")
  }
  host
  .enter_backed_read_context(self.original, domain, self.original)
  .resident_initial_require("installed command read entry refused")
  self.read_entered = true
}

///|
/// Call only after all managed parser/command aliases unwind. A failure keeps
/// the exact outstanding stage; no process exit or logical close is an ACK.
fn ResidentInitialControl::close(self : ResidentInitialControl) -> Bool {
  if self.retired {
    return true
  }
  if self.sqlite is Some(_) ||
    self.failed_sqlite is Some(_) ||
    self.crypto is Some(_) ||
    self.crypto_component is Some(_) ||
    self.http_library is Some(_) ||
    self.failed_http_library is Some(_) ||
    self.http_client is Some(_) ||
    self.failed_http_client is Some(_) {
    return false
  }
  if self.host is Some(host) {
    if self.control_entered {
      guard self.scope is Some(scope) else { return false }
      if host.leave_backed_read_control(self.original, scope) is Err(_) {
        return false
      }
      self.control_entered = false
    }
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
  if retire_resident_entry_ffi(self.original) != 1 {
    return false
  }
  self.retired = true
  true
}

///|
fn[T, E] Result::resident_initial_require(
  self : Result[T, E],
  message : String,
) -> T raise CommandStop {
  match self {
    Ok(value) => value
    Err(_) => stop(message)
  }
}

///|
fn resident_read_payload_bytes(domain_bytes : Int64) -> Int64 raise CommandStop {
  if domain_bytes <= 0L || domain_bytes > 2147483647L {
    stop("installed managed extent unavailable")
  }
  let mut lower = 0L
  let mut upper = domain_bytes
  // The compiled private arena is Int-bounded. This finite search quotes the
  // SAME provider for its largest coexisting payload, including its tables.
  for index = 0; index < 31 && lower < upper; index = index + 1 {
    let candidate = lower + (upper - lower + 1L) / 2L
    let necessary = @bootstrap.execution_domain_necessary_bytes(
      domain_bytes, candidate,
    )
    if necessary > 0L && necessary <= domain_bytes {
      lower = candidate
    } else {
      upper = candidate - 1L
    }
  }
  let necessary = @bootstrap.execution_domain_necessary_bytes(
    domain_bytes, lower,
  )
  if lower <= 0L ||
    lower != upper ||
    necessary <= 0L ||
    necessary > domain_bytes {
    stop("installed managed layout unavailable")
  }
  lower
}

///|
fn ResidentInitialControl::close_libraries(
  self : ResidentInitialControl,
) -> Bool {
  self.libraries_retiring = true
  if self.failed_http_client is Some(original) {
    if original.retry_cleanup() is Err(_) {
      return false
    }
    self.failed_http_client = None
  }
  if self.http_client is Some(original) {
    if original.close_checked() is Err(_) {
      return false
    }
    self.http_client = None
  }
  if self.failed_http_library is Some(original) {
    if original.retry_cleanup() is Err(_) {
      return false
    }
    self.failed_http_library = None
  }
  if self.http_library is Some(original) {
    if original.close_checked() is Err(_) {
      return false
    }
    self.http_library = None
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
  // These original selections were parsed inside the SAME managed Read.
  // Keep them through every pending child/Library close, then drop their
  // aliases before asking that Read to retire. The retirement fence above
  // prevents an emptied selection from admitting another acquisition.
  self.http_path = None
  self.crypto_path = None
  self.sqlite_path = None
  true
}

///|
fn ResidentInitialControl::load_sqlite(
  self : ResidentInitialControl,
  path : String,
) -> Result[@sqlite.Library, String] {
  if self.retired ||
    self.libraries_retiring ||
    !self.read_entered ||
    resident_entry_current_ffi(self.original) != 1 {
    return Err("original installed command Read unavailable")
  }
  if self.sqlite_path is Some(original_path) {
    return if original_path == path && self.sqlite is Some(original) {
      Ok(original)
    } else {
      Err("original SQLite acquisition unavailable")
    }
  }
  // Retain the original selection before a fallible physical acquisition.
  // Refusal never authorizes a second load; same-path reuse returns only the
  // actual retained Library while the current command Read remains alive.
  self.sqlite_path = Some(path)
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
fn ResidentInitialControl::load_crypto(
  self : ResidentInitialControl,
  path : String,
) -> Result[@signature.Library, String] {
  if self.retired ||
    self.libraries_retiring ||
    !self.read_entered ||
    resident_entry_current_ffi(self.original) != 1 {
    return Err("original installed command Read unavailable")
  }
  if self.crypto_path is Some(original_path) {
    return if original_path == path && self.crypto is Some(original) {
      Ok(original)
    } else {
      Err("original Crypto acquisition unavailable")
    }
  }
  self.crypto_path = Some(path)
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

///|
/// Signal observation is only a wake for the SAME original cleanup pass.
/// This path may already be outside the Read, so use the existing allocation-
/// free native wait/park ports and C diagnostic, never managed report DATA.
fn wait_resident_initial_cleanup() -> Unit {
  while !@slot.install_native_termination_request() {
    resident_control_diagnostic_ffi(4)
    ignore(park_holder_cleanup_unconfirmed_ffi())
  }
  if wait_holder_cleanup_signal_ffi() != 0 {
    resident_control_diagnostic_ffi(4)
    ignore(park_holder_cleanup_unconfirmed_ffi())
  }
}

///|
fn ResidentInitialControl::load_http(
  self : ResidentInitialControl,
  path : String,
) -> Result[@http.Library, String] {
  if self.retired ||
    self.libraries_retiring ||
    !self.read_entered ||
    resident_entry_current_ffi(self.original) != 1 {
    return Err("original installed command Read unavailable")
  }
  if self.http_path is Some(original_path) {
    return if original_path == path && self.http_library is Some(original) {
      Ok(original)
    } else {
      Err("original HTTP Library acquisition unavailable")
    }
  }
  self.http_path = Some(path)
  match
    @http.load_library_with_custody(
      path,
      diagnostic_ceiling=Some(self.diagnostic_bytes),
    ) {
    Ok(original) => {
      self.http_library = Some(original)
      Ok(original)
    }
    Err(RefusedBeforeAcquisition(_)) => Err("HTTP Library acquisition refused")
    Err(CleanupRequired(original)) => {
      self.failed_http_library = Some(original)
      Err("HTTP Library acquisition cleanup pending")
    }
  }
}
