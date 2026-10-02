///|
struct ModelSlotReplayStorage {
  mut bundle : @publication.ModelCaptureBundleRead?
  mut observation : @publication.RunEvidenceValue?
  mut records : Array[@publication.RunEvidenceValue]
  count : Int
  max_slot_wire_units : Int
  mut proofs : Array[ModelAttemptRecords]?
  mut saved_admission : @publication.RunPublicationAdmission?
  mut saved_definition : @publication.PublicationContract?
  mut uses : Int
}

///|
/// Private saved observations offered by the installing capture owner after
/// authenticating their Store holdings. Structural admission is not attempt,
/// policy, accounting, execution or publication authority. Fresh bounded replay
/// still checks every saved outcome against the Program's actual call scope.
pub struct ModelSlotReplayRead {
  storage : ModelSlotReplayStorage
  mut released : Bool
}

///|
/// The ObservationSet supplies the entire ordered inventory; the bundle
/// supplies only successful responses. Start does not scan or copy either
/// inventory. Records are matched individually before their outcomes are used.
pub fn read_model_slot_replay(
  observation : @publication.RunEvidenceValue,
  records : Array[@publication.RunEvidenceValue],
  bundle : @publication.ModelCaptureBundleRead,
  max_slots : Int,
  max_slot_wire_units : Int,
) -> Result[ModelSlotReplayRead, ModelExecutionIssue] {
  if max_slots < 0 || max_slot_wire_units < 1 {
    return Err(InvalidLimits)
  }
  guard @publication.model_observation_slot_count(observation) is Some(count) else {
    return Err(OutputIdentity)
  }
  if count > max_slots {
    return Err(ItemLimit)
  }
  let successes = @publication.model_capture_bundle_count(bundle)
  if records.length() != count || successes < 0 || successes > count {
    return Err(OutputIdentity)
  }
  guard @publication.retain_model_capture_bundle_read(bundle) is Some(retained) else {
    return Err(OutputIdentity)
  }
  Ok({
    storage: {
      bundle: Some(retained),
      observation: Some(observation),
      records,
      count,
      max_slot_wire_units,
      proofs: None,
      saved_admission: None,
      saved_definition: None,
      uses: 1,
    },
    released: false,
  })
}

///|
/// Stored leaves are observations, not grants. Their exact chain is checked
/// per slot by the shared verifier before fresh bounded replay adopts it.
pub(all) struct ModelAttemptRecords {
  attempt : @publication.RunEvidenceValue
  accounting : @publication.RunEvidenceValue
  outcome : @publication.RunEvidenceValue
  authority : @publication.RunEvidenceValue
}

///|
pub fn read_verified_model_slot_replay(
  observation : @publication.RunEvidenceValue,
  records : Array[@publication.RunEvidenceValue],
  bundle : @publication.ModelCaptureBundleRead,
  proofs : Array[ModelAttemptRecords],
  saved_admission : @publication.RunPublicationAdmission,
  saved_definition : @publication.PublicationContract,
  max_slots : Int,
  max_slot_wire_units : Int,
) -> Result[ModelSlotReplayRead, ModelExecutionIssue] {
  if proofs.length() != records.length() {
    return Err(OutputIdentity)
  }
  let read = match
    read_model_slot_replay(
      observation, records, bundle, max_slots, max_slot_wire_units,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let storage = read.storage
  storage.proofs = Some(proofs)
  storage.saved_admission = Some(saved_admission)
  storage.saved_definition = Some(saved_definition)
  Ok(read)
}

///|
pub fn model_slot_replay_count(read : ModelSlotReplayRead) -> Int? {
  if read.released ||
    read.storage.observation is None ||
    read.storage.bundle is None ||
    read.storage.records.length() != read.storage.count {
    None
  } else {
    Some(read.storage.count)
  }
}

///|
pub fn retain_model_slot_replay(
  read : ModelSlotReplayRead,
) -> ModelSlotReplayRead? {
  if model_slot_replay_count(read) is None || read.storage.uses == 2147483647 {
    return None
  }
  read.storage.uses += 1
  Some({ storage: read.storage, released: false, })
}

///|
pub fn release_model_slot_replay(read : ModelSlotReplayRead) -> Bool {
  if read.released {
    return false
  }
  read.released = true
  read.storage.uses -= 1
  if read.storage.uses == 0 {
    if read.storage.bundle is Some(bundle) {
      @publication.release_model_capture_bundle_read(bundle) |> ignore
    }
    read.storage.bundle = None
    read.storage.observation = None
    // Do not clear an array belonging to the caller or another Store owner.
    read.storage.records = []
    read.storage.proofs = None
    read.storage.saved_admission = None
    read.storage.saved_definition = None
  }
  true
}

///|
fn restored_slot_binding(
  read : ModelSlotReplayRead,
  index : Int,
  call : @publication.RunEvidenceValue,
) -> Result[@publication.BoundModelSlotCapture, ModelExecutionIssue] {
  guard model_slot_replay_count(read) is Some(_) &&
    read.storage.observation is Some(observation) &&
    read.storage.records.get(index) is Some(record) else {
    return Err(OutputIdentity)
  }
  if @publication.run_evidence_value_json(record).length() >
    read.storage.max_slot_wire_units {
    return Err(RequestLimit)
  }
  if @publication.model_observation_slot_at(observation, index) !=
    Some(@publication.run_evidence_value_identity(record)) {
    return Err(
      InvocationEvidence(
        @publication.RunEvidenceReferenceMismatch("model_slot_capture_cids"),
      ),
    )
  }
  let binding = match @publication.bind_model_slot_capture(call, record) {
    Ok(value) => value
    Err(issue) => return Err(InvocationEvidence(issue))
  }
  if read.storage.proofs is Some(proofs) {
    guard proofs.length() == read.storage.count &&
      proofs.get(index) is Some(proof) &&
      read.storage.saved_admission is Some(admission) &&
      read.storage.saved_definition is Some(definition) else {
      return Err(OutputIdentity)
    }
    for
      leaf in [proof.attempt, proof.accounting, proof.outcome, proof.authority] {
      if @publication.run_evidence_value_json(leaf).length() >
        read.storage.max_slot_wire_units {
        return Err(RequestLimit)
      }
    }
    match
      @publication.bind_model_slot_attempt_evidence(
        binding,
        proof.attempt,
        proof.accounting,
        proof.outcome,
        proof.authority,
        admission,
        definition,
      ) {
      Err(issue) => return Err(InvocationEvidence(issue))
      Ok(_) => ()
    }
  }
  Ok(binding)
}
