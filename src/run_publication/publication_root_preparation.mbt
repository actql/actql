///|
priv enum PublicationRootPhase {
  Begin
  DefinitionKinds(Int)
  ArtifactKinds(Int)
  References
  Names(Int, Int, Int)
  Counts
  Missing(Int, Int, Int)
  Foreign(Int, Int, Int)
  Definition(Int)
  Artifact(Int, Int, Int, Int)
  Binding(Int, Int)
  Result(Int, Int, Int, Int)
  Wire(Int, String, EvidenceStreamPreparation)
  Done
}

///|
priv struct PublicationRootPreparation {
  mut inputs : PublicationRootInputs?
  mut results : @json.FrozenArray[(String, @json.CanonicalValue)]?
  max_workspace : Int
  mut phase : PublicationRootPhase
  mut peak : Int
  mut closed : Bool
}

///|
priv struct PublicationRootInputs {
  run_definition : PublicationContract
  invocation : PublicationContract
  definitions : Array[PublicationContract]
  artifacts : Array[PublicationContract]
  manifest : PublicationContract
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
fn start_publication_root_preparation(
  inputs : PublicationRootInputs,
  max_workspace : Int,
) -> PublicationRootPreparation {
  {
    inputs: Some(inputs),
    results: None,
    max_workspace,
    phase: Begin,
    peak: 12,
    closed: false,
  }
}

///|
fn root_name(inputs : PublicationRootInputs, index : Int) -> String? {
  contract_string(inputs.definitions[index], "result_name")
}

///|
fn PublicationRootPreparation::step(
  self : PublicationRootPreparation,
) -> Result[Unit, RunEvidenceChainIssue] {
  let inputs = self.inputs.unwrap()
  match self.phase {
    Begin => {
      if self.max_workspace < 12 {
        return Err(EvidenceEncoding)
      }
      for
        (actual, expected) in [
          (inputs.run_definition.name, "run_definition"),
          (inputs.invocation.name, "run_invocation"),
          (inputs.manifest.name, "result_manifest"),
        ] {
        if actual != expected {
          return Err(EvidenceRoot(ChainWrongContract(expected)))
        }
      }
      self.phase = DefinitionKinds(0)
    }
    DefinitionKinds(index) =>
      if index == inputs.definitions.length() {
        self.phase = ArtifactKinds(0)
      } else if inputs.definitions[index].name != "result_definition" {
        return Err(EvidenceRoot(ChainWrongContract("result_definition")))
      } else {
        self.phase = DefinitionKinds(index + 1)
      }
    ArtifactKinds(index) =>
      if index == inputs.artifacts.length() {
        self.phase = References
      } else if inputs.artifacts[index].name != "result_artifact" {
        return Err(EvidenceRoot(ChainWrongContract("result_artifact")))
      } else {
        self.phase = ArtifactKinds(index + 1)
      }
    References => {
      if contract_string(inputs.run_definition, "invocation_template_cid") !=
        contract_string(inputs.invocation, "invocation_template_cid") {
        return Err(EvidenceRoot(ChainInvocationTemplateMismatch))
      }
      if contract_string(inputs.manifest, "run_definition_cid") !=
        Some(inputs.run_definition.identity) {
        return Err(EvidenceRoot(ChainRunDefinitionMismatch))
      }
      if contract_string(inputs.manifest, "invocation_cid") !=
        Some(inputs.invocation.identity) {
        return Err(EvidenceRoot(ChainInvocationMismatch))
      }
      guard @json.object_field(inputs.manifest.value, "results")
        is Some(@json.Object(results)) else {
        return Err(EvidenceRoot(ChainEncoding))
      }
      self.results = Some(results)
      self.phase = Names(0, 0, 0)
    }
    Names(index, prior, offset) =>
      if index == inputs.definitions.length() {
        self.phase = Counts
      } else {
        guard root_name(inputs, index) is Some(name) else {
          return Err(EvidenceRoot(ChainEncoding))
        }
        if prior == index {
          self.phase = Names(index + 1, 0, 0)
        } else {
          let (comparison, next, _) = @canonical.compare_utf16_fragment(
            name,
            root_name(inputs, prior).unwrap(),
            offset,
            64,
          )
          self.phase = match comparison {
            None => Names(index, prior, next)
            Some(0) => return Err(EvidenceRoot(ChainDuplicateResult(name)))
            Some(_) => Names(index, prior + 1, 0)
          }
        }
      }
    Counts => {
      let count = @json.array_count(self.results.unwrap())
      self.phase = if count != inputs.definitions.length() ||
        inputs.artifacts.length() != inputs.definitions.length() {
        Missing(0, 0, 0)
      } else {
        Foreign(0, 0, 0)
      }
    }
    Missing(index, result, offset) =>
      if index == inputs.definitions.length() {
        return Err(EvidenceRoot(ChainArtifactMismatch("inventory")))
      } else {
        let name = root_name(inputs, index).unwrap()
        guard @json.array_at(self.results.unwrap(), result) is Some((other, _)) else {
          return Err(EvidenceRoot(ChainMissingResult(name)))
        }
        let (comparison, next, _) = @canonical.compare_utf16_fragment(
          name, other, offset, 64,
        )
        self.phase = match comparison {
          None => Missing(index, result, next)
          Some(0) => Missing(index + 1, 0, 0)
          Some(_) => Missing(index, result + 1, 0)
        }
      }
    Foreign(result, index, offset) =>
      if result == @json.array_count(self.results.unwrap()) {
        self.phase = Definition(0)
      } else {
        let name = @json.array_at(self.results.unwrap(), result).unwrap().0
        if index == inputs.definitions.length() {
          return Err(EvidenceRoot(ChainForeignResult(name)))
        }
        let (comparison, next, _) = @canonical.compare_utf16_fragment(
          name,
          root_name(inputs, index).unwrap(),
          offset,
          64,
        )
        self.phase = match comparison {
          None => Foreign(result, index, next)
          Some(0) => Foreign(result + 1, 0, 0)
          Some(_) => Foreign(result, index + 1, 0)
        }
      }
    Definition(index) =>
      if index == inputs.definitions.length() {
        self.phase = Done
      } else {
        self.phase = Artifact(index, 0, -1, 0)
      }
    Artifact(definition, index, found, count) =>
      if index < inputs.artifacts.length() {
        let matches = contract_string(
            inputs.artifacts[index],
            "result_definition_cid",
          ) ==
          Some(inputs.definitions[definition].identity)
        self.phase = Artifact(
          definition,
          index + 1,
          if matches {
            index
          } else {
            found
          },
          count + (if matches { 1 } else { 0 }),
        )
      } else if count != 1 {
        return Err(
          EvidenceRoot(
            ChainArtifactMismatch(root_name(inputs, definition).unwrap()),
          ),
        )
      } else {
        self.phase = Binding(definition, found)
      }
    Binding(definition, artifact) => {
      let value = inputs.artifacts[artifact]
      if contract_string(value, "invocation_cid") !=
        Some(inputs.invocation.identity) {
        return Err(EvidenceRoot(ChainInvocationMismatch))
      }
      if contract_string(value, "result_definition_cid") !=
        Some(inputs.definitions[definition].identity) {
        return Err(
          EvidenceRoot(
            ChainResultDefinitionMismatch(
              root_name(inputs, definition).unwrap(),
            ),
          ),
        )
      }
      self.phase = Result(definition, artifact, 0, 0)
    }
    Result(definition, artifact, index, offset) => {
      let name = root_name(inputs, definition).unwrap()
      guard @json.array_at(self.results.unwrap(), index)
        is Some((other, nested)) else {
        return Err(EvidenceRoot(ChainMissingResult(name)))
      }
      let (comparison, next, _) = @canonical.compare_utf16_fragment(
        name, other, offset, 64,
      )
      match comparison {
        None => self.phase = Result(definition, artifact, index, next)
        Some(0) => {
          if physical_equal(nested, inputs.artifacts[artifact].value) &&
            publication_contract_check_limits(
              inputs.artifacts[artifact],
              inputs.max_wire_bytes,
              inputs.max_nodes,
              inputs.max_depth,
            )
            is Ok(_) {
            self.phase = Definition(definition + 1)
            return Ok(())
          }
          if self.max_workspace - 12 < 12 {
            return Err(EvidenceEncoding)
          }
          self.phase = Wire(
            definition,
            name,
            start_evidence_stream(
              nested,
              Wire(inputs.artifacts[artifact].wire),
              inputs.max_wire_bytes,
              inputs.max_nodes,
              inputs.max_depth,
              self.max_workspace - 12,
            ),
          )
        }
        Some(_) => self.phase = Result(definition, artifact, index + 1, 0)
      }
    }
    Wire(index, name, child) =>
      match child.advance(1) {
        Err(_) => return Err(EvidenceRoot(ChainEncoding))
        Ok((done, _)) => {
          self.peak = Int::max(self.peak, 12 + child.peak)
          if done {
            if !child.finish().unwrap() {
              return Err(EvidenceRoot(ChainArtifactMismatch(name)))
            }
            self.phase = Definition(index + 1)
          }
        }
      }
    Done => ()
  }
  Ok(())
}

///|
fn PublicationRootPreparation::advance(
  self : PublicationRootPreparation,
  quantum : Int,
) -> Result[(Bool, Int), RunEvidenceChainIssue] {
  if self.closed || quantum < 1 {
    return Err(EvidenceEncoding)
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
fn PublicationRootPreparation::cancel(
  self : PublicationRootPreparation,
) -> Unit {
  if self.phase is Wire(_, _, child) {
    child.cancel()
  }
  self.inputs = None
  self.results = None
  self.phase = Done
  self.closed = true
}
