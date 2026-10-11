///|
pub(all) enum NativeClientPreparationFenceIssue {
  Original(NativeClientSourceWorkIssue)
  Unavailable
  ForeignCapture
  Member(@host.ClientEffectMemberDescriptorIssue)
  Occurrence(@host.ClientEffectLocalIdentityIssue)
  Identity(@credential.RemoteCredentialIssue)
}

///|
/// An in-process binding to the same started Work and its original live capture.
/// Public identity admission cannot construct this value. It is not issuer,
/// observation-read or mutation authority and does not claim a credential use.
struct NativeClientEffectPreparationFence {
  work : NativeClientEffectSourceWork
  context : @resident.ResidentLocalEffectCaptureContext
  inputs : @strategy.CapturedEffectInputs
  artifact : @host.ClientEffectLocalResultArtifact
  occurrence : @host.ClientEffectLocalIdentity
  member_index : Int
  identity : @credential.LocalPreparationFenceIdentity
}

///|
fn NativeClientEffectPreparationFence::require_current(
  self : NativeClientEffectPreparationFence,
) -> Result[Unit, NativeClientPreparationFenceIssue] {
  match self.work.require_preparation_start() {
    Ok(_) => ()
    Err(issue) => return Err(Original(issue))
  }
  // The capture getter rechecks its original permission and retained pins.
  // Neither an equal CID nor another Run's capture replaces these live owners.
  guard self.context.facts() is Some(facts) &&
    self.work.owner.effect_run() is Some(run) &&
    physical_equal(facts.inputs, self.inputs) &&
    physical_equal(facts.consumer, self.artifact) &&
    @strategy.captured_effect_inputs_match_run(self.inputs, run) &&
    physical_equal(facts.materials.prepared, self.work.materials.prepared) &&
    physical_equal(facts.materials.compilation, self.work.materials.compilation) &&
    facts.materials.request == Some(self.work.request) &&
    @host.client_effect_local_identity_matches(
      self.occurrence,
      self.work.materials.prepared,
      self.member_index,
      self.artifact,
    ) else {
    return Err(ForeignCapture)
  }
  let fields = @credential.local_preparation_fence_fields(self.identity)
  if fields.client_request_intent_cid !=
    @host.client_request_intent_cid(self.work.request) ||
    fields.client_request_scope_cid !=
    @host.client_request_scope_cid(self.work.request) ||
    fields.operation_occurrence_cid !=
    @host.client_effect_local_identity_cid(self.occurrence) ||
    fields.run_invocation_cid !=
    @publication.publication_contract_identity(facts.invocation) ||
    fields.unit_definition_cid !=
    @host.client_effect_local_invocation_unit_definition_cid(
      @host.client_effect_local_artifact_invocation(self.artifact),
    ) {
    return Err(ForeignCapture)
  }
  // Reading facts can call current authorization. Check the original Work
  // again after that callback, including cancellation and Checkpoint fencing.
  self.work.require_preparation_start().map_err(issue => Original(issue))
}

///|
/// Bind a preparation observation to the original checked member after its
/// Source/Compute capture exists, before target observation I/O. The same Work
/// already retained its opaque first-start witness before acquisition. The
/// checked semantic occurrence is issued now; no future mutation claim, caller
/// occurrence CID, template invocation or resume generation is substituted.
pub fn NativeClientEffectSourceWork::prepare_observation_fence(
  self : NativeClientEffectSourceWork,
  context : @resident.ResidentLocalEffectCaptureContext,
  stage : Int,
  effect_id : String,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  NativeClientEffectPreparationFence,
  NativeClientPreparationFenceIssue,
] {
  match self.require_preparation_start() {
    Ok(_) => ()
    Err(issue) => return Err(Original(issue))
  }
  guard context.facts() is Some(facts) && self.owner.effect_run() is Some(run) else {
    return Err(Unavailable)
  }
  if !physical_equal(facts.materials.prepared, self.materials.prepared) ||
    !physical_equal(facts.materials.compilation, self.materials.compilation) ||
    facts.materials.request != Some(self.request) ||
    !@strategy.captured_effect_inputs_match_run(facts.inputs, run) ||
    @strategy.captured_effect_inputs_run_definition_cid(facts.inputs) !=
    Some(@publication.publication_contract_identity(self.definition)) {
    return Err(ForeignCapture)
  }
  let descriptor = match
    @host.client_effect_member_descriptor(
      self.materials.prepared,
      stage,
      effect_id,
      max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Member(issue))
  }
  // The first finite Local path observes an update candidate. The Catalog
  // request Owner separately checks its exact GET target and installed scope.
  if descriptor.2 != "update" || descriptor.6 is None {
    return Err(ForeignCapture)
  }
  let occurrence = match
    @host.issue_source_free_client_effect_local_identity(
      self.materials.prepared,
      facts.inputs,
      descriptor.0,
      facts.consumer,
      max_work,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Occurrence(issue))
  }
  let identity = match
    @credential.prepare_local_preparation_fence_identity({
      client_request_intent_cid: @host.client_request_intent_cid(self.request),
      client_request_scope_cid: @host.client_request_scope_cid(self.request),
      operation_occurrence_cid: @host.client_effect_local_identity_cid(
        occurrence,
      ),
      run_invocation_cid: @publication.publication_contract_identity(
        facts.invocation,
      ),
      unit_definition_cid: @host.client_effect_local_invocation_unit_definition_cid(
        @host.client_effect_local_artifact_invocation(facts.consumer),
      ),
    }) {
    Ok(value) => value
    Err(issue) => return Err(Identity(issue))
  }
  let fence : NativeClientEffectPreparationFence = {
    work: self,
    context,
    inputs: facts.inputs,
    artifact: facts.consumer,
    occurrence,
    member_index: descriptor.0,
    identity,
  }
  fence.require_current().map(_ => fence)
}

///|
/// Read the already-bound original identity through the live fence. This
/// neither reconstructs a token from bytes nor grants Provider entry.
pub fn NativeClientEffectPreparationFence::identity(
  self : NativeClientEffectPreparationFence,
) -> Result[
  @credential.LocalPreparationFenceIdentity,
  NativeClientPreparationFenceIssue,
] {
  self.require_current().map(_ => self.identity)
}
