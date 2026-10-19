///|
// Only the fixed publisher constructor/current predicates below borrow this
// route. No public callback, raw handle or caller permission is accepted.
fn[T] NativeLocalStoreOperation::with_publisher_read(
  self : NativeLocalStoreOperation,
  call : (NativeLocalHostConnection, NativeClientJournalOperationAccess) -> Result[
    T,
    NativeLocalPublisherBindingIssue,
  ],
) -> Result[T, NativeLocalPublisherBindingIssue] {
  let receiver = self.receiver
  guard self.bridge is Some(bridge) &&
    receiver.ready &&
    !receiver.closed &&
    !receiver.closing &&
    receiver.primary is None else {
    return Err(OriginalOperation(None, StoreOperationUnavailable))
  }
  let (_, original) = match receiver.originals(receiver.library, false) {
    Ok(value) => value
    Err(issue) => return Err(OriginalOperation(None, issue))
  }
  let borrowed = if original.store_operation is Some(active) {
    if !physical_equal(active, receiver) ||
      receiver.phase != StoreRouteRead ||
      !(original.host.observe_local_host_consuming_read_scope(
        original.pair,
        original.read,
      )
      is Ok(@arena.ReadEntered)) ||
      !(bridge.pending_scope() is Ok(true)) {
      return Err(OriginalOperation(None, StoreOperationUnavailable))
    }
    true
  } else {
    match bridge.enter_store() {
      Ok(_) => ()
      Err(issue) => {
        let retained = receiver.primary.unwrap_or(StoreOperationSqlite(issue))
        receiver.refuse(retained) |> ignore
        return Err(OriginalOperation(None, retained))
      }
    }
    false
  }
  // The body result is retained before later current/return can fail. A lost
  // metadata COMMIT reply remains the original Journal Unknown, never a retry.
  let output : Ref[Result[T, NativeLocalPublisherBindingIssue]?] = Ref(None)
  let captured = receiver.capture.with_current_adoption_material_in_original_read((
      host,
      _material,
      operations,
    ) => {
      let result = call(host, operations)
      output.val = Some(result)
      match result {
        Err(Journal(TransactionUnknown | Epoch(TransactionUnknown))) =>
          Err(Journal(TransactionUnknown))
        _ => Ok(())
      }
    },
  )
  let body : Result[T, NativeLocalPublisherBindingIssue] = match
    (captured, output.val) {
    (Err(issue), value) => {
      receiver.refuse(StoreOperationCapture(issue)) |> ignore
      Err(
        OriginalOperation(
          match value {
            Some(Err(primary)) => Some(primary)
            _ => None
          },
          StoreOperationCapture(issue),
        ),
      )
    }
    (Ok(_), Some(value)) => value
    (Ok(_), None) => Err(OriginalOperation(None, StoreOperationUnavailable))
  }
  if !borrowed {
    match bridge.leave_store() {
      Err(issue) => {
        let retained = receiver.primary.unwrap_or(StoreOperationSqlite(issue))
        receiver.refuse(retained) |> ignore
        return Err(
          OriginalOperation(
            match body {
              Err(primary) => Some(primary)
              Ok(_) => None
            },
            retained,
          ),
        )
      }
      Ok(_) => ()
    }
  }
  body
}

///|
fn NativeLocalPublisherBinding::selected_original(
  self : NativeLocalPublisherBinding,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  match self.authority.capture {
    None => self.authority.host.selected_configuration(self.file.name)
    Some(capture) =>
      capture.selected_configuration_in_original_read(self.file.name)
  }
}

///|
fn NativeLocalPublisherBinding::current_checked_in_mode(
  self : NativeLocalPublisherBinding,
  join_owned_transaction : Bool,
) -> Bool {
  match self.operation {
    None => self.current_in_mode(join_owned_transaction)
    Some(operation) => {
      guard operation.bridge is Some(original) &&
        self.store.matches_original_operation(original) else {
        return false
      }
      operation.with_publisher_read((host, operations) => {
        if !physical_equal(host, self.authority.host) {
          return Err(AuthorizationDenied)
        }
        Ok(
          self.current_in_mode(
            join_owned_transaction,
            reads=Some(operations.reads),
          ),
        )
      })
      is Ok(true)
    }
  }
}

///|
/// Bind the existing publisher only to this actual Host/operation/Store and
/// current publish Account tuple. Store association is metadata, not a grant;
/// all original current, Journal, selection and request checks remain active.
pub fn NativeLocalHostConnection::bind_original_run_publisher(
  self : NativeLocalHostConnection,
  operation : NativeLocalStoreOperation,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  installation_file : String,
  store : @publication_store.Store,
) -> Result[NativeLocalPublisherBinding, NativeLocalPublisherBindingIssue] {
  guard operation.bridge is Some(original) &&
    store.matches_original_operation(original) else {
    return Err(SelectionMismatch)
  }
  operation.with_publisher_read((host, operations) => {
    if !physical_equal(host, self) {
      return Err(SelectionMismatch)
    }
    self.bind_run_publisher_with_operations(
      operation.receiver.capture.crypto,
      principal,
      connection,
      request,
      definition,
      installation_file,
      store,
      operations=Some(operations),
      capture=Some(operation.receiver.capture),
      operation=Some(operation),
    )
  })
}

///|
/// Sample one material/fence correlation using the selected publisher's same
/// original Library and current Read. The digest retains the existing SHA-256
/// preimage; it is DATA, never a publication grant or a replacement attempt.
pub fn NativeLocalPublisherBinding::sample_original_generation_cid(
  self : NativeLocalPublisherBinding,
) -> Result[String, NativeLocalPublisherBindingIssue] {
  guard self.operation is Some(operation) else { return Err(InvalidOriginal) }
  operation.with_publisher_read((host, operations) => {
    if !physical_equal(host, self.authority.host) ||
      !self.current_in_mode(false, reads=Some(operations.reads)) {
      return Err(AuthorizationDenied)
    }
    let nonce = match self.authority.crypto.random_bytes(32) {
      Ok(bytes) => bytes
      Err(issue) => return Err(Adoption(Crypto(issue)))
    }
    // The existing bounded pure digest has no physical Hasher child to lose
    // when a later current/return fence refuses. The actual random sample is
    // still obtained only through this Library's selected physical component.
    let generation = "sha256:" + @sha.hex(nonce)
    if !self.current_in_mode(false, reads=Some(operations.reads)) {
      return Err(AuthorizationDenied)
    }
    Ok(generation)
  })
}
