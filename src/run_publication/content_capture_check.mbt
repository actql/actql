///|
priv enum ContentCapturePhase {
  Begin
  External(Int, Int)
  Record(Int)
  DuplicateNode(Int, Int, Int)
  Links(Int, Int, Int)
  Identity(Int, Int)
  Hash(EvidenceStreamPreparation, Int, Int)
  Availability(Int, Int)
  Done
}

///|
/// A bounded child of the existing computation evidence validator. It validates
/// saved proof closure, never issues a Ref or asserts current physical custody.
priv struct ContentCaptureCheck {
  mut inputs : ComputationEvidenceInputs?
  mut context : @json.CanonicalValue?
  mut records : @json.FrozenArray[@json.CanonicalValue]?
  mut identities : @json.FrozenArray[@json.CanonicalValue]?
  mut external : @json.FrozenArray[@json.CanonicalValue]?
  mut availability : @json.FrozenArray[@json.CanonicalValue]?
  max_workspace : Int
  mut phase : ContentCapturePhase
  mut peak : Int
  mut closed : Bool
}

///|
fn start_content_capture_check(
  inputs : ComputationEvidenceInputs,
  context : @json.CanonicalValue,
  workspace : Int,
) -> ContentCaptureCheck {
  {
    inputs: Some(inputs),
    context: Some(context),
    records: None,
    identities: None,
    external: None,
    availability: None,
    max_workspace: workspace,
    phase: Begin,
    peak: 12,
    closed: false,
  }
}

///|
fn content_capture_proof(
  record : @json.CanonicalValue,
  kind : Int,
) -> (@json.CanonicalValue, String)? {
  let (name, field) = match kind {
    0 => ("content_evidence", "evidence_cid")
    1 => ("content_generation", "generation_cid")
    2 => ("content_input_artifact", "input_artifact_cid")
    3 => ("content_reference", "content_ref_cid")
    4 => ("invocation_template", "bound_invocation_template_cid")
    5 => {
      guard @json.object_field(record, "content_reference") is Some(reference) &&
        @json.object_field(reference, "metadata") is Some(metadata) &&
        @json.object_field(metadata, "issuer_evidence") is Some(issuer) else {
        return None
      }
      return Some((issuer, "evidence_cid"))
    }
    _ => return None
  }
  @json.object_field(record, name).map(value => (value, field))
}

///|
fn content_capture_links(
  inputs : ComputationEvidenceInputs,
  record : @json.CanonicalValue,
) -> Bool {
  guard content_capture_proof(record, 0) is Some((derivation, _)) &&
    content_capture_proof(record, 1) is Some((generation, _)) &&
    content_capture_proof(record, 2) is Some((input, _)) &&
    content_capture_proof(record, 3) is Some((reference, _)) &&
    content_capture_proof(record, 4) is Some((template, _)) &&
    @json.object_field(inputs.receipt.value, "observation_set")
    is Some(observation) else {
    return false
  }
  // Saved intermediate Content retains its original input policy. A Model's
  // output policy is validated by the Model evidence/scope owner separately.
  if !content_generation_structure_matches(
      template,
      input,
      derivation,
      generation,
      reference,
      inputs.run_definition.identity,
    ) ||
    (
      !model_template_value_requires_slots(template) &&
      evidence_string(observation, "data_policy_cid") !=
      evidence_string(input, "effective_data_policy_cid")
    ) ||
    evidence_string(generation, "bound_invocation_template_cid") !=
    contract_string(inputs.invocation, "invocation_template_cid") ||
    evidence_string(input, "program_definition_cid") !=
    evidence_string(inputs.receipt.value, "program_definition_cid") {
    return false
  }
  true
}

///|
/// Shared metadata closure for captured evidence and authenticated recovery.
/// This validates no physical bytes and issues no current access permission.
fn content_generation_structure_matches(
  template : @json.CanonicalValue,
  input : @json.CanonicalValue,
  derivation : @json.CanonicalValue,
  generation : @json.CanonicalValue,
  reference : @json.CanonicalValue,
  run_definition_cid : String,
) -> Bool {
  guard @json.object_field(reference, "metadata") is Some(metadata) &&
    @json.object_field(metadata, "issuer_evidence") is Some(issuer) else {
    return false
  }
  let get = evidence_string
  let policy = get(input, "effective_data_policy_cid")
  if policy is None ||
    get(generation, "run_definition_cid") != Some(run_definition_cid) ||
    get(template, "bound_invocation_template_cid") !=
    get(generation, "bound_invocation_template_cid") ||
    get(derivation, "effective_data_policy_cid") != policy ||
    get(metadata, "effective_data_policy_cid") != policy ||
    get(issuer, "effective_data_policy_cid") != policy ||
    get(issuer, "issuer_kind") != Some("content_derivation") ||
    get(metadata, "capture_authority") != Some("read_content") ||
    !(@json.object_field(metadata, "truncated") is Some(@json.Bool(false))) {
    return false
  }
  guard @json.object_field(derivation, "row_count") is Some(@json.Number(rows)) &&
    @json.object_field(input, "row_count") is Some(@json.Number(input_rows)) &&
    @json.object_field(derivation, "byte_count") is Some(@json.Number(bytes)) &&
    @json.object_field(metadata, "size_bytes") is Some(@json.Number(size)) else {
    return false
  }
  rows == input_rows && bytes == size
}

///|
fn content_capture_link_pair(
  record : @json.CanonicalValue,
  index : Int,
) -> (String, String)? {
  let derivation = content_capture_proof(record, 0).unwrap().0
  let generation = content_capture_proof(record, 1).unwrap().0
  let input = content_capture_proof(record, 2).unwrap().0
  let reference = content_capture_proof(record, 3).unwrap().0
  let template = content_capture_proof(record, 4).unwrap().0
  let issuer = content_capture_proof(record, 5).unwrap().0
  content_generation_link_pair(
    derivation, generation, input, reference, template, issuer, index,
  )
}

///|
fn content_generation_link_pair(
  derivation : @json.CanonicalValue,
  generation : @json.CanonicalValue,
  input : @json.CanonicalValue,
  reference : @json.CanonicalValue,
  template : @json.CanonicalValue,
  issuer : @json.CanonicalValue,
  index : Int,
) -> (String, String)? {
  let metadata = @json.object_field(reference, "metadata").unwrap()
  let (left, key, right, other) = match index {
    0 => (input, "program_definition_cid", template, "program_definition_cid")
    1 => (input, "parameter_values_cid", template, "parameter_values_cid")
    2 => (input, "invocation_bindings_cid", template, "invocation_bindings_cid")
    3 => (generation, "barrier_cid", derivation, "barrier_cid")
    4 => (generation, "content_evidence_cid", derivation, "evidence_cid")
    5 => (derivation, "barrier_input_artifact_cid", input, "input_artifact_cid")
    6 => (derivation, "content_ref_cid", reference, "content_ref_cid")
    7 => (derivation, "content_issuer_evidence_cid", issuer, "evidence_cid")
    8 => (derivation, "content_cid", metadata, "content_cid")
    9 => (derivation, "content_cid", issuer, "content_cid")
    10 => (derivation, "media_type", reference, "media_type")
    11 => (derivation, "media_type", metadata, "media_type")
    12 => (generation, "content_store_cid", issuer, "content_store_cid")
    13 => (generation, "workspace_scope_cid", issuer, "workspace_scope_cid")
    14 =>
      (
        generation, "availability_evidence_cid", metadata, "availability_evidence_cid",
      )
    _ => return None
  }
  guard evidence_string(left, key) is Some(a) &&
    evidence_string(right, other) is Some(b) else {
    return None
  }
  Some((a, b))
}

///|
fn ContentCaptureCheck::step(
  self : ContentCaptureCheck,
) -> Result[Unit, RunEvidenceChainIssue] {
  let inputs = self.inputs.unwrap()
  let issue = EvidenceReferenceMismatch("content_generations")
  match self.phase {
    Begin => {
      if self.max_workspace < 12 {
        return Err(EvidenceEncoding)
      }
      guard @json.object_field(inputs.receipt.value, "observation_set")
        is Some(observation) &&
        @json.object_field(
          inputs.receipt.value,
          "external_observation_evidence",
        )
        is Some(@json.Array(external)) else {
        return Err(issue)
      }
      self.external = Some(external)
      let records = @json.object_field(
        self.context.unwrap(),
        "content_generations",
      )
      let identities = @json.object_field(
        observation, "content_generation_cids",
      )
      match (records, identities) {
        (None, None) => ()
        (Some(@json.Array(saved)), Some(@json.Array(expected))) => {
          if @json.array_count(saved) < 1 ||
            @json.array_count(saved) != @json.array_count(expected) {
            return Err(issue)
          }
          guard @json.object_field(observation, "replayability") is Some(replay) &&
            @json.object_field(replay, "materialized") is Some(@json.Bool(true)) &&
            @json.object_field(replay, "availability_evidence_cids")
            is Some(@json.Array(availability)) else {
            return Err(issue)
          }
          self.records = Some(saved)
          self.identities = Some(expected)
          self.availability = Some(availability)
        }
        _ => return Err(issue)
      }
      self.phase = External(0, 0)
    }
    External(index, content) => {
      let values = self.external.unwrap()
      let count = self.records.map(@json.array_count).unwrap_or(0)
      if index == @json.array_count(values) {
        if content != count {
          return Err(issue)
        }
        self.phase = if count == 0 { Done } else { Record(0) }
      } else {
        let item = @json.array_at(values, index).unwrap()
        if evidence_string(item, "kind") == Some("content_generation") {
          if content >= count ||
            evidence_string(item, "evidence_cid") !=
            optional_string(@json.array_at(self.identities.unwrap(), content)) {
            return Err(issue)
          }
          self.phase = External(index + 1, content + 1)
        } else {
          self.phase = External(index + 1, content)
        }
      }
    }
    Record(index) =>
      if index == @json.array_count(self.records.unwrap()) {
        self.phase = Done
      } else {
        // Reserve fixed metadata scratch before the borrowed proof traversal.
        if self.max_workspace < 32 {
          return Err(EvidenceEncoding)
        }
        self.peak = Int::max(self.peak, 32)
        let record = @json.array_at(self.records.unwrap(), index).unwrap()
        guard content_capture_proof(record, 1) is Some((generation, _)) &&
          evidence_string(generation, "generation_cid") ==
          optional_string(@json.array_at(self.identities.unwrap(), index)) &&
          content_capture_links(inputs, record) else {
          return Err(issue)
        }
        self.phase = DuplicateNode(index, 0, 0)
      }
    DuplicateNode(index, previous, offset) =>
      if previous == index {
        self.phase = Links(index, 0, 0)
      } else {
        let records = self.records.unwrap()
        let current = content_capture_proof(
            @json.array_at(records, index).unwrap(),
            1,
          ).unwrap().0
        let prior = content_capture_proof(
            @json.array_at(records, previous).unwrap(),
            1,
          ).unwrap().0
        let (compared, next, _) = @canonical.compare_utf16_fragment(
          evidence_string(current, "node_id").unwrap(),
          evidence_string(prior, "node_id").unwrap(),
          offset,
          64,
        )
        match compared {
          Some(0) => return Err(issue)
          Some(_) => self.phase = DuplicateNode(index, previous + 1, 0)
          None => self.phase = DuplicateNode(index, previous, next)
        }
      }
    Links(index, field, offset) =>
      if field == 15 {
        self.phase = Identity(index, 0)
      } else {
        let record = @json.array_at(self.records.unwrap(), index).unwrap()
        guard content_capture_link_pair(record, field) is Some((a, b)) else {
          return Err(issue)
        }
        let (compared, next, _) = @canonical.compare_utf16_fragment(
          a, b, offset, 64,
        )
        match compared {
          Some(0) => self.phase = Links(index, field + 1, 0)
          Some(_) => return Err(issue)
          None => self.phase = Links(index, field, next)
        }
      }
    Identity(index, kind) =>
      if kind == 6 {
        self.phase = Availability(index, 0)
      } else {
        let record = @json.array_at(self.records.unwrap(), index).unwrap()
        guard content_capture_proof(record, kind) is Some((value, field)) &&
          evidence_string(value, field) is Some(identity) &&
          @json.object_without_field(value, field) is Some(body) else {
          return Err(issue)
        }
        if self.max_workspace - 12 < 12 {
          return Err(EvidenceEncoding)
        }
        self.phase = Hash(
          start_evidence_stream(
            body,
            Identity(identity),
            inputs.max_wire_bytes,
            inputs.max_nodes,
            inputs.max_depth,
            self.max_workspace - 12,
          ),
          index,
          kind,
        )
      }
    Hash(child, index, kind) => {
      let (done, _) = match child.advance(1) {
        Ok(result) => result
        Err(error) => return Err(error)
      }
      self.peak = Int::max(self.peak, 12 + child.peak)
      if done {
        if !child.finish().unwrap() {
          return Err(issue)
        }
        self.phase = Identity(index, kind + 1)
      }
    }
    Availability(index, offset) => {
      let values = self.availability.unwrap()
      if offset == @json.array_count(values) {
        return Err(issue)
      }
      let record = @json.array_at(self.records.unwrap(), index).unwrap()
      let generation = content_capture_proof(record, 1).unwrap().0
      if optional_string(@json.array_at(values, offset)) ==
        evidence_string(generation, "availability_evidence_cid") {
        self.phase = Record(index + 1)
      } else {
        self.phase = Availability(index, offset + 1)
      }
    }
    Done => ()
  }
  Ok(())
}

///|
fn ContentCaptureCheck::advance(
  self : ContentCaptureCheck,
  quantum : Int,
) -> Result[(Bool, Int), RunEvidenceChainIssue] {
  if self.closed || quantum < 1 {
    return Err(EvidenceEncoding)
  }
  let mut used = 0
  while used < quantum && !(self.phase is Done) {
    match self.step() {
      Ok(_) => used += 1
      Err(issue) => {
        self.cancel()
        return Err(issue)
      }
    }
  }
  Ok((self.phase is Done, used))
}

///|
fn ContentCaptureCheck::cancel(self : ContentCaptureCheck) -> Unit {
  if self.closed {
    return
  }
  if self.phase is Hash(child, _, _) {
    child.cancel()
  }
  self.inputs = None
  self.context = None
  self.records = None
  self.identities = None
  self.external = None
  self.availability = None
  self.phase = Done
  self.closed = true
}
