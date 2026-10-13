///|
// Pure wire custody delegates to the common codec. Journal/CAS/current
// authority remain in this Native Host and are not inferred from the packet.
fn run_policy_originals_wire(
  prepared : @host.PreparedClientProgram,
  compiled? : @host.ClientCompiledRun,
) -> Result[String, NativeClientRunJournalIssue] {
  @host.issue_client_run_policy_originals(prepared, compiled?).map_err(
    policy_originals_issue,
  )
}

///|
fn read_run_policy_originals(
  wire : String,
) -> Result[
  Array[@publication.CapturedEffectDependencyBody],
  NativeClientRunJournalIssue,
] {
  @host.read_client_run_policy_originals(wire).map_err(policy_originals_issue)
}

///|
fn policy_originals_issue(
  issue : @host.ClientRunPolicyOriginalsIssue,
) -> NativeClientRunJournalIssue {
  match issue {
    ForeignRun => ForeignRun
    PublicationPolicy(issue) => PublicationPolicy(issue)
    CapacityExceeded => CapacityExceeded
    Encoding => Encoding
    CustodyLost => CustodyLost
  }
}

///|
/// Keep exact checked originals only before dispatch/start. The existing Run
/// transaction, current authority and checked binding decide the mutation.
/// A restored Run with missing originals is never re-prepared to repair them.
fn NativeClientRunJournal::retain_publication_policy_originals(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  authority : NativeLocalPolicyAuthority,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  if !authority.current_for(self, request) {
    return Err(AuthorizationDenied)
  }
  match
    validate_native_client_run_binding(request, prepared, compiled, definition) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let wire = match run_policy_originals_wire(prepared, compiled~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.transaction(() => {
    if !authority.current_for(self, request) {
      return Err(AuthorizationDenied)
    }
    let record = match self.retained(request) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    if @publication.publication_contract_identity(record.definition) !=
      @publication.publication_contract_identity(definition) {
      return Err(ForeignRun)
    }
    if record.publication_policy_originals is Some(original) {
      if original != wire {
        return Err(CustodyLost)
      }
      if !authority.current_for(self, request) {
        return Err(AuthorizationDenied)
      }
      return Ok(record)
    }
    if record.dispatch_reserved ||
      record.physical_start_claimed ||
      record.cancellation_requested {
      return Err(Fenced)
    }
    // Recheck after preparation/transaction reads, immediately before CAS.
    if !authority.current_for(self, request) {
      return Err(AuthorizationDenied)
    }
    self.save({ ..record, publication_policy_originals: Some(wire), })
  })
}

///|
/// Resolve only a retained original under current read authority. The caller
/// obtains actual_policy_cid from the committed Result Artifact, not from
/// current Source configuration. This method never creates a grant or payload.
fn NativeClientRunJournal::lookup_publication_policy_original(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  actual_policy_cid : String,
  authority : NativeLocalPolicyAuthority,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  NativeClientRunJournalIssue,
] {
  if !authority.current_for(self, request) {
    return Err(AuthorizationDenied)
  }
  self.transaction(() => {
    if !authority.current_for(self, request) {
      return Err(AuthorizationDenied)
    }
    let (record, selected_policy) = match
      self.retained_with_selected_policy(request, Some(actual_policy_cid)) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    guard record.publication_policy_originals is Some(_) &&
      selected_policy is Some(body) else {
      return Err(PublicationPolicy(@checked.MissingDependency))
    }
    if !authority.current_for(self, request) {
      return Err(AuthorizationDenied)
    }
    Ok(body)
  })
}
