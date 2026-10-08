///|
priv struct ComputationSuffixInputs {
  context : @json.CanonicalValue
  program : String?
  external_model_cids : Array[String]
  preview : EffectPreviewIdentity?
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
priv enum ComputationSuffixPhase {
  Begin
  Authoring(EvidenceStreamPreparation, @json.CanonicalValue)
  Models
  Model(Int)
  Identity(Int, String, EvidenceStreamPreparation)
  External(Int)
  SortModels(@sort.Sort)
  SortExternal(@sort.Sort)
  Compare(Int, Int)
  Done
}

///|
/// Continue the existing suffix validation without borrowing mutable sort
/// state from the prelude. Physical custody remains with the parent owner.
priv struct ComputationSuffixPreparation {
  mut inputs : ComputationSuffixInputs?
  max_workspace : Int
  mut models : @json.FrozenArray[@json.CanonicalValue]?
  mut listed : @json.FrozenArray[@json.CanonicalValue]?
  model_keys : Array[Array[String]]
  external_keys : Array[Array[String]]
  mut model_sort : @sort.Sort?
  mut external_sort : @sort.Sort?
  mut phase : ComputationSuffixPhase
  mut live : Int
  mut peak : Int
  mut closed : Bool
}

///|
fn start_computation_suffix(
  inputs : ComputationSuffixInputs,
  max_workspace : Int,
) -> ComputationSuffixPreparation {
  {
    inputs: Some(inputs),
    max_workspace,
    models: None,
    listed: None,
    model_keys: [],
    external_keys: [],
    model_sort: None,
    external_sort: None,
    phase: Begin,
    live: 16,
    peak: 16,
    closed: false,
  }
}

///|
fn ComputationSuffixPreparation::reserve(
  self : ComputationSuffixPreparation,
  slots : Int,
) -> Result[Unit, RunEvidenceChainIssue] {
  if slots < 0 || slots > self.max_workspace - self.live {
    return Err(EvidenceEncoding)
  }
  self.live += slots
  self.peak = Int::max(self.peak, self.live)
  Ok(())
}

///|
fn ComputationSuffixPreparation::identity(
  self : ComputationSuffixPreparation,
  value : @json.CanonicalValue,
  field : String,
  issue : RunEvidenceChainIssue,
) -> Result[(String, EvidenceStreamPreparation), RunEvidenceChainIssue] {
  let inputs = self.inputs.unwrap()
  guard evidence_string(value, field) is Some(cid) &&
    @json.object_without_field(value, field) is Some(body) else {
    return Err(issue)
  }
  if self.max_workspace - self.live < 12 {
    return Err(EvidenceEncoding)
  }
  Ok(
    (
      cid,
      start_evidence_stream(
        body,
        Identity(cid),
        inputs.max_wire_bytes,
        inputs.max_nodes,
        inputs.max_depth,
        self.max_workspace - self.live,
      ),
    ),
  )
}

///|
fn ComputationSuffixPreparation::step(
  self : ComputationSuffixPreparation,
) -> Result[Unit, RunEvidenceChainIssue] {
  let inputs = self.inputs.unwrap()
  match self.phase {
    Begin => {
      guard self.reserve(0) is Ok(_) else { return Err(EvidenceEncoding) }
      let authoring = match
        evidence_object(inputs.context, "authoring_context") {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let (_, child) = match
        self.identity(
          authoring,
          "authoring_context_cid",
          EvidenceEmbeddedIdentity("authoring_context_cid"),
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.phase = Authoring(child, authoring)
    }
    Authoring(child, authoring) => {
      let (done, _) = match child.advance(1) {
        Ok(result) => result
        Err(_) => return Err(EvidenceEmbeddedIdentity("authoring_context_cid"))
      }
      self.peak = Int::max(self.peak, self.live + child.peak)
      if done {
        if !child.finish().unwrap() ||
          evidence_string(authoring, "program_definition_cid") != inputs.program {
          return Err(EvidenceEmbeddedIdentity("authoring_context_cid"))
        }
        if inputs.preview is Some(preview) &&
          evidence_string(authoring, "authoring_context_cid") !=
          Some(preview.authoring_context_cid) {
          return Err(EvidenceReferenceMismatch("preview.authoring_context_cid"))
        }
        self.phase = Models
      }
    }
    Models => {
      guard @json.object_field(inputs.context, "model_invocation_evidence")
        is Some(models) else {
        return Err(EvidenceMissingField("model_invocation_evidence"))
      }
      guard @json.object_field(inputs.context, "model_invocation_evidence_cids")
        is Some(listed) else {
        return Err(EvidenceMissingField("model_invocation_evidence_cids"))
      }
      guard models is @json.Array(model_array) &&
        listed is @json.Array(listed_array) &&
        @json.array_count(model_array) == @json.array_count(listed_array) else {
        return Err(EvidenceReferenceMismatch("model_invocation_evidence_cids"))
      }
      self.models = Some(model_array)
      self.listed = Some(listed_array)
      self.phase = Model(0)
    }
    Model(index) =>
      if index == @json.array_count(self.models.unwrap()) {
        self.phase = External(0)
      } else {
        let value = @json.array_at(self.models.unwrap(), index).unwrap()
        let (cid, child) = match
          self.identity(
            value,
            "model_invocation_evidence_cid",
            EvidenceReferenceMismatch("model_invocation_evidence_cids"),
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        self.phase = Identity(index, cid, child)
      }
    Identity(index, cid, child) => {
      let (done, _) = match child.advance(1) {
        Ok(result) => result
        Err(_) =>
          return Err(
            EvidenceReferenceMismatch("model_invocation_evidence_cids"),
          )
      }
      self.peak = Int::max(self.peak, self.live + child.peak)
      if done {
        if !child.finish().unwrap() {
          return Err(
            EvidenceReferenceMismatch("model_invocation_evidence_cids"),
          )
        }
        guard @json.array_at(self.listed.unwrap(), index)
          is Some(@json.String(listed)) &&
          listed == cid else {
          return Err(
            EvidenceReferenceMismatch("model_invocation_evidence_cids"),
          )
        }
        // Singleton tuple, component and two deferred-sort index slots.
        guard self.reserve(4) is Ok(_) else { return Err(EvidenceEncoding) }
        self.model_keys.push([cid])
        self.phase = Model(index + 1)
      }
    }
    External(index) =>
      if index == inputs.external_model_cids.length() {
        if self.model_keys.length() != self.external_keys.length() {
          return Err(EvidenceReferenceMismatch("external_model_evidence"))
        }
        let sort = match
          @sort.prepare_deferred(self.model_keys, self.model_keys.length() * 2) {
          Ok(value) => value
          Err(_) => return Err(EvidenceEncoding)
        }
        self.model_sort = Some(sort)
        self.phase = SortModels(sort)
      } else {
        guard self.reserve(4) is Ok(_) else { return Err(EvidenceEncoding) }
        self.external_keys.push([inputs.external_model_cids[index]])
        self.phase = External(index + 1)
      }
    SortModels(sort) =>
      match @sort.advance(sort, 1) {
        Err(_) => return Err(EvidenceEncoding)
        Ok(@sort.Continue(..)) => ()
        Ok(@sort.Complete(..)) => {
          let external = match
            @sort.prepare_deferred(
              self.external_keys,
              self.external_keys.length() * 2,
            ) {
            Ok(value) => value
            Err(_) => return Err(EvidenceEncoding)
          }
          self.external_sort = Some(external)
          self.phase = SortExternal(external)
        }
      }
    SortExternal(sort) =>
      match @sort.advance(sort, 1) {
        Err(_) => return Err(EvidenceEncoding)
        Ok(@sort.Continue(..)) => ()
        Ok(@sort.Complete(..)) => self.phase = Compare(0, 0)
      }
    Compare(index, offset) =>
      if index == self.model_keys.length() {
        self.phase = Done
      } else {
        let left = @sort.key_component_at(self.model_sort.unwrap(), index, 0).unwrap()
        let right = @sort.key_component_at(
          self.external_sort.unwrap(),
          index,
          0,
        ).unwrap()
        let (compared, next, _) = @canonical.compare_utf16_fragment(
          left, right, offset, 64,
        )
        match compared {
          None => self.phase = Compare(index, next)
          Some(0) => self.phase = Compare(index + 1, 0)
          Some(_) =>
            return Err(EvidenceReferenceMismatch("external_model_evidence"))
        }
      }
    Done => ()
  }
  Ok(())
}

///|
fn ComputationSuffixPreparation::advance(
  self : ComputationSuffixPreparation,
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
fn ComputationSuffixPreparation::finish(
  self : ComputationSuffixPreparation,
) -> Result[Unit, RunEvidenceChainIssue] {
  if self.closed || !(self.phase is Done) {
    return Err(EvidenceEncoding)
  }
  self.cancel()
  Ok(())
}

///|
fn ComputationSuffixPreparation::cancel(
  self : ComputationSuffixPreparation,
) -> Unit {
  if self.closed {
    return
  }
  match self.phase {
    Authoring(child, _) | Identity(_, _, child) => child.cancel()
    _ => ()
  }
  if self.model_sort is Some(sort) {
    let _ = @sort.cleanup(sort)
  }
  if self.external_sort is Some(sort) {
    let _ = @sort.cleanup(sort)
  }
  self.model_sort = None
  self.external_sort = None
  self.model_keys.clear()
  self.external_keys.clear()
  self.models = None
  self.listed = None
  self.inputs = None
  self.phase = Done
  self.live = 0
  self.closed = true
}
