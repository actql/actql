///|
priv struct CaptureInventoryInputs {
  context : @json.CanonicalValue
  manifest_results : @json.CanonicalValue
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
priv enum CaptureInventoryPhase {
  Begin
  Artifacts(EvidenceStreamPreparation)
  Names(Int)
  Compare(Int, Int, Int)
  Done
}

///|
/// Borrow canonical, sorted inventories rather than copying Result names or
/// materializing serialized Artifact arrays. Custody remains with the parent.
priv struct CaptureInventoryPreparation {
  mut inputs : CaptureInventoryInputs?
  max_workspace : Int
  mut expected : @json.FrozenArray[(String, @json.CanonicalValue)]?
  mut values : @json.CanonicalValue?
  mut fields : @json.CanonicalValue?
  mut current : @json.FrozenArray[(String, @json.CanonicalValue)]?
  mut phase : CaptureInventoryPhase
  mut live : Int
  mut peak : Int
  mut closed : Bool
}

///|
fn start_capture_inventory(
  inputs : CaptureInventoryInputs,
  max_workspace : Int,
) -> CaptureInventoryPreparation {
  {
    inputs: Some(inputs),
    max_workspace,
    expected: None,
    values: None,
    fields: None,
    current: None,
    phase: Begin,
    live: 12,
    peak: 12,
    closed: false,
  }
}

///|
fn capture_inventory_field(section : Int) -> String {
  if section == 0 {
    "result_values"
  } else {
    "result_fields"
  }
}

///|
fn CaptureInventoryPreparation::step(
  self : CaptureInventoryPreparation,
) -> Result[Unit, RunEvidenceChainIssue] {
  let inputs = self.inputs.unwrap()
  match self.phase {
    Begin => {
      if self.max_workspace < self.live || self.max_workspace - self.live < 12 {
        return Err(EvidenceEncoding)
      }
      guard @json.object_field(inputs.context, "result_artifacts")
        is Some(artifacts) else {
        return Err(EvidenceMissingField("result_artifacts"))
      }
      self.phase = Artifacts(
        start_evidence_stream(
          artifacts,
          Pair(inputs.manifest_results),
          inputs.max_wire_bytes,
          inputs.max_nodes,
          inputs.max_depth,
          self.max_workspace - self.live,
        ),
      )
    }
    Artifacts(child) => {
      let (done, _) = match child.advance(1) {
        Ok(result) => result
        Err(_) =>
          return Err(EvidenceInventoryMismatch("captured_result_artifacts"))
      }
      self.peak = Int::max(self.peak, self.live + child.peak)
      if done {
        if !child.finish().unwrap() {
          return Err(EvidenceInventoryMismatch("captured_result_artifacts"))
        }
        guard inputs.manifest_results is @json.Object(expected) else {
          return Err(EvidenceInventoryMismatch("captured_result_artifacts"))
        }
        self.expected = Some(expected)
        self.phase = Names(0)
      }
    }
    Names(section) =>
      if section == 2 {
        self.phase = Done
      } else {
        let field = capture_inventory_field(section)
        guard @json.object_field(inputs.context, field) is Some(inventory) else {
          return Err(EvidenceMissingField(field))
        }
        guard inventory is @json.Object(current) &&
          @json.array_count(current) ==
          @json.array_count(self.expected.unwrap()) else {
          return Err(EvidenceInventoryMismatch(field))
        }
        if section == 0 {
          self.values = Some(inventory)
        } else {
          self.fields = Some(inventory)
        }
        self.current = Some(current)
        self.phase = Compare(section, 0, 0)
      }
    Compare(section, index, offset) => {
      let expected = self.expected.unwrap()
      if index == @json.array_count(expected) {
        self.current = None
        self.phase = Names(section + 1)
      } else {
        let name = @json.array_at(expected, index).unwrap().0
        let other = @json.array_at(self.current.unwrap(), index).unwrap().0
        if name.is_empty() || other.is_empty() {
          return Err(
            EvidenceInventoryMismatch(capture_inventory_field(section)),
          )
        }
        let (compared, next, _) = @canonical.compare_utf16_fragment(
          name, other, offset, 64,
        )
        match compared {
          None => self.phase = Compare(section, index, next)
          Some(0) => self.phase = Compare(section, index + 1, 0)
          Some(_) =>
            return Err(
              EvidenceInventoryMismatch(capture_inventory_field(section)),
            )
        }
      }
    }
    Done => ()
  }
  Ok(())
}

///|
fn CaptureInventoryPreparation::advance(
  self : CaptureInventoryPreparation,
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
fn CaptureInventoryPreparation::finish(
  self : CaptureInventoryPreparation,
) -> Result[(@json.CanonicalValue, @json.CanonicalValue), RunEvidenceChainIssue] {
  if self.closed || !(self.phase is Done) {
    return Err(EvidenceEncoding)
  }
  let values = self.values.unwrap()
  let fields = self.fields.unwrap()
  self.cancel()
  Ok((values, fields))
}

///|
fn CaptureInventoryPreparation::cancel(
  self : CaptureInventoryPreparation,
) -> Unit {
  if self.closed {
    return
  }
  if self.phase is Artifacts(child) {
    child.cancel()
  }
  self.inputs = None
  self.expected = None
  self.values = None
  self.fields = None
  self.current = None
  self.phase = Done
  self.live = 0
  self.closed = true
}
