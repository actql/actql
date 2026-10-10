///|
fn effect_response_cid_valid(use_cid : String) -> Bool {
  use_cid.length() == 71 &&
  use_cid.has_prefix("sha256:") &&
  use_cid
  .unsafe_substring(start=7, end=use_cid.length())
  .iter()
  .all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
}

///|
priv suberror EffectLedgerStorageFailure {
  StorageIssue(NativeRemoteJournalIssue)
}

///|
fn[T] ledger_storage(
  result : Result[T, NativeRemoteJournalIssue],
) -> T raise EffectLedgerStorageFailure {
  match result {
    Ok(value) => value
    Err(issue) => raise StorageIssue(issue)
  }
}

///|
fn effect_ledger_bound_body(
  request : @remote.DispatchRequest,
  report : @remote.RemoteEffectCheckpointReport,
) -> Bytes {
  @utf8.encode(
    @remote.dispatch_request_identity(request) +
    "\n" +
    @remote.remote_effect_checkpoint_report_identity(report),
  )
}

///|
/// Store the common Owner's exact dispatch entry before any physical write.
/// Winning this storage claim is necessary, not sufficient, for sending:
/// the caller must still admit the original signed Resolution, current
/// independent approval, resume fence and checked Provider row. No permission
/// is inferred from the saved Checkpoint or native execution state.
pub fn Journal::claim_effect_ledger_dispatch(
  self : Journal,
  request : @remote.DispatchRequest,
  scope : @request_scope.LogicalRequestScope,
  locator : @effect.LogicalItemLocator,
  key : @effect.EffectDispatchKey,
  basis : @effect.EffectLedgerBasis,
  limits : @checkpoint.WireLimits,
  checkpoint_limits : @checkpoint.WireLimits,
) -> Result[(Bool, @effect.EffectLedgerEntry), NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let prepared = match
    @effect.issue_prepared_effect_ledger_entry(
      basis,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  let dispatching = match
    @effect.issue_next_effect_ledger_entry(
      prepared,
      "dispatching",
      None,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  if !@effect.effect_ledger_entry_admits_dispatch(
      dispatching,
      scope,
      locator,
      key,
      basis.canonical_request_cid,
    ) {
    return Err(StateCollision)
  }
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let result = (fn() -> Result[
    (Bool, @effect.EffectLedgerEntry),
    NativeRemoteJournalIssue,
  ] raise EffectLedgerStorageFailure {
    let record = ledger_storage(self.require(request))
    guard @remote.dispatch_record_state(record)
      is (@remote.NativeSettled, _, @remote.CleanupActive, _, _) else {
      return Err(StateCollision)
    }
    if ledger_storage(self.cancellation_requested(request)) {
      return Err(StateCollision)
    }
    let (report, _) = ledger_storage(
      self.effect_checkpoint_report(request, checkpoint_limits),
    )
    let checkpoint = @remote.remote_effect_checkpoint_report_checkpoint(report)
    if checkpoint.checkpoint.required_artifact_cid !=
      @effect.effect_dispatch_key_preview_cid(key) {
      return Err(StateCollision)
    }
    let locator_cid = @effect.logical_item_locator_cid(locator)
    let binding = effect_ledger_bound_body(request, report)
    let stored = match
      self.database.read("site_effect_ledger_head", locator_cid) {
      Err(@sqlite.NotFound) => {
        match self.database.read("site_effect_ledger_binding", locator_cid) {
          Err(@sqlite.NotFound) => ()
          _ => return Err(StateCollision)
        }
        ledger_storage(
          self.database
          .insert("site_effect_ledger_binding", locator_cid, binding)
          .map_err(issue => Physical(issue)),
        )
        |> ignore
        None
      }
      Err(issue) => return Err(Physical(issue))
      Ok(value) => {
        let original = ledger_storage(
          self.database
          .read("site_effect_ledger_binding", locator_cid)
          .map_err(issue => Physical(issue)),
        )
        if original.revision != 0L || original.body != binding {
          return Err(StateCollision)
        }
        let wire = @utf8.decode(value.body) catch {
          _ => return Err(StateCollision)
        }
        let entry = match
          @effect.admit_effect_ledger_entry(
            wire,
            limits.max_wire_bytes,
            limits.max_nodes,
            limits.max_depth,
          ) {
          Ok(entry) => entry
          Err(_) => return Err(StateCollision)
        }
        if !@effect.effect_ledger_entry_matches_basis(entry, basis) {
          return Err(StateCollision)
        }
        Some((value.revision, entry))
      }
    }
    let action = @effect.effect_row_recovery_action_from_entry(
      locator,
      basis.intent_fingerprint_cid,
      key,
      basis.canonical_request_cid,
      stored.map(value => value.1),
      false,
    )
    // Only the existing common Owner decides whether this original row can
    // begin dispatch. A possibly-sent row is reconciled, never claimed again.
    if action >= 3 && action <= 7 {
      return Ok((false, stored.unwrap().1))
    }
    if action != 0 && action != 1 {
      return Err(StateCollision)
    }
    let prior = stored.map(value => value.1).unwrap_or(prepared)
    let next = match
      @effect.issue_next_effect_ledger_entry(
        prior,
        "dispatching",
        None,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) {
      Ok(value) => value
      Err(_) => return Err(StateCollision)
    }
    if !@effect.effect_ledger_entry_follows(Some(prior), next) {
      return Err(StateCollision)
    }
    for entry in [prior, next] {
      let cid = @effect.effect_ledger_entry_cid(entry)
      let bytes = @utf8.encode(@effect.effect_ledger_entry_wire(entry))
      match self.database.read("site_effect_ledger_entry", cid) {
        Ok(value) if value.revision == 0L && value.body == bytes => ()
        Err(@sqlite.NotFound) =>
          ledger_storage(
            self.database
            .insert("site_effect_ledger_entry", cid, bytes)
            .map_err(issue => Physical(issue)),
          )
          |> ignore
        Err(issue) => return Err(Physical(issue))
        _ => return Err(StateCollision)
      }
    }
    let bytes = @utf8.encode(@effect.effect_ledger_entry_wire(next))
    match stored {
      None =>
        ledger_storage(
          self.database
          .insert("site_effect_ledger_head", locator_cid, bytes)
          .map_err(issue => Physical(issue)),
        )
        |> ignore
      Some((revision, _)) =>
        ledger_storage(
          self.database
          .compare_exchange(
            "site_effect_ledger_head", locator_cid, revision, bytes,
          )
          .map_err(issue => Physical(issue)),
        )
        |> ignore
    }
    Ok((true, next))
  })() catch {
    StorageIssue(issue) => Err(issue)
  }
  match result {
    Err(issue) => {
      ignore(self.database.rollback())
      Err(issue)
    }
    Ok(value) => {
      match self.finish_effect_checkpoint_mutation(Ok(())) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      Ok(value)
    }
  }
}

///|
/// Retain raw bytes atomically with their immutable physical binding before
/// interpreting the Provider response. Cancellation after sending does not
/// erase this obligation or prevent its evidence from being saved.
pub fn Journal::record_effect_ledger_response(
  self : Journal,
  request : @remote.DispatchRequest,
  dispatching : @effect.EffectLedgerEntry,
  scope : @request_scope.LogicalRequestScope,
  locator : @effect.LogicalItemLocator,
  key : @effect.EffectDispatchKey,
  canonical_request_cid : String,
  response : NativeEffectSavedResponse,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let use_cid = response.credential_use_cid
  if !effect_response_cid_valid(use_cid) ||
    response.status_code < 100 ||
    response.status_code > 599 ||
    !@effect.effect_ledger_entry_admits_dispatch(
      dispatching, scope, locator, key, canonical_request_cid,
    ) {
    return Err(StateCollision)
  }
  if response.body.length().to_int64() > self.max_record_bytes {
    return Err(Physical(@sqlite.BodyTooLarge))
  }
  let cid = @effect.effect_ledger_entry_cid(dispatching)
  let metadata = @utf8.encode(
    use_cid +
    "\n" +
    response.status_code.to_string() +
    "\n" +
    @sha.hex(response.body),
  )
  let bytes = Bytes::from_array(response.body.to_array())
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let result = (fn() -> Result[Unit, NativeRemoteJournalIssue] raise EffectLedgerStorageFailure {
    ledger_storage(self.require(request)) |> ignore
    let binding = ledger_storage(
      self.database
      .read(
        "site_effect_ledger_binding",
        @effect.logical_item_locator_cid(locator),
      )
      .map_err(issue => Physical(issue)),
    )
    let parts = @utf8.decode(binding.body) catch {
      _ => return Err(StateCollision)
    }
    if binding.revision != 0L ||
      parts.split("\n").map(value => value.to_owned()).to_array().get(0) !=
      Some(@remote.dispatch_request_identity(request)) {
      return Err(StateCollision)
    }
    let entry = ledger_storage(
      self.database
      .read("site_effect_ledger_entry", cid)
      .map_err(issue => Physical(issue)),
    )
    if entry.revision != 0L ||
      entry.body != @utf8.encode(@effect.effect_ledger_entry_wire(dispatching)) {
      return Err(StateCollision)
    }
    match
      (
        self.database.read("site_effect_response_meta", cid),
        self.database.read("site_effect_response_bytes", cid),
      ) {
      (Ok(saved), Ok(body)) if saved.revision == 0L &&
        body.revision == 0L &&
        saved.body == metadata &&
        body.body == bytes => Ok(())
      (Err(@sqlite.NotFound), Err(@sqlite.NotFound)) => {
        ledger_storage(
          self.database
          .insert("site_effect_response_meta", cid, metadata)
          .map_err(issue => Physical(issue)),
        )
        |> ignore
        ledger_storage(
          self.database
          .insert("site_effect_response_bytes", cid, bytes)
          .map_err(issue => Physical(issue)),
        )
        |> ignore
        Ok(())
      }
      (Err(issue), _) | (_, Err(issue)) if !(issue is @sqlite.NotFound) =>
        Err(Physical(issue))
      _ => Err(StateCollision)
    }
  })() catch {
    StorageIssue(issue) => Err(issue)
  }
  self.finish_effect_checkpoint_mutation(result)
}

///|
/// Custody inspection for the original row. This neither sends nor classifies
/// the response, and grants no evidence-view permission to an external caller.
pub fn Journal::effect_ledger_response(
  self : Journal,
  request : @remote.DispatchRequest,
  dispatching : @effect.EffectLedgerEntry,
) -> Result[NativeEffectSavedResponse?, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  (fn() -> Result[NativeEffectSavedResponse?, NativeRemoteJournalIssue] raise EffectLedgerStorageFailure {
    ledger_storage(self.require(request)) |> ignore
    let binding = ledger_storage(
      self.database
      .read(
        "site_effect_ledger_binding",
        @effect.effect_ledger_entry_locator_cid(dispatching),
      )
      .map_err(issue => Physical(issue)),
    )
    let bound = @utf8.decode(binding.body) catch {
      _ => return Err(StateCollision)
    }
    if binding.revision != 0L ||
      bound.split("\n").map(value => value.to_owned()).to_array().get(0) !=
      Some(@remote.dispatch_request_identity(request)) {
      return Err(StateCollision)
    }
    let cid = @effect.effect_ledger_entry_cid(dispatching)
    let original = ledger_storage(
      self.database
      .read("site_effect_ledger_entry", cid)
      .map_err(issue => Physical(issue)),
    )
    if original.revision != 0L ||
      original.body !=
      @utf8.encode(@effect.effect_ledger_entry_wire(dispatching)) {
      return Err(StateCollision)
    }
    match
      (
        self.database.read("site_effect_response_meta", cid),
        self.database.read("site_effect_response_bytes", cid),
      ) {
      (Err(@sqlite.NotFound), Err(@sqlite.NotFound)) => Ok(None)
      (Ok(meta), Ok(bytes)) if meta.revision == 0L && bytes.revision == 0L => {
        let text = @utf8.decode(meta.body) catch {
          _ => return Err(StateCollision)
        }
        let parts = text.split("\n").map(value => value.to_owned()).to_array()
        guard parts.length() == 3 else { return Err(StateCollision) }
        let status = @string.parse_int(parts[1]) catch {
          _ => return Err(StateCollision)
        }
        if !effect_response_cid_valid(parts[0]) ||
          status < 100 ||
          status > 599 ||
          status.to_string() != parts[1] ||
          @sha.hex(bytes.body) != parts[2] {
          return Err(StateCollision)
        }
        Ok(
          Some({
            credential_use_cid: parts[0],
            status_code: status,
            body: Bytes::from_array(bytes.body.to_array()),
          }),
        )
      }
      (Err(issue), _) | (_, Err(issue)) if !(issue is @sqlite.NotFound) =>
        Err(Physical(issue))
      _ => Err(StateCollision)
    }
  })() catch {
    StorageIssue(issue) => Err(issue)
  }
}
