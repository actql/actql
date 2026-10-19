///|
// Closed Values setup only: the same operation brackets the Journal binding,
// without wrapping an entire Store body in a SQLite scope.
fn NativeLocalValuesOriginalAccess::bind_publication(
  self : NativeLocalValuesOriginalAccess,
  binding : String,
) -> Result[Unit, NativeClientValuesWorkIssue] {
  self.in_original_read((operations, current) => {
    self.host.journal
    .bind_publication(
      self.request,
      binding,
      current,
      operations=Some(operations),
    )
    .map_err(issue => Journal(issue))
  })
}

///|
// The command returns Business to its original borrowed Read before commit.
// The Journal fence owns that Read, not a Store C flight. Each Store method
// therefore enters and acknowledges its own original flight independently.
fn NativeLocalValuesOriginalAccess::fence_publication(
  self : NativeLocalValuesOriginalAccess,
  definition : @publication.PublicationContract,
  binding : String,
  commit : () -> Result[
    @native_publication.NativeRunPublicationResult,
    @native_publication.NativeRunPublicationIssue,
  ],
) -> Result[
  @native_publication.NativeRunPublicationResult,
  @native_publication.NativeRunPublicationIssue,
] {
  let receiver = self.operation.receiver
  guard self.operation.bridge is Some(bridge) &&
    receiver.ready &&
    !receiver.closed &&
    !receiver.closing &&
    !receiver.borrowed_read &&
    receiver.primary is None &&
    receiver.capture.read_callback_active &&
    bridge.pending_scope() is Ok(false) else {
    self.retain(OriginalOperation(None, StoreOperationUnavailable)) |> ignore
    return Err(@native_publication.CommitFenceUnavailable)
  }
  let (_, original) = match receiver.originals(receiver.library, false) {
    Ok(value) => value
    Err(issue) => {
      self.retain(OriginalOperation(None, issue)) |> ignore
      return Err(@native_publication.CommitFenceUnavailable)
    }
  }
  guard original.store_operation is None &&
    original.active_phase is Some(@arena.HostRead) &&
    original.host.observe_local_host_consuming_read_scope(
      original.pair,
      original.read,
    )
    is Ok(@arena.ReadEntered) &&
    original.host.observe_domain_retained_execution_scope(receiver.execution)
    is Ok(@bootstrap.BackedReadUnentered) else {
    self.retain(OriginalOperation(None, StoreOperationUnavailable)) |> ignore
    return Err(@native_publication.CommitFenceUnavailable)
  }
  let output : Ref[
    Result[
      @native_publication.NativeRunPublicationResult,
      @native_publication.NativeRunPublicationIssue,
    ]?,
  ] = Ref(None)
  let captured = receiver.capture.with_current_adoption_material_in_original_read((
      host,
      material,
      operations,
    ) => {
      if !physical_equal(host, self.host) {
        return Err(CustodyLost)
      }
      let current = () => {
        receiver.capture.original_submit_allowed(
          host,
          material,
          self.principal,
          self.connection,
          @host.client_request_authority_scope_cid(self.request),
        )
        is Ok(true)
      }
      match
        host.journal.fence_publication_outcome(
          self.request,
          definition,
          binding,
          current,
          commit,
          operations=Some(operations),
        ) {
        Ok(result) => {
          output.val = Some(result)
          Ok(())
        }
        Err(issue) => {
          self.retain(Journal(issue)) |> ignore
          Err(Journal(issue))
        }
      }
    },
  )
  match captured {
    Err(issue) => {
      let routing = StoreOperationCapture(issue)
      receiver.refuse(routing) |> ignore
      // Preserve a committed/lost Journal reply together with its actual Read
      // return failure. Neither failure permits a replacement publication.
      self.primary = Some(OriginalOperation(self.primary, routing))
      Err(@native_publication.CommitFenceUnavailable)
    }
    Ok(_) =>
      output.val.unwrap_or(Err(@native_publication.CommitFenceUnavailable))
  }
}
