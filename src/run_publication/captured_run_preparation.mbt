///|
priv struct CapturedRunIssuanceInputs {
  run_definition : PublicationContract
  invocation : PublicationContract
  definitions : Array[PublicationContract]
  artifacts : Array[PublicationContract]
  manifest : PublicationContract
  receipt : PublicationContract
  snapshots : Array[CapturedResultSnapshot]
  sources : Array[CapturedEffectSourceArtifact]
  local_sources : Array[CapturedLocalEffectSourceEvidence]
  advances : Array[PendingSourceStateAdvance]
  authoring : RunEvidenceValue
  models : Array[RunEvidenceValue]
  preview : EffectPreviewIdentity?
  plan_values : Array[(String, String)]
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  dependency_inventory : CapturedEffectDependencyInventory?
}

///|
priv enum CapturedRunPreparationPhase {
  Prepare
  Root(PublicationRootPreparation)
  PrepareChecked
  Context(EffectContextPreparation)
  Envelope(Int)
  Emit(@json.CanonicalEmit, Int)
  Seal(PublicationSealPreparation)
  Check(ComputationEvidenceCheck)
  Done
}

///|
/// Aggregate continuation of the original issuer. The caller retains Store
/// custody until finish transfers the checked contract; cancel retires only
/// this preparation and never releases inputs or reruns Compute.
struct CapturedRunIssuancePreparation {
  mut inputs : CapturedRunIssuanceInputs?
  max_workspace : Int
  mut context : @json.CanonicalValue?
  mut writer : @encode.Writer?
  mut contract : PublicationContract?
  mut phase : CapturedRunPreparationPhase
  mut live : Int
  mut peak : Int
  mut closed : Bool
}

///|
fn start_captured_computation_preparation(
  inputs : CapturedRunIssuanceInputs,
  max_workspace : Int,
) -> CapturedRunIssuancePreparation {
  {
    inputs: Some(inputs),
    max_workspace,
    context: None,
    writer: None,
    contract: None,
    phase: Prepare,
    live: 16,
    peak: 16,
    closed: false,
  }
}

///|
pub fn start_effect_free_captured_run(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  snapshots : Array[CapturedResultSnapshot],
  advances : Array[PendingSourceStateAdvance],
  authoring : RunEvidenceValue,
  models : Array[RunEvidenceValue],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
) -> CapturedRunIssuancePreparation {
  start_captured_computation_preparation(
    {
      run_definition,
      invocation,
      definitions,
      artifacts,
      manifest,
      receipt,
      snapshots,
      sources: [],
      local_sources: [],
      advances,
      authoring,
      models,
      preview: None,
      plan_values: [],
      max_wire_bytes,
      max_nodes,
      max_depth,
      dependency_inventory: None,
    },
    max_workspace,
  )
}

///|
pub fn start_effectful_captured_run(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  snapshots : Array[CapturedResultSnapshot],
  sources : Array[CapturedEffectSourceArtifact],
  local_sources : Array[CapturedLocalEffectSourceEvidence],
  advances : Array[PendingSourceStateAdvance],
  authoring : RunEvidenceValue,
  models : Array[RunEvidenceValue],
  preview : EffectPreviewIdentity,
  plan_values : Array[(String, String)],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
  dependency_inventory? : CapturedEffectDependencyInventory? = None,
) -> CapturedRunIssuancePreparation {
  start_captured_computation_preparation(
    {
      run_definition,
      invocation,
      definitions,
      artifacts,
      manifest,
      receipt,
      snapshots,
      sources,
      local_sources,
      advances,
      authoring,
      models,
      preview: Some(preview),
      plan_values,
      max_wire_bytes,
      max_nodes,
      max_depth,
      dependency_inventory,
    },
    max_workspace,
  )
}

///|
fn CapturedRunIssuancePreparation::reserve(
  self : CapturedRunIssuancePreparation,
  count : Int,
) -> Result[Unit, CapturedRunIssuanceIssue] {
  if count < 0 || count > self.max_workspace - self.live {
    return Err(CaptureIssuanceEncoding)
  }
  self.live += count
  self.peak = Int::max(self.peak, self.live)
  Ok(())
}

///|
fn CapturedRunIssuancePreparation::step(
  self : CapturedRunIssuancePreparation,
) -> Result[Unit, CapturedRunIssuanceIssue] {
  let inputs = self.inputs.unwrap()
  match self.phase {
    Prepare => {
      if self.max_workspace < self.live {
        return Err(CaptureIssuanceEncoding)
      }
      if inputs.authoring.name != "authoring_context" {
        return Err(CaptureIssuanceWrongContract("authoring_context"))
      }
      if self.max_workspace - self.live < 12 {
        return Err(CaptureIssuanceEncoding)
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
        Err(issue) => return Err(CaptureIssuanceChain(issue))
        Ok((done, _)) => {
          self.peak = Int::max(self.peak, self.live + child.peak)
          if done {
            child.cancel()
            self.phase = PrepareChecked
          }
        }
      }
    PrepareChecked => {
      let prepared = match
        prepare_captured_computation_inputs_after_root(inputs) {
        Ok(prepared) => prepared
        Err(issue) => return Err(issue)
      }
      let child = match
        start_effect_context_preparation(
          prepared.snapshots,
          prepared.sources,
          prepared.local_sources,
          prepared.dependencies,
          prepared.advances,
          prepared.authoring,
          prepared.models,
          prepared.preview,
          prepared.plans,
          inputs.max_wire_bytes,
          inputs.max_nodes,
          inputs.max_depth,
          self.max_workspace - self.live,
        ) {
        Ok(child) => child
        Err(issue) => return Err(issue)
      }
      self.phase = Context(child)
    }
    Context(child) =>
      match child.advance(1) {
        Err(issue) => return Err(issue)
        Ok((done, _)) => {
          self.peak = Int::max(self.peak, self.live + child.peak)
          if done {
            self.context = Some(
              match child.finish() {
                Ok(value) => value
                Err(issue) => return Err(issue)
              },
            )
            try {
              let writer = @encode.writer(
                inputs.max_wire_bytes,
                inputs.max_nodes,
                inputs.max_depth,
              )
              self.writer = Some(writer)
              @encode.begin_ordered_object(writer)
              self.phase = Envelope(0)
            } catch {
              _ => return Err(CaptureIssuanceEncoding)
            }
          }
        }
      }
    Envelope(index) => {
      let writer = self.writer.unwrap()
      try {
        if index == 6 {
          @encode.end_object(writer)
          let wire = @encode.finish(writer)
          self.writer = None
          self.context = None
          let child = match
            start_publication_seal_preparation(
              "captured_run",
              wire,
              inputs.max_wire_bytes,
              inputs.max_nodes,
              inputs.max_depth,
              self.max_workspace - self.live,
            ) {
            Ok(child) => child
            Err(issue) => return Err(CaptureIssuanceContract(issue))
          }
          self.phase = Seal(child)
        } else {
          let field = match index {
            0 => "effect_context"
            1 => "encryption_required"
            2 => "receipt"
            3 => "retention_class"
            4 => "sensitivity"
            _ => "version"
          }
          // Only fixed envelope keys/scalars are emitted without a child.
          @encode.ordered_key(writer, field)
          match index {
            0 | 2 => {
              match self.reserve(1) {
                Err(issue) => return Err(issue)
                Ok(_) => ()
              }
              let value = if index == 0 {
                self.context.unwrap()
              } else {
                inputs.receipt.value
              }
              self.phase = Emit(@json.start_emit(value, writer), index + 1)
            }
            1 => {
              @encode.bool_value(writer, true)
              self.phase = Envelope(index + 1)
            }
            _ => {
              @encode.string_value(
                writer,
                match index {
                  3 => "run-evidence"
                  4 => "private"
                  _ => "actql-captured-run/0.1"
                },
              )
              self.phase = Envelope(index + 1)
            }
          }
        }
      } catch {
        _ => return Err(CaptureIssuanceEncoding)
      }
    }
    Emit(cursor, next) => {
      let before = @json.emit_pending_frames(cursor)
      match self.reserve(1) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      try {
        let done = @json.advance_emit(cursor)
        self.live += @json.emit_pending_frames(cursor) - before - 1
        if done {
          self.phase = Envelope(next)
        }
      } catch {
        _ => return Err(CaptureIssuanceEncoding)
      }
    }
    Seal(child) =>
      match child.advance(1) {
        Err(issue) => return Err(CaptureIssuanceContract(issue))
        Ok((done, _)) => {
          self.peak = Int::max(self.peak, self.live + child.peak)
          if done {
            let contract = match child.finish() {
              Ok(contract) => contract
              Err(issue) => return Err(CaptureIssuanceContract(issue))
            }
            self.contract = Some(contract)
            self.phase = Check(
              start_computation_evidence_check(
                {
                  run_definition: inputs.run_definition,
                  invocation: inputs.invocation,
                  definitions: inputs.definitions,
                  artifacts: inputs.artifacts,
                  manifest: inputs.manifest,
                  receipt: inputs.receipt,
                  captured_run: contract,
                  preview: inputs.preview,
                  max_wire_bytes: inputs.max_wire_bytes,
                  max_nodes: inputs.max_nodes,
                  max_depth: inputs.max_depth,
                },
                self.max_workspace - self.live,
              ),
            )
          }
        }
      }
    Check(child) =>
      match child.advance(1) {
        Err(issue) => return Err(CaptureIssuanceChain(issue))
        Ok((done, _)) => {
          self.peak = Int::max(self.peak, self.live + child.peak)
          if done {
            match child.finish() {
              Err(issue) => return Err(CaptureIssuanceChain(issue))
              Ok(_) => self.phase = Done
            }
          }
        }
      }
    Done => ()
  }
  Ok(())
}

///|
pub fn CapturedRunIssuancePreparation::advance(
  self : CapturedRunIssuancePreparation,
  quantum : Int,
) -> Result[(Bool, Int), CapturedRunIssuanceIssue] {
  if self.closed || quantum < 1 {
    return Err(CaptureIssuanceEncoding)
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
pub fn CapturedRunIssuancePreparation::finish(
  self : CapturedRunIssuancePreparation,
) -> Result[PublicationContract, CapturedRunIssuanceIssue] {
  guard !self.closed && self.phase is Done && self.contract is Some(contract) else {
    return Err(CaptureIssuanceEncoding)
  }
  self.contract = None
  self.cancel()
  Ok(contract)
}

///|
pub fn CapturedRunIssuancePreparation::cancel(
  self : CapturedRunIssuancePreparation,
) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  match self.phase {
    Root(child) => child.cancel()
    Context(child) => child.cancel()
    Emit(cursor, _) => @json.cancel_emit(cursor)
    Seal(child) => child.cancel()
    Check(child) => child.cancel()
    _ => ()
  }
  if self.writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  self.inputs = None
  self.context = None
  self.writer = None
  self.contract = None
  self.phase = Done
  self.live = 0
}

///|
/// Read-only fixture synchronization; not a Run outcome or authority proof.
pub fn captured_run_preparation_fixture_phase(
  preparation : CapturedRunIssuancePreparation,
) -> String {
  if preparation.closed {
    return "closed"
  }
  match preparation.phase {
    Prepare => "prepare"
    Root(_) => "root-check"
    PrepareChecked => "prepare"
    Context(_) => "context"
    Envelope(_) | Emit(_, _) => "envelope"
    Seal(_) => "seal"
    Check(child) => computation_evidence_check_fixture_phase(child)
    Done => "done"
  }
}
