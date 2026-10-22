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
  content_generations : Array[BoundContentGeneration]
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
  Advances(Int, String)
  SnapshotInventory(CapturedOrderedInventoryPreparation)
  Sources
  ModelInventory(CapturedOrderedInventoryPreparation)
  PrepareContext
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
  mut snapshot_inventory : Array[CapturedResultSnapshot]?
  mut source_inventory : (
    Array[CapturedEffectSourceArtifact],
    Array[CapturedLocalEffectSourceEvidence],
  )?
  mut model_inventory : Array[RunEvidenceValue]?
  mut inventory_slots : Int
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
    snapshot_inventory: None,
    source_inventory: None,
    model_inventory: None,
    inventory_slots: 0,
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
  content_generations? : Array[BoundContentGeneration] = [],
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
      content_generations,
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
  content_generations? : Array[BoundContentGeneration] = [],
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
      content_generations,
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
      if inputs.definitions.is_empty() && inputs.preview is None {
        return Err(CaptureIssuanceChain(EvidenceRoot(ChainEmptyInventory)))
      }
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
      if inputs.receipt.name != "run_receipt" {
        return Err(CaptureIssuanceWrongContract("run_receipt"))
      }
      guard contract_string(inputs.invocation, "observation_set_cid")
        is Some(observation_set_cid) else {
        return Err(CaptureIssuanceReferenceMismatch("observation_set_cid"))
      }
      self.phase = Advances(0, observation_set_cid)
    }
    Advances(index, observation_set_cid) =>
      if index < inputs.advances.length() {
        if evidence_string(inputs.advances[index].value, "observation_set_cid") !=
          Some(observation_set_cid) {
          return Err(CaptureIssuanceReferenceMismatch("source_state_advance"))
        }
        self.phase = Advances(index + 1, observation_set_cid)
      } else {
        guard evidence_string(inputs.receipt.value, "program_definition_cid")
          is Some(program_definition_cid) else {
          return Err(CaptureIssuanceReferenceMismatch("program_definition_cid"))
        }
        if evidence_string(inputs.authoring.value, "program_definition_cid") !=
          Some(program_definition_cid) {
          return Err(CaptureIssuanceReferenceMismatch("authoring_context"))
        }
        if self.max_workspace - self.live < 12 {
          return Err(CaptureIssuanceEncoding)
        }
        self.phase = SnapshotInventory(
          start_captured_ordered_inventory(
            Snapshots(inputs.definitions, inputs.artifacts, inputs.snapshots),
            self.max_workspace - self.live,
          ),
        )
      }
    SnapshotInventory(child) => {
      let (done, _) = match child.advance(1) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.peak = Int::max(self.peak, self.live + child.peak)
      if done {
        guard child.finish() is Ok(OrderedSnapshots(snapshots)) else {
          return Err(CaptureIssuanceEncoding)
        }
        match self.reserve(snapshots.length()) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
        self.inventory_slots += snapshots.length()
        self.snapshot_inventory = Some(snapshots)
        self.phase = Sources
      }
    }
    Sources => {
      // Effect-specific admission keeps its original position and semantics.
      // It is not yet an asynchronous dependency-closure preparation.
      self.source_inventory = Some(
        match prepare_captured_effect_sources(inputs) {
          Ok(sources) => sources
          Err(issue) => return Err(issue)
        },
      )
      if self.max_workspace - self.live < 12 {
        return Err(CaptureIssuanceEncoding)
      }
      self.phase = ModelInventory(
        start_captured_ordered_inventory(
          Models(inputs.receipt, inputs.models),
          self.max_workspace - self.live,
        ),
      )
    }
    ModelInventory(child) => {
      let (done, _) = match child.advance(1) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.peak = Int::max(self.peak, self.live + child.peak)
      if done {
        guard child.finish() is Ok(OrderedModels(models)) else {
          return Err(CaptureIssuanceEncoding)
        }
        match self.reserve(models.length()) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
        self.inventory_slots += models.length()
        self.model_inventory = Some(models)
        self.phase = PrepareContext
      }
    }
    PrepareContext => {
      let (sources, local_sources) = self.source_inventory.unwrap()
      let prepared = match
        prepare_captured_context_inputs(
          inputs,
          self.snapshot_inventory.unwrap(),
          sources,
          local_sources,
          self.model_inventory.unwrap(),
        ) {
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
          content_generations=prepared.content_generations,
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
            // These detached reference arrays were held through context
            // emission. Retire them only after the child has stopped using them.
            self.snapshot_inventory.unwrap().clear()
            self.model_inventory.unwrap().clear()
            self.snapshot_inventory = None
            self.model_inventory = None
            self.source_inventory = None
            self.live -= self.inventory_slots
            self.inventory_slots = 0
            try {
              let writer = @encode.measuring_writer(
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
          let usage = @encode.finish_measurement_usage(writer)
          self.writer = None
          guard @json.object_with_replaced_fields(
              captured_run_envelope_template,
              [
                ("effect_context", self.context.unwrap()),
                ("receipt", inputs.receipt.value),
              ],
            )
            is Some(value) else {
            return Err(CaptureIssuanceEncoding)
          }
          self.context = None
          let child = match
            start_issued_publication_seal_preparation(
              "captured_run",
              value,
              usage,
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
            let check = start_computation_evidence_check(
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
            )
            // This same owner completed Root before constructing the capture.
            // Its borrowed root contracts, inventories and bounds are unchanged;
            // only the new capture still needs the remaining evidence checks.
            check.phase = PreludeAfterRoot
            self.phase = Check(check)
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
/// Fixed envelope members are admitted once. Each issuance replaces only the
/// two original immutable children, not authority, Run or permission facts.
let captured_run_envelope_template : @json.CanonicalValue = {
  let parsed = @source.parse_json(
    "{\"effect_context\":null,\"encryption_required\":true,\"receipt\":null,\"retention_class\":\"run-evidence\",\"sensitivity\":\"private\",\"version\":\"actql-captured-run/0.1\"}",
    { max_input_bytes: 256, max_nodes: 7, max_depth: 1, },
  ).unwrap()
  @json.from_source(parsed, 7, 1, 256) catch {
    _ => abort("Invalid captured Run envelope template")
  }
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
    SnapshotInventory(child) | ModelInventory(child) => child.cancel()
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
  if self.snapshot_inventory is Some(snapshots) {
    snapshots.clear()
  }
  if self.model_inventory is Some(models) {
    models.clear()
  }
  self.snapshot_inventory = None
  self.source_inventory = None
  self.model_inventory = None
  self.inventory_slots = 0
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
    Advances(_, _) => "source-advances"
    SnapshotInventory(_) => "snapshot-inventory"
    Sources | PrepareContext => "prepare"
    ModelInventory(_) => "model-inventory"
    Context(_) => "context"
    Envelope(_) | Emit(_, _) => "envelope"
    Seal(_) => "seal"
    Check(child) => computation_evidence_check_fixture_phase(child)
    Done => "done"
  }
}

///|
/// Read-only fixture accounting; not custody, authority or completion evidence.
pub fn captured_run_preparation_fixture_inventory(
  preparation : CapturedRunIssuancePreparation,
) -> (Int, Int, Bool, Bool) {
  (
    preparation.live,
    preparation.inventory_slots,
    preparation.snapshot_inventory is Some(_),
    preparation.model_inventory is Some(_),
  )
}
