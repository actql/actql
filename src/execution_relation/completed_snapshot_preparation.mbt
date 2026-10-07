///|
priv enum CompletedSnapshotPhase {
  Begin
  Row
  Column
  Key(@encode.OrderedKeyEmitCursor)
  Cell(SteppedRuntimeWire)
  EndRow
  End
  Fields
  Done
}

///|
/// Private snapshot emission from the exact finished export. The parent keeps
/// its receipt/pin until snapshot admission succeeds or cleanup settles.
struct CompletedRelationSnapshotPreparation {
  mut rows : CompletedExportRows?
  mut order : RowWireOrder?
  mut receipt : CompletedRelationExportReceipt?
  writer : @encode.Writer
  workspace : RowWorkspace
  mut phase : CompletedSnapshotPhase
  mut row : Int
  mut column : Int
  mut field : Int
  mut fields : Array[String]
  mut wire : String?
  mut closed : Bool
  mut advancing : Bool
}

///|
pub fn start_completed_relation_export_snapshot(
  stream : CompletedOutputExport,
  receipt : CompletedRelationExportReceipt,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace_slots : Int,
) -> Result[CompletedRelationSnapshotPreparation, CompletedExportIssue] {
  guard receipt.rows.source is Some(source) else { return Err(Closed) }
  if !physical_equal(stream.export_identity, receipt.rows.export_identity) {
    return Err(ForeignMaterial)
  }
  if !completed_output_available(source) {
    return Err(Unavailable)
  }
  if stream.source is Some(_) ||
    stream.row != IndexedRows::row_count(stream.rows) {
    return Err(NotFinished)
  }
  if max_bytes < 0 || max_nodes < 0 || max_depth < 0 || max_workspace_slots < 0 {
    return Err(Wire(InvalidLimits))
  }
  let workspace = row_workspace(max_workspace_slots)
  // Owner, borrowed row view/order and private field inventory.
  if !reserve_slots(workspace, 4) {
    return Err(Admission(CaptureLimit))
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    issue => {
      release_slots(workspace, 4)
      return Err(Wire(Encoding(issue)))
    }
  }
  Ok({
    rows: Some(stream.rows),
    order: Some(stream.order),
    receipt: Some(receipt),
    writer,
    workspace,
    phase: Begin,
    row: 0,
    column: 0,
    field: 0,
    fields: [],
    wire: None,
    closed: false,
    advancing: false,
  })
}

///|
fn completed_snapshot_available(
  preparation : CompletedRelationSnapshotPreparation,
) -> Result[Unit, CompletedExportIssue] {
  guard !preparation.closed && preparation.receipt is Some(receipt) else {
    return Err(Closed)
  }
  guard receipt.rows.source is Some(source) else { return Err(Closed) }
  if !completed_output_available(source) {
    return Err(Unavailable)
  }
  Ok(())
}

///|
/// A snapshot child can retain the receipt without gaining release authority.
pub fn completed_relation_export_receipt_live(
  receipt : CompletedRelationExportReceipt,
) -> Bool {
  match receipt.rows.source {
    Some(source) => completed_output_available(source)
    None => false
  }
}

///|
fn CompletedRelationSnapshotPreparation::step(
  self : CompletedRelationSnapshotPreparation,
) -> Result[Unit, CompletedExportIssue] {
  guard self.rows is Some(rows) && self.order is Some(order) else {
    return Err(Closed)
  }
  let writer = self.writer
  try {
    match self.phase {
      Begin => {
        @encode.begin_array(writer)
        self.phase = Row
      }
      Row =>
        if self.row == IndexedRows::row_count(rows) {
          self.phase = End
        } else {
          @encode.begin_ordered_object(writer)
          self.column = 0
          self.phase = Column
        }
      Column =>
        if self.column == order.columns.length() {
          self.phase = EndRow
        } else {
          let (name, column) = order.columns[self.column]
          if !IndexedRows::cell_present(rows, self.row, column) {
            self.column += 1
          } else {
            if !reserve_slots(self.workspace, 1) {
              return Err(Admission(CaptureLimit))
            }
            let key = @encode.start_ordered_key(writer, name) catch {
              issue => {
                release_slots(self.workspace, 1)
                return Err(Wire(Encoding(issue)))
              }
            }
            self.phase = Key(key)
          }
        }
      Key(key) =>
        if @encode.advance_ordered_key(key) {
          @encode.cancel_ordered_key(key)
          release_slots(self.workspace, 1)
          // Retire the key before a fallible cell lookup/reservation; cleanup
          // cannot release the same cursor twice if that next boundary fails.
          self.phase = Column
          let (_, column) = order.columns[self.column]
          let value = IndexedRows::read_cell(rows, self.row, column)
          let wire = match
            start_stepped_runtime_wire(value, writer, self.workspace) {
            Ok(wire) => wire
            Err(Workspace) => return Err(Admission(CaptureLimit))
            Err(Encoding(issue)) => return Err(Wire(Encoding(issue)))
          }
          self.phase = Cell(wire)
        }
      Cell(wire) =>
        match advance_stepped_runtime_wire(wire) {
          Err(Workspace) => return Err(Admission(CaptureLimit))
          Err(Encoding(issue)) => return Err(Wire(Encoding(issue)))
          Ok(false) => ()
          Ok(true) => {
            self.column += 1
            self.phase = Column
          }
        }
      EndRow => {
        @encode.end_object(writer)
        self.row += 1
        self.phase = Row
      }
      End => {
        @encode.end_array(writer)
        self.wire = Some(@encode.finish(writer))
        self.phase = Fields
      }
      Fields =>
        if self.field == rows.names.length() {
          self.phase = Done
        } else {
          if !reserve_slots(self.workspace, 1) {
            return Err(Admission(CaptureLimit))
          }
          self.fields.push(rows.names[self.field])
          self.field += 1
        }
      Done => ()
    }
    Ok(())
  } catch {
    issue => Err(Wire(Encoding(issue)))
  }
}

///|
pub fn CompletedRelationSnapshotPreparation::advance(
  self : CompletedRelationSnapshotPreparation,
  quantum : Int,
) -> Result[(Bool, Int), CompletedExportIssue] {
  if quantum < 1 || self.advancing {
    return Err(Closed)
  }
  if completed_snapshot_available(self) is Err(issue) {
    self.cancel()
    return Err(issue)
  }
  self.advancing = true
  let result = (fn() -> Result[(Bool, Int), CompletedExportIssue] {
    let mut used = 0
    while used < quantum && !(self.phase is Done) {
      if completed_snapshot_available(self) is Err(issue) {
        return Err(issue)
      }
      if self.step() is Err(issue) {
        return Err(issue)
      }
      used += 1
      if completed_snapshot_available(self) is Err(issue) {
        return Err(issue)
      }
    }
    Ok((self.phase is Done, used))
  })()
  self.advancing = false
  if result is Err(_) {
    self.cancel()
  }
  result
}

///|
pub fn CompletedRelationSnapshotPreparation::finish(
  self : CompletedRelationSnapshotPreparation,
) -> Result[(String, Array[String]), CompletedExportIssue] {
  if self.advancing {
    return Err(Closed)
  }
  if completed_snapshot_available(self) is Err(issue) {
    return Err(issue)
  }
  guard self.phase is Done && self.wire is Some(wire) else {
    return Err(NotFinished)
  }
  let fields = self.fields
  self.fields = []
  self.wire = None
  self.rows = None
  self.order = None
  self.receipt = None
  release_slots(self.workspace, self.workspace.live)
  self.closed = true
  Ok((wire, fields))
}

///|
pub fn CompletedRelationSnapshotPreparation::cancel(
  self : CompletedRelationSnapshotPreparation,
) -> Unit {
  self.closed = true
  if self.advancing {
    return
  }
  match self.phase {
    Key(key) => @encode.cancel_ordered_key(key)
    Cell(wire) => close_stepped_runtime_wire(wire)
    _ => ()
  }
  self.phase = Done
  self.fields.clear()
  self.wire = None
  self.rows = None
  self.order = None
  self.receipt = None
  @encode.cancel_writer(self.writer)
  release_slots(self.workspace, self.workspace.live)
}
