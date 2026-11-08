///|
priv enum LocalStoreOperationOrigin {
  StoreFromIdle
  StoreFromRead
  StoreFromBusiness
}

///|
priv enum LocalStoreOperationPhase {
  StoreRouteIdle
  StoreRouteRead
  StoreRouteSqlite
  StoreRoutePending
} derive(Eq)

///|
// The observation route owns only the existing Host Read/SQLite pair. It has
// no retained execution to suspend or resume, and cannot enter business work.
priv enum LocalStoreOperationDomain {
  StoreBusinessDomain(@arena.InstalledArenaRetainedExecution)
  StoreRunObservationDomain
}

///|
pub(all) enum NativeLocalStoreOperationIssue {
  StoreOperationUnavailable
  StoreOperationForeignOriginal
  StoreOperationCapture(NativeLocalAdoptionIssue)
  StoreOperationResources(@arena.InstalledArenaLocalHostResourcesIssue)
  StoreOperationExecution(@arena.InstalledArenaRetainedExecutionIssue)
  StoreOperationSqlite(@sqlite.NativeSqliteIssue)
}

///|
// Original routing custody, never a callback/permission factory. The fixed
// bridge retains this receiver; it does not retain the bridge in return.
priv struct NativeLocalStoreOperationReceiver {
  capture : NativeLocalJournalCapture
  domain : LocalStoreOperationDomain
  runtime : NativeLocalPackagedRuntime
  library : @sqlite.Library
  mut original : NativeLocalJournalOriginalResources?
  mut ready : Bool
  mut closing : Bool
  mut closed : Bool
  mut cleanup : Bool
  mut origin : LocalStoreOperationOrigin?
  mut phase : LocalStoreOperationPhase
  mut business_pending : Bool
  mut borrowed_read : Bool
  mut return_acknowledged : Bool
  mut primary : NativeLocalStoreOperationIssue?
  mut cleanup_issue : NativeLocalStoreOperationIssue?
}

///|
// Keep both records before activation. Explicit metadata retirement follows
// the actual Store/Database and outstanding scope acknowledgements.
struct NativeLocalStoreOperation {
  receiver : NativeLocalStoreOperationReceiver
  mut bridge : @sqlite.NativeStoreOperationOriginal?
}

///|
#borrow(library, receiver)
extern "C" fn prepare_store_operation_ffi(
  library : @sqlite.Library,
  receiver : NativeLocalStoreOperationReceiver,
  route : FuncRef[
    (NativeLocalStoreOperationReceiver, @sqlite.Library, Int) -> Int,
  ],
  construction : FuncRef[
    (NativeLocalStoreOperationReceiver, @sqlite.Library, Int) -> Int,
  ],
) -> @sqlite.NativeStoreOperationOriginal = "actql_native_sqlite_prepare_store_operation_with_delivery_construction"

///|
extern "C" fn store_operation_control_clear_ffi() -> Int = "actql_bootstrap_control_scope_clear"

///|
/// Construct routing custody only in the original outer control scope. The
/// receiver and bridge outlive individual Read/business entries, so neither
/// may be allocated in one of those child scopes. Activation separately checks
/// the existing actual Host/pair/Library/business/runtime originals.
pub fn prepare_native_local_store_operation(
  capture : NativeLocalJournalCapture,
  execution : @arena.InstalledArenaRetainedExecution,
  runtime : NativeLocalPackagedRuntime,
  library : @sqlite.Library,
) -> Result[NativeLocalStoreOperation, NativeLocalStoreOperationIssue] {
  prepare_native_local_store_operation_for_domain(
    capture,
    StoreBusinessDomain(execution),
    runtime,
    library,
  )
}

///|
/// Retain routing for original saved-Run metadata observation. Activation still
/// requires the same actual Host/pair, SQLite Library and runtime. This does
/// not create a Run, payload reader, grant, retained execution or new domain.
pub fn prepare_native_local_run_observation_store_operation(
  capture : NativeLocalJournalCapture,
  runtime : NativeLocalPackagedRuntime,
  library : @sqlite.Library,
) -> Result[NativeLocalStoreOperation, NativeLocalStoreOperationIssue] {
  prepare_native_local_store_operation_for_domain(
    capture,
    StoreRunObservationDomain,
    runtime,
    library,
  )
}

///|
fn prepare_native_local_store_operation_for_domain(
  capture : NativeLocalJournalCapture,
  domain : LocalStoreOperationDomain,
  runtime : NativeLocalPackagedRuntime,
  library : @sqlite.Library,
) -> Result[NativeLocalStoreOperation, NativeLocalStoreOperationIssue] {
  if store_operation_control_clear_ffi() != 1 {
    return Err(StoreOperationUnavailable)
  }
  let receiver = {
    capture,
    domain,
    runtime,
    library,
    original: None,
    ready: false,
    closing: false,
    closed: false,
    cleanup: false,
    origin: None,
    phase: StoreRouteIdle,
    business_pending: false,
    borrowed_read: false,
    return_acknowledged: false,
    primary: None,
    cleanup_issue: None,
  }
  let bridge = prepare_store_operation_ffi(
    library,
    receiver,
    fn(original, library, tag) { original.route(library, tag) },
    fn(original, library, target) {
      original.prepare_delivery_window(library, target)
    },
  )
  Ok({ receiver, bridge: Some(bridge), })
}

///|
/// Exact Buffer(size_hint=target) backing and its to_bytes copy coexist.
/// The original Read's row/input basis is unchanged and remains additive.
/// The selected ABI supplies contiguous requests independently of the tariff.
pub fn native_local_result_delivery_window_construction(
  target : Int,
) -> (Int64, Int64, Int64)? {
  if target < 1 || target > 16777216 {
    return None
  }
  guard @execution.preparation_representation_cost({
      // Buffer1H1R1W, its exact Byte array1H and returned Bytes1H.
      record_headers: 3L,
      reference_slots: 1L,
      scalar_words: 1L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 2L * target.to_int64(),
    })
    is Some(bytes) else {
    return None
  }
  let (header, _, _, _, pointer) = @bootstrap.native_managed_value_layout()
  if header <= 0L || pointer <= 0L {
    return None
  }
  Some(
    (
      bytes,
      bytes,
      Int64::max(header + target.to_int64() + 1L, header + pointer + 8L),
    ),
  )
}

///|
fn NativeLocalStoreOperationReceiver::prepare_delivery_window(
  self : NativeLocalStoreOperationReceiver,
  library : @sqlite.Library,
  target : Int,
) -> Int {
  let (_, original) = match self.originals(library, false) {
    Ok(value) => value
    Err(issue) => return self.refuse(issue)
  }
  guard self.ready &&
    !self.cleanup &&
    self.primary is None &&
    self.phase == StoreRouteRead &&
    self.origin is Some(_) &&
    original.active_phase is Some(@arena.HostRead) &&
    original.store_operation is Some(active) &&
    physical_equal(active, self) &&
    native_local_result_delivery_window_construction(target)
    is Some((retained, execution, contiguous)) else {
    return self.refuse(StoreOperationUnavailable)
  }
  match
    original.host.prepare_domain_original_read_construction(
      original.read,
      retained,
      execution,
      contiguous,
    ) {
    Err(issue) => self.refuse(StoreOperationResources(@arena.Read(issue)))
    Ok(_) =>
      if self.closing ||
        self.capture.closing ||
        original.interrupted ||
        !(original.active_phase is Some(@arena.HostRead)) ||
        !(original.store_operation is Some(active) &&
        physical_equal(active, self)) {
        self.refuse(StoreOperationUnavailable)
      } else {
        0
      }
  }
}

///|
fn NativeLocalStoreOperationReceiver::refuse(
  self : NativeLocalStoreOperationReceiver,
  issue : NativeLocalStoreOperationIssue,
) -> Int {
  if self.primary is None {
    self.primary = Some(issue)
  } else if self.cleanup_issue is None {
    self.cleanup_issue = Some(issue)
  }
  self.ready = false
  -1
}

///|
fn NativeLocalStoreOperationReceiver::originals(
  self : NativeLocalStoreOperationReceiver,
  library : @sqlite.Library,
  cleanup : Bool,
) -> Result[
  (NativeLocalHostConnection, NativeLocalJournalOriginalResources),
  NativeLocalStoreOperationIssue,
] {
  if self.closed || !physical_equal(self.library, library) {
    return Err(StoreOperationForeignOriginal)
  }
  guard self.capture.opening is JournalAcquired(host) &&
    self.capture.original_resources is Some(original) else {
    return Err(StoreOperationUnavailable)
  }
  if original.store_operation is Some(active) && !physical_equal(active, self) {
    return Err(StoreOperationForeignOriginal)
  }
  if self.original is Some(retained) && !physical_equal(retained, original) {
    return Err(StoreOperationForeignOriginal)
  }
  if cleanup {
    guard self.original is Some(_) else {
      return Err(StoreOperationUnavailable)
    }
    return Ok((host, original))
  }
  if self.closing ||
    self.capture.closing ||
    host.closed ||
    self.capture.read_operation_issue is Some(_) ||
    original.interrupted {
    return Err(StoreOperationUnavailable)
  }
  guard host.packaged_runtime is Some(binding) &&
    physical_equal(binding.current, self.runtime) else {
    return Err(StoreOperationForeignOriginal)
  }
  match original.host.borrow_local_host_sqlite(original.pair) {
    Err(issue) => return Err(StoreOperationResources(issue))
    Ok(current) if !physical_equal(current, library) =>
      return Err(StoreOperationForeignOriginal)
    Ok(_) => ()
  }
  match self.domain {
    StoreBusinessDomain(execution) =>
      match original.host.require_domain_retained_execution_current(execution) {
        Err(issue) => Err(StoreOperationExecution(issue))
        Ok(_) => Ok((host, original))
      }
    StoreRunObservationDomain => Ok((host, original))
  }
}

///|
fn NativeLocalStoreOperationReceiver::leave_phase(
  self : NativeLocalStoreOperationReceiver,
  original : NativeLocalJournalOriginalResources,
) -> Result[Unit, NativeLocalStoreOperationIssue] {
  match original.host.leave_local_host_phase(original.pair) {
    Err(issue) => {
      original.interrupted = true
      self.phase = StoreRoutePending
      Err(StoreOperationResources(issue))
    }
    Ok(_) => {
      original.active_phase = None
      Ok(())
    }
  }
}

///|
fn NativeLocalStoreOperationReceiver::enter_phase(
  self : NativeLocalStoreOperationReceiver,
  original : NativeLocalJournalOriginalResources,
  phase : @arena.InstalledArenaLocalHostPhase,
) -> Result[Unit, NativeLocalStoreOperationIssue] {
  let entered = if self.cleanup {
    original.host.enter_local_host_cleanup(original.pair, phase)
  } else {
    original.host.enter_local_host_phase(original.pair, phase)
  }
  match entered {
    Err(issue) => {
      original.interrupted = true
      self.phase = StoreRoutePending
      Err(StoreOperationResources(issue))
    }
    Ok(_) => {
      original.active_phase = Some(phase)
      self.phase = match phase {
        @arena.HostRead => StoreRouteRead
        @arena.HostSqlite => StoreRouteSqlite
      }
      Ok(())
    }
  }
}

///|
fn NativeLocalStoreOperationReceiver::activate_original(
  self : NativeLocalStoreOperationReceiver,
  library : @sqlite.Library,
) -> Result[Unit, NativeLocalStoreOperationIssue] {
  if self.ready || self.origin is Some(_) || self.phase != StoreRouteIdle {
    return Err(StoreOperationUnavailable)
  }
  let (_host, original) = match self.originals(library, false) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let read = match
    original.host.observe_local_host_consuming_read_scope(
      original.pair,
      original.read,
    ) {
    Ok(value) => value
    Err(issue) => return Err(StoreOperationResources(issue))
  }
  if self.domain is StoreBusinessDomain(execution) {
    let business = match
      original.host.observe_domain_retained_execution_scope(execution) {
      Ok(value) => value
      Err(issue) => return Err(StoreOperationExecution(issue))
    }
    if business != @bootstrap.BackedReadUnentered {
      return Err(StoreOperationUnavailable)
    }
  }
  let current = match read {
    @arena.ReadEntered => self.capture.check_current_in_original_read()
    @arena.ReadUnentered => {
      if original.active_phase is Some(_) ||
        store_operation_control_clear_ffi() != 1 {
        return Err(StoreOperationUnavailable)
      }
      self.capture.check_current_between_original_phases()
    }
  }
  match current {
    Err(issue) => Err(StoreOperationCapture(issue))
    Ok(_) => {
      self.original = Some(original)
      self.ready = true
      Ok(())
    }
  }
}

///|
fn NativeLocalStoreOperationReceiver::begin_original(
  self : NativeLocalStoreOperationReceiver,
  library : @sqlite.Library,
) -> Result[Unit, NativeLocalStoreOperationIssue] {
  self.return_acknowledged = false
  if !self.ready ||
    self.primary is Some(_) ||
    self.origin is Some(_) ||
    self.phase != StoreRouteIdle {
    return Err(StoreOperationUnavailable)
  }
  let (_host, original) = match self.originals(library, false) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let read = match
    original.host.observe_local_host_consuming_read_scope(
      original.pair,
      original.read,
    ) {
    Ok(value) => value
    Err(issue) => return Err(StoreOperationResources(issue))
  }
  let business = match self.domain {
    StoreBusinessDomain(execution) =>
      match original.host.observe_domain_retained_execution_scope(execution) {
        Ok(value) => Some(value)
        Err(issue) => return Err(StoreOperationExecution(issue))
      }
    StoreRunObservationDomain => None
  }
  if original.store_operation is Some(_) {
    return Err(StoreOperationUnavailable)
  }
  match (read, business) {
    (@arena.ReadEntered, None | Some(@bootstrap.BackedReadUnentered)) => {
      if !(original.active_phase is Some(@arena.HostRead)) {
        return Err(StoreOperationUnavailable)
      }
      original.store_operation = Some(self)
      self.origin = Some(StoreFromRead)
      self.phase = StoreRouteRead
      self.capture
      .check_current_in_original_read()
      .map_err(issue => StoreOperationCapture(issue))
    }
    (@arena.ReadUnentered, _) => {
      if original.active_phase is Some(_) {
        return Err(StoreOperationUnavailable)
      }
      original.store_operation = Some(self)
      if business is Some(@bootstrap.BackedReadEntered) {
        guard self.domain is StoreBusinessDomain(execution) else {
          return Err(StoreOperationUnavailable)
        }
        self.origin = Some(StoreFromBusiness)
        self.business_pending = true
        match original.host.leave_domain_retained_execution(execution) {
          Err(issue) => return Err(StoreOperationExecution(issue))
          Ok(_) => self.business_pending = false
        }
      } else {
        self.origin = Some(StoreFromIdle)
      }
      if store_operation_control_clear_ffi() != 1 {
        return Err(StoreOperationUnavailable)
      }
      match self.capture.check_current_between_original_phases() {
        Err(issue) => return Err(StoreOperationCapture(issue))
        Ok(_) => ()
      }
      self.enter_phase(original, @arena.HostRead)
    }
    _ => Err(StoreOperationUnavailable)
  }
}

///|
fn NativeLocalStoreOperationReceiver::begin_cleanup(
  self : NativeLocalStoreOperationReceiver,
  library : @sqlite.Library,
) -> Result[Unit, NativeLocalStoreOperationIssue] {
  self.return_acknowledged = false
  // A borrowed parent callback must return before its Read can be retired.
  // Only that same pending owner may acknowledge an interrupted leave.
  if self.capture.read_callback_active {
    return Err(StoreOperationUnavailable)
  }
  let (_, original) = match self.originals(library, true) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  original.store_operation = Some(self)
  self.closing = true
  self.ready = false
  match self.domain {
    StoreBusinessDomain(execution) => {
      let business_scope = match
        original.host.observe_domain_retained_execution_scope(execution) {
        Ok(scope) => Ok(scope)
        Err(_) =>
          original.host.observe_domain_retained_execution_cleanup_scope(
            execution,
          )
      }
      match business_scope {
        Ok(@bootstrap.BackedReadUnentered) => self.business_pending = false
        Ok(@bootstrap.BackedReadEntered) | Err(_) =>
          // A successful prior resume can leave the real business frame entered
          // after its attempted-switch latch cleared. Observe that same frame;
          // neither the latch nor a failed observation proves it was left.
          match original.host.leave_domain_retained_execution(execution) {
            Err(issue) =>
              // A failed original C entry can retain only its nominal attempt. The
              // existing cleanup port verifies this SAME context/lease had no C
              // entry, unwinds its saved preparation scope, and never revives use.
              match
                original.host.finish_domain_retained_execution_failed_entry_cleanup(
                  execution,
                ) {
                Err(cleanup) => {
                  self.refuse(StoreOperationExecution(issue)) |> ignore
                  self.refuse(StoreOperationExecution(cleanup)) |> ignore
                  return Err(self.primary.unwrap_or(StoreOperationUnavailable))
                }
                Ok(_) => self.business_pending = false
              }
            Ok(_) => self.business_pending = false
          }
      }
    }
    StoreRunObservationDomain =>
      if self.business_pending || self.origin is Some(StoreFromBusiness) {
        return Err(StoreOperationUnavailable)
      }
  }
  match original.finish_pending_store_leave(self) {
    Err(issue) => return Err(StoreOperationCapture(issue))
    Ok(_) => ()
  }
  if store_operation_control_clear_ffi() != 1 {
    return Err(StoreOperationUnavailable)
  }
  self.cleanup = true
  self.origin = Some(StoreFromIdle)
  self.enter_phase(original, @arena.HostRead)
}

///|
fn NativeLocalStoreOperationReceiver::route(
  self : NativeLocalStoreOperationReceiver,
  library : @sqlite.Library,
  tag : Int,
) -> Int {
  // C still requires this exact outstanding flight before invoking tag3.
  // A cached actual return ACK cannot start another operation; every new
  // begin invalidates it before its first attempted acquisition.
  if tag == 3 &&
    self.return_acknowledged &&
    self.phase == StoreRouteIdle &&
    self.origin is None &&
    !self.business_pending &&
    !self.borrowed_read {
    return match self.originals(library, true) {
      Ok(_) => 0
      Err(issue) => self.refuse(issue)
    }
  }
  let result = match tag {
    -1 => self.activate_original(library)
    0 => self.begin_original(library)
    4 => self.begin_cleanup(library)
    1 | 2 | 3 => {
      let originals = self.originals(library, self.cleanup)
      match originals {
        Err(issue) => Err(issue)
        Ok((_host, original)) =>
          if !(original.store_operation is Some(active) &&
            physical_equal(active, self)) {
            Err(StoreOperationUnavailable)
          } else if !self.cleanup && (!self.ready || self.primary is Some(_)) {
            Err(StoreOperationUnavailable)
          } else if tag == 1 && self.phase == StoreRouteRead {
            match self.leave_phase(original) {
              Err(issue) => Err(issue)
              Ok(_) => self.enter_phase(original, @arena.HostSqlite)
            }
          } else if tag == 2 && self.phase == StoreRouteSqlite {
            match self.leave_phase(original) {
              Err(issue) => Err(issue)
              Ok(_) => self.enter_phase(original, @arena.HostRead)
            }
          } else if tag == 3 &&
            self.cleanup &&
            self.phase == StoreRoutePending &&
            self.origin is Some(_) {
            // Retry only the same failed original return, never a SQL body.
            match original.finish_pending_store_leave(self) {
              Err(issue) => Err(StoreOperationCapture(issue))
              Ok(_) => {
                self.acknowledge_return(original)
                Ok(())
              }
            }
          } else if tag == 3 &&
            self.phase == StoreRouteRead &&
            self.origin is Some(origin) {
            let current = if self.cleanup {
              Ok(())
            } else {
              self.capture
              .check_current_in_original_read()
              .map_err(issue => StoreOperationCapture(issue))
            }
            match current {
              Err(issue) => Err(issue)
              Ok(_) => {
                let left = if !self.cleanup && origin is StoreFromRead {
                  Ok(())
                } else {
                  self.leave_phase(original)
                }
                match left {
                  Err(issue) => Err(issue)
                  Ok(_) => {
                    let resumed = if !self.cleanup &&
                      origin is StoreFromBusiness {
                      match
                        self.capture.check_current_between_original_phases() {
                        Err(issue) => Err(StoreOperationCapture(issue))
                        Ok(_) =>
                          match self.domain {
                            StoreRunObservationDomain =>
                              Err(StoreOperationUnavailable)
                            StoreBusinessDomain(execution) => {
                              self.business_pending = true
                              original.host
                              .enter_domain_retained_execution(execution)
                              .map_err(issue => StoreOperationExecution(issue))
                            }
                          }
                      }
                    } else {
                      Ok(())
                    }
                    match resumed {
                      Err(issue) => Err(issue)
                      Ok(_) => {
                        // Actual original restoration/leave acknowledged. Only
                        // now release this flight and its retained cycle.
                        self.acknowledge_return(original)
                        Ok(())
                      }
                    }
                  }
                }
              }
            }
          } else {
            Err(StoreOperationUnavailable)
          }
      }
    }
    _ => Err(StoreOperationUnavailable)
  }
  match result {
    Ok(_) => 0
    Err(issue) => self.refuse(issue)
  }
}

///|
fn NativeLocalStoreOperationReceiver::acknowledge_return(
  self : NativeLocalStoreOperationReceiver,
  original : NativeLocalJournalOriginalResources,
) -> Unit {
  original.store_operation = None
  self.business_pending = false
  if self.cleanup {
    self.borrowed_read = false
  }
  self.origin = None
  self.phase = StoreRouteIdle
  self.cleanup = false
  self.return_acknowledged = true
}

///|
/// Finish only this receiver's recorded scope duty after its borrowed parent
/// callback returns. No Store/DB/Library close or SQL replay is performed here.
pub fn NativeLocalStoreOperation::retry_scope_cleanup(
  self : NativeLocalStoreOperation,
) -> Result[Unit, NativeLocalStoreOperationIssue] {
  if self.receiver.capture.read_callback_active {
    return Err(StoreOperationUnavailable)
  }
  guard self.bridge is Some(bridge) else {
    return Err(StoreOperationUnavailable)
  }
  match self.pending_scope() {
    Ok(false) => return Ok(())
    Err(issue) => return Err(issue)
    Ok(true) => ()
  }
  // First retry the SAME outstanding return. In particular a cleanup flight
  // can have entered successfully and lost only its tag3 return: another
  // cleanup entry must not bypass or duplicate that flight. No-flight leave
  // refuses in C before a callback, and never acknowledges a borrowed parent.
  if bridge.leave_store() is Ok(_) {
    match self.pending_scope() {
      Ok(false) => return Ok(())
      Err(issue) => return Err(issue)
      // A completed Store flight can still owe return of its borrowed parent
      // business frame. Keep that distinct duty until cleanup's actual ACK.
      Ok(true) => ()
    }
  }
  match bridge.enter_cleanup() {
    Err(issue) => return Err(StoreOperationSqlite(issue))
    Ok(_) => ()
  }
  match bridge.leave_store() {
    Err(issue) => return Err(StoreOperationSqlite(issue))
    Ok(_) => ()
  }
  match self.pending_scope() {
    Ok(false) => Ok(())
    Ok(true) => Err(StoreOperationUnavailable)
    Err(issue) => Err(issue)
  }
}

///|
pub fn NativeLocalStoreOperation::activate(
  self : NativeLocalStoreOperation,
) -> Result[Unit, NativeLocalStoreOperationIssue] {
  guard self.bridge is Some(bridge) else {
    return Err(StoreOperationUnavailable)
  }
  match bridge.activate() {
    Ok(_) => Ok(())
    Err(issue) => {
      let retained = self.receiver.primary.unwrap_or(
        StoreOperationSqlite(issue),
      )
      self.receiver.refuse(retained) |> ignore
      Err(retained)
    }
  }
}

///|
/// Borrow only the activated original; SQLite still binds its exact Database.
pub fn NativeLocalStoreOperation::sqlite_original(
  self : NativeLocalStoreOperation,
) -> Result[
  @sqlite.NativeStoreOperationOriginal,
  NativeLocalStoreOperationIssue,
] {
  if !self.receiver.ready || self.receiver.closing || self.receiver.closed {
    return Err(self.receiver.primary.unwrap_or(StoreOperationUnavailable))
  }
  match self.bridge {
    None => Err(StoreOperationUnavailable)
    Some(bridge) => Ok(bridge)
  }
}

///|
/// Observe this same routing original's outstanding scope duty. An idle result
/// does not acknowledge Store, Database, Library, domain or Host retirement.
pub fn NativeLocalStoreOperation::pending_scope(
  self : NativeLocalStoreOperation,
) -> Result[Bool, NativeLocalStoreOperationIssue] {
  guard self.bridge is Some(bridge) && !self.receiver.closed else {
    return Err(StoreOperationUnavailable)
  }
  let pending = match bridge.pending_scope() {
    Ok(value) => value
    Err(issue) => return Err(StoreOperationSqlite(issue))
  }
  let receiver = self.receiver
  let retained = match receiver.original {
    Some(original) =>
      original.store_operation is Some(active) &&
      physical_equal(active, receiver)
    None => false
  }
  Ok(
    pending ||
    retained ||
    receiver.borrowed_read ||
    receiver.business_pending ||
    receiver.origin is Some(_) ||
    receiver.phase != StoreRouteIdle,
  )
}

///|
/// Only routing metadata. This does not close the Store or acknowledge its DB,
/// Library, Read, retained output, domain, Host or descriptor retirement.
pub fn NativeLocalStoreOperation::close_checked(
  self : NativeLocalStoreOperation,
) -> Result[Unit, NativeLocalStoreOperationIssue] {
  match self.bridge {
    None => Ok(())
    Some(bridge) => {
      match self.pending_scope() {
        Err(issue) => return Err(issue)
        Ok(true) => return Err(StoreOperationUnavailable)
        Ok(false) => ()
      }
      match bridge.close_checked() {
        Err(issue) => return Err(StoreOperationSqlite(issue))
        Ok(_) => ()
      }
      self.bridge = None
      self.receiver.closed = true
      self.receiver.ready = false
      Ok(())
    }
  }
}
