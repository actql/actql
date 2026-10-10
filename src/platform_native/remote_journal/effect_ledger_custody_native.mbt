///|
fn Journal::effect_ledger_history(
  self : Journal,
  current : @effect.EffectLedgerEntry,
  limits : @checkpoint.WireLimits,
) -> Result[Array[@effect.EffectLedgerEntry], NativeRemoteJournalIssue] {
  if limits.max_nodes < 1 {
    return Err(StateCollision)
  }
  (fn() -> Result[Array[@effect.EffectLedgerEntry], NativeRemoteJournalIssue] raise EffectLedgerStorageFailure {
    let reverse : Array[@effect.EffectLedgerEntry] = []
    let mut entry = current
    for _ in 0..<limits.max_nodes {
      let stored = ledger_storage(
        self.database
        .read(
          "site_effect_ledger_entry",
          @effect.effect_ledger_entry_cid(entry),
        )
        .map_err(issue => Physical(issue)),
      )
      if stored.revision != 0L ||
        stored.body != @utf8.encode(@effect.effect_ledger_entry_wire(entry)) {
        return Err(StateCollision)
      }
      reverse.push(entry)
      match entry.prior_entry_cid {
        None => break
        Some(cid) => {
          let prior = ledger_storage(
            self.database
            .read("site_effect_ledger_entry", cid)
            .map_err(issue => Physical(issue)),
          )
          let wire = @utf8.decode(prior.body) catch {
            _ => return Err(StateCollision)
          }
          entry = match
            @effect.admit_effect_ledger_entry(
              wire,
              limits.max_wire_bytes,
              limits.max_nodes,
              limits.max_depth,
            ) {
            Ok(value) if @effect.effect_ledger_entry_cid(value) == cid => value
            _ => return Err(StateCollision)
          }
        }
      }
    }
    if reverse[reverse.length() - 1].prior_entry_cid is Some(_) {
      return Err(StateCollision)
    }
    let history = Array::makei(reverse.length(), i => {
      reverse[reverse.length() - 1 - i]
    })
    let mut previous : @effect.EffectLedgerEntry? = None
    for value in history {
      if !@effect.effect_ledger_entry_follows(previous, value) {
        return Err(StateCollision)
      }
      previous = Some(value)
    }
    Ok(history)
  })() catch {
    StorageIssue(issue) => Err(issue)
  }
}

///|
/// Read original row custody in one existing SQLite transaction. No claim,
/// Provider request, capacity return or semantic transition is issued. Evidence
/// view permission remains the installed caller's responsibility; historical
/// custody can be read after cancellation or a Site binding becomes stale.
pub fn Journal::effect_ledger_custody(
  self : Journal,
  request : @remote.DispatchRequest,
  scope : @request_scope.LogicalRequestScope,
  locator : @effect.LogicalItemLocator,
  key : @effect.EffectDispatchKey,
  basis : @effect.EffectLedgerBasis,
  limits : @checkpoint.WireLimits,
  checkpoint_limits : @checkpoint.WireLimits,
) -> Result[NativeEffectRowCustody?, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  if limits.max_nodes < 1 {
    return Err(StateCollision)
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
  match self.begin_mutation(false) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let result = (fn() -> Result[
    NativeEffectRowCustody?,
    NativeRemoteJournalIssue,
  ] raise EffectLedgerStorageFailure {
    ledger_storage(self.require(request)) |> ignore
    let (report, _) = ledger_storage(
      self.effect_checkpoint_report(request, checkpoint_limits),
    )
    let checkpoint = @remote.remote_effect_checkpoint_report_checkpoint(report)
    if checkpoint.checkpoint.required_artifact_cid !=
      @effect.effect_dispatch_key_preview_cid(key) {
      return Err(StateCollision)
    }
    let locator_cid = @effect.logical_item_locator_cid(locator)
    let stored = match
      self.database.read("site_effect_ledger_head", locator_cid) {
      Err(@sqlite.NotFound) =>
        match self.database.read("site_effect_ledger_binding", locator_cid) {
          Err(@sqlite.NotFound) => return Ok(None)
          Err(issue) => return Err(Physical(issue))
          Ok(_) => return Err(StateCollision)
        }
      Err(issue) => return Err(Physical(issue))
      Ok(value) => value
    }
    let binding = ledger_storage(
      self.database
      .read("site_effect_ledger_binding", locator_cid)
      .map_err(issue => Physical(issue)),
    )
    if binding.revision != 0L ||
      binding.body != effect_ledger_bound_body(request, report) {
      return Err(StateCollision)
    }
    let wire = @utf8.decode(stored.body) catch {
      _ => return Err(StateCollision)
    }
    let head = match
      @effect.admit_effect_ledger_entry(
        wire,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) {
      Ok(value) if @effect.effect_ledger_entry_matches_basis(value, basis) =>
        value
      _ => return Err(StateCollision)
    }
    let history = ledger_storage(self.effect_ledger_history(head, limits))
    let mut original : @effect.EffectLedgerEntry? = None
    for entry in history {
      if !@effect.effect_ledger_entry_matches_basis(entry, basis) {
        return Err(StateCollision)
      }
      if entry.state == @effect.Dispatching {
        // This initial unavailable-capability connection has one physical
        // dispatch. Do not choose between multiple historical attempts.
        if original is Some(_) {
          return Err(StateCollision)
        }
        original = Some(entry)
      }
    }
    let response = match original {
      None => None
      Some(entry) => ledger_storage(self.effect_ledger_response(request, entry))
    }
    Ok(Some({ head, dispatching: original, response, }))
  })() catch {
    StorageIssue(issue) => Err(issue)
  }
  match result {
    Err(issue) => {
      ignore(self.database.rollback())
      Err(issue)
    }
    Ok(value) =>
      match self.finish_effect_checkpoint_mutation(Ok(())) {
        Ok(_) => Ok(value)
        Err(issue) => Err(issue)
      }
  }
}
