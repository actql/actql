///|
priv struct ComputationEvidenceInputs {
  run_definition : PublicationContract
  invocation : PublicationContract
  definitions : Array[PublicationContract]
  artifacts : Array[PublicationContract]
  manifest : PublicationContract
  receipt : PublicationContract
  captured_run : PublicationContract
  preview : EffectPreviewIdentity?
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
priv struct ComputationEvidencePrelude {
  effect_context : @json.CanonicalValue
  program : String?
  external_model_cids : Array[String]
  manifest_results : @json.CanonicalValue
}

///|
priv enum ComputationEvidencePhase {
  Prelude
  PreludeCheck(ComputationPreludePreparation)
  ContextHash(@json.CanonicalEmit, String)
  Inventory
  Artifact(Int)
  Definition(Int, Int, String, Int)
  Fields(
    Int,
    PublicationContract,
    @json.CanonicalValue,
    @json.FrozenArray[@json.CanonicalValue],
    Int
  )
  Rows(Int, CapturedResultSnapshotPreparation)
  Suffix
  SuffixCheck(ComputationSuffixPreparation)
  Done
}

///|
/// The existing chain validator's context hash and Result-row checks. Metadata
/// leaf checks still use their original validators; no CID-only shortcut grants
/// validity to a row inventory. Borrowed contracts remain with the caller.
struct ComputationEvidenceCheck {
  mut inputs : ComputationEvidenceInputs?
  max_workspace : Int
  mut prelude : ComputationEvidencePrelude?
  mut values : @json.CanonicalValue?
  mut field_inventory : @json.CanonicalValue?
  fields : Array[String]
  mut writer : @encode.Writer?
  mut phase : ComputationEvidencePhase
  mut live : Int
  mut peak : Int
  mut closed : Bool
}

///|
fn start_computation_evidence_check(
  inputs : ComputationEvidenceInputs,
  max_workspace : Int,
) -> ComputationEvidenceCheck {
  {
    inputs: Some(inputs),
    max_workspace,
    prelude: None,
    values: None,
    field_inventory: None,
    fields: [],
    writer: None,
    phase: Prelude,
    live: 12,
    peak: 12,
    closed: false,
  }
}

///|
fn ComputationEvidenceCheck::reserve(
  self : ComputationEvidenceCheck,
  count : Int,
) -> Result[Unit, RunEvidenceChainIssue] {
  if count < 0 || count > self.max_workspace - self.live {
    return Err(EvidenceEncoding)
  }
  self.live += count
  self.peak = Int::max(self.peak, self.live)
  Ok(())
}

///|
fn ComputationEvidenceCheck::step(
  self : ComputationEvidenceCheck,
) -> Result[Unit, RunEvidenceChainIssue] {
  let inputs = self.inputs.unwrap()
  match self.phase {
    Prelude => {
      if self.max_workspace < self.live {
        return Err(EvidenceEncoding)
      }
      if self.max_workspace - self.live < 16 {
        return Err(EvidenceEncoding)
      }
      self.phase = PreludeCheck(
        start_computation_prelude(inputs, self.max_workspace - self.live),
      )
    }
    PreludeCheck(child) => {
      let (done, _) = match child.advance(1) {
        Ok(result) => result
        Err(issue) => return Err(issue)
      }
      self.peak = Int::max(self.peak, self.live + child.peak)
      if !done {
        return Ok(())
      }
      let prelude = child.finish().unwrap()
      match self.reserve(prelude.external_model_cids.length()) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      self.prelude = Some(prelude)
      guard evidence_string(prelude.effect_context, "effect_context_cid")
        is Some(identity) &&
        @json.object_without_field(prelude.effect_context, "effect_context_cid")
        is Some(body) else {
        return Err(EvidenceEmbeddedIdentity("effect_context_cid"))
      }
      match self.reserve(1) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      try {
        let writer = @encode.hashing_writer(
          inputs.max_wire_bytes,
          inputs.max_nodes,
          inputs.max_depth,
        )
        self.writer = Some(writer)
        self.phase = ContextHash(@json.start_emit(body, writer), identity)
      } catch {
        _ => return Err(EvidenceEmbeddedIdentity("effect_context_cid"))
      }
    }
    ContextHash(cursor, identity) => {
      let before = @json.emit_pending_frames(cursor)
      match self.reserve(1) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      try {
        let done = @json.advance_emit(cursor)
        self.live += @json.emit_pending_frames(cursor) - before - 1
        if done {
          let (digest, _, _) = @encode.finish_hash_usage(self.writer.unwrap())
          self.writer = None
          if "sha256:" + digest != identity {
            return Err(EvidenceEmbeddedIdentity("effect_context_cid"))
          }
          self.phase = Inventory
        }
      } catch {
        _ => return Err(EvidenceEmbeddedIdentity("effect_context_cid"))
      }
    }
    Inventory => {
      let (values, fields) = match
        computation_evidence_capture_inventory(inputs, self.prelude.unwrap()) {
        Ok(pair) => pair
        Err(issue) => return Err(issue)
      }
      self.values = Some(values)
      self.field_inventory = Some(fields)
      self.phase = Artifact(0)
    }
    Artifact(index) => {
      if index == inputs.artifacts.length() {
        self.phase = Suffix
        return Ok(())
      }
      guard contract_string(inputs.artifacts[index], "result_definition_cid")
        is Some(definition) else {
        return Err(EvidenceInventoryMismatch("captured_results"))
      }
      self.phase = Definition(index, 0, definition, -1)
    }
    Definition(artifact, index, identity, found) =>
      if index < inputs.definitions.length() {
        if inputs.definitions[index].identity == identity {
          if found >= 0 {
            return Err(EvidenceInventoryMismatch("captured_results"))
          }
          self.phase = Definition(artifact, index + 1, identity, index)
        } else {
          self.phase = Definition(artifact, index + 1, identity, found)
        }
      } else {
        if found < 0 {
          return Err(EvidenceInventoryMismatch("captured_results"))
        }
        let definition = inputs.definitions[found]
        guard contract_string(definition, "result_name") is Some(name) &&
          @json.object_field(self.values.unwrap(), name) is Some(rows) &&
          rows is @json.Array(_) &&
          @json.object_field(self.field_inventory.unwrap(), name)
          is Some(@json.Array(fields)) else {
          return Err(EvidenceInventoryMismatch("captured_results"))
        }
        self.phase = Fields(artifact, definition, rows, fields, 0)
      }
    Fields(artifact, definition, rows, fields, index) =>
      if index == @json.array_count(fields) {
        let child = match
          start_captured_snapshot_value_check(
            definition,
            inputs.artifacts[artifact],
            rows,
            self.fields,
            inputs.max_wire_bytes,
            inputs.max_nodes,
            inputs.max_depth,
            self.max_workspace - self.live,
          ) {
          Ok(child) => child
          Err(_) =>
            return Err(EvidenceReferenceMismatch("captured_result_values"))
        }
        self.peak = Int::max(self.peak, self.live + child.live)
        self.phase = Rows(artifact, child)
      } else {
        guard @json.array_at(fields, index).unwrap() is @json.String(field) else {
          return Err(EvidenceInventoryMismatch("captured_results"))
        }
        match self.reserve(1) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
        self.fields.push(field)
        self.phase = Fields(artifact, definition, rows, fields, index + 1)
      }
    Rows(index, child) =>
      match child.advance(1) {
        Err(_) =>
          return Err(EvidenceReferenceMismatch("captured_result_values"))
        Ok((done, _)) => {
          self.peak = Int::max(self.peak, self.live + child.peak)
          if done {
            // No snapshot transfer is required for validation. Retire the child
            // before releasing the field array it borrowed from this owner.
            child.cancel()
            self.live -= self.fields.length()
            self.fields.clear()
            self.phase = Artifact(index + 1)
          }
        }
      }
    Suffix => {
      if self.max_workspace - self.live < 16 {
        return Err(EvidenceEncoding)
      }
      let prelude = self.prelude.unwrap()
      self.phase = SuffixCheck(
        start_computation_suffix(
          {
            context: prelude.effect_context,
            program: prelude.program,
            external_model_cids: prelude.external_model_cids,
            preview: inputs.preview,
            max_wire_bytes: inputs.max_wire_bytes,
            max_nodes: inputs.max_nodes,
            max_depth: inputs.max_depth,
          },
          self.max_workspace - self.live,
        ),
      )
    }
    SuffixCheck(child) => {
      let (done, _) = match child.advance(1) {
        Ok(result) => result
        Err(issue) => return Err(issue)
      }
      self.peak = Int::max(self.peak, self.live + child.peak)
      if done {
        child.finish().unwrap()
        self.phase = Done
      }
    }
    Done => ()
  }
  Ok(())
}

///|
pub fn ComputationEvidenceCheck::advance(
  self : ComputationEvidenceCheck,
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
pub fn ComputationEvidenceCheck::finish(
  self : ComputationEvidenceCheck,
) -> Result[Unit, RunEvidenceChainIssue] {
  if self.closed || !(self.phase is Done) {
    return Err(EvidenceEncoding)
  }
  self.cancel()
  Ok(())
}

///|
pub fn ComputationEvidenceCheck::cancel(
  self : ComputationEvidenceCheck,
) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  match self.phase {
    PreludeCheck(child) => child.cancel()
    SuffixCheck(child) => child.cancel()
    ContextHash(cursor, _) => @json.cancel_emit(cursor)
    Rows(_, child) => child.cancel()
    _ => ()
  }
  if self.writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  self.inputs = None
  self.prelude = None
  self.values = None
  self.field_inventory = None
  self.writer = None
  self.fields.clear()
  self.phase = Done
  self.live = 0
}
