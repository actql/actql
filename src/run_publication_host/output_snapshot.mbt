///|
priv enum PublicationSnapshotPhase {
  Export(@execution.CompletedRelationSnapshotPreparation)
  Admit(@publication.CapturedResultSnapshotPreparation)
  Done
}

///|
/// Private snapshot preparation borrows the parent export's exact live receipt.
/// Cancelling this child never releases the parent's retained Result pin.
struct PublicationOutputSnapshotPreparation {
  mut parent : PublicationOutputExport?
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  mut phase : PublicationSnapshotPhase
  mut closed : Bool
}

///|
pub fn PublicationOutputExport::start_captured_snapshot(
  self : PublicationOutputExport,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationOutputSnapshotPreparation, PublicationOutputExportIssue] {
  guard self.receipt is Some(receipt) &&
    self.definition is Some(_) &&
    self.artifact is Some(_) else {
    return Err(InvalidState)
  }
  let emission = match
    @execution.start_completed_relation_export_snapshot(
      self.stream,
      receipt,
      max_wire_bytes,
      max_nodes,
      max_depth,
      self.max_snapshot_workspace,
    ) {
    Ok(emission) => emission
    Err(issue) => return Err(Output(issue))
  }
  Ok({
    parent: Some(self),
    max_wire_bytes,
    max_nodes,
    max_depth,
    phase: Export(emission),
    closed: false,
  })
}

///|
pub fn PublicationOutputSnapshotPreparation::advance(
  self : PublicationOutputSnapshotPreparation,
  quantum : Int,
) -> Result[(Bool, Int), PublicationOutputExportIssue] {
  guard !self.closed && quantum > 0 && self.parent is Some(parent) else {
    return Err(InvalidState)
  }
  guard parent.receipt is Some(receipt) else {
    self.cancel()
    return Err(InvalidState)
  }
  if !@execution.completed_relation_export_receipt_live(receipt) {
    self.cancel()
    return Err(InvalidState)
  }
  let mut used = 0
  while used < quantum {
    match self.phase {
      Export(emission) =>
        match emission.advance(1) {
          Err(issue) => {
            self.cancel()
            return Err(Output(issue))
          }
          Ok((done, work)) => {
            used += work
            if done {
              let (wire, fields) = match emission.finish() {
                Ok(value) => value
                Err(issue) => {
                  self.cancel()
                  return Err(Output(issue))
                }
              }
              let admission = match
                @publication.start_captured_result_snapshot(
                  parent.definition.unwrap(),
                  parent.artifact.unwrap(),
                  wire,
                  fields,
                  self.max_wire_bytes,
                  self.max_nodes,
                  self.max_depth,
                  parent.max_snapshot_workspace,
                ) {
                Ok(value) => value
                Err(issue) => {
                  self.cancel()
                  return Err(Capture(issue))
                }
              }
              self.phase = Admit(admission)
            }
          }
        }
      Admit(admission) =>
        match admission.advance(1) {
          Err(issue) => {
            self.cancel()
            return Err(Capture(issue))
          }
          Ok((done, work)) => {
            used += work
            if done {
              return Ok((true, used))
            }
          }
        }
      Done => return Err(InvalidState)
    }
  }
  Ok((false, used))
}

///|
pub fn PublicationOutputSnapshotPreparation::finish(
  self : PublicationOutputSnapshotPreparation,
) -> Result[@publication.CapturedResultSnapshot, PublicationOutputExportIssue] {
  guard !self.closed &&
    self.parent is Some(parent) &&
    parent.receipt is Some(receipt) &&
    @execution.completed_relation_export_receipt_live(receipt) else {
    self.cancel()
    return Err(InvalidState)
  }
  guard self.phase is Admit(admission) else { return Err(InvalidState) }
  match admission.finish() {
    Err(issue) => Err(Capture(issue))
    Ok(value) => {
      self.phase = Done
      self.parent = None
      self.closed = true
      Ok(value)
    }
  }
}

///|
pub fn PublicationOutputSnapshotPreparation::cancel(
  self : PublicationOutputSnapshotPreparation,
) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  match self.phase {
    Export(emission) => emission.cancel()
    Admit(admission) => admission.cancel()
    Done => ()
  }
  self.parent = None
  self.phase = Done
}
