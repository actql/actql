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
  PreludeAfterRoot
  PreludeCheck(ComputationPreludePreparation)
  ContextHash(@json.CanonicalEmit, String)
  Content
  ContentCheck(ContentCaptureCheck)
  Inventory
  InventoryCheck(CaptureInventoryPreparation)
  Artifact(Int)
  Definition(Int, Int, String, Int)
  ResultLookup(Int, PublicationContract, String, Int, Int)
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
  mut retained_capture : CapturedRunIssuancePreparation?
  mut retained_snapshots : Array[CapturedResultSnapshot?]?
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
    retained_capture: None,
    retained_snapshots: None,
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
    Prelude | PreludeAfterRoot => {
      let after_root = self.phase is PreludeAfterRoot
      if self.max_workspace < self.live {
        return Err(EvidenceEncoding)
      }
      if self.max_workspace - self.live < 16 {
        return Err(EvidenceEncoding)
      }
      self.phase = PreludeCheck(
        start_computation_prelude(
          inputs,
          self.max_workspace - self.live,
          after_root~,
        ),
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
          self.phase = Content
        }
      } catch {
        _ => return Err(EvidenceEmbeddedIdentity("effect_context_cid"))
      }
    }
    Content => {
      if self.max_workspace - self.live < 12 {
        return Err(EvidenceEncoding)
      }
      self.phase = ContentCheck(
        start_content_capture_check(
          inputs,
          self.prelude.unwrap().effect_context,
          self.max_workspace - self.live,
        ),
      )
    }
    ContentCheck(child) => {
      let (done, _) = match child.advance(1) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.peak = Int::max(self.peak, self.live + child.peak)
      if done {
        child.cancel()
        self.phase = Inventory
      }
    }
    Inventory => {
      let prelude = self.prelude.unwrap()
      match computation_evidence_capture_preflight(inputs, prelude) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      if self.max_workspace - self.live < 12 {
        return Err(EvidenceEncoding)
      }
      self.phase = InventoryCheck(
        start_capture_inventory(
          {
            context: prelude.effect_context,
            manifest_results: prelude.manifest_results,
            max_wire_bytes: inputs.max_wire_bytes,
            max_nodes: inputs.max_nodes,
            max_depth: inputs.max_depth,
          },
          self.max_workspace - self.live,
        ),
      )
    }
    InventoryCheck(child) => {
      let (done, _) = match child.advance(1) {
        Ok(result) => result
        Err(issue) => return Err(issue)
      }
      self.peak = Int::max(self.peak, self.live + child.peak)
      if done {
        let (values, fields) = child.finish().unwrap()
        self.values = Some(values)
        self.field_inventory = Some(fields)
        self.phase = Artifact(0)
      }
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
        guard contract_string(definition, "result_name") is Some(name) else {
          return Err(EvidenceInventoryMismatch("captured_results"))
        }
        self.phase = ResultLookup(artifact, definition, name, 0, 0)
      }
    ResultLookup(artifact, definition, name, index, offset) => {
      guard self.values.unwrap() is @json.Object(values) &&
        self.field_inventory.unwrap() is @json.Object(field_inventory) &&
        @json.array_at(values, index) is Some((current, rows)) else {
        return Err(EvidenceInventoryMismatch("captured_results"))
      }
      let (compared, next, _) = @canonical.compare_utf16_fragment(
        name, current, offset, 64,
      )
      match compared {
        None =>
          self.phase = ResultLookup(artifact, definition, name, index, next)
        Some(0) => {
          guard rows is @json.Array(_) &&
            @json.array_at(field_inventory, index)
            is Some((_, @json.Array(fields))) else {
            return Err(EvidenceInventoryMismatch("captured_results"))
          }
          // Both borrowed objects were admitted with exactly the same sorted
          // keys. Reuse this index; never repeat a synchronous name lookup.
          self.phase = Fields(artifact, definition, rows, fields, 0)
        }
        Some(_) =>
          self.phase = ResultLookup(artifact, definition, name, index + 1, 0)
      }
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
            match self.retained_snapshots {
              None => child.cancel()
              Some(snapshots) => {
                // SAME checked rows are borrowed from the original captured
                // contract. Fund the transferred snapshot/field inventory
                // before finish; no second parse or Result execution occurs.
                match self.reserve(12 + child.fields.length()) {
                  Err(issue) => return Err(issue)
                  Ok(_) => ()
                }
                let snapshot = match child.finish() {
                  Ok(value) => value
                  Err(_) =>
                    return Err(
                      EvidenceReferenceMismatch("captured_result_values"),
                    )
                }
                snapshots[index] = Some(snapshot)
              }
            }
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
  if self.retained_capture is Some(original) && original.closed {
    self.cancel()
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
  if self.closed ||
    !(self.phase is Done) ||
    (self.retained_capture is Some(original) && original.closed) {
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
    InventoryCheck(child) => child.cancel()
    SuffixCheck(child) => child.cancel()
    ContentCheck(child) => child.cancel()
    ContextHash(cursor, _) => @json.cancel_emit(cursor)
    Rows(_, child) => child.cancel()
    _ => ()
  }
  if self.writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  self.inputs = None
  self.retained_capture = None
  if self.retained_snapshots is Some(snapshots) {
    snapshots.clear()
  }
  self.retained_snapshots = None
  self.prelude = None
  self.values = None
  self.field_inventory = None
  self.writer = None
  self.fields.clear()
  self.phase = Done
  self.live = 0
}

///|
// Opt-in transfer only after the SAME complete validator succeeds. The exact
// pre-sized slots cannot grow or escape on a failed later suffix validation.
fn ComputationEvidenceCheck::retain_result_snapshots(
  self : ComputationEvidenceCheck,
) -> Result[Unit, RunEvidenceChainIssue] {
  guard !self.closed && self.phase is Prelude && self.inputs is Some(inputs) else {
    return Err(EvidenceEncoding)
  }
  match self.reserve(2 + inputs.artifacts.length()) {
    Err(issue) => {
      self.cancel()
      return Err(issue)
    }
    Ok(_) => ()
  }
  self.retained_snapshots = Some(Array::make(inputs.artifacts.length(), None))
  Ok(())
}

///|
fn ComputationEvidenceCheck::finish_result_snapshots(
  self : ComputationEvidenceCheck,
) -> Result[Array[CapturedResultSnapshot?], RunEvidenceChainIssue] {
  guard !self.closed &&
    self.phase is Done &&
    self.retained_snapshots is Some(snapshots) &&
    !(self.retained_capture is Some(original) && original.closed) else {
    self.cancel()
    return Err(EvidenceEncoding)
  }
  self.retained_snapshots = None
  self.cancel()
  Ok(snapshots)
}
