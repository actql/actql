///|
priv struct ResultEvidenceInputs {
  definitions : Array[PublicationContract]
  artifacts : Array[PublicationContract]
  derivations : Array[PublicationContract]
  orderings : Array[PublicationContract]
  retentions : Array[PublicationContract]
}

///|
priv enum ResultEvidencePhase {
  Begin
  Retentions(Int, Int)
  Initialize(Int, Int)
  Artifact(Int)
  Lookup(Int, String, Int, Int, Int)
  Use
  Ordering
  ArtifactEvidence(ResultArtifactCheck)
  Done
}

///|
/// Resolve the existing evidence set incrementally. Arrays are borrowed;
/// only the three occurrence-use inventories belong to this continuation.
priv struct ResultEvidencePreparation {
  mut inputs : ResultEvidenceInputs?
  max_workspace : Int?
  derivations_used : Array[Bool]
  orderings_used : Array[Bool]
  retentions_used : Array[Bool]
  mut retention_count : Int
  mut artifact : Int
  mut definition : Int
  mut ordering : Int
  mut derivation : Int
  mut retention : Int
  mut phase : ResultEvidencePhase
  mut live : Int64
  mut peak : Int64
  mut closed : Bool
}

///|
fn start_result_evidence_preparation(
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  derivations : Array[PublicationContract],
  orderings : Array[PublicationContract],
  retentions : Array[PublicationContract],
  max_workspace : Int?,
) -> ResultEvidencePreparation {
  {
    inputs: Some({ definitions, artifacts, derivations, orderings, retentions, }),
    max_workspace,
    derivations_used: [],
    orderings_used: [],
    retentions_used: [],
    retention_count: 0,
    artifact: 0,
    definition: -1,
    ordering: -1,
    derivation: -1,
    retention: -1,
    phase: Begin,
    live: 16L,
    peak: 16L,
    closed: false,
  }
}

///|
fn ResultEvidencePreparation::reserve(
  self : ResultEvidencePreparation,
  slots : Int,
) -> Result[Unit, PublicationCommitIssue] {
  if self.max_workspace is Some(limit) &&
    slots.to_int64() > limit.to_int64() - self.live {
    return Err(CommitEncoding)
  }
  self.live += slots.to_int64()
  if self.live > self.peak {
    self.peak = self.live
  }
  Ok(())
}

///|
fn ResultEvidencePreparation::step(
  self : ResultEvidencePreparation,
) -> Result[Unit, PublicationCommitIssue] {
  let inputs = self.inputs.unwrap()
  match self.phase {
    Begin => {
      match self.reserve(0) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      if inputs.definitions.length() != inputs.artifacts.length() ||
        inputs.artifacts.length() != inputs.derivations.length() ||
        inputs.artifacts.length() != inputs.orderings.length() ||
        (inputs.artifacts.length() > 0 && inputs.retentions.is_empty()) {
        return Err(CommitResultEvidence(ResultEvidenceCount))
      }
      self.phase = Retentions(0, 0)
    }
    Retentions(index, prior) =>
      if index == inputs.retentions.length() {
        self.phase = Initialize(0, 0)
      } else if prior < index {
        if inputs.retentions[prior].identity ==
          inputs.retentions[index].identity {
          return Err(CommitResultEvidence(ResultEvidenceDuplicate))
        }
        self.phase = Retentions(index, prior + 1)
      } else {
        match self.reserve(1) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
        self.retentions_used.push(false)
        self.phase = Retentions(index + 1, 0)
      }
    Initialize(kind, index) => {
      let flags = if kind == 0 {
        self.derivations_used
      } else {
        self.orderings_used
      }
      if index == inputs.artifacts.length() {
        self.phase = if kind == 0 { Initialize(1, 0) } else { Artifact(0) }
      } else {
        match self.reserve(1) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
        flags.push(false)
        self.phase = Initialize(kind, index + 1)
      }
    }
    Artifact(index) =>
      if index == inputs.artifacts.length() {
        if self.retention_count != inputs.retentions.length() {
          return Err(CommitResultEvidence(ResultEvidenceCount))
        }
        self.phase = Done
      } else {
        self.artifact = index
        guard contract_string(inputs.artifacts[index], "result_definition_cid")
          is Some(identity) else {
          return Err(CommitResultEvidence(ResultEvidenceMissingDefinition))
        }
        self.phase = Lookup(0, identity, 0, -1, 0)
      }
    Lookup(kind, identity, index, found, count) => {
      let contracts = match kind {
        0 => inputs.definitions
        1 => inputs.orderings
        2 => inputs.derivations
        _ => inputs.retentions
      }
      if index < contracts.length() {
        let matches = contracts[index].identity == identity
        self.phase = Lookup(
          kind,
          identity,
          index + 1,
          if matches {
            index
          } else {
            found
          },
          count + (if matches { 1 } else { 0 }),
        )
      } else {
        if count != 1 {
          return Err(
            CommitResultEvidence(
              match kind {
                0 => ResultEvidenceMissingDefinition
                1 => ResultEvidenceMissingOrdering
                2 => ResultEvidenceMissingDerivation
                _ => ResultEvidenceMissingRetention
              },
            ),
          )
        }
        let artifact = inputs.artifacts[self.artifact]
        match kind {
          0 => {
            self.definition = found
            guard contract_string(artifact, "ordering_evidence_cid")
              is Some(next) else {
              return Err(CommitResultEvidence(ResultEvidenceMissingOrdering))
            }
            self.phase = Lookup(1, next, 0, -1, 0)
          }
          1 => {
            self.ordering = found
            guard ordering_derivation_cid(inputs.orderings[found]) is Some(next) else {
              return Err(CommitResultEvidence(ResultEvidenceMissingDerivation))
            }
            self.phase = Lookup(2, next, 0, -1, 0)
          }
          2 => {
            self.derivation = found
            guard contract_string(artifact, "effective_retention_policy_cid")
              is Some(next) else {
              return Err(CommitResultEvidence(ResultEvidenceMissingRetention))
            }
            self.phase = Lookup(3, next, 0, -1, 0)
          }
          _ => {
            self.retention = found
            self.phase = Use
          }
        }
      }
    }
    Use => {
      if self.derivations_used[self.derivation] ||
        self.orderings_used[self.ordering] {
        return Err(CommitResultEvidence(ResultEvidenceDuplicate))
      }
      self.derivations_used[self.derivation] = true
      self.orderings_used[self.ordering] = true
      if !self.retentions_used[self.retention] {
        self.retentions_used[self.retention] = true
        self.retention_count += 1
      }
      self.phase = Ordering
    }
    Ordering => {
      let definition = inputs.definitions[self.definition]
      let artifact = inputs.artifacts[self.artifact]
      let evidence = match
        validate_result_occurrence_ordering_evidence(
          definition,
          inputs.derivations[self.derivation],
          inputs.orderings[self.ordering],
          contract_string(artifact, "logical_result_cid").unwrap(),
          contract_string(artifact, "result_schema_cid").unwrap(),
          contract_string(artifact, "effective_data_policy_cid").unwrap(),
        ) {
        Ok(evidence) => evidence
        Err(issue) =>
          return Err(CommitResultEvidence(ResultEvidenceOrdering(issue)))
      }
      match self.reserve(8) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      self.phase = ArtifactEvidence(
        start_result_artifact_check(
          definition.identity,
          artifact,
          evidence,
          inputs.retentions[self.retention],
        ),
      )
    }
    ArtifactEvidence(child) =>
      match child.step() {
        Err(issue) =>
          return Err(CommitResultEvidence(ResultEvidenceArtifact(issue)))
        Ok(done) =>
          if done {
            child.cancel()
            self.live -= 8L
            self.phase = Artifact(self.artifact + 1)
          }
      }
    Done => ()
  }
  Ok(())
}

///|
fn ResultEvidencePreparation::advance(
  self : ResultEvidencePreparation,
  quantum : Int,
) -> Result[(Bool, Int), PublicationCommitIssue] {
  if self.closed || quantum < 1 {
    return Err(CommitEncoding)
  }
  let mut used = 0
  while used < quantum && !(self.phase is Done) {
    match self.step() {
      Err(issue) => {
        self.cancel()
        return Err(issue)
      }
      Ok(_) => used += 1
    }
  }
  Ok((self.phase is Done, used))
}

///|
fn ResultEvidencePreparation::cancel(self : ResultEvidencePreparation) -> Unit {
  if self.closed {
    return
  }
  if self.phase is ArtifactEvidence(child) {
    child.cancel()
  }
  self.derivations_used.clear()
  self.orderings_used.clear()
  self.retentions_used.clear()
  self.inputs = None
  self.phase = Done
  self.live = 0L
  self.closed = true
}

///|
priv enum ResultArtifactCheckPhase {
  Header
  Provenance(@json.FrozenArray[@json.CanonicalValue], Int)
  Done
}

///|
priv struct ResultArtifactCheck {
  mut inputs : (
    String,
    PublicationContract,
    ResultOrderingEvidence,
    PublicationContract,
  )?
  mut phase : ResultArtifactCheckPhase
  mut closed : Bool
}

///|
fn start_result_artifact_check(
  producer : String,
  artifact : PublicationContract,
  evidence : ResultOrderingEvidence,
  retention : PublicationContract,
) -> ResultArtifactCheck {
  {
    inputs: Some((producer, artifact, evidence, retention)),
    phase: Header,
    closed: false,
  }
}

///|
fn ResultArtifactCheck::step(
  self : ResultArtifactCheck,
) -> Result[Bool, ResultArtifactEvidenceIssue] {
  if self.closed {
    return Err(ArtifactEncoding)
  }
  let (producer, artifact, evidence, retention) = self.inputs.unwrap()
  match self.phase {
    Header => {
      match
        validate_result_artifact_fields(producer, artifact, evidence, retention) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard @json.object_field(artifact.value, "provenance_evidence_cids")
        is Some(@json.Array(values)) else {
        return Err(ArtifactMissingDerivation)
      }
      self.phase = Provenance(values, 0)
    }
    Provenance(values, index) => {
      if index == @json.array_count(values) {
        return Err(ArtifactMissingDerivation)
      }
      if string_value(@json.array_at(values, index).unwrap()) ==
        Some(evidence.derivation.identity) {
        self.phase = Done
      } else {
        self.phase = Provenance(values, index + 1)
      }
    }
    Done => ()
  }
  Ok(self.phase is Done)
}

///|
fn ResultArtifactCheck::cancel(self : ResultArtifactCheck) -> Unit {
  self.inputs = None
  self.phase = Done
  self.closed = true
}
