///|
pub(all) enum NativeClientSubmittedEffectValuesInvocationIssue {
  Work(NativeClientSubmittedEffectValuesWorkIssue)
  Policy(NativeClientSubmittedEffectMaterialsIssue)
  Evidence(@publication.RunEvidenceValueIssue)
}

///|
// The decoded body stays inside the original reader's call. Only its verified
// identity survives to the pure issuer; no current configuration or caller CID
// can supply a missing accepted original.
fn NativeSubmittedEffectValuesBinding::original_policy_cid(
  self : NativeSubmittedEffectValuesBinding,
  now : Double,
) -> Result[String, NativeClientSubmittedEffectMaterialsIssue] {
  self.authority.host
  .lookup_submitted_effect_values_policy_original(
    self.authority.crypto,
    self.authority.principal,
    self.authority.connection,
    self.reference,
    self.request,
    now,
  )
  .map(body => @publication.captured_effect_dependency_body_cid(body))
}

///|
/// Issue only source-free Observation/Invocation metadata for this Work's
/// original compilation and accepted Policy. This neither captures a Preview
/// nor issues a Checkpoint, approval, publication or Result availability.
pub fn NativeClientSubmittedEffectValuesWork::original_invocation(
  self : NativeClientSubmittedEffectValuesWork,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  NativeClientSubmittedEffectValuesInvocationIssue,
] {
  match self.run_for_capture() {
    Ok(_) => ()
    Err(issue) => return Err(Work(issue))
  }
  let now = (self.binding.epoch_clock)()
  let policy = self.binding.original_policy_cid(now)
  // All trusted clock/current callbacks may retire this Work or its original
  // custody. Always run the existing terminal Work fence, including on refusal.
  let current = self.run_for_capture()
  let policy_cid = match policy {
    Ok(value) => value
    Err(issue) => return Err(Policy(issue))
  }
  match current {
    Ok(_) => ()
    Err(issue) => return Err(Work(issue))
  }
  let candidate = @host.issue_client_effect_source_free_invocation(
    self.binding.materials.compilation,
    policy_cid,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
  // This reader uses actual Native current authority, not a caller callback.
  // Re-read after every callback above; missing originals are never repaired.
  let retained_cid = match self.binding.original_policy_cid(now) {
    Ok(value) => value
    Err(issue) => return Err(Policy(issue))
  }
  if retained_cid != policy_cid {
    return Err(Policy(Journal(CustodyLost)))
  }
  let authority = self.binding.authority
  match
    self.work.start.require_current(
      authority.host.journal,
      self.binding.request,
      () => authority.current_for(authority.host.journal, self.binding.request),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Work(Work(Start(issue))))
  }
  // No external callback follows the last current/original/claim checks.
  if self.work.closed || self.work.execution.material() is None {
    return Err(Work(Work(Unavailable)))
  }
  candidate.map_err(issue => Evidence(issue))
}
