///|
priv enum CapturedSnapshotPhase {
  Parse(@source.JsonParse)
  Decode(@decode.Admission)
  Canonical(@json.CursorAdmission)
  Emit(@json.CanonicalEmit)
  Compare(String, Int)
  Fields
  Sort(@sort.Sort)
  Unique(Int, Int)
  Rows(Int, Int, Int)
  Hash(@json.CanonicalEmit)
  Done
}

///|
/// One private admission of an immutable canonical payload. The export owner
/// retains its receipt throughout this preparation and verifies it at transfer.
/// Caller-owned fields must not be mutated during this operation.
struct CapturedResultSnapshotPreparation {
  name : String
  definition : PublicationContract
  artifact : PublicationContract
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_workspace : Int
  mut wire : String?
  mut source_fields : Array[String]?
  mut rows : @json.CanonicalValue?
  fields : Array[String]
  keys : Array[Array[String]]
  mut sorted : @sort.Sort?
  mut writer : @encode.Writer?
  mut phase : CapturedSnapshotPhase
  mut field : Int
  mut live : Int
  mut peak : Int
  mut closed : Bool
  mut row_wire_bytes : Int
  mut row_nodes : Int
  mut row_depth : Int
}

///|
pub fn start_captured_result_snapshot(
  definition : PublicationContract,
  artifact : PublicationContract,
  rows_wire : String,
  fields : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
) -> Result[CapturedResultSnapshotPreparation, CapturedRunIssuanceIssue] {
  if definition.name != "result_definition" ||
    artifact.name != "result_artifact" {
    return Err(CaptureIssuanceWrongContract("result"))
  }
  guard contract_string(definition, "result_name") is Some(name) else {
    return Err(CaptureIssuanceInvalidFields("result_name"))
  }
  if contract_string(artifact, "result_definition_cid") !=
    Some(definition.identity) {
    return Err(CaptureIssuanceReferenceMismatch("result_definition_cid"))
  }
  if max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(CaptureIssuanceInvalidRows(name))
  }
  // Fixed owner/borrowed inputs, canonical root, writer and child continuations.
  if max_workspace < 8 {
    return Err(CaptureIssuanceEncoding)
  }
  let parser = match
    @source.start_json_parse(
      rows_wire,
      { max_input_bytes: max_wire_bytes, max_nodes, max_depth, },
      data_keys=true,
    ) {
    Ok(parser) => parser
    Err(_) => return Err(CaptureIssuanceInvalidRows(name))
  }
  Ok({
    name,
    definition,
    artifact,
    max_wire_bytes,
    max_nodes,
    max_depth,
    max_workspace,
    wire: Some(rows_wire),
    source_fields: Some(fields),
    rows: None,
    fields: [],
    keys: [],
    sorted: None,
    writer: None,
    phase: Parse(parser),
    field: 0,
    live: 8,
    peak: 8,
    closed: false,
    row_wire_bytes: 0,
    row_nodes: 0,
    row_depth: 0,
  })
}

///|
/// Recheck already admitted canonical rows with the same field, ordering,
/// count and logical-CID phases. The enclosing evidence owner keeps custody.
fn start_captured_snapshot_value_check(
  definition : PublicationContract,
  artifact : PublicationContract,
  rows : @json.CanonicalValue,
  fields : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
) -> Result[CapturedResultSnapshotPreparation, CapturedRunIssuanceIssue] {
  if definition.name != "result_definition" ||
    artifact.name != "result_artifact" {
    return Err(CaptureIssuanceWrongContract("result"))
  }
  guard contract_string(definition, "result_name") is Some(name) else {
    return Err(CaptureIssuanceInvalidFields("result_name"))
  }
  if contract_string(artifact, "result_definition_cid") !=
    Some(definition.identity) {
    return Err(CaptureIssuanceReferenceMismatch("result_definition_cid"))
  }
  guard rows is @json.Array(_) else {
    return Err(CaptureIssuanceInvalidRows(name))
  }
  if max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 || max_workspace < 8 {
    return Err(CaptureIssuanceEncoding)
  }
  Ok({
    name,
    definition,
    artifact,
    max_wire_bytes,
    max_nodes,
    max_depth,
    max_workspace,
    wire: None,
    source_fields: Some(fields),
    rows: Some(rows),
    fields: [],
    keys: [],
    sorted: None,
    writer: None,
    phase: Fields,
    field: 0,
    live: 8,
    peak: 8,
    closed: false,
    row_wire_bytes: 0,
    row_nodes: 0,
    row_depth: 0,
  })
}

///|
fn CapturedResultSnapshotPreparation::reserve(
  self : CapturedResultSnapshotPreparation,
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
fn CapturedResultSnapshotPreparation::step(
  self : CapturedResultSnapshotPreparation,
) -> Result[Unit, CapturedRunIssuanceIssue] {
  try {
    match self.phase {
      Parse(parser) =>
        match @source.advance_json_parse(parser, 1) {
          Ok(@source.JsonParseContinue(..)) => ()
          Ok(@source.JsonParseComplete(parsed, ..)) => {
            let admission = match
              @decode.start_admission(parsed.node, {
                max_nodes: self.max_nodes,
                max_depth: self.max_depth,
                max_string_bytes: self.max_wire_bytes,
                max_total_string_bytes: self.max_wire_bytes,
              }) {
              Ok(value) => value
              Err(_) => return Err(CaptureIssuanceInvalidRows(self.name))
            }
            self.phase = Decode(admission)
          }
          _ => return Err(CaptureIssuanceInvalidRows(self.name))
        }
      Decode(admission) =>
        match @decode.advance_admission(admission, 1) {
          Ok(@decode.AdmissionContinue(..)) => ()
          Ok(@decode.AdmissionComplete(cursor, ..)) => {
            guard @json.start_cursor_admission(
                cursor,
                self.max_nodes,
                self.max_depth,
                self.max_wire_bytes,
                self.max_wire_bytes,
                data_keys=true,
              )
              is Some(canonical) else {
              return Err(CaptureIssuanceInvalidRows(self.name))
            }
            self.phase = Canonical(canonical)
          }
          _ => return Err(CaptureIssuanceInvalidRows(self.name))
        }
      Canonical(admission) =>
        match @json.advance_cursor_admission(admission) {
          @json.CursorAdmissionContinue => ()
          @json.CursorAdmissionComplete(rows, _, _) => {
            guard rows is @json.Array(_) else {
              return Err(CaptureIssuanceInvalidRows(self.name))
            }
            self.rows = Some(rows)
            let writer = @encode.writer(
              self.max_wire_bytes,
              self.max_nodes,
              self.max_depth,
            )
            self.writer = Some(writer)
            self.phase = Emit(@json.start_emit(rows, writer))
          }
          _ => return Err(CaptureIssuanceInvalidRows(self.name))
        }
      Emit(cursor) =>
        if @json.advance_emit(cursor) {
          let canonical = @encode.finish(self.writer.unwrap())
          self.writer = None
          self.phase = Compare(canonical, 0)
        }
      Compare(canonical, offset) => {
        let (compared, next, _) = @canonical.compare_utf16_fragment(
          canonical,
          self.wire.unwrap(),
          offset,
          64,
        )
        match compared {
          Some(0) => {
            self.wire = None
            self.phase = Fields
          }
          Some(_) => return Err(CaptureIssuanceInvalidRows(self.name))
          None => self.phase = Compare(canonical, next)
        }
      }
      Fields => {
        let fields = self.source_fields.unwrap()
        if self.field == fields.length() {
          // Two index arrays belong to the existing deferred sorter.
          if fields.length() > (self.max_workspace - self.live) / 2 {
            return Err(CaptureIssuanceEncoding)
          }
          if self.reserve(fields.length() * 2) is Err(issue) {
            return Err(issue)
          }
          let sort = match
            @sort.prepare_deferred(self.keys, fields.length() * 2) {
            Ok(sort) => sort
            Err(_) => return Err(CaptureIssuanceEncoding)
          }
          self.sorted = Some(sort)
          self.source_fields = None
          self.phase = Sort(sort)
        } else {
          let field = fields[self.field]
          guard !field.is_empty() &&
            @canonical.normalize_nfc_lf(field) is Ok(normalized) else {
            return Err(CaptureIssuanceInvalidFields(self.name))
          }
          if normalized != field {
            return Err(CaptureIssuanceInvalidFields(self.name))
          }
          // Authored field reference, singleton sort tuple and its component.
          if self.reserve(3) is Err(issue) {
            return Err(issue)
          }
          self.fields.push(field)
          self.keys.push([field])
          self.field += 1
        }
      }
      Sort(sort) =>
        match @sort.advance(sort, 1) {
          Ok(@sort.Continue(..)) => ()
          Ok(@sort.Complete(..)) => self.phase = Unique(1, 0)
          Err(_) => return Err(CaptureIssuanceEncoding)
        }
      Unique(index, offset) => {
        let sort = self.sorted.unwrap()
        if index >= self.fields.length() {
          self.phase = Rows(0, 0, 0)
        } else {
          let left = self.fields[@sort.index_at(sort, index - 1).unwrap()]
          let right = self.fields[@sort.index_at(sort, index).unwrap()]
          let (compared, next, _) = @canonical.compare_utf16_fragment(
            left, right, offset, 64,
          )
          match compared {
            Some(0) => return Err(CaptureIssuanceInvalidFields(self.name))
            Some(_) => self.phase = Unique(index + 1, 0)
            None => self.phase = Unique(index, next)
          }
        }
      }
      Rows(row, column, offset) => {
        guard self.rows.unwrap() is @json.Array(rows) else {
          return Err(CaptureIssuanceInvalidRows(self.name))
        }
        if row == @json.array_count(rows) {
          if contract_count(self.artifact, "actual_row_count") !=
            Some(row.to_int64()) {
            return Err(CaptureIssuanceReferenceMismatch("actual_row_count"))
          }
          let writer = @encode.hashing_writer(
            self.max_wire_bytes,
            self.max_nodes,
            self.max_depth,
          )
          self.writer = Some(writer)
          @encode.begin_object(writer)
          @encode.key(writer, "sort")
          @encode.string_value(writer, "relation")
          @encode.key(writer, "value")
          self.phase = Hash(@json.start_emit(self.rows.unwrap(), writer))
        } else {
          guard @json.array_at(rows, row).unwrap() is @json.Object(entries) else {
            return Err(CaptureIssuanceInvalidFields(self.name))
          }
          if @json.array_count(entries) != self.fields.length() {
            return Err(CaptureIssuanceInvalidFields(self.name))
          }
          if column == self.fields.length() {
            self.phase = Rows(row + 1, 0, 0)
          } else {
            let (actual, _) = @json.array_at(entries, column).unwrap()
            let expected = self.fields[@sort.index_at(
                self.sorted.unwrap(),
                column,
              ).unwrap()]
            let (compared, next, _) = @canonical.compare_utf16_fragment(
              actual, expected, offset, 64,
            )
            match compared {
              Some(0) => self.phase = Rows(row, column + 1, 0)
              Some(_) => return Err(CaptureIssuanceInvalidFields(self.name))
              None => self.phase = Rows(row, column, next)
            }
          }
        }
      }
      Hash(cursor) =>
        if @json.advance_emit(cursor) {
          let writer = self.writer.unwrap()
          @encode.end_object(writer)
          let (digest, bytes, nodes, depth) = @encode.finish_hash_metrics(writer)
          self.writer = None
          if contract_string(self.artifact, "logical_result_cid") !=
            Some("sha256:" + digest) {
            return Err(CaptureIssuanceReferenceMismatch("logical_result_cid"))
          }
          // The same hash emits {"sort":"relation","value":rows}.
          // Remove exactly its 28 UTF-8 bytes, two values and one container.
          self.row_wire_bytes = bytes - 28
          self.row_nodes = nodes - 2
          self.row_depth = depth - 1
          self.phase = Done
        }
      Done => ()
    }
    Ok(())
  } catch {
    _ => Err(CaptureIssuanceEncoding)
  }
}

///|
pub fn CapturedResultSnapshotPreparation::advance(
  self : CapturedResultSnapshotPreparation,
  quantum : Int,
) -> Result[(Bool, Int), CapturedRunIssuanceIssue] {
  if self.closed || quantum < 1 {
    return Err(CaptureIssuanceEncoding)
  }
  let mut used = 0
  while used < quantum && !(self.phase is Done) {
    if self.step() is Err(issue) {
      self.cancel()
      return Err(issue)
    }
    used += 1
  }
  Ok((self.phase is Done, used))
}

///|
pub fn CapturedResultSnapshotPreparation::finish(
  self : CapturedResultSnapshotPreparation,
) -> Result[CapturedResultSnapshot, CapturedRunIssuanceIssue] {
  guard !self.closed && self.phase is Done && self.rows is Some(rows) else {
    return Err(CaptureIssuanceEncoding)
  }
  // Transfer the final field inventory, not a synchronous whole-array copy.
  let fields = self.fields
  self.rows = None
  self.closed = true
  if self.sorted is Some(sort) {
    ignore(@sort.cleanup(sort))
  }
  self.sorted = None
  self.keys.clear()
  self.live = 0
  Ok({
    name: self.name,
    definition: self.definition,
    artifact: self.artifact,
    rows,
    fields,
    row_wire_bytes: self.row_wire_bytes,
    row_nodes: self.row_nodes,
    row_depth: self.row_depth,
  })
}

///|
pub fn CapturedResultSnapshotPreparation::cancel(
  self : CapturedResultSnapshotPreparation,
) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  match self.phase {
    Parse(parser) => @source.cancel_json_parse(parser)
    Decode(admission) => @decode.cancel_admission(admission)
    Canonical(admission) => @json.cancel_cursor_admission(admission)
    Emit(cursor) | Hash(cursor) => @json.cancel_emit(cursor)
    _ => ()
  }
  if self.writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  if self.sorted is Some(sort) {
    ignore(@sort.cleanup(sort))
  }
  self.writer = None
  self.sorted = None
  self.wire = None
  self.source_fields = None
  self.rows = None
  self.fields.clear()
  self.keys.clear()
  self.phase = Done
  self.live = 0
}
