///|
priv enum ComputationPreludeContinuation {
  Prepared
  Authorization
  Observation
  Manifest
  Results
  Source(Int)
  Capture
}

///|
priv enum ComputationPreludePhase {
  Begin
  Root(PublicationRootPreparation)
  Receipt
  Programs(Int)
  Prepared
  Check(
    EvidenceStreamPreparation,
    ComputationPreludeContinuation,
    RunEvidenceChainIssue
  )
  Sources(Int)
  External(Int, Int, Bool)
  Capture
  Done
}

///|
/// Private continuation of the existing computation validator. Admission and
/// physical custody remain with the caller; this owner retains traversal only.
priv struct ComputationPreludePreparation {
  mut inputs : ComputationEvidenceInputs?
  max_workspace : Int
  mut phase : ComputationPreludePhase
  mut prepared : @json.CanonicalValue?
  mut authorization : @json.CanonicalValue?
  mut manifest_results : @json.CanonicalValue?
  mut source_values : @json.FrozenArray[@json.CanonicalValue]?
  mut source_cids : @json.FrozenArray[@json.CanonicalValue]?
  mut external : @json.FrozenArray[@json.CanonicalValue]?
  mut context : @json.CanonicalValue?
  mut program : String?
  mut models : Array[String]
  mut live : Int
  mut peak : Int
  mut closed : Bool
}

///|
fn start_computation_prelude(
  inputs : ComputationEvidenceInputs,
  max_workspace : Int,
  after_root? : Bool = false,
) -> ComputationPreludePreparation {
  {
    inputs: Some(inputs),
    max_workspace,
    phase: if after_root {
      Receipt
    } else {
      Begin
    },
    prepared: None,
    authorization: None,
    manifest_results: None,
    source_values: None,
    source_cids: None,
    external: None,
    context: None,
    program: None,
    models: [],
    live: 16,
    peak: 16,
    closed: false,
  }
}

///|
fn ComputationPreludePreparation::check(
  self : ComputationPreludePreparation,
  value : @json.CanonicalValue,
  target : EvidenceStreamTarget,
  next : ComputationPreludeContinuation,
  issue : RunEvidenceChainIssue,
) -> Result[Unit, RunEvidenceChainIssue] {
  let inputs = self.inputs.unwrap()
  if self.max_workspace - self.live < 12 {
    return Err(EvidenceEncoding)
  }
  self.phase = Check(
    start_evidence_stream(
      value,
      target,
      inputs.max_wire_bytes,
      inputs.max_nodes,
      inputs.max_depth,
      self.max_workspace - self.live,
    ),
    next,
    issue,
  )
  Ok(())
}

///|
fn ComputationPreludePreparation::identity(
  self : ComputationPreludePreparation,
  value : @json.CanonicalValue,
  field : String,
  next : ComputationPreludeContinuation,
  issue : RunEvidenceChainIssue,
) -> Result[Unit, RunEvidenceChainIssue] {
  guard evidence_string(value, field) is Some(identity) &&
    @json.object_without_field(value, field) is Some(body) else {
    return Err(issue)
  }
  self.check(body, Identity(identity), next, issue)
}

///|
fn ComputationPreludePreparation::continue_after(
  self : ComputationPreludePreparation,
  next : ComputationPreludeContinuation,
) -> Result[Unit, RunEvidenceChainIssue] {
  let inputs = self.inputs.unwrap()
  let receipt = inputs.receipt.value
  match next {
    Prepared => {
      let prepared = self.prepared.unwrap()
      if evidence_string(prepared, "invocation_template_cid") !=
        contract_string(inputs.invocation, "invocation_template_cid") ||
        evidence_string(prepared, "compiled_plan_cid") !=
        contract_string(inputs.run_definition, "compiled_plan_cid") {
        return Err(EvidenceReferenceMismatch("prepared_invocation"))
      }
      let authorization = match evidence_object(receipt, "run_authorization") {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.authorization = Some(authorization)
      self.identity(
        authorization,
        "run_authorization_cid",
        Authorization,
        EvidenceEmbeddedIdentity("run_authorization_cid"),
      )
    }
    Authorization => {
      let prepared = self.prepared.unwrap()
      let authorization = self.authorization.unwrap()
      for
        field in [
          "prepared_invocation_cid", "execution_context_cid", "host_policy_cid",
        ] {
        if evidence_string(authorization, field) !=
          evidence_string(prepared, field) {
          return Err(EvidenceReferenceMismatch("run_authorization"))
        }
      }
      if evidence_string(prepared, "policy_decision") != Some("allow") ||
        evidence_string(authorization, "decision") != Some("allowed") {
        return Err(EvidenceReferenceMismatch("run_authorization"))
      }
      let observation = match evidence_object(receipt, "observation_set") {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.identity(
        observation,
        "observation_set_cid",
        Observation,
        EvidenceEmbeddedIdentity("observation_set_cid"),
      )
    }
    Observation => {
      let observation = evidence_object(receipt, "observation_set").unwrap()
      if evidence_string(observation, "invocation_template_cid") !=
        contract_string(inputs.invocation, "invocation_template_cid") ||
        evidence_string(observation, "observation_set_cid") !=
        contract_string(inputs.invocation, "observation_set_cid") ||
        evidence_string(receipt, "observation_set_cid") !=
        contract_string(inputs.invocation, "observation_set_cid") {
        return Err(EvidenceReferenceMismatch("observation_set"))
      }
      let manifest = match evidence_object(receipt, "result_manifest") {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.check(
        manifest,
        Wire(inputs.manifest.wire),
        Manifest,
        EvidenceReferenceMismatch("result_manifest"),
      )
    }
    Manifest => {
      guard @json.object_field(receipt, "result_artifacts") is Some(artifacts) else {
        return Err(EvidenceMissingField("result_artifacts"))
      }
      guard @json.object_field(inputs.manifest.value, "results")
        is Some(results) else {
        return Err(EvidenceMissingField("results"))
      }
      self.manifest_results = Some(results)
      self.check(
        artifacts,
        Pair(results),
        Results,
        EvidenceInventoryMismatch("result_artifacts"),
      )
    }
    Results => {
      guard @json.object_field(receipt, "source_evidence") is Some(source) else {
        return Err(EvidenceMissingField("source_evidence"))
      }
      guard @json.object_field(receipt, "source_evidence_cids") is Some(cids) else {
        return Err(EvidenceMissingField("source_evidence_cids"))
      }
      guard source is @json.Array(values) && cids is @json.Array(listed) else {
        return Err(EvidenceReferenceMismatch("source_evidence_cids"))
      }
      self.source_values = Some(values)
      self.source_cids = Some(listed)
      self.phase = Sources(0)
      Ok(())
    }
    Source(index) => {
      let value = @json.array_at(self.source_values.unwrap(), index).unwrap()
      guard @json.array_at(self.source_cids.unwrap(), index)
        is Some(@json.String(identity)) &&
        evidence_string(value, "source_evidence_cid") == Some(identity) else {
        return Err(EvidenceReferenceMismatch("source_evidence_cids"))
      }
      self.phase = Sources(index + 1)
      Ok(())
    }
    Capture => {
      let context = match
        evidence_object(inputs.captured_run.value, "effect_context") {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.context = Some(context)
      self.phase = Done
      Ok(())
    }
  }
}

///|
fn ComputationPreludePreparation::step(
  self : ComputationPreludePreparation,
) -> Result[Unit, RunEvidenceChainIssue] {
  let inputs = self.inputs.unwrap()
  let receipt = inputs.receipt.value
  match self.phase {
    Begin => {
      // Empty public inventory is valid only for a checked Effectful chain.
      // The shared root still validates the exact empty Manifest and bindings.
      if inputs.definitions.is_empty() && inputs.preview is None {
        return Err(EvidenceRoot(ChainEmptyInventory))
      }
      if self.max_workspace < self.live + 12 {
        return Err(EvidenceEncoding)
      }
      self.phase = Root(
        start_publication_root_preparation(
          {
            run_definition: inputs.run_definition,
            invocation: inputs.invocation,
            definitions: inputs.definitions,
            artifacts: inputs.artifacts,
            manifest: inputs.manifest,
            max_wire_bytes: inputs.max_wire_bytes,
            max_nodes: inputs.max_nodes,
            max_depth: inputs.max_depth,
          },
          self.max_workspace - self.live,
        ),
      )
    }
    Root(child) =>
      match child.advance(1) {
        Err(issue) => return Err(issue)
        Ok((done, _)) => {
          self.peak = Int::max(self.peak, self.live + child.peak)
          if done {
            child.cancel()
            self.phase = Receipt
          }
        }
      }
    Receipt => {
      if inputs.receipt.name != "run_receipt" {
        return Err(EvidenceWrongContract("run_receipt"))
      }
      if inputs.captured_run.name != "captured_run" {
        return Err(EvidenceWrongContract("captured_run"))
      }
      if @json.object_field(receipt, "effect_preview_cid") is Some(_) ||
        @json.object_field(receipt, "effect_set_apply_receipt_cid") is Some(_) ||
        @json.object_field(receipt, "captured_run_cid") is Some(_) {
        return match inputs.preview {
          None => Err(EvidenceNotEffectFree)
          Some(_) => Err(EvidenceReferenceMismatch("computation_receipt"))
        }
      }
      if evidence_string(receipt, "invocation_cid") !=
        Some(inputs.invocation.identity) {
        return Err(EvidenceReferenceMismatch("invocation_cid"))
      }
      if evidence_string(receipt, "compiled_plan_cid") !=
        contract_string(inputs.run_definition, "compiled_plan_cid") {
        return Err(EvidenceReferenceMismatch("compiled_plan_cid"))
      }
      if inputs.preview is Some(preview) {
        for
          (field, expected) in [
            ("program_semantics_cid", preview.program_semantics_cid),
            ("program_definition_cid", preview.program_definition_cid),
            ("invocation_cid", preview.invocation_cid),
            ("compiled_plan_cid", preview.compiled_plan_cid),
            ("check_environment_cid", preview.check_environment_cid),
          ] {
          if evidence_string(receipt, field) != Some(expected) {
            return Err(EvidenceReferenceMismatch("preview." + field))
          }
        }
        if preview.run_identity_cid != inputs.run_definition.identity {
          return Err(EvidenceReferenceMismatch("preview.run_identity_cid"))
        }
      }
      if evidence_string(receipt, "result_manifest_cid") !=
        Some(inputs.manifest.identity) {
        return Err(EvidenceReferenceMismatch("result_manifest_cid"))
      }
      self.program = computation_prelude_program_identity(
        inputs.definitions,
        inputs.preview,
      )
      if evidence_string(receipt, "program_definition_cid") != self.program {
        return Err(EvidenceReferenceMismatch("program_definition_cid"))
      }
      self.phase = Programs(0)
    }
    Programs(index) =>
      if index == inputs.definitions.length() {
        self.phase = Prepared
      } else {
        if contract_string(inputs.definitions[index], "program_definition_cid") !=
          self.program {
          return Err(EvidenceReferenceMismatch("program_definition_cid"))
        }
        self.phase = Programs(index + 1)
      }
    Prepared => {
      let value = match evidence_object(receipt, "prepared_invocation") {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.prepared = Some(value)
      return self.identity(
        value,
        "prepared_invocation_cid",
        Prepared,
        EvidenceEmbeddedIdentity("prepared_invocation_cid"),
      )
    }
    Check(child, next, issue) =>
      match child.advance(1) {
        Err(_) => return Err(issue)
        Ok((done, _)) => {
          self.peak = Int::max(self.peak, self.live + child.peak)
          if done {
            if !child.finish().unwrap() {
              return Err(issue)
            }
            return self.continue_after(next)
          }
        }
      }
    Sources(index) => {
      let values = self.source_values.unwrap()
      if index == @json.array_count(values) {
        if index != @json.array_count(self.source_cids.unwrap()) {
          return Err(EvidenceReferenceMismatch("source_evidence_cids"))
        }
        guard @json.object_field(receipt, "external_observation_evidence")
          is Some(@json.Array(external)) else {
          return Err(EvidenceMissingField("external_observation_evidence"))
        }
        self.external = Some(external)
        self.phase = External(0, 0, true)
      } else {
        return self.identity(
          @json.array_at(values, index).unwrap(),
          "source_evidence_cid",
          Source(index),
          EvidenceReferenceMismatch("source_evidence_cids"),
        )
      }
    }
    External(index, source, matches) => {
      let external = self.external.unwrap()
      if index == @json.array_count(external) {
        if !matches || source != @json.array_count(self.source_cids.unwrap()) {
          return Err(EvidenceReferenceMismatch("external_source_evidence"))
        }
        self.phase = Capture
      } else {
        let item = @json.array_at(external, index).unwrap()
        guard evidence_string(item, "kind") is Some(kind) &&
          evidence_string(item, "evidence_cid") is Some(identity) else {
          return Err(EvidenceReferenceMismatch("external_observation_evidence"))
        }
        match kind {
          "content_generation" =>
            // The bounded Content child validates the entire ordered inventory
            // and embedded proof closure after the context hash is checked.
            self.phase = External(index + 1, source, matches)
          "source_lookup" => {
            let valid = match
              @json.array_at(self.source_cids.unwrap(), source) {
              Some(@json.String(expected)) => identity == expected
              _ => false
            }
            self.phase = External(index + 1, source + 1, matches && valid)
          }
          "model_invocation" => {
            if self.live >= self.max_workspace {
              return Err(EvidenceEncoding)
            }
            self.live += 1
            self.peak = Int::max(self.peak, self.live)
            self.models.push(identity)
            self.phase = External(index + 1, source, matches)
          }
          _ =>
            return Err(
              EvidenceReferenceMismatch("external_observation_evidence"),
            )
        }
      }
    }
    Capture => {
      let value = match evidence_object(inputs.captured_run.value, "receipt") {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      return self.check(
        value,
        Wire(inputs.receipt.wire),
        Capture,
        EvidenceReferenceMismatch("receipt"),
      )
    }
    Done => ()
  }
  Ok(())
}

///|
/// Empty public inventory obtains identity from the already admitted Preview,
/// never from a caller-authored Receipt or a fabricated Result definition.
fn computation_prelude_program_identity(
  definitions : Array[PublicationContract],
  preview : EffectPreviewIdentity?,
) -> String? {
  match definitions.get(0) {
    Some(definition) => contract_string(definition, "program_definition_cid")
    None => preview.map(value => value.program_definition_cid)
  }
}

///|
fn ComputationPreludePreparation::advance(
  self : ComputationPreludePreparation,
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
fn ComputationPreludePreparation::finish(
  self : ComputationPreludePreparation,
) -> Result[ComputationEvidencePrelude, RunEvidenceChainIssue] {
  guard !self.closed && self.phase is Done else { return Err(EvidenceEncoding) }
  let output = {
    effect_context: self.context.unwrap(),
    program: self.program,
    external_model_cids: self.models,
    manifest_results: self.manifest_results.unwrap(),
  }
  self.models = []
  self.cancel()
  Ok(output)
}

///|
fn ComputationPreludePreparation::cancel(
  self : ComputationPreludePreparation,
) -> Unit {
  match self.phase {
    Root(child) => child.cancel()
    Check(child, _, _) => child.cancel()
    _ => ()
  }
  self.inputs = None
  self.prepared = None
  self.authorization = None
  self.manifest_results = None
  self.source_values = None
  self.source_cids = None
  self.external = None
  self.context = None
  self.program = None
  self.models.clear()
  self.phase = Done
  self.live = 0
  self.closed = true
}
