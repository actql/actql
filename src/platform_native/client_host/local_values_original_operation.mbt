///|
// Fixed Native Work routing, never a public callback/Allow factory. Its result
// records retain their actual Read-domain aliases until Work/caller retirement;
// a scope exchange does not free those aliases or acknowledge their domains.
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
) -> Result[T, NativeClientValuesWorkIssue] {
  guard self.operation.bridge is Some(bridge) &&
    self.operation.receiver.ready &&
    !self.operation.receiver.closed &&
    !self.operation.receiver.closing else {
    return Err(self.retain(OriginalOperation(None, StoreOperationUnavailable)))
  }
  match bridge.enter_store() {
    Err(issue) =>
      return Err(
        self.retain(OriginalOperation(None, self.routing_issue(issue))),
      )
    Ok(_) => ()
  }
  // Publish the actual Work result before a later original Read/current/leave
  // can fail. A committed claim remains one-shot even if that return is lost.
  let output : Ref[Result[T, NativeClientValuesWorkIssue]?] = Ref(None)
  let captured = self.operation.receiver.capture
  let current = captured.with_current_adoption_material_in_original_read((
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
    let result = if direct_current() {
      call(operations, direct_current)
    } else {
      Err(AuthorizationDenied)
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
  let body = match (current, output.val) {
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
  let after = bridge.leave_store()
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
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  finalization_quantum : Int,
  max_finalization_rounds : Int,
) -> Result[NativeClientValuesWork, NativeClientValuesWorkFailure] {
  let receiver = operation.receiver
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
    !(original.host.observe_domain_retained_execution_scope(receiver.execution)
    is Ok(@bootstrap.BackedReadEntered)) {
    return Err(
      local_values_work_failure(
        OriginalOperation(None, StoreOperationForeignOriginal),
      ),
    )
  }
  let ledger = match
    original.host.borrow_domain_retained_execution_ledger(receiver.execution) {
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
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    finalization_quantum,
    max_finalization_rounds,
    () => access.current(),
    ledger=Some(ledger),
    original_access=Some(access),
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
      guard receiver.original is Some(original) else { return false }
      original.host.observe_domain_retained_execution_scope(receiver.execution)
      is Ok(@bootstrap.BackedReadEntered)
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
