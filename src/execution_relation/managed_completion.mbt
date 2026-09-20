///|
/// An installed Host verifier for one managed execution attempt. The verifier
/// must cover demanded semantics/failures, selected identity obligations,
/// authorization, resource settlement and exact immutable output correspondence.
/// Receiving valid values or retaining a file alone cannot satisfy this port.
struct ManagedCompletionPort[P, T] {
  profile : ManagedExecutionProfile
  preparation : CompletionPreparation
  target : @pipeline.Target
  inputs : Array[ProducerRead]
  managed_inputs : Array[ManagedProducerRead[T]]
  common_inputs : Array[ManagedInputBinding]
  bindings : Array[ProducerBindingIdentity]
  verify : (P) -> ManagedRetainedOutput[T]?
  obligations : ManagedObligations
  identity_issuers : Array[ManagedIdentityIssuer[T]]
  mut attempt : ManagedExecutionAttempt?
  mut open : Bool
  mut verifying : Bool
  mut revoked : Bool
}

///|
/// One opaque physical execution attempt. Common execution management issues
/// this token when it admits a task; preparations and output generations do
/// not manufacture or substitute it.
struct ManagedExecutionAttempt {
  identity : Ref[Unit]
}

///|
/// Trusted common-Host construction point. A token has no completion or CID
/// authority until the physical strategy binds it to its admitted task.
pub fn issue_managed_execution_attempt() -> ManagedExecutionAttempt {
  { identity: Ref(()), }
}

///|
pub fn managed_execution_attempt_same(
  left : ManagedExecutionAttempt,
  right : ManagedExecutionAttempt,
) -> Bool {
  physical_equal(left.identity, right.identity)
}

///|
priv struct ManagedCompletedIdentity {
  requirement : ManagedIdentityRequirement
  canonical_contract_cid : Ref[String?]
  cid : Ref[String?]
  establishing : Ref[Ref[Unit]?]
}

///|
/// Host-registered finite identity implementation. This is issuance authority,
/// not an identity result, and is fixed to one canonical preimage contract.
struct ManagedIdentityIssuanceCapability {
  identity : Ref[Unit]
  domain : ManagedIdentityDomain
  subject : ManagedIdentitySubject
  occurrence : ManagedResultOccurrence?
  canonical_contract_cid : String
}

///|
/// Attempt authority is derived before an output generation exists. It binds
/// the registered implementation to the exact checked preparation and demand.
struct ManagedIdentityAttemptPermit {
  capability : ManagedIdentityIssuanceCapability
  attempt : ManagedExecutionAttempt
  preparation : CompletionPreparation
  requirement : ManagedIdentityRequirement
  mut bound : Bool
}

///|
/// The issuer exists only after the exact retained generation is known. The
/// callback computes a CID; common code owns authority and canonical scope.
struct ManagedIdentityIssuer[T] {
  permit : ManagedIdentityAttemptPermit
  material : ManagedRetainedOutput[T]
  issue : (ManagedRetainedOutput[T]) -> String?
  valid : Bool
}

///|
pub fn register_managed_identity_issuance_capability(
  domain : ManagedIdentityDomain,
  subject : ManagedIdentitySubject,
  occurrence : ManagedResultOccurrence?,
  canonical_contract_cid : String,
) -> Result[ManagedIdentityIssuanceCapability, ManagedIdentityIssuanceIssue] {
  let registered_contract = match domain {
    OrderedRows => Some(ordered_rows_canonical_contract_cid())
    LogicalRelation => Some(logical_relation_canonical_contract_cid())
    _ => None
  }
  if !valid_managed_cid(canonical_contract_cid) ||
    registered_contract != Some(canonical_contract_cid) {
    return Err(InvalidCapability)
  }
  match (subject, occurrence) {
    (NamedResult, Some(_)) | (_, None) => ()
    _ => return Err(InvalidCapability)
  }
  Ok({ identity: Ref(()), domain, subject, occurrence, canonical_contract_cid, })
}

///|
pub fn managed_identity_issuance_capability_same(
  left : ManagedIdentityIssuanceCapability,
  right : ManagedIdentityIssuanceCapability,
) -> Bool {
  physical_equal(left.identity, right.identity)
}

///|
pub fn authorize_managed_identity_attempt(
  capability : ManagedIdentityIssuanceCapability,
  preparation : CompletionPreparation,
  requirement : ManagedIdentityRequirement,
) -> Result[ManagedIdentityAttemptPermit, ManagedIdentityIssuanceIssue] {
  authorize_managed_identity_execution_attempt(
    capability,
    issue_managed_execution_attempt(),
    preparation,
    requirement,
  )
}

///|
/// Common execution management supplies the exact admitted attempt. The older
/// detached authorization entry remains source-compatible for standalone
/// tooling, but its fresh token can never match a common task execution.
pub fn authorize_managed_identity_execution_attempt(
  capability : ManagedIdentityIssuanceCapability,
  attempt : ManagedExecutionAttempt,
  preparation : CompletionPreparation,
  requirement : ManagedIdentityRequirement,
) -> Result[ManagedIdentityAttemptPermit, ManagedIdentityIssuanceIssue] {
  let owner = completion_preparation_owner(preparation)
  if capability.domain != requirement.domain ||
    capability.subject != requirement.subject ||
    !managed_result_occurrence_equal(
      capability.occurrence,
      requirement.occurrence,
    ) {
    return Err(ForeignRequirement)
  }
  if requirement.occurrence is Some(occurrence) &&
    !physical_equal(occurrence.owner, owner) {
    return Err(ForeignAttempt)
  }
  Ok({ capability, attempt, preparation, requirement, bound: false, })
}

///|
pub fn[T] bind_managed_identity_issuer(
  permit : ManagedIdentityAttemptPermit,
  material : ManagedRetainedOutput[T],
  issue : (ManagedRetainedOutput[T]) -> String?,
) -> ManagedIdentityIssuer[T] {
  match try_bind_managed_identity_issuer(permit, material, issue) {
    Ok(value) => value
    Err(_) => { permit, material, issue, valid: false, }
  }
}

///|
/// Bind once to one exact retained generation. A retry or transfer requires a
/// new attempt permit; an arbitrary material cannot consume the old permit.
pub fn[T] try_bind_managed_identity_issuer(
  permit : ManagedIdentityAttemptPermit,
  material : ManagedRetainedOutput[T],
  issue : (ManagedRetainedOutput[T]) -> String?,
) -> Result[ManagedIdentityIssuer[T], ManagedIdentityIssuanceIssue] {
  if permit.bound {
    return Err(ForeignMaterial)
  }
  if managed_retained_output_payload(material) is None {
    return Err(ForeignMaterial)
  }
  permit.bound = true
  Ok({ permit, material, issue, valid: true, })
}

///|
/// New-profile component completion, deliberately not CompletedOutput or a
/// legacy Artifact. No conversion exists by relabelling a physical digest.
/// Input provenance retains binding identities, not input read handles. The
/// material still owns backing storage needed by its particular representation.
struct ManagedCompletedOutput[T] {
  identity : Ref[Unit]
  lifecycle : @managed_carrier.Completed[ManagedOutputValueReceipt, T]
  profile : ManagedExecutionProfile
  preparation : CompletionPreparation
  target : @pipeline.Target
  bindings : Array[ProducerBindingIdentity]
  managed_bindings : Array[Ref[Unit]]
  material : ManagedRetainedOutput[T]
  identities : Array[ManagedCompletedIdentity]
  identity_issuers : Array[ManagedIdentityIssuer[T]]
  attempt : ManagedExecutionAttempt?
}

///|
/// Type-erased occurrence reference for common scheduling and lifetime
/// ownership. It is not content identity, a portable handle, read authority or
/// a replacement for the typed completed output. Only a verified managed
/// completion can create it.
struct ManagedCompletionReference {
  lifecycle : @managed_carrier.CompletionReference
}

///|
pub fn[P, T] prepare_managed_completion_port(
  profile : ManagedExecutionProfile,
  preparation : CompletionPreparation,
  target : @pipeline.Target,
  max_entries : Int,
  max_name_bytes : Int,
  verify : (P) -> ManagedRetainedOutput[T]?,
  inputs? : Array[ProducerRead],
  managed_inputs? : Array[ManagedProducerRead[T]],
  common_inputs? : Array[ManagedInputBinding],
  obligations? : ManagedObligations,
  identity_issuer? : ManagedIdentityIssuer[T],
  identity_issuers? : Array[ManagedIdentityIssuer[T]],
  attempt? : ManagedExecutionAttempt,
) -> Result[ManagedCompletionPort[P, T], TrustedOutputIssue] {
  // A fixed-input set has one explicit provenance family, never a partial mix
  // that silently drops the remaining ports. Acquisition may omit both.
  if (
      inputs is Some(_) &&
      (managed_inputs is Some(_) || common_inputs is Some(_))
    ) ||
    (managed_inputs is Some(_) && common_inputs is Some(_)) {
    return Err(ForeignInputs)
  }
  let (_, _, bindings) = match
    validate_trusted_output_contract(
      preparation, target, max_entries, max_name_bytes, inputs,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if managed_inputs is Some(values) {
    if values.length() > max_entries {
      return Err(Limit)
    }
    let owner = completion_preparation_owner(preparation)
    if values.length() !=
      @lower.preparation_input_count(@lower.bound_preparation(owner)) {
      return Err(ForeignInputs)
    }
    for index, input in values {
      if !physical_equal(input.receiver, owner) ||
        input.input_index != index ||
        input.output.profile.cid != profile.cid ||
        !managed_producer_read_available(input) {
        return Err(ForeignInputs)
      }
    }
  }
  let selected_common_inputs = match common_inputs {
    Some(values) => values.copy()
    None =>
      managed_inputs
      .map(values => values.map(input => managed_relation_input_binding(input)))
      .unwrap_or([])
  }
  if common_inputs is Some(_) {
    if selected_common_inputs.length() > max_entries {
      return Err(Limit)
    }
    let owner = completion_preparation_owner(preparation)
    if selected_common_inputs.length() !=
      @lower.preparation_input_count(@lower.bound_preparation(owner)) {
      return Err(ForeignInputs)
    }
    for index, input in selected_common_inputs {
      if !managed_input_binding_matches_input(input, owner, index) ||
        managed_input_binding_profile_cid(input) != profile.cid {
        return Err(ForeignInputs)
      }
    }
  }
  let owner = completion_preparation_owner(preparation)
  let selected_obligations = obligations.unwrap_or_else(() => {
    process_managed_obligations(owner)
  })
  if !physical_equal(managed_obligations_owner(selected_obligations), owner) {
    return Err(ForeignOutput)
  }
  let selected_identity_issuers = identity_issuers
    .map(values => values.copy())
    .unwrap_or([])
  if identity_issuer is Some(issuer) {
    selected_identity_issuers.push(issuer)
  }
  for index, issuer in selected_identity_issuers {
    if !issuer.valid ||
      !physical_equal(issuer.permit.preparation, preparation) ||
      !selected_obligations.identities.any(requirement => {
        managed_identity_requirement_equal(
          requirement,
          issuer.permit.requirement,
        )
      }) {
      return Err(ForeignOutput)
    }
    for prior in 0..<index {
      if managed_identity_requirement_equal(
          selected_identity_issuers[prior].permit.requirement,
          issuer.permit.requirement,
        ) {
        return Err(ForeignOutput)
      }
    }
  }
  let selected_attempt = match attempt {
    Some(value) => Some(value)
    None =>
      if selected_identity_issuers.is_empty() {
        None
      } else {
        Some(selected_identity_issuers[0].permit.attempt)
      }
  }
  if selected_attempt is Some(selected) {
    for issuer in selected_identity_issuers {
      if !managed_execution_attempt_same(selected, issuer.permit.attempt) {
        return Err(ForeignOutput)
      }
    }
  }
  Ok({
    profile,
    preparation,
    target,
    bindings,
    inputs: inputs.map(values => values.copy()).unwrap_or([]),
    managed_inputs: managed_inputs.map(values => values.copy()).unwrap_or([]),
    common_inputs: selected_common_inputs,
    verify,
    obligations: selected_obligations,
    identity_issuers: selected_identity_issuers,
    attempt: selected_attempt,
    open: true,
    verifying: false,
    revoked: false,
  })
}

///|
/// Bind a port prepared before common task admission to the exact admitted
/// attempt. Rebinding, including to another retry, is rejected.
pub fn[P, T] bind_managed_completion_attempt(
  port : ManagedCompletionPort[P, T],
  attempt : ManagedExecutionAttempt,
) -> Bool {
  if !port.open || port.attempt is Some(_) {
    return false
  }
  for issuer in port.identity_issuers {
    if !managed_execution_attempt_same(issuer.permit.attempt, attempt) {
      return false
    }
  }
  port.attempt = Some(attempt)
  true
}

///|
pub fn[P, T] cancel_managed_completion_port(
  port : ManagedCompletionPort[P, T],
) -> Bool {
  if port.revoked || (!port.open && !port.verifying) {
    return false
  }
  port.open = false
  port.revoked = true
  true
}

///|
pub fn[P, T] complete_managed_output(
  port : ManagedCompletionPort[P, T],
  proof : P,
) -> Result[ManagedCompletedOutput[T], TrustedOutputIssue] {
  if !port.open {
    return Err(Unverified)
  }
  port.open = false
  port.verifying = true
  let result = verify_managed_completion_material(port, proof)
  port.verifying = false
  if port.revoked {
    return Err(Unverified)
  }
  let material = match result {
    Ok(material) => material
    Err(issue) => return Err(issue)
  }
  for issuer in port.identity_issuers {
    if !physical_equal(issuer.material, material) {
      return Err(ForeignOutput)
    }
  }
  let lifecycle = match @managed_carrier.complete(material.core) {
    Ok(value) => value
    Err(_) => return Err(Unverified)
  }
  Ok({
    identity: Ref(()),
    lifecycle,
    profile: port.profile,
    preparation: port.preparation,
    target: port.target,
    bindings: port.bindings,
    managed_bindings: port.common_inputs.map(input => input.identity),
    material,
    identities: managed_obligations_identities(port.obligations).map(requirement => {
      requirement,
      canonical_contract_cid: Ref(None),
      cid: Ref(None),
      establishing: Ref(None),
    }),
    identity_issuers: port.identity_issuers,
    attempt: port.attempt,
  })
}

///|
fn valid_managed_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < 71; index = index + 1 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn[T] managed_completed_identity_record(
  output : ManagedCompletedOutput[T],
  domain : ManagedIdentityDomain,
  subject : ManagedIdentitySubject,
  occurrence : ManagedResultOccurrence?,
) -> ManagedCompletedIdentity? {
  for identity in output.identities {
    if identity.requirement.domain == domain &&
      identity.requirement.subject == subject &&
      managed_result_occurrence_equal(
        identity.requirement.occurrence,
        occurrence,
      ) {
      return Some(identity)
    }
  }
  None
}

///|
fn[T] managed_completed_identity_issuer(
  output : ManagedCompletedOutput[T],
  requirement : ManagedIdentityRequirement,
) -> ManagedIdentityIssuer[T]? {
  for issuer in output.identity_issuers {
    if managed_identity_requirement_equal(
        issuer.permit.requirement,
        requirement,
      ) {
      return Some(issuer)
    }
  }
  None
}

///|
pub fn[T] managed_completed_identity_status(
  output : ManagedCompletedOutput[T],
  domain : ManagedIdentityDomain,
  subject : ManagedIdentitySubject,
) -> ManagedIdentityStatus? {
  guard managed_completed_identity_record(output, domain, subject, None)
    is Some(identity) else {
    return None
  }
  let retained = managed_completed_output_available(output)
  match (identity.canonical_contract_cid.val, identity.cid.val, retained) {
    (Some(contract), Some(cid), true) =>
      Some(EstablishedSourceRetained(contract, cid))
    (Some(contract), Some(cid), false) =>
      Some(EstablishedSourceUnavailable(contract, cid))
    (None, None, true) => Some(UnestablishedSourceRetained)
    (None, None, false) => Some(UnestablishedSourceUnavailable)
    _ => None
  }
}

///|
/// Inspect one exact occurrence-aware identity requirement. This is required
/// for Named Results because aliases of one producer port remain distinct
/// publication occurrences.
pub fn[T] managed_completed_identity_requirement_status(
  output : ManagedCompletedOutput[T],
  requirement : ManagedIdentityRequirement,
) -> ManagedIdentityStatus? {
  guard managed_completed_identity_record(
      output,
      requirement.domain,
      requirement.subject,
      requirement.occurrence,
    )
    is Some(identity) &&
    managed_identity_requirement_equal(identity.requirement, requirement) else {
    return None
  }
  let retained = managed_completed_output_available(output)
  match (identity.canonical_contract_cid.val, identity.cid.val, retained) {
    (Some(contract), Some(cid), true) =>
      Some(EstablishedSourceRetained(contract, cid))
    (Some(contract), Some(cid), false) =>
      Some(EstablishedSourceUnavailable(contract, cid))
    (None, None, true) => Some(UnestablishedSourceRetained)
    (None, None, false) => Some(UnestablishedSourceUnavailable)
    _ => None
  }
}

///|
/// Establish one delayed logical identity through the verifier installed on
/// this exact completion. Failure never revokes the already valid completion.
pub fn[T] establish_managed_completed_identity(
  output : ManagedCompletedOutput[T],
  domain : ManagedIdentityDomain,
  subject : ManagedIdentitySubject,
) -> Result[Unit, ManagedIdentityEstablishmentIssue] {
  guard managed_completed_identity_record(output, domain, subject, None)
    is Some(identity) else {
    return Err(UnknownIdentity)
  }
  match (identity.canonical_contract_cid.val, identity.cid.val) {
    (Some(_), Some(_)) => return Ok(())
    (None, None) => ()
    _ => return Err(ConflictingIdentity)
  }
  if !managed_completed_output_available(output) {
    return Err(SourceUnavailable)
  }
  establish_managed_completed_identity_record(output, identity)
}

///|
/// Establish one exact occurrence-aware identity requirement. Each Named
/// Result occurrence consumes only its own registered issuer.
pub fn[T] establish_managed_completed_identity_requirement(
  output : ManagedCompletedOutput[T],
  requirement : ManagedIdentityRequirement,
) -> Result[Unit, ManagedIdentityEstablishmentIssue] {
  guard managed_completed_identity_record(
      output,
      requirement.domain,
      requirement.subject,
      requirement.occurrence,
    )
    is Some(identity) &&
    managed_identity_requirement_equal(identity.requirement, requirement) else {
    return Err(UnknownIdentity)
  }
  establish_managed_completed_identity_record(output, identity)
}

///|
fn[T] establish_managed_completed_identity_record(
  output : ManagedCompletedOutput[T],
  identity : ManagedCompletedIdentity,
) -> Result[Unit, ManagedIdentityEstablishmentIssue] {
  match (identity.canonical_contract_cid.val, identity.cid.val) {
    (Some(_), Some(_)) => return Ok(())
    (None, None) => ()
    _ => return Err(ConflictingIdentity)
  }
  if identity.establishing.val is Some(_) {
    return Err(ConflictingIdentity)
  }
  if !managed_completed_output_available(output) {
    return Err(SourceUnavailable)
  }
  guard managed_completed_identity_issuer(output, identity.requirement)
    is Some(issuer) else {
    return Err(IssuerUnavailable)
  }
  if !physical_equal(issuer.permit.preparation, output.preparation) ||
    output.attempt is None ||
    !managed_execution_attempt_same(
      output.attempt.unwrap(),
      issuer.permit.attempt,
    ) ||
    !physical_equal(issuer.material, output.material) ||
    !managed_identity_requirement_equal(
      issuer.permit.requirement,
      identity.requirement,
    ) {
    return Err(UnverifiedIdentity)
  }
  let token = Ref(())
  identity.establishing.val = Some(token)
  let issued = (issuer.issue)(output.material)
  guard identity.establishing.val is Some(active) &&
    physical_equal(active, token) else {
    return Err(ConflictingIdentity)
  }
  guard issued is Some(cid) else {
    identity.establishing.val = None
    return Err(UnverifiedIdentity)
  }
  let canonical_contract_cid = issuer.permit.capability.canonical_contract_cid
  if !valid_managed_cid(canonical_contract_cid) || !valid_managed_cid(cid) {
    identity.establishing.val = None
    return Err(InvalidIdentity)
  }
  if !managed_completed_output_available(output) {
    identity.establishing.val = None
    return Err(UnverifiedIdentity)
  }
  match (identity.canonical_contract_cid.val, identity.cid.val) {
    (None, None) => ()
    _ => {
      identity.establishing.val = None
      return Err(ConflictingIdentity)
    }
  }
  identity.canonical_contract_cid.val = Some(canonical_contract_cid)
  identity.cid.val = Some(cid)
  identity.establishing.val = None
  Ok(())
}

///|
pub fn[T] managed_completed_output_matches_attempt(
  output : ManagedCompletedOutput[T],
  attempt : ManagedExecutionAttempt,
) -> Bool {
  output.attempt is Some(actual) &&
  managed_execution_attempt_same(actual, attempt)
}

///|
/// Check the exact common boundary before a CID-dependent operation,
/// publication or irreversible source discard.
pub fn[T] managed_completed_deadline_satisfied(
  output : ManagedCompletedOutput[T],
  deadline : ManagedIdentityDeadline,
) -> Bool {
  for identity in output.identities {
    if identity.requirement.need is EstablishedBy(required) &&
      required == deadline &&
      (identity.canonical_contract_cid.val is None || identity.cid.val is None) {
      return false
    }
  }
  true
}

///|
fn[P, T] verify_managed_completion_material(
  port : ManagedCompletionPort[P, T],
  proof : P,
) -> Result[ManagedRetainedOutput[T], TrustedOutputIssue] {
  for input in port.inputs {
    if !producer_read_available(input) {
      return Err(ForeignInputs)
    }
  }
  for input in port.managed_inputs {
    if !managed_producer_read_available(input) {
      return Err(ForeignInputs)
    }
  }
  for input in port.common_inputs {
    if !managed_input_binding_available(input) {
      return Err(ForeignInputs)
    }
  }
  let verified = (port.verify)(proof)
  if port.revoked {
    return Err(Unverified)
  }
  guard verified is Some(material) else { return Err(Unverified) }
  let receipt = material.receipt
  let owner = completion_preparation_owner(port.preparation)
  if !managed_output_value_receipt_matches(receipt, owner, port.target) {
    return Err(ForeignOutput)
  }
  guard @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      port.target,
    )
    is Some(schema) &&
    physical_equal(schema, receipt.schema) else {
    return Err(ForeignOutput)
  }
  let live = @managed_carrier.retained_available(material.core)
  if port.revoked || !live {
    return Err(Unverified)
  }
  for input in port.inputs {
    if !producer_read_available(input) {
      return Err(ForeignInputs)
    }
  }
  for input in port.managed_inputs {
    if !managed_producer_read_available(input) {
      return Err(ForeignInputs)
    }
  }
  for input in port.common_inputs {
    if !managed_input_binding_available(input) {
      return Err(ForeignInputs)
    }
  }
  Ok(material)
}

///|
pub fn[T] managed_completed_profile_cid(
  output : ManagedCompletedOutput[T],
) -> String {
  output.profile.cid
}

///|
/// Historical occurrence identity, not content equality or current permission.
pub fn[T] managed_completed_same_occurrence(
  left : ManagedCompletedOutput[T],
  right : ManagedCompletedOutput[T],
) -> Bool {
  physical_equal(left.identity, right.identity)
}

///|
pub fn[T] managed_completed_output_available(
  output : ManagedCompletedOutput[T],
) -> Bool {
  @managed_carrier.completed_available(output.lifecycle)
}

///|
/// Common schedulers retain only this occurrence reference. The concrete
/// representation remains owned by the installed Host and must be supplied at
/// each typed consumer boundary.
pub fn[T] managed_completed_reference(
  output : ManagedCompletedOutput[T],
) -> ManagedCompletionReference {
  { lifecycle: @managed_carrier.completion_reference(output.lifecycle), }
}

///|
pub fn managed_completed_reference_available(
  reference : ManagedCompletionReference,
) -> Bool {
  @managed_carrier.completion_reference_available(reference.lifecycle)
}

///|
pub fn managed_completed_reference_same(
  left : ManagedCompletionReference,
  right : ManagedCompletionReference,
) -> Bool {
  @managed_carrier.completion_reference_same(left.lifecycle, right.lifecycle)
}

///|
pub fn[T] managed_completed_reference_matches(
  reference : ManagedCompletionReference,
  output : ManagedCompletedOutput[T],
) -> Bool {
  @managed_carrier.completion_reference_matches(
    reference.lifecycle,
    output.lifecycle,
  )
}

///|
pub fn[T] managed_completed_output_storage_bytes(
  output : ManagedCompletedOutput[T],
) -> Int64? {
  managed_retained_output_storage_bytes(output.material)
}

///|
pub fn[T] managed_completed_output_row_count(
  output : ManagedCompletedOutput[T],
) -> Int {
  output.material.receipt.rows
}

///|
pub fn[T] managed_completed_output_matches_port(
  output : ManagedCompletedOutput[T],
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
) -> Bool {
  physical_equal(completion_preparation_owner(output.preparation), owner) &&
  output.target == target &&
  managed_completed_output_available(output)
}

///|
/// Historical input binding only; completed independent outputs do not borrow
/// current upstream liveness. New uses still need their own admission.
pub fn[T] managed_completed_output_matches_inputs(
  output : ManagedCompletedOutput[T],
  inputs : Array[ProducerRead],
) -> Bool {
  if !output.managed_bindings.is_empty() ||
    inputs.length() != output.bindings.length() {
    return false
  }
  for index, binding in output.bindings {
    if !physical_equal(inputs[index].bound.identity, binding) {
      return false
    }
  }
  true
}

///|
/// Historical checked managed use-sites. Does not require released upstream
/// storage to remain alive after an independent downstream output completes.
pub fn[T] managed_completed_output_matches_managed_inputs(
  output : ManagedCompletedOutput[T],
  inputs : Array[ManagedProducerRead[T]],
) -> Bool {
  if !output.bindings.is_empty() ||
    inputs.length() != output.managed_bindings.length() {
    return false
  }
  for index, binding in output.managed_bindings {
    if !physical_equal(inputs[index].identity, binding) {
      return false
    }
  }
  true
}

///|
pub fn[T] managed_completed_output_matches_common_inputs(
  output : ManagedCompletedOutput[T],
  inputs : Array[ManagedInputBinding],
) -> Bool {
  if !output.bindings.is_empty() ||
    inputs.length() != output.managed_bindings.length() {
    return false
  }
  for index, binding in output.managed_bindings {
    if !physical_equal(inputs[index].identity, binding) {
      return false
    }
  }
  true
}

///|
pub fn[T] managed_completed_output_matches_material(
  output : ManagedCompletedOutput[T],
  material : ManagedRetainedOutput[T],
) -> Bool {
  physical_equal(output.material, material) &&
  managed_completed_output_available(output)
}
