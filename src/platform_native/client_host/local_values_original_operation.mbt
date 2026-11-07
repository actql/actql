///|
// Fixed Native Work routing, never a public callback/Allow factory. Its result
// records retain their actual Read-domain aliases until Work/caller retirement;
// a scope exchange does not free those aliases or acknowledge their domains.
priv enum NativeLocalWorkSourceOriginal {
  SourceFree
  RelationFile(
    @rows.RowDeclaration,
    @planning.QueryRequirement,
    @rows.RowAcquisition
  )
}

///|
priv struct NativeLocalValuesOriginalAccess {
  operation : NativeLocalStoreOperation
  host : NativeLocalHostConnection
  principal : String
  connection : String
  request : @host.ClientRequestIdentity
  mut primary : NativeClientValuesWorkIssue?
}

///|
fn values_original_issue(
  access : NativeLocalValuesOriginalAccess?,
  fallback : NativeClientValuesWorkIssue,
) -> NativeClientValuesWorkIssue {
  match access {
    Some(original) => original.primary.unwrap_or(fallback)
    None => fallback
  }
}

///|
fn NativeLocalValuesOriginalAccess::retain(
  self : NativeLocalValuesOriginalAccess,
  issue : NativeClientValuesWorkIssue,
) -> NativeClientValuesWorkIssue {
  if self.primary is None {
    self.primary = Some(issue)
  }
  self.primary.unwrap()
}

///|
fn NativeLocalValuesOriginalAccess::routing_issue(
  self : NativeLocalValuesOriginalAccess,
  issue : @sqlite.NativeSqliteIssue,
) -> NativeLocalStoreOperationIssue {
  let receiver = self.operation.receiver
  let original = receiver.primary.unwrap_or(StoreOperationSqlite(issue))
  receiver.refuse(original) |> ignore
  original
}

///|
// Only these closed Work operations call this helper. The C flight excludes
// reentry; current predicates inside this operation use the direct same-Read
// material below instead of attempting another flight or borrowing Allow.
fn[T] NativeLocalValuesOriginalAccess::in_original_read(
  self : NativeLocalValuesOriginalAccess,
  call : (NativeClientJournalOperationAccess, () -> Bool) -> Result[
    T,
    NativeClientValuesWorkIssue,
  ],
  source? : NativeLocalWorkSourceOriginal = SourceFree,
) -> Result[T, NativeClientValuesWorkIssue] {
  guard self.operation.receiver.domain is StoreBusinessDomain(execution) else {
    return Err(self.retain(OriginalOperation(None, StoreOperationUnavailable)))
  }
  guard self.operation.bridge is Some(bridge) &&
    self.operation.receiver.ready &&
    !self.operation.receiver.closed &&
    !self.operation.receiver.closing else {
    return Err(self.retain(OriginalOperation(None, StoreOperationUnavailable)))
  }
  let (_, original) = match
    self.operation.receiver.originals(self.operation.receiver.library, false) {
    Ok(value) => value
    Err(issue) => return Err(self.retain(OriginalOperation(None, issue)))
  }
  // Publication predicates can run inside this same Store's Read flight or
  // the original Journal fence. Borrow only that actual entered Read. They
  // neither open a second flight nor acknowledge the caller's return.
  let borrowed = if original.host.observe_local_host_consuming_read_scope(
      original.pair,
      original.read,
    )
    is Ok(@arena.ReadEntered) {
    let same_flight = match original.store_operation {
      Some(active) =>
        physical_equal(active, self.operation.receiver) &&
        self.operation.receiver.phase == StoreRouteRead &&
        bridge.pending_scope() is Ok(true)
      None =>
        self.operation.receiver.phase == StoreRouteIdle &&
        bridge.pending_scope() is Ok(false)
    }
    if !same_flight ||
      !(original.active_phase is Some(@arena.HostRead)) ||
      !(original.host.observe_domain_retained_execution_scope(execution)
      is Ok(@bootstrap.BackedReadUnentered)) {
      return Err(
        self.retain(OriginalOperation(None, StoreOperationUnavailable)),
      )
    }
    true
  } else {
    false
  }
  if !borrowed {
    match bridge.enter_store() {
      Err(issue) =>
        return Err(
          self.retain(OriginalOperation(None, self.routing_issue(issue))),
        )
      Ok(_) => ()
    }
  }
  // Publish the actual Work result before a later original Read/current/leave
  // can fail. A committed claim remains one-shot even if that return is lost.
  let output : Ref[Result[T, NativeClientValuesWorkIssue]?] = Ref(None)
  let captured = self.operation.receiver.capture
  let current = match source {
    SourceFree =>
      captured.with_current_adoption_material_in_original_read((
        host,
        material,
        operations,
      ) => {
        if !physical_equal(host, self.host) {
          return Err(CustodyLost)
        }
        let scope = @host.client_request_authority_scope_cid(self.request)
        let direct_current = () => {
          captured.original_submit_allowed(
            host,
            material,
            self.principal,
            self.connection,
            scope,
          )
          is Ok(true)
        }

        // Every closed caller below invokes this actual current port before its
        // first Journal read or write. Start/claim retain their later checks after
        // durable boundaries. Do not add an entry check immediately before that
        // same observation, or retain an Allow between calls or SQL operations.
        let result : Result[T, NativeClientValuesWorkIssue] = match
          call(operations, direct_current) {
          Err(Journal(AuthorizationDenied) | Start(AuthorizationDenied)) =>
            Err(AuthorizationDenied)
          result => result
        }
        output.val = Some(result)
        // Preserve the existing combined Read/COMMIT-Unknown return rule, rather
        // than hiding a committed/lost reply inside an otherwise successful value.
        match result {
          Err(Journal(TransactionUnknown) | Start(Journal(TransactionUnknown))) =>
            Err(Journal(TransactionUnknown))
          _ => Ok(())
        }
      })
    RelationFile(_, _, _) =>
      captured.with_current_adoption_material_in_original_read((
        host,
        material,
        operations,
      ) => {
        if !physical_equal(host, self.host) {
          return Err(CustodyLost)
        }
        let scope = @host.client_request_authority_scope_cid(self.request)
        let direct_current = () => {
          captured.original_submit_allowed(
            host,
            material,
            self.principal,
            self.connection,
            scope,
          )
          is Ok(true) &&
          self.source_allowed_in_original_read(source, captured, host, material)
        }

        // Every closed caller below invokes this actual current port before its
        // first Journal read or write. Start/claim retain their later checks after
        // durable boundaries. Do not add an entry check immediately before that
        // same observation, or retain an Allow between calls or SQL operations.
        let result : Result[T, NativeClientValuesWorkIssue] = match
          call(operations, direct_current) {
          Err(Journal(AuthorizationDenied) | Start(AuthorizationDenied)) =>
            Err(AuthorizationDenied)
          result => result
        }
        output.val = Some(result)
        // Preserve the existing combined Read/COMMIT-Unknown return rule, rather
        // than hiding a committed/lost reply inside an otherwise successful value.
        match result {
          Err(Journal(TransactionUnknown) | Start(Journal(TransactionUnknown))) =>
            Err(Journal(TransactionUnknown))
          _ => Ok(())
        }
      })
  }
  let body : Result[T, NativeClientValuesWorkIssue] = match
    (current, output.val) {
    (Err(issue), value) =>
      Err(
        OriginalOperation(
          match value {
            Some(Err(primary)) => Some(primary)
            _ => None
          },
          StoreOperationCapture(issue),
        ),
      )
    (Ok(_), Some(value)) => value
    (Ok(_), None) => Err(OriginalOperation(None, StoreOperationUnavailable))
  }
  let after = if borrowed { Ok(()) } else { bridge.leave_store() }
  let result = match after {
    Ok(_) => body
    Err(issue) =>
      Err(
        OriginalOperation(
          match body {
            Err(primary) => Some(primary)
            Ok(_) => None
          },
          self.routing_issue(issue),
        ),
      )
  }
  match result {
    Err(issue) => Err(self.retain(issue))
    Ok(value) => Ok(value)
  }
}

///|
// Poll only the same already-claimed synchronous Compute occurrence. Full
// Account/Run checks remain at the surrounding dispatch and callback-return
// boundaries. No SQL, configuration validation, entry, leave or ACK occurs.
fn NativeLocalValuesOriginalAccess::poll_execution_original(
  self : NativeLocalValuesOriginalAccess,
  start : NativeClientWorkFirstStart,
) -> Bool {
  if self.primary is Some(_) {
    return false
  }
  if !physical_equal(start.journal, self.host.journal) ||
    @host.client_request_identity_relation(start.request, self.request) !=
    @host.SameRequest {
    self.retain(Journal(ForeignRun)) |> ignore
    return false
  }
  if self.host.journal.fenced ||
    self.host.closed ||
    self.host.database_closed ||
    self.host.session_closed ||
    self.operation.receiver.primary is Some(_) ||
    !self.operation.receiver.ready ||
    self.operation.receiver.closing ||
    self.operation.receiver.closed {
    self.retain(AuthorizationDenied) |> ignore
    return false
  }
  let receiver = self.operation.receiver
  guard receiver.domain is StoreBusinessDomain(execution) &&
    self.operation.bridge is Some(bridge) else {
    self.retain(OriginalOperation(None, StoreOperationUnavailable)) |> ignore
    return false
  }
  let (host, original) = match receiver.originals(receiver.library, false) {
    Ok(value) => value
    Err(issue) => {
      self.retain(OriginalOperation(None, issue)) |> ignore
      return false
    }
  }
  if !physical_equal(host, self.host) ||
    original.active_phase is Some(_) ||
    original.store_operation is Some(_) ||
    receiver.phase != StoreRouteIdle {
    self.retain(OriginalOperation(None, StoreOperationForeignOriginal))
    |> ignore
    return false
  }
  match bridge.pending_scope() {
    Ok(false) => ()
    Ok(true) => {
      self.retain(OriginalOperation(None, StoreOperationUnavailable)) |> ignore
      return false
    }
    Err(issue) => {
      self.retain(OriginalOperation(None, self.routing_issue(issue))) |> ignore
      return false
    }
  }
  match
    original.host.observe_local_host_consuming_read_scope(
      original.pair,
      original.read,
    ) {
    Ok(@arena.ReadUnentered) => ()
    Ok(_) => {
      self.retain(OriginalOperation(None, StoreOperationUnavailable)) |> ignore
      return false
    }
    Err(issue) => {
      self.retain(OriginalOperation(None, StoreOperationResources(issue)))
      |> ignore
      return false
    }
  }
  match original.host.observe_domain_retained_execution_scope(execution) {
    Ok(@bootstrap.BackedReadEntered) => true
    Ok(_) => {
      self.retain(OriginalOperation(None, StoreOperationUnavailable)) |> ignore
      false
    }
    Err(issue) => {
      self.retain(OriginalOperation(None, StoreOperationExecution(issue)))
      |> ignore
      false
    }
  }
}

///|
fn NativeLocalValuesOriginalAccess::current(
  self : NativeLocalValuesOriginalAccess,
) -> Bool {
  self.in_original_read((_operations, current) => {
    if current() {
      Ok(())
    } else {
      Err(AuthorizationDenied)
    }
  })
  is Ok(_)
}

///|
fn NativeLocalValuesOriginalAccess::lookup(
  self : NativeLocalValuesOriginalAccess,
) -> Result[NativeClientRunLookup, NativeClientValuesWorkIssue] {
  self.in_original_read((operations, current) => {
    self.host.journal
    .lookup_with_reads(self.request, current(), reads=Some(operations.reads))
    .map_err(issue => Journal(issue))
  })
}

///|
fn NativeLocalValuesOriginalAccess::claim(
  self : NativeLocalValuesOriginalAccess,
) -> Result[NativeClientWorkFirstStart, NativeClientValuesWorkIssue] {
  self.in_original_read((operations, current) => {
    claim_native_client_retained_work_first_start_with_operations(
      self.host.journal,
      self.request,
      current,
      operations=Some(operations),
    ).map_err(issue => Start(issue))
  })
}

///|
fn NativeLocalValuesOriginalAccess::require_start_current(
  self : NativeLocalValuesOriginalAccess,
  start : NativeClientWorkFirstStart,
) -> Result[Unit, NativeClientValuesWorkIssue] {
  self.in_original_read((operations, current) => {
    start
    .require_current(
      self.host.journal,
      self.request,
      current,
      reads=Some(operations.reads),
    )
    .map_err(issue => Start(issue))
  })
}

///|
fn values_original_current(
  access : NativeLocalValuesOriginalAccess?,
  start : NativeClientWorkFirstStart,
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  current : () -> Bool,
) -> Result[Unit, NativeClientValuesWorkIssue] {
  match access {
    Some(original) => original.require_start_current(start)
    None =>
      start
      .require_current(journal, request, current)
      .map_err(issue => Start(issue))
  }
}

///|
/// The trusted coordinator has admitted the same business installation before
/// durable Submission/Run work. Borrow its actual entered execution Ledger;
/// neither a caller Ledger nor a static preparation allowance selects this path.
pub fn NativeLocalHostConnection::open_original_values_work(
  self : NativeLocalHostConnection,
  operation : NativeLocalStoreOperation,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  installed_contracts : @local.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  finalization_quantum : Int,
  max_finalization_rounds : Int,
  requirements? : @local.ClientLocalRequirements? = None,
) -> Result[NativeClientValuesWork, NativeClientValuesWorkFailure] {
  let receiver = operation.receiver
  guard receiver.domain is StoreBusinessDomain(execution) else {
    return Err(
      local_values_work_failure(
        OriginalOperation(None, StoreOperationUnavailable),
      ),
    )
  }
  if !receiver.ready || receiver.closing || receiver.closed {
    return Err(
      local_values_work_failure(
        OriginalOperation(None, StoreOperationUnavailable),
      ),
    )
  }
  let (host, original) = match receiver.originals(receiver.library, false) {
    Err(issue) =>
      return Err(local_values_work_failure(OriginalOperation(None, issue)))
    Ok(value) => value
  }
  if !physical_equal(self, host) ||
    !(original.host.observe_domain_retained_execution_scope(execution)
    is Ok(@bootstrap.BackedReadEntered)) {
    return Err(
      local_values_work_failure(
        OriginalOperation(None, StoreOperationForeignOriginal),
      ),
    )
  }
  let ledger = match
    original.host.borrow_domain_retained_execution_ledger(execution) {
    Err(issue) =>
      return Err(
        local_values_work_failure(
          OriginalOperation(None, StoreOperationExecution(issue)),
        ),
      )
    Ok(value) => value
  }
  let access : NativeLocalValuesOriginalAccess = {
    operation,
    host,
    principal,
    connection,
    request,
    primary: None,
  }
  let result = open_native_client_local_values_work(
    self.journal,
    request,
    prepared,
    compiled,
    definition,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    finalization_quantum,
    max_finalization_rounds,
    () => access.current(),
    ledger=Some(ledger),
    original_access=Some(access),
    requirements~,
  )
  match result {
    Ok(work) => Ok(work)
    Err(failure) => {
      // Keep the same routing receiver even when no Compute owner was opened.
      // Work cleanup never acknowledges the separate operation/Store/Host ACKs.
      failure.original_access = Some(access)
      Err(failure)
    }
  }
}

///|
fn values_original_cleanup_entered(
  access : NativeLocalValuesOriginalAccess?,
) -> Bool {
  match access {
    None => true
    Some(value) => {
      let receiver = value.operation.receiver
      guard receiver.domain is StoreBusinessDomain(execution) else {
        return false
      }
      guard receiver.original is Some(original) else { return false }
      let entered = match
        original.host.observe_domain_retained_execution_scope(execution) {
        Ok(scope) => Ok(scope)
        // Cleanup has a separate original/current port once normal current is
        // retired. Neither an observation failure nor Unentered is a close ACK.
        Err(_) =>
          original.host.observe_domain_retained_execution_cleanup_scope(
            execution,
          )
      }
      entered is Ok(@bootstrap.BackedReadEntered)
    }
  }
}

///|
fn values_unstarted_failure(
  run : @strategy.CapturedDAG,
  access : NativeLocalValuesOriginalAccess?,
  issue : NativeClientValuesWorkIssue,
) -> NativeClientValuesWorkFailure {
  if access is None {
    stop_unstarted_values_setup(run)
    return local_values_work_failure(issue)
  }
  // A failed Read return may have left Compute suspended. Keep this original
  // setup before retrying cleanup in its actual execution/cleanup scope.
  local_values_work_failure(
    issue,
    cleanup=() => {
      stop_unstarted_values_setup(run)
      true
    },
    original_access=access,
    requires_execution_scope=true,
  )
}

///|
// The variant is closed and private. SourceFree keeps the original Values
// decision unchanged. RelationFile derives the actual Source tuple anew from
// retained checking originals, never from caller selection strings or Allow.
fn NativeLocalValuesOriginalAccess::source_allowed_in_original_read(
  self : NativeLocalValuesOriginalAccess,
  source : NativeLocalWorkSourceOriginal,
  captured : NativeLocalJournalCapture,
  host : NativeLocalHostConnection,
  material : @host.ClientLocalAdoptedHostMaterial[
    @sqlite.Database,
    NativeLocalAdoptionIssue,
  ],
) -> Bool {
  match source {
    SourceFree => true
    RelationFile(declaration, requirement, acquisition) => {
      guard @rows.check_row_acquisition_original(
          acquisition, declaration, requirement,
        )
        is Ok(_) &&
        @rows.row_source_target(declaration, requirement) is Ok((resource, _)) else {
        return false
      }
      captured.operation_account(host, material, {
        principal: self.principal,
        connection: declaration.connector_id,
        resource,
        operation: "read",
      })
      is Ok(@authorization.Allow(_))
    }
  }
}
