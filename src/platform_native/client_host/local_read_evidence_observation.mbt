///|
// A confirmed immutable packet/holding observation in the existing command.
// Only successful Journal COMMIT/read return supplies this DATA. Permission,
// receiver lifetime and the physical Journal fence remain separate checks.
priv struct NativeLocalReadEvidenceObservation {
  binding : NativeLocalReadPolicyBinding
  original : @host.ClientRequestIdentity
  request : @result_access.NativeResultAccessRequest
  bodies : NativeLocalReadAdmissionOriginals
  admission : @result_access.NativeResultReadAdmission
}

///|
fn NativeLocalJournalCapture::clear_read_evidence_observations(
  self : NativeLocalJournalCapture,
) -> Unit {
  self.read_evidence.clear()
  self.read_evidence.shrink_to_fit()
}

///|
fn NativeLocalReadPolicyBinding::observed_read_evidence(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
  bodies : NativeLocalReadAdmissionOriginals,
) -> @result_access.NativeResultReadAdmission? {
  guard self.capture is Some(owner) &&
    !owner.closing &&
    owner.read_operation_issue is None &&
    owner.read_callback_active &&
    owner.read_facts_valid &&
    owner.opening is JournalAcquired(host) &&
    physical_equal(host, self.host) &&
    host.journal.operation_active else {
    return None
  }
  for observed in owner.read_evidence {
    if physical_equal(observed.binding, self) &&
      @host.client_request_identity_relation(observed.original, original) ==
      @host.SameRequest &&
      local_read_file_same_request(observed.request, facts.request) &&
      observed.bodies.authorization.cid == bodies.authorization.cid &&
      observed.bodies.authorization.wire == bodies.authorization.wire &&
      observed.bodies.ceiling.cid == bodies.ceiling.cid &&
      observed.bodies.ceiling.wire == bodies.ceiling.wire &&
      observed.bodies.egress.cid == bodies.egress.cid &&
      observed.bodies.egress.wire == bodies.egress.wire {
      return Some(observed.admission)
    }
  }
  None
}

///|
// Called after the original transaction has confirmed its return, never from
// the preimage builder or before COMMIT. A full slot list merely omits reuse;
// it does not change the existing evidence quota or refuse a valid operation.
fn NativeLocalReadPolicyBinding::remember_read_evidence(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
  bodies : NativeLocalReadAdmissionOriginals,
  admission : @result_access.NativeResultReadAdmission,
) -> Unit {
  guard self.capture is Some(owner) &&
    !owner.closing &&
    owner.read_operation_issue is None &&
    owner.read_callback_active &&
    owner.read_facts_valid &&
    owner.opening is JournalAcquired(host) &&
    physical_equal(host, self.host) &&
    host.journal.operation_active else {
    return
  }
  if owner.read_evidence.length() < 64 &&
    self.observed_read_evidence(original, facts, bodies) is None {
    owner.read_evidence.push({
      binding: self,
      original,
      request: facts.request,
      bodies,
      admission,
    })
  }
}

///|
fn NativeLocalReadPolicyBinding::forget_read_evidence(
  self : NativeLocalReadPolicyBinding,
) -> Unit {
  if self.capture is Some(owner) {
    owner.clear_read_evidence_observations()
  }
}
