///|
priv enum CapturedOrderedInventoryInput {
  Snapshots(
    Array[PublicationContract],
    Array[PublicationContract],
    Array[CapturedResultSnapshot]
  )
  Models(PublicationContract, Array[RunEvidenceValue])
}

///|
priv enum CapturedOrderedInventoryOutput {
  OrderedSnapshots(Array[CapturedResultSnapshot])
  OrderedModels(Array[RunEvidenceValue])
}

///|
priv enum CapturedOrderedInventoryPhase {
  Begin
  Collect(Int)
  Sort(@sort.Sort, Bool)
  Snapshot(Int, Int)
  Definition(Int, Int)
  Artifact(Int, Int)
  AppendSnapshot(Int)
  Model(Int)
  External(Int)
  Compare(Int, Int)
  Done
}

///|
/// Private ordering inside the capture issuer. Keys and sort indices are
/// reserved before append; payloads and admitted contracts remain borrowed.
priv struct CapturedOrderedInventoryPreparation {
  mut inputs : CapturedOrderedInventoryInput?
  max_workspace : Int
  keys : Array[Array[String]]
  mut sorted : @sort.Sort?
  mut snapshots : Array[CapturedResultSnapshot]
  mut models : Array[RunEvidenceValue]
  mut external : @json.FrozenArray[@json.CanonicalValue]?
  mut phase : CapturedOrderedInventoryPhase
  mut live : Int
  mut peak : Int
  mut closed : Bool
}

///|
fn start_captured_ordered_inventory(
  inputs : CapturedOrderedInventoryInput,
  max_workspace : Int,
) -> CapturedOrderedInventoryPreparation {
  {
    inputs: Some(inputs),
    max_workspace,
    keys: [],
    sorted: None,
    snapshots: [],
    models: [],
    external: None,
    phase: Begin,
    live: 12,
    peak: 12,
    closed: false,
  }
}

///|
fn CapturedOrderedInventoryPreparation::reserve(
  self : CapturedOrderedInventoryPreparation,
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
fn CapturedOrderedInventoryPreparation::retire_sort(
  self : CapturedOrderedInventoryPreparation,
) -> Unit {
  if self.sorted is Some(sort) {
    let _ = @sort.cleanup(sort)
  }
  self.sorted = None
  self.live -= self.keys.length() * 4
  self.keys.clear()
}

///|
fn CapturedOrderedInventoryPreparation::sort(
  self : CapturedOrderedInventoryPreparation,
  external : Bool,
) -> Result[Unit, CapturedRunIssuanceIssue] {
  let sort = match @sort.prepare_deferred(self.keys, self.keys.length() * 2) {
    Ok(sort) => sort
    Err(_) => return Err(CaptureIssuanceEncoding)
  }
  self.sorted = Some(sort)
  self.phase = Sort(sort, external)
  Ok(())
}

///|
fn CapturedOrderedInventoryPreparation::step(
  self : CapturedOrderedInventoryPreparation,
) -> Result[Unit, CapturedRunIssuanceIssue] {
  let inputs = self.inputs.unwrap()
  match self.phase {
    Begin => {
      match self.reserve(0) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      if inputs is Snapshots(definitions, artifacts, snapshots) &&
        (
          definitions.length() != artifacts.length() ||
          definitions.length() != snapshots.length()
        ) {
        return Err(CaptureIssuanceInventoryMismatch("results"))
      }
      self.phase = Collect(0)
    }
    Collect(index) => {
      let count = match inputs {
        Snapshots(_, _, snapshots) => snapshots.length()
        Models(_, models) => models.length()
      }
      if index == count {
        return self.sort(false)
      }
      let key = match inputs {
        Snapshots(_, _, snapshots) => snapshots[index].name
        Models(_, models) => models[index].identity
      }
      match self.reserve(4) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      self.keys.push([key])
      self.phase = Collect(index + 1)
    }
    Sort(sort, external) =>
      match @sort.advance(sort, 1) {
        Err(_) => return Err(CaptureIssuanceEncoding)
        Ok(@sort.Continue(..)) => ()
        Ok(@sort.Complete(..)) =>
          self.phase = if external {
            if self.keys.length() != self.models.length() {
              return Err(CaptureIssuanceReferenceMismatch("model_evidence"))
            }
            Compare(0, 0)
          } else {
            match inputs {
              Snapshots(_, _, _) => Snapshot(0, 0)
              Models(_, _) => Model(0)
            }
          }
      }
    Snapshot(index, offset) => {
      guard inputs is Snapshots(_, _, snapshots) else {
        return Err(CaptureIssuanceEncoding)
      }
      if index == snapshots.length() {
        self.retire_sort()
        self.phase = Done
      } else {
        let current = snapshots[@sort.index_at(self.sorted.unwrap(), index).unwrap()]
        if index == 0 {
          self.phase = Definition(index, 0)
        } else {
          let previous = snapshots[@sort.index_at(
              self.sorted.unwrap(),
              index - 1,
            ).unwrap()]
          let (compared, next, _) = @canonical.compare_utf16_fragment(
            previous.name,
            current.name,
            offset,
            64,
          )
          match compared {
            None => self.phase = Snapshot(index, next)
            Some(0) =>
              return Err(CaptureIssuanceInventoryMismatch(current.name))
            Some(_) => self.phase = Definition(index, 0)
          }
        }
      }
    }
    Definition(index, position) => {
      guard inputs is Snapshots(definitions, _, snapshots) else {
        return Err(CaptureIssuanceEncoding)
      }
      let current = snapshots[@sort.index_at(self.sorted.unwrap(), index).unwrap()]
      if position == definitions.length() {
        return Err(CaptureIssuanceInventoryMismatch(current.name))
      }
      // Admitted contract identities are fixed-size full CIDs, not long names.
      self.phase = if definitions[position].identity ==
        current.definition.identity {
        Artifact(index, 0)
      } else {
        Definition(index, position + 1)
      }
    }
    Artifact(index, position) => {
      guard inputs is Snapshots(_, artifacts, snapshots) else {
        return Err(CaptureIssuanceEncoding)
      }
      let current = snapshots[@sort.index_at(self.sorted.unwrap(), index).unwrap()]
      if position == artifacts.length() {
        return Err(CaptureIssuanceInventoryMismatch(current.name))
      }
      self.phase = if artifacts[position].identity == current.artifact.identity {
        AppendSnapshot(index)
      } else {
        Artifact(index, position + 1)
      }
    }
    AppendSnapshot(index) => {
      guard inputs is Snapshots(_, _, snapshots) else {
        return Err(CaptureIssuanceEncoding)
      }
      match self.reserve(1) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      self.snapshots.push(
        snapshots[@sort.index_at(self.sorted.unwrap(), index).unwrap()],
      )
      self.phase = Snapshot(index + 1, 0)
    }
    Model(index) => {
      guard inputs is Models(receipt, models) else {
        return Err(CaptureIssuanceEncoding)
      }
      if index == models.length() {
        self.retire_sort()
        guard @json.object_field(receipt.value, "external_observation_evidence")
          is Some(@json.Array(external)) else {
          return Err(CaptureIssuanceReferenceMismatch("external_observations"))
        }
        self.external = Some(external)
        self.phase = External(0)
      } else {
        let current = models[@sort.index_at(self.sorted.unwrap(), index).unwrap()]
        if current.name != "model_invocation_evidence" ||
          (index > 0 && self.models[index - 1].identity == current.identity) {
          return Err(CaptureIssuanceInventoryMismatch("model_evidence"))
        }
        match self.reserve(1) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
        self.models.push(current)
        self.phase = Model(index + 1)
      }
    }
    External(index) => {
      let external = self.external.unwrap()
      if index == @json.array_count(external) {
        return self.sort(true)
      }
      let item = @json.array_at(external, index).unwrap()
      if evidence_string(item, "kind") == Some("model_invocation") {
        guard evidence_string(item, "evidence_cid") is Some(cid) else {
          return Err(CaptureIssuanceReferenceMismatch("external_observations"))
        }
        match self.reserve(4) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
        self.keys.push([cid])
      }
      self.phase = External(index + 1)
    }
    Compare(index, offset) =>
      if index == self.models.length() {
        self.retire_sort()
        self.phase = Done
      } else {
        let expected = @sort.key_component_at(self.sorted.unwrap(), index, 0).unwrap()
        let (compared, next, _) = @canonical.compare_utf16_fragment(
          expected,
          self.models[index].identity,
          offset,
          64,
        )
        match compared {
          None => self.phase = Compare(index, next)
          Some(0) => self.phase = Compare(index + 1, 0)
          Some(_) =>
            return Err(CaptureIssuanceReferenceMismatch("model_evidence"))
        }
      }
    Done => ()
  }
  Ok(())
}

///|
fn CapturedOrderedInventoryPreparation::advance(
  self : CapturedOrderedInventoryPreparation,
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
fn CapturedOrderedInventoryPreparation::finish(
  self : CapturedOrderedInventoryPreparation,
) -> Result[CapturedOrderedInventoryOutput, CapturedRunIssuanceIssue] {
  if self.closed || !(self.phase is Done) {
    return Err(CaptureIssuanceEncoding)
  }
  let output = match self.inputs.unwrap() {
    Snapshots(_, _, _) => {
      let snapshots = self.snapshots
      self.snapshots = []
      OrderedSnapshots(snapshots)
    }
    Models(_, _) => {
      let models = self.models
      self.models = []
      OrderedModels(models)
    }
  }
  self.cancel()
  Ok(output)
}

///|
fn CapturedOrderedInventoryPreparation::cancel(
  self : CapturedOrderedInventoryPreparation,
) -> Unit {
  if self.closed {
    return
  }
  self.retire_sort()
  self.snapshots.clear()
  self.models.clear()
  self.external = None
  self.inputs = None
  self.phase = Done
  self.live = 0
  self.closed = true
}
