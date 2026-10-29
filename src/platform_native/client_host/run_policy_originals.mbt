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
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  let reads = operations.map(value => value.reads)
  if !authority.current_for(self, request) {
    return Err(AuthorizationDenied)
  }
  match
    self.validate_prepared_run_binding(request, prepared, compiled, definition) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let wire = match run_policy_originals_wire(prepared, compiled~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.transaction_with_reads(
    () => {
      if !authority.current_for(self, request) {
        return Err(AuthorizationDenied)
      }
      let record = match self.retained(request, reads~) {
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
      self.save_with_operations(
        { ..record, publication_policy_originals: Some(wire), },
        operations~,
      )
    },
    reads~,
  )
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
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  NativeClientRunJournalIssue,
] {
  if !authority.current_for(self, request) {
    return Err(AuthorizationDenied)
  }
  self.transaction_with_reads(
    () => {
      if !authority.current_for(self, request) {
        return Err(AuthorizationDenied)
      }
      let (wire, comparison) = match
        self.retained_policy_wire(request, reads~) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let body = match
        self.select_publication_policy(wire, comparison, actual_policy_cid) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if !authority.current_for(self, request) {
        return Err(AuthorizationDenied)
      }
      Ok(body)
    },
    reads~,
  )
}

///|
fn select_admitted_run_policy(
  bodies : Array[@publication.CapturedEffectDependencyBody]?,
  comparison : RunPolicyRequestComparison,
  selected_policy_cid : String,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  NativeClientRunJournalIssue,
] {
  match comparison {
    OriginalRequest => ()
    ChangedOriginalIntent => return Err(ChangedIntent)
    ForeignOriginalRequest => return Err(CustodyLost)
  }
  guard bodies is Some(admitted) else {
    return Err(PublicationPolicy(@checked.MissingDependency))
  }
  guard admitted
    .iter()
    .find_first(body => {
      @publication.captured_effect_dependency_body_kind(body) == "data_policy" &&
      @publication.captured_effect_dependency_body_cid(body) ==
      selected_policy_cid
    })
    is Some(body) else {
    return Err(PublicationPolicy(@checked.MissingDependency))
  }
  Ok(body)
}

///|
// Parsed immutable Policy bodies share the selected Journal operation's
// lifetime. Equality is exact wire equality; no target or permission is cached.
fn NativeClientRunJournal::publication_originals(
  self : NativeClientRunJournal,
  wire : String,
) -> Result[
  Array[@publication.CapturedEffectDependencyBody],
  NativeClientRunJournalIssue,
] {
  if self.operation_active {
    for (original, bodies) in self.admitted_publications {
      if original == wire {
        return Ok(bodies)
      }
    }
  }
  let bodies = match read_run_policy_originals(wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if self.operation_active {
    self.admitted_publications.push((wire, bodies))
  }
  Ok(bodies)
}

///|
fn NativeClientRunJournal::select_publication_policy(
  self : NativeClientRunJournal,
  wire : String?,
  comparison : RunPolicyRequestComparison,
  selected_policy_cid : String,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  NativeClientRunJournalIssue,
] {
  let bodies = match wire {
    Some(wire) =>
      match self.publication_originals(wire) {
        Ok(value) => Some(value)
        Err(_) => return Err(CustodyLost)
      }
    None => None
  }
  select_admitted_run_policy(bodies, comparison, selected_policy_cid)
}
