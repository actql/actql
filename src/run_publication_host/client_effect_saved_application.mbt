///|
/// Exact saved computation and checked, ordered Preview after one current
/// claim. Preparing this context does not issue a dispatch or write a file.
pub struct ClientEffectSavedApplication {
  claim : ClientEffectResolutionResumeClaim
  computation : ClientEffectSavedComputation
  scoped_request : @request_scope.LogicalRequestScope
  approval : @checkpoint.ResumedApproval
  account_cid : String
  principal : String
  keys : Array[Array[@effect.EffectDispatchKey]]
}

///|
/// Bound cold reconstruction by the exact authenticated capture, using the
/// installed dependency codec's finite passes over bodies, references and
/// graph indexes. This supplies no byte capacity or application permission.
pub fn ClientEffectHostAttestationUse::application_recovery_work_bound(
  self : ClientEffectHostAttestationUse,
  max_wire_bytes : Int,
) -> Int64? {
  let units = self.attestation.review.captured.length()
  guard units > 0 && units <= max_wire_bytes else { return None }
  let span = 1L + 3L * units.to_int64()
  Some(256L + 128L * span)
}

///|
pub fn ClientEffectHostAttestationUse::restore_saved_application(
  self : ClientEffectHostAttestationUse,
  claim : ClientEffectResolutionResumeClaim,
  actual : ClientJournalPhysicalRow,
  at_ms : Int64,
  limits : @checkpoint.WireLimits,
  fund : (Int, Int, Int) -> Bool,
  work : (Int) -> Bool,
) -> Result[ClientEffectSavedApplication, ClientEffectResolutionOriginalIssue] {
  let original = self.attestation.review.reference
  let checkpoint = original.waiting.checkpoint.artifact
  let scope = client_request_logical_scope(original.waiting.run.request)
  let selected = @credential.local_signing_credential_grant_scope(self.grant)
  let verified = claim.verified
  let verified_limits = client_checkpoint_journal_limits()
  guard self.attestation.admitted.decision == @checkpoint.Approved &&
    claim.confirmed(actual) is Some(_) &&
    verified.checkpoint_cid == checkpoint.checkpoint_cid &&
    verified.resolution_cid == self.attestation.admitted.resolution_cid &&
    @scalar.admit_utf8_length(verified.wire, verified_limits.max_wire_bytes)
    is Ok(verified_bytes) &&
    fund(
      verified_bytes,
      Int::min(verified_limits.max_nodes, verified_bytes),
      verified_limits.max_depth,
    ) &&
    @checkpoint.resumed_approval(verified.wire, verified_limits) is Ok(approval) &&
    approval.verified_resolution_cid == verified.verified_resolution_cid &&
    approval.checkpoint_cid == verified.checkpoint_cid &&
    approval.resolution_cid == verified.resolution_cid &&
    at_ms >= 0L &&
    at_ms < claim.lease_expires_ms &&
    @values.timestamp_epoch_milliseconds(checkpoint.checkpoint.expires_at)
    is Some(expires_at) &&
    at_ms < expires_at else {
    return Err(InvalidOriginal)
  }
  let computation = match
    self.attestation.restore_computation(limits, fund, work) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  let count = @publication.effect_preview_member_count(original.preview)
  let (key_bytes, key_nodes, key_depth) = @effect.effect_dispatch_key_codec_limits()
  let mut rows = 0
  let mut max_correlation = 1
  for member_index in 0..<count {
    guard @publication.effect_preview_member_authority_scope_cid(
        original.preview,
        member_index,
      ) ==
      Some(client_request_authority_scope_cid(original.waiting.run.request)) &&
      @publication.effect_preview_member_kind(original.preview, member_index) ==
      Some("update") &&
      @publication.effect_preview_row_count(original.preview, member_index)
      is Some(length) &&
      length >= 0 &&
      rows <= limits.max_nodes - length &&
      work(length + 1) else {
      return Err(InvalidOriginal)
    }
    rows += length
    for row_index in 0..<length {
      guard @publication.effect_preview_row_correlation_wire(
          original.preview,
          member_index,
          row_index,
        )
        is Some(wire) &&
        @scalar.admit_utf8_length(wire, key_bytes) is Ok(bytes) &&
        work(bytes) else {
        return Err(InvalidOriginal)
      }
      max_correlation = Int::max(max_correlation, bytes)
    }
  }
  // The same UPDATE codec keeps the already admitted correlation String.
  // Only one parser/hash frame is active; all returned key records coexist.
  // Preserve the original parser policy and fund this input's actual span.
  guard count > 0 &&
    count <= 128 &&
    rows <= 128 / 3 &&
    fund(
      max_correlation + 320,
      Int::min(key_nodes, max_correlation) + count + 32 * rows + 4,
      key_depth + 1,
    ) &&
    work(count + rows) &&
    @effect.recover_effect_preview_apply_keys(
      original.preview,
      scope,
      count,
      Int::max(1, rows),
      count + rows,
      key_bytes,
      key_nodes,
      key_depth,
    )
    is Ok(keys) else {
    return Err(InvalidOriginal)
  }
  Ok({
    claim,
    computation,
    scoped_request: scope,
    keys,
    approval,
    account_cid: selected.account_configuration_cid,
    principal: selected.principal,
  })
}

///|
pub fn ClientEffectSavedApplication::ordered_count(
  self : ClientEffectSavedApplication,
) -> (Int, Int) {
  let mut rows = 0
  for member_index in self.keys {
    rows += member_index.length()
  }
  (self.keys.length(), rows)
}

///|
/// Borrow one checked row and the dispatch key restored in the same order.
pub fn ClientEffectSavedApplication::ordered_original(
  self : ClientEffectSavedApplication,
  member_index : Int,
  ordinal : Int,
  now_ms : Int64,
) -> (
  @publication.EffectPreviewIdentity,
  @request_scope.LogicalRequestScope,
  @effect.EffectDispatchKey,
  @canonical.CanonicalValue,
)? {
  if now_ms < 0L || now_ms >= self.claim.lease_expires_ms {
    return None
  }
  let preview = self.computation.preview
  guard self.keys.get(member_index) is Some(keys) &&
    @publication.effect_preview_ordered_row_identity(
      preview.preview,
      member_index,
      ordinal,
    )
    is Some(identity) &&
    @publication.effect_preview_row_index(
      preview.preview,
      member_index,
      identity,
    )
    is Some(raw) &&
    keys.get(raw) is Some(key) &&
    @canonical.object_field(preview.preview_original, "effects")
    is Some(@canonical.Array(effects)) &&
    @canonical.array_at(effects, member_index) is Some(effect) &&
    @canonical.object_field(effect, "changes")
    is Some(@canonical.Array(changes)) &&
    @canonical.array_at(changes, raw) is Some(row) else {
    return None
  }
  Some((preview.preview, self.scoped_request, key, row))
}

///|
/// Coordinates from the same admitted Preview and recovered member keys.
pub fn ClientEffectSavedApplication::file_member(
  self : ClientEffectSavedApplication,
  index : Int,
) -> (String, String, String, Int)? {
  let preview = self.computation.preview.preview
  guard self.keys.get(index) is Some(keys) &&
    @publication.effect_preview_member_source_binding_cid(preview, index)
    is Some(binding) &&
    @publication.effect_preview_member_resolved_contract(preview, index)
    is Some(@publication.Mapping(reference, mapping)) else {
    return None
  }
  Some((binding, reference, mapping, keys.length()))
}

///|
/// Rebind the same authenticated approval to one selected project target.
pub fn ClientEffectSavedApplication::authorize_file_target(
  self : ClientEffectSavedApplication,
  account : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  at : String,
  fund : (Int, Int, Int) -> Bool,
) -> Bool {
  let original = self.computation.preview.waiting.checkpoint
  guard @values.timestamp_epoch_milliseconds(at) is Some(now) &&
    now >= 0L &&
    now < self.claim.lease_expires_ms &&
    tuple.principal == self.principal &&
    account.configuration_cid() == self.account_cid &&
    @checkpoint.resumed_approval_current(self.approval, at) &&
    fund(
      1024 + 6 * tuple.connection.length() + 6 * tuple.resource.length(),
      272,
      16,
    ) else {
    return false
  }
  bind_client_saved_effect_target_authorization(
    account,
    tuple,
    original.artifact.checkpoint.required_artifact_cid,
    original.binding.authorization_context_cid,
    self.approval,
    self.approval.reviewer_id,
    original.artifact.checkpoint.requirements,
  )
  is Ok(_)
}

///|
/// The exact canonical CID addresses and delimiters of the waiting witness.
pub fn ClientEffectSavedApplication::empty_ledger_coordinate(
  self : ClientEffectSavedApplication,
) -> (String, Int) {
  let waiting = self.computation.preview.waiting
  let key = client_request_scope_cid(waiting.run.request)
  (
    key,
    key.length() +
    @publication.publication_contract_identity(waiting.run.definition).length() +
    waiting.checkpoint.artifact.checkpoint_cid.length() +
    3,
  )
}
