///|
/// One bounded original JSON document. The shared work counter covers initial
/// admission and every projection attempt; it is DATA, not a lifetime owner.
pub struct RelationDocument {
  priv mut original : RelationDocument?
  priv bytes : Bytes
  priv root : @decode.Cursor
  priv limits : RowPageLimits
  priv usage : @decode.AdmissionUsage
  priv work : Ref[Int]
  priv mut projection_attempts : Int
  priv mut projections : Int
  priv mut projected_rows : Int64
  priv mut projected_cells : Int64
}

///|
/// Bounded cumulative observations, not a capacity quotation or retirement
/// receipt. Construction must be funded before receiving the original bytes.
pub(all) struct RelationDocumentUsage {
  raw_bytes : Int
  raw_nodes : Int
  raw_depth : Int
  raw_text_bytes : Int
  projection_attempts : Int
  projections : Int
  projected_rows : Int64
  projected_cells : Int64
  remaining_work : Int
} derive(Eq, Debug)

///|
/// Owned, schema-admitted relation DATA from a JSON document. This supplies no
/// file identity, current grant, read receipt, approval or dispatch claim.
pub struct RelationTargetDocument {
  priv mut original : RelationTargetDocument?
  priv backing : RelationDocument
  priv declaration : RowDeclaration
  priv view : RowDeclaredView
  priv bytes : Bytes
  priv schema : @schema.Schema
  priv columns : Array[String]
  priv identity_index : Int
  priv writable_fields : Array[String]
  priv row_cursors : Array[@decode.Cursor]
  priv rows : Array[Array[@admitted.CheckedValue]]
  priv limits : RowPageLimits
  priv usage : @decode.AdmissionUsage
}

///|
pub struct RelationTargetRow {
  priv mut original : RelationTargetRow?
  priv document : RelationTargetDocument
  priv index : Int
  priv before_wire : String
  priv version_cid : String
}

///|
priv suberror RelationDocumentStop {
  RelationDocumentStop(RowSourceIssue)
}

///|
fn relation_document_work(
  work : Ref[Int],
  amount : Int,
) -> Unit raise RelationDocumentStop {
  if amount < 0 || amount > work.val {
    raise RelationDocumentStop(InvalidPage)
  }
  work.val -= amount
}

///|
fn relation_document_field(
  object : @decode.ObjectView,
  name : String,
) -> @decode.Cursor raise RelationDocumentStop {
  @decode.lookup(object, name).unwrap_or_else(() => {
    raise RelationDocumentStop(MissingField(name))
  })
}

///|
fn relation_document_path(
  root : @decode.Cursor,
  path : Array[String],
) -> @decode.Cursor raise RelationDocumentStop {
  let mut selected = root
  for name in path {
    let object = @decode.open_object(selected).unwrap_or_else(() => {
      raise RelationDocumentStop(InvalidPage)
    })
    selected = relation_document_field(object, name)
  }
  selected
}

///|
// Physical JSON int64 numbers are interpreted from their exact original token,
// never the parser's Double. This is a storage codec, not a widening of the
// normal typed-wire int64 contract, which continues to require decimal text.
fn relation_document_integer(
  cell : @decode.Cursor,
  bytes : Bytes,
  limits : @admitted.Limits,
) -> @decode.Cursor raise RelationDocumentStop {
  let span = @decode.cursor_span(cell)
  if span.start_byte < 0 ||
    span.end_byte <= span.start_byte ||
    span.end_byte > bytes.length() {
    raise RelationDocumentStop(InvalidPage)
  }
  let text = @utf8.decode(bytes[span.start_byte:span.end_byte]) catch {
    _ => raise RelationDocumentStop(InvalidPage)
  }
  let start = if text.has_prefix("-") { 1 } else { 0 }
  if text.length() <= start {
    raise RelationDocumentStop(InvalidPage)
  }
  for index in start..<text.length() {
    if text[index] < '0' || text[index] > '9' {
      raise RelationDocumentStop(InvalidPage)
    }
  }
  let cursor = @decode.admit_raw_json(text.to_json(), span, {
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
    max_string_bytes: limits.max_text_bytes,
    max_total_string_bytes: limits.max_text_bytes,
  }).unwrap_or_else(() => raise RelationDocumentStop(InvalidPage))
  guard @decode.decimal_int64(cursor) is Ok(_) else {
    raise RelationDocumentStop(InvalidPage)
  }
  cursor
}

///|
// Both relation reads and target observation use this schema-directed codec.
// Nested Arrays and Objects preserve their declared contracts; JSON fields
// keep their literal physical payload, including any literal "$json" key.
fn relation_document_value(
  contract : @contract.Contract,
  cursor : @decode.Cursor,
  bytes : Bytes,
  limits : @admitted.Limits,
  work : Ref[Int],
) -> @admitted.CheckedValue raise RelationDocumentStop {
  relation_document_work(work, limits.max_nodes)
  let checked = if @decode.is_null(cursor) {
    @admitted.admit(contract, cursor, limits).to_option()
  } else {
    match contract.shape {
      @contract.Signed64 if @decode.view(cursor) is @decode.NumberValue(_) =>
        @admitted.admit(
          contract,
          relation_document_integer(cursor, bytes, limits),
          limits,
        ).to_option()
      @contract.Array(item, ..) => {
        let cursors = @decode.elements(cursor).unwrap_or_else(() => {
          raise RelationDocumentStop(InvalidPage)
        })
        let items = cursors.map(child => {
          relation_document_value(item, child, bytes, limits, work).value
        })
        @admitted.recheck_runtime_value(
          @admitted.array_value(items),
          contract,
          limits,
        )
      }
      @contract.Object(fields) => {
        let declared = @contract.fields(fields)
        let object = @decode.closed_object(
          cursor,
          declared.map(field => field.name),
        ).unwrap_or_else(() => raise RelationDocumentStop(InvalidPage))
        let values = declared.map(field => {
          (
            field.name,
            relation_document_value(
              field.contract,
              relation_document_field(object, field.name),
              bytes,
              limits,
              work,
            ).value,
          )
        })
        @admitted.object_value(values).bind(value => {
          @admitted.recheck_runtime_value(value, contract, limits)
        })
      }
      _ => @admitted.admit(contract, cursor, limits).to_option()
    }
  }
  checked.unwrap_or_else(() => raise RelationDocumentStop(InvalidPage))
}

///|
fn relation_document_original(document : RelationDocument) -> Bool {
  document.original is Some(original) && physical_equal(document, original)
}

///|
fn relation_target_original(document : RelationTargetDocument) -> Bool {
  document.original is Some(original) &&
  physical_equal(document, original) &&
  relation_document_original(document.backing)
}

///|
fn relation_target_row_original(row : RelationTargetRow) -> Bool {
  row.original is Some(original) &&
  physical_equal(row, original) &&
  relation_target_original(row.document)
}

///|
/// Discard only this DATA handle's self-original mark. True means this call
/// severed that reference, not that children, escaped DATA or physical backing
/// retired. Callers discard their private projections before the raw document.
/// Existing getters reject the discarded handle; already returned DATA is
/// unchanged. A copied carrier cannot mutate the original's mark.
pub fn discard_relation_document_original(document : RelationDocument) -> Bool {
  guard document.original is Some(original) &&
    physical_equal(document, original) else {
    return false
  }
  document.original = None
  true
}

///|
/// Discard only this projection's self-original mark, never its shared backing
/// or sibling projections. Check this handle itself rather than parent liveness:
/// a caller can still discard its child after an earlier parent invalidation.
/// False means no mark was severed; neither result acknowledges physical cleanup.
pub fn discard_relation_target_document_original(
  document : RelationTargetDocument,
) -> Bool {
  guard document.original is Some(original) &&
    physical_equal(document, original) else {
    return false
  }
  document.original = None
  true
}

///|
/// Admit one owned original from explicit caller bytes, without model data or
/// a schema cache. Later projections share this exact byte/cursor backing.
pub fn admit_relation_document(
  bytes : Bytes,
  limits : RowPageLimits,
  max_work : Int,
) -> Result[RelationDocument, RowSourceIssue] {
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_rows < 0 ||
    bytes.length() > limits.max_bytes {
    return Err(InvalidPage)
  }
  try {
    let work = Ref(max_work)
    relation_document_work(work, bytes.length())
    let original = Bytes::makei(bytes.length(), index => bytes[index])
    let node = @source.parse_json_bytes_preserving(original, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }).unwrap_or_else(() => raise RelationDocumentStop(InvalidPage))
    let root = @decode.admit(node, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }).unwrap_or_else(() => raise RelationDocumentStop(InvalidPage))
    let usage = @decode.admission_usage(root)
    relation_document_work(work, usage.nodes)
    let document : RelationDocument = {
      original: None,
      bytes: original,
      root,
      limits,
      usage,
      work,
      projection_attempts: 0,
      projections: 0,
      projected_rows: 0L,
      projected_cells: 0L,
    }
    document.original = Some(document)
    Ok(document)
  } catch {
    RelationDocumentStop(issue) => Err(issue)
  }
}

///|
/// Admit every selected relation row under its original declared closed
/// schema. All projections, including failures and repeated requests, spend
/// the same original's finite work budget. Paths and keys are explicit model
/// DATA; sibling relations require their own projection of this same backing.
pub fn project_relation_target_document(
  backing : RelationDocument,
  declaration : RowDeclaration,
  resource : String,
  items_path : Array[String],
  key_path : Array[String]?,
  primary_identity : String,
  writable_fields : Array[String],
) -> Result[RelationTargetDocument, RowSourceIssue] {
  if !relation_document_original(backing) {
    return Err(ForeignSource)
  }
  try {
    let work = backing.work
    relation_document_work(work, 1)
    backing.projection_attempts += 1
    let limits = backing.limits
    if items_path.length() > limits.max_depth ||
      (key_path is Some(path) && path.length() > limits.max_depth) ||
      writable_fields.length() > limits.max_nodes {
      raise RelationDocumentStop(InvalidPage)
    }
    for
      name in [
        resource,
        primary_identity,
        ..items_path,
        ..key_path.unwrap_or([]),
        ..writable_fields,
      ] {
      relation_document_work(work, name.length())
      if @scalar.admit_utf8_length(name, limits.max_bytes) is Err(_) {
        raise RelationDocumentStop(InvalidInputSchema)
      }
    }
    relation_document_work(work, limits.max_nodes)
    let (_, contract) = mapping_original_relation(
      declaration,
      resource,
      primary_identity,
      {
        max_bytes: limits.max_bytes,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_views: limits.max_nodes,
        max_fields: limits.max_nodes,
      },
    ).unwrap_or_else(() => raise RelationDocumentStop(InvalidInputSchema))
    let schema = @schema.from_object(contract).unwrap_or_else(() => {
      raise RelationDocumentStop(InvalidInputSchema)
    })
    let columns = @schema.fields(schema).map(@schema.field_reference_name)
    let identity_index = columns
      .search(primary_identity)
      .unwrap_or_else(() => raise RelationDocumentStop(InvalidInputSchema))
    let identity = @schema.field_at(schema, identity_index).unwrap().contract
    if identity.nullable || !(identity.shape is @contract.Text(_)) {
      raise RelationDocumentStop(InvalidInputSchema)
    }
    let writable = []
    for name in writable_fields {
      relation_document_work(work, columns.length())
      relation_document_work(work, writable.length())
      if name == primary_identity ||
        !columns.contains(name) ||
        writable.contains(name) {
        raise RelationDocumentStop(InvalidInputSchema)
      }
      writable.push(name)
    }
    let view = declaration.views[declaration.views
      .search_by(view => view.resource == resource)
      .unwrap()]
    let original = backing.bytes
    let root = backing.root
    let usage = backing.usage
    if key_path is Some(path) {
      let keys = @decode.elements(relation_document_path(root, path)).unwrap_or_else(() => {
          raise RelationDocumentStop(InvalidPage)
        },
      )
      if keys.length() != 1 || @decode.text(keys[0]) != Ok(primary_identity) {
        raise RelationDocumentStop(InvalidInputSchema)
      }
    }
    let selected = relation_document_path(root, items_path)
    let row_cursors = @decode.elements(selected).unwrap_or_else(() => {
      raise RelationDocumentStop(InvalidPage)
    })
    if row_cursors.length() > limits.max_rows {
      raise RelationDocumentStop(InvalidPage)
    }
    let values : @admitted.Limits = {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_bytes,
    }
    let keys : Array[String] = []
    let rows = []
    for cursor in row_cursors {
      let object = @decode.closed_object(cursor, columns).unwrap_or_else(() => {
        raise RelationDocumentStop(InvalidPage)
      })
      let row = []
      for name in columns {
        let contract = @schema.lookup_reference(schema, name).unwrap().contract
        let value = relation_document_value(
          contract,
          relation_document_field(object, name),
          original,
          values,
          work,
        ) catch {
          _ => raise RelationDocumentStop(Value(name))
        }
        row.push(value)
      }
      guard row[identity_index].value is @admitted.Text(key) else {
        raise RelationDocumentStop(InvalidInputSchema)
      }
      for previous in keys {
        relation_document_work(work, previous.length())
        relation_document_work(work, key.length())
        if previous == key {
          raise RelationDocumentStop(InvalidPage)
        }
      }
      keys.push(key)
      rows.push(row)
    }
    let document : RelationTargetDocument = {
      original: None,
      backing,
      declaration,
      view,
      bytes: original,
      schema,
      columns,
      identity_index,
      writable_fields: writable,
      row_cursors,
      rows,
      limits,
      usage,
    }
    document.original = Some(document)
    backing.projections += 1
    backing.projected_rows += rows.length().to_int64()
    backing.projected_cells += rows.length().to_int64() *
      columns.length().to_int64()
    Ok(document)
  } catch {
    RelationDocumentStop(issue) => Err(issue)
  }
}

///|
/// Compatibility convenience for a single projection. Multi-relation callers
/// must admit once and project every declared relation from that same original.
pub fn admit_relation_target_document(
  declaration : RowDeclaration,
  resource : String,
  items_path : Array[String],
  key_path : Array[String]?,
  primary_identity : String,
  writable_fields : Array[String],
  bytes : Bytes,
  limits : RowPageLimits,
  max_work : Int,
) -> Result[RelationTargetDocument, RowSourceIssue] {
  admit_relation_document(bytes, limits, max_work).bind(backing => {
    project_relation_target_document(
      backing, declaration, resource, items_path, key_path, primary_identity, writable_fields,
    )
  })
}

///|
pub fn relation_document_usage(
  document : RelationDocument,
) -> RelationDocumentUsage? {
  if !relation_document_original(document) {
    return None
  }
  Some({
    raw_bytes: document.bytes.length(),
    raw_nodes: document.usage.nodes,
    raw_depth: document.usage.depth,
    raw_text_bytes: document.usage.total_string_bytes,
    projection_attempts: document.projection_attempts,
    projections: document.projections,
    projected_rows: document.projected_rows,
    projected_cells: document.projected_cells,
    remaining_work: document.work.val,
  })
}

///|
fn emit_relation_target_row(
  document : RelationTargetDocument,
  index : Int,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for column in 0..<document.columns.length() {
    @encode.key(writer, document.columns[column])
    @admitted.emit_checked_wire_value(document.rows[index][column], writer)
  }
  @encode.end_object(writer)
}

///|
pub fn observe_relation_target(
  document : RelationTargetDocument,
  declaration : RowDeclaration,
  identity : String,
) -> Result[RelationTargetRow, RowSourceIssue] {
  if !relation_target_original(document) ||
    !physical_equal(declaration, document.declaration) {
    return Err(ForeignSource)
  }
  if @scalar.admit_utf8_length(identity, document.limits.max_bytes) is Err(_) {
    return Err(InvalidPage)
  }
  let index = document.rows
    .search_by(row => {
      row[document.identity_index].value is @admitted.Text(value) &&
      value == identity
    })
    .unwrap_or_else(() => -1)
  if index < 0 {
    return Err(InvalidPage)
  }
  try {
    let limits = document.limits
    let writer = @encode.writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_relation_target_row(document, index, writer)
    let before_wire = @encode.finish(writer)
    let hash = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_relation_target_row(document, index, hash)
    let row : RelationTargetRow = {
      original: None,
      document,
      index,
      before_wire,
      version_cid: "sha256:" + @encode.finish_hash(hash),
    }
    row.original = Some(row)
    Ok(row)
  } catch {
    _ => Err(InvalidPage)
  }
}

///|
pub fn relation_target_before(row : RelationTargetRow) -> String? {
  if relation_target_row_original(row) {
    Some(row.before_wire)
  } else {
    None
  }
}

///|
pub fn relation_target_version(row : RelationTargetRow) -> String? {
  if relation_target_row_original(row) {
    Some(row.version_cid)
  } else {
    None
  }
}

///|
// Convert checked typed-wire DATA to physical JSON. Only the typed JsonData
// wrapper disappears; literal payload keys and nested contract shapes survive.
fn emit_relation_document_value(
  value : @admitted.Value,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  match value {
    @admitted.JsonData(payload) => emit_relation_document_value(payload, writer)
    @admitted.Array(items) => {
      @encode.begin_array(writer)
      for index in 0..<@admitted.element_count(items) {
        emit_relation_document_value(
          @admitted.element_at(items, index).unwrap(),
          writer,
        )
      }
      @encode.end_array(writer)
    }
    @admitted.Object(fields) => {
      @encode.begin_object(writer)
      for index in 0..<@admitted.element_count(fields) {
        let (name, child) = @admitted.element_at(fields, index).unwrap()
        @encode.key(writer, name)
        emit_relation_document_value(child, writer)
      }
      @encode.end_object(writer)
    }
    _ => @admitted.emit_wire_value(value, writer)
  }
}

///|
/// Prepare byte-preserving changes for an already checked UPDATE. Exact row
/// version and original correspondence are required, but remain DATA checks:
/// only the installed file Owner may bind approval/currentness and replace it.
pub fn prepare_relation_target_update(
  document : RelationTargetDocument,
  row : RelationTargetRow,
  expected_version : String,
  value_wire : String,
  max_work : Int,
) -> Result[Bytes, RowSourceIssue] {
  if !relation_target_row_original(row) ||
    !physical_equal(document, row.document) ||
    expected_version != row.version_cid {
    return Err(ForeignSource)
  }
  try {
    let work = Ref(max_work)
    let limits = document.limits
    relation_document_work(work, value_wire.length())
    if value_wire.length() > limits.max_bytes {
      raise RelationDocumentStop(InvalidPage)
    }
    let wire = @utf8.encode(value_wire)
    relation_document_work(work, wire.length())
    let node = @source.parse_json_bytes_preserving(wire, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }).unwrap_or_else(() => raise RelationDocumentStop(InvalidPage))
    let cursor = @decode.admit(node, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }).unwrap_or_else(() => raise RelationDocumentStop(InvalidPage))
    relation_document_work(work, @decode.admission_usage(cursor).nodes)
    let changes = @decode.closed_object(cursor, document.writable_fields).unwrap_or_else(() => {
        raise RelationDocumentStop(InvalidPage)
      },
    )
    let names = @decode.object_field_names(cursor).unwrap_or_else(() => {
      raise RelationDocumentStop(InvalidPage)
    })
    if names.is_empty() {
      raise RelationDocumentStop(InvalidPage)
    }
    let original = @decode.open_object(document.row_cursors[row.index]).unwrap()
    let replacements = []
    let mut size = document.bytes.length()
    for name in names {
      relation_document_work(work, limits.max_nodes)
      let contract = @schema.lookup_reference(document.schema, name).unwrap().contract
      let checked = @admitted.admit_wire(
        contract,
        relation_document_field(changes, name),
        {
          max_nodes: limits.max_nodes,
          max_depth: limits.max_depth,
          max_text_bytes: limits.max_bytes,
        },
      ).unwrap_or_else(() => raise RelationDocumentStop(Value(name)))
      let writer = @encode.writer(
        limits.max_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
      emit_relation_document_value(checked.value, writer)
      let replacement = @utf8.encode(@encode.finish(writer))
      relation_document_work(work, replacement.length())
      let span = @decode.cursor_span(relation_document_field(original, name))
      if span.start_byte < 0 ||
        span.end_byte <= span.start_byte ||
        span.end_byte > document.bytes.length() {
        raise RelationDocumentStop(InvalidPage)
      }
      size -= span.end_byte - span.start_byte
      replacements.push((span.start_byte, span.end_byte, replacement))
    }
    for replacement in replacements {
      if replacement.2.length() > limits.max_bytes - size {
        raise RelationDocumentStop(InvalidPage)
      }
      size += replacement.2.length()
      relation_document_work(work, replacements.length())
    }
    replacements.sort_by((left, right) => left.0.compare(right.0))
    let mut previous = 0
    for replacement in replacements {
      if replacement.0 < previous {
        raise RelationDocumentStop(InvalidPage)
      }
      previous = replacement.1
    }
    relation_document_work(work, size)
    let mut source = 0
    let mut replacement_index = 0
    let mut replacement_offset = 0
    let output = Bytes::makei(size, _ => {
      if replacements.get(replacement_index) is Some((start, end, replacement)) &&
        source == start {
        let byte = replacement[replacement_offset]
        replacement_offset += 1
        if replacement_offset == replacement.length() {
          source = end
          replacement_index += 1
          replacement_offset = 0
        }
        byte
      } else {
        let byte = document.bytes[source]
        source += 1
        byte
      }
    })
    Ok(output)
  } catch {
    RelationDocumentStop(issue) => Err(issue)
    _ => Err(InvalidPage)
  }
}

///|
/// Consume the original physical response ticket and append selected values
/// through the ordinary admitted-input owner. The document cannot authorize
/// transport, acknowledge cleanup or be substituted for another declaration.
pub fn accept_charged_relation_document(
  run : RowRun,
  charge : RowPageCharge,
  acquisition : RowAcquisition,
  document : RelationTargetDocument,
  max_work : Int,
) -> Result[Int, RowHostIssue] {
  guard !run.closed && run.attempt.state is Reading(read) else {
    return Err(InvalidState)
  }
  match consume_row_page_charge(run, charge) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let result = try {
    guard relation_target_original(document) &&
      run.attempt.preparation is DirectPreparation(preparation) &&
      physical_equal(preparation, acquisition.preparation) &&
      physical_equal(read.schema, preparation.schema) &&
      physical_equal(preparation.view, document.view) &&
      charge.received_bytes == document.bytes.length().to_int64() &&
      document.bytes.length() <= read.page_limits.max_bytes &&
      document.usage.nodes <= read.page_limits.max_nodes &&
      document.usage.depth <= read.page_limits.max_depth &&
      document.rows.length() <= read.page_limits.max_rows &&
      read.pages == 0L &&
      read.listing is None &&
      read.keyed is None else {
      raise RelationDocumentStop(ForeignSource)
    }
    let work = Ref(max_work)
    let indices = []
    let contracts = []
    for name in read.columns {
      let index = document.columns
        .search(name)
        .unwrap_or_else(() => raise RelationDocumentStop(InvalidInputSchema))
      let contract = @schema.lookup_reference(read.schema, name).unwrap().contract
      relation_document_work(work, read.values.max_nodes)
      let same = @contract.type_equal(
        @schema.lookup_reference(document.schema, name).unwrap().contract,
        contract,
        read.values.max_nodes,
      ) catch {
        _ => false
      }
      if !same {
        raise RelationDocumentStop(InvalidInputSchema)
      }
      indices.push(index)
      contracts.push(contract)
    }
    let rows = document.rows.map(row => {
      indices.mapi((column, index) => {
        relation_document_work(work, read.values.max_nodes)
        @admitted.recheck_runtime_value(
          row[index].value,
          contracts[column],
          read.values,
        ).unwrap_or_else(() => {
          raise RelationDocumentStop(Value(read.columns[column]))
        })
      })
    })
    accept_row_source_values(read, read.columns, rows)
  } catch {
    RelationDocumentStop(issue) => Err(issue)
  }
  match result {
    Ok(count) => Ok(count)
    Err(issue) => {
      abort_row_run(run)
      Err(Source(issue))
    }
  }
}

///|
/// Exact admitted scalar DATA for model-declared physical roles. This does
/// not create a ResourceRef, version grant, locator or ContentRef authority.
pub fn relation_target_text(row : RelationTargetRow, field : String) -> String? {
  if !relation_target_row_original(row) ||
    @scalar.admit_utf8_length(field, row.document.limits.max_bytes) is Err(_) {
    return None
  }
  guard row.document.columns.search(field) is Some(index) &&
    row.document.rows[row.index][index].value is @admitted.Text(text) else {
    return None
  }
  Some(text)
}

///|
/// Decode the already-admitted Text to UTF-8 without normalization. The file
/// role and content encoding are installation DATA checked by the Host.
pub fn relation_target_text_bytes(
  row : RelationTargetRow,
  field : String,
) -> Bytes? {
  relation_target_text(row, field).bind(text => {
    if @scalar.admit_utf8_length(text, row.document.limits.max_bytes) is Err(_) {
      None
    } else {
      Some(@utf8.encode(text))
    }
  })
}

///|
pub fn relation_target_row_count(document : RelationTargetDocument) -> Int? {
  if relation_target_original(document) {
    Some(document.rows.length())
  } else {
    None
  }
}

///|
pub fn relation_target_row_identity(
  document : RelationTargetDocument,
  index : Int,
) -> String? {
  if !relation_target_original(document) {
    return None
  }
  guard document.rows.get(index) is Some(row) &&
    row[document.identity_index].value is @admitted.Text(identity) else {
    return None
  }
  Some(identity)
}
