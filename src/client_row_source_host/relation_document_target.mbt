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
// The original admitted declaration's schema only. It is DATA held by the
// installing caller, not Source/Effect authority or a document observation.
// Private fields prevent a caller-supplied Contract from replacing its schema.
struct RelationDocumentPreparedContract {
  declaration : RowDeclaration
  resource : String
  primary_identity : String
  limits : RowPageLimits
  contract : @contract.Contract
  schema : @schema.Schema
  columns : Array[String]
  identity_index : Int
}

///|
/// Prepared ordered key metadata for the original declared relation.
struct RelationDocumentPreparedKey {
  original : RelationDocumentPreparedContract
  positions : Array[Int]
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
  priv ordered_positions : Array[Int]?
  priv writable_fields : Array[String]
  priv row_array : @decode.Cursor
  priv rows : Array[Array[@admitted.CheckedValue]]
  priv limits : RowPageLimits
  priv usage : @decode.AdmissionUsage
}

///|
/// The same physical file projection and its original ordered key layout.
struct RelationOrderedTargetDocument {
  document : RelationTargetDocument
  positions : Array[Int]
}

///|
/// A checked tuple tied to one original prepared layout. It retains typed
/// DATA for comparison and canonical emission, without any read authority.
struct RelationTargetKey {
  positions : Array[Int]
  checked : Array[@admitted.CheckedValue]
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
fn RelationTargetDocument::row_cursor(
  self : RelationTargetDocument,
  index : Int,
) -> @decode.Cursor {
  @decode.element_at(self.row_array, index).unwrap()
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
/// Sever this row observation's private self-original after its consumer has
/// returned. The parent document may already be invalidated by reentry. This
/// invalidates row getters but neither closes a read nor acknowledges physical
/// cleanup; returned immutable DATA keeps its existing meaning.
pub fn discard_relation_target_row_original(row : RelationTargetRow) -> Bool {
  guard row.original is Some(original) && physical_equal(row, original) else {
    return false
  }
  row.original = None
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
  prepared_contract? : RelationDocumentPreparedContract? = None,
) -> Result[RelationTargetDocument, RowSourceIssue] {
  project_relation_target_document_selected(
    backing,
    declaration,
    resource,
    items_path,
    key_path,
    primary_identity,
    writable_fields,
    prepared_contract,
    None,
  )
}

///|
/// Select the original declared File projection. An ordered key borrows the
/// layout already prepared under its installation owner.
pub fn project_relation_target_document_from_catalog_key(
  backing : RelationDocument,
  declaration : RowDeclaration,
  resource : String,
  items_path : Array[String],
  key_path : Array[String]?,
  primary_identity : String?,
  prepared_key : RelationDocumentPreparedKey?,
  writable_fields : Array[String],
) -> Result[RelationTargetDocument, RowSourceIssue] {
  match (primary_identity, prepared_key) {
    (Some(identity), None) =>
      project_relation_target_document(
        backing, declaration, resource, items_path, key_path, identity, writable_fields,
      )
    (None, Some(prepared)) =>
      project_relation_target_document_with_key(
        backing, declaration, resource, items_path, key_path, writable_fields, prepared,
      ).map(relation_ordered_target_document)
    _ => Err(InvalidInputSchema)
  }
}

///|
/// Project the same original relation under its prepared ordered key. The
/// caller funds prepared metadata and the same document projection recipe.
pub fn project_relation_target_document_with_key(
  backing : RelationDocument,
  declaration : RowDeclaration,
  resource : String,
  items_path : Array[String],
  key_path : Array[String]?,
  writable_fields : Array[String],
  prepared : RelationDocumentPreparedKey,
) -> Result[RelationOrderedTargetDocument, RowSourceIssue] {
  project_relation_target_document_selected(
    backing,
    declaration,
    resource,
    items_path,
    key_path,
    prepared.original.primary_identity,
    writable_fields,
    Some(prepared.original),
    Some(prepared.positions),
  ).map(document => { document, positions: prepared.positions, })
}

///|
fn project_relation_target_document_selected(
  backing : RelationDocument,
  declaration : RowDeclaration,
  resource : String,
  items_path : Array[String],
  key_path : Array[String]?,
  primary_identity : String,
  writable_fields : Array[String],
  prepared_contract : RelationDocumentPreparedContract?,
  ordered_positions : Array[Int]?,
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
    let (schema, columns, identity_index) = match prepared_contract {
      Some(original) => {
        if !physical_equal(original.declaration, declaration) ||
          original.resource != resource ||
          original.primary_identity != primary_identity ||
          original.limits.max_bytes != limits.max_bytes ||
          (if ordered_positions is Some(_) {
            original.limits.max_nodes < limits.max_nodes
          } else {
            original.limits.max_nodes != limits.max_nodes
          }) ||
          original.limits.max_depth != limits.max_depth {
          raise RelationDocumentStop(ForeignSource)
        }
        // Same already-admitted metadata; no schema read/hash or work charge
        // for a mapping which was not reconstructed. Every actual row, path,
        // key and Value below still spends this document's original work.
        (original.schema, original.columns, original.identity_index)
      }
      None => {
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
        (schema, columns, identity_index)
      }
    }
    let writable = []
    for name in writable_fields {
      relation_document_work(work, columns.length())
      relation_document_work(work, writable.length())
      if ordered_positions is Some(positions) {
        relation_document_work(work, positions.length())
      }
      if name == primary_identity ||
        (
          ordered_positions is Some(positions) &&
          positions.any(position => columns[position] == name)
        ) ||
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
      if !relation_target_identity_matches_path(
          identity_index, ordered_positions, columns, keys, work,
        ) {
        raise RelationDocumentStop(InvalidInputSchema)
      }
    }
    let row_array = relation_document_path(root, items_path)
    let row_count = @decode.array_length(row_array).unwrap_or_else(() => {
      raise RelationDocumentStop(InvalidPage)
    })
    if row_count > limits.max_rows {
      raise RelationDocumentStop(InvalidPage)
    }
    let values : @admitted.Limits = {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_bytes,
    }
    let rows : Array[Array[@admitted.CheckedValue]] = []
    for index in 0..<row_count {
      let cursor = @decode.element_at(row_array, index).unwrap()
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
      for previous in rows {
        if relation_target_rows_share_identity(
            identity_index, ordered_positions, previous, row, work,
          ) {
          raise RelationDocumentStop(InvalidPage)
        }
      }
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
      identity_index: if ordered_positions is None {
        identity_index
      } else {
        -1
      },
      ordered_positions,
      writable_fields: writable,
      row_array,
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
fn relation_target_identity_matches_path(
  identity_index : Int,
  ordered_positions : Array[Int]?,
  columns : Array[String],
  keys : Array[@decode.Cursor],
  work : Ref[Int],
) -> Bool raise RelationDocumentStop {
  match ordered_positions {
    None =>
      keys.length() == 1 && @decode.text(keys[0]) == Ok(columns[identity_index])
    Some(positions) => {
      if keys.length() != positions.length() {
        return false
      }
      for ordinal, position in positions {
        relation_document_work(work, 1)
        let expected = columns[position]
        relation_document_work(work, expected.length())
        if @decode.text(keys[ordinal]) != Ok(expected) {
          return false
        }
      }
      true
    }
  }
}

///|
fn relation_target_key_cell_matches(
  left : @admitted.CheckedValue,
  right : @admitted.CheckedValue,
  work : Ref[Int],
) -> Bool raise RelationDocumentStop {
  relation_document_work(work, 1)
  if (left.value, right.value) is (@admitted.Text(a), @admitted.Text(b)) {
    relation_document_work(work, a.length())
    relation_document_work(work, b.length())
  }
  match @admitted.compare_key_values(left, right) {
    Ok(order) => order == 0
    Err(_) => raise RelationDocumentStop(InvalidInputSchema)
  }
}

///|
fn relation_target_rows_share_identity(
  identity_index : Int,
  ordered_positions : Array[Int]?,
  left : Array[@admitted.CheckedValue],
  right : Array[@admitted.CheckedValue],
  work : Ref[Int],
) -> Bool raise RelationDocumentStop {
  match ordered_positions {
    None => {
      guard (left[identity_index].value, right[identity_index].value)
        is (@admitted.Text(a), @admitted.Text(b)) else {
        raise RelationDocumentStop(InvalidInputSchema)
      }
      relation_document_work(work, a.length())
      relation_document_work(work, b.length())
      a == b
    }
    Some(positions) => {
      for position in positions {
        if !relation_target_key_cell_matches(
            left[position],
            right[position],
            work,
          ) {
          return false
        }
      }
      true
    }
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
  before_document? : Ref[@encode.EncodedDocument?]? = None,
) -> Result[RelationTargetRow, RowSourceIssue] {
  if !relation_target_original(document) ||
    !physical_equal(declaration, document.declaration) ||
    (before_document is Some(slot) && slot.val is Some(_)) {
    return Err(ForeignSource)
  }
  if @scalar.admit_utf8_length(identity, document.limits.max_bytes) is Err(_) {
    return Err(InvalidPage)
  }
  let position = document.identity_index
  if position < 0 {
    return Err(InvalidInputSchema)
  }
  let index = document.rows
    .search_by(row => {
      row[position].value is @admitted.Text(value) && value == identity
    })
    .unwrap_or_else(() => -1)
  if index < 0 {
    return Err(InvalidPage)
  }
  relation_target_observation(document, index, before_document~)
}

///|
/// Observe through the original catalog projection. The document selects
/// scalar Text or canonical typed tuple, independently of the request wire.
pub fn observe_relation_target_from_catalog_key(
  document : RelationTargetDocument,
  declaration : RowDeclaration,
  identity : String,
) -> Result[RelationTargetRow, RowSourceIssue] {
  guard document.ordered_positions is Some(_) else {
    return observe_relation_target(document, declaration, identity)
  }
  find_relation_target_from_catalog_key(document, declaration, identity).bind(row => {
    match row {
      Some(value) => Ok(value)
      None => Err(InvalidPage)
    }
  })
}

///|
/// A successful complete ordered search may prove absence. Malformed input,
/// a foreign original or exhausted work cannot produce that proof.
pub fn find_relation_target_from_catalog_key(
  document : RelationTargetDocument,
  declaration : RowDeclaration,
  identity : String,
) -> Result[RelationTargetRow?, RowSourceIssue] {
  if !relation_target_original(document) ||
    !physical_equal(declaration, document.declaration) {
    return Err(ForeignSource)
  }
  guard document.ordered_positions is Some(positions) else {
    return Err(InvalidInputSchema)
  }
  let original : RelationOrderedTargetDocument = { document, positions, }
  admit_relation_target_key_wire(original, identity).bind(key => {
    find_relation_target_with_key(original, declaration, key)
  })
}

///|
/// Compare the ordered typed wire tuple against the original retained rows.
/// The cursor is borrowed from the caller's bounded typed-wire admission.
pub fn observe_relation_target_with_key(
  original : RelationOrderedTargetDocument,
  declaration : RowDeclaration,
  key : @decode.Cursor,
) -> Result[RelationTargetRow, RowSourceIssue] {
  if !physical_equal(declaration, original.document.declaration) {
    return Err(ForeignSource)
  }
  let target = match admit_relation_target_key(original, key) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match find_relation_target_with_key(original, declaration, target) {
    Ok(Some(row)) => Ok(row)
    Ok(None) => Err(InvalidPage)
    Err(issue) => Err(issue)
  }
}

///|
/// Admit the key under the exact prepared layout and original document work.
/// The caller keeps the borrowed input and funds the temporary tuple.
pub fn admit_relation_target_key(
  original : RelationOrderedTargetDocument,
  key : @decode.Cursor,
) -> Result[RelationTargetKey, RowSourceIssue] {
  let { document, positions, } = original
  if !relation_target_original(document) {
    return Err(ForeignSource)
  }
  if @decode.array_length(key) != Some(positions.length()) {
    return Err(InvalidPage)
  }
  try {
    let work = document.backing.work
    let limits = document.limits
    let values : @admitted.Limits = {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_bytes,
    }
    let mut key_bytes = limits.max_bytes
    let checked = positions.mapi((index, position) => {
      relation_document_work(work, limits.max_nodes)
      let field = @schema.field_at(document.schema, position).unwrap()
      let cursor = @decode.element_at(key, index).unwrap()
      guard @decode.text(cursor) is Ok(text) else {
        raise RelationDocumentStop(Value(document.columns[position]))
      }
      relation_document_work(work, text.length())
      guard @scalar.admit_utf8_length(text, key_bytes) is Ok(bytes) else {
        raise RelationDocumentStop(Value(document.columns[position]))
      }
      key_bytes -= bytes
      @admitted.admit_wire(field.contract, cursor, values).unwrap_or_else(() => {
        raise RelationDocumentStop(Value(document.columns[position]))
      })
    })
    Ok({ positions, checked, })
  } catch {
    RelationDocumentStop(issue) => Err(issue)
  }
}

///|
/// Emit the checked tuple into the caller's bounded canonical writer.
/// Field and type correspondence stays with the admitted layout.
pub fn emit_relation_target_key(
  key : RelationTargetKey,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(writer)
  for component in key.checked {
    @admitted.emit_checked_wire_value(component, writer)
  }
  @encode.end_array(writer)
}

///|
/// Decode the exact canonical wire selected by the Effect. The returned key
/// is bound to the original layout, and its comparison uses the shared work.
pub fn admit_relation_target_key_wire(
  original : RelationOrderedTargetDocument,
  key_wire : String,
) -> Result[RelationTargetKey, RowSourceIssue] {
  let document = original.document
  if !relation_target_original(document) {
    return Err(ForeignSource)
  }
  let limits = document.limits
  let width = original.positions.length()
  if width >= limits.max_nodes ||
    limits.max_depth < 2 ||
    key_wire.is_empty() ||
    key_wire.length() > limits.max_bytes {
    return Err(InvalidPage)
  }
  try {
    let work = document.backing.work
    relation_document_work(work, key_wire.length())
    let bytes = @scalar.admit_utf8_length(key_wire, limits.max_bytes).unwrap_or_else(() => {
        raise RelationDocumentStop(InvalidPage)
      },
    )
    relation_document_work(work, bytes)
    let nodes = width + 1
    let parsed = @source.parse_json(key_wire, {
      max_input_bytes: bytes,
      max_nodes: nodes,
      max_depth: 2,
    }).unwrap_or_else(() => raise RelationDocumentStop(InvalidPage))
    let cursor = @decode.admit(parsed, {
      max_nodes: nodes,
      max_depth: 2,
      max_string_bytes: bytes,
      max_total_string_bytes: bytes,
    }).unwrap_or_else(() => raise RelationDocumentStop(InvalidPage))
    let checked = match admit_relation_target_key(original, cursor) {
      Ok(key) => key
      Err(issue) => raise RelationDocumentStop(issue)
    }
    let writer = @encode.writer(bytes, nodes, 2)
    defer @encode.cancel_writer(writer)
    emit_relation_target_key(checked, writer)
    if @encode.finish(writer) != key_wire {
      raise RelationDocumentStop(InvalidPage)
    }
    Ok(checked)
  } catch {
    RelationDocumentStop(issue) => Err(issue)
    _ => Err(InvalidPage)
  }
}

///|
/// Prove absence only after completing the original bounded comparison.
/// A foreign layout, retired document, exhausted work, or failed row
/// observation remains an error and cannot be treated as a missing target.
pub fn find_relation_target_with_key(
  original : RelationOrderedTargetDocument,
  declaration : RowDeclaration,
  key : RelationTargetKey,
) -> Result[RelationTargetRow?, RowSourceIssue] {
  find_relation_target_index_with_key(original, declaration, key).bind(index => {
    match index {
      Some(index) =>
        relation_target_observation(original.document, index).map(row => {
          Some(row)
        })
      None => Ok(None)
    }
  })
}

///|
fn find_relation_target_index_with_key(
  original : RelationOrderedTargetDocument,
  declaration : RowDeclaration,
  key : RelationTargetKey,
) -> Result[Int?, RowSourceIssue] {
  let { document, positions, } = original
  if !relation_target_original(document) ||
    !physical_equal(declaration, document.declaration) ||
    !physical_equal(positions, key.positions) {
    return Err(ForeignSource)
  }
  try {
    let work = document.backing.work
    for index, row in document.rows {
      let mut matches = true
      for ordinal, position in positions {
        if !relation_target_key_cell_matches(
            row[position],
            key.checked[ordinal],
            work,
          ) {
          matches = false
          break
        }
      }
      if matches {
        return Ok(Some(index))
      }
    }
    Ok(None)
  } catch {
    RelationDocumentStop(issue) => Err(issue)
  }
}

///|
/// Borrow the same projected data for the existing replacement and retirement
/// operations. A Text probe cannot use this ordered-key document.
pub fn relation_ordered_target_document(
  original : RelationOrderedTargetDocument,
) -> RelationTargetDocument {
  original.document
}

///|
fn relation_target_observation(
  document : RelationTargetDocument,
  index : Int,
  before_document? : Ref[@encode.EncodedDocument?]? = None,
) -> Result[RelationTargetRow, RowSourceIssue] {
  try {
    let limits = document.limits
    let writer = @encode.writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_relation_target_row(document, index, writer)
    let mut encoded : @encode.EncodedDocument? = None
    let before_wire = if before_document is Some(_) {
      let original = @encode.finish_document(writer)
      encoded = Some(original)
      @encode.document_text(original)
    } else {
      @encode.finish(writer)
    }
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
    if before_document is Some(slot) {
      slot.val = encoded
    }
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
/// Prepare an insertion from the original locked document DATA and mapped
/// CREATE values. The caller supplies the physical Text identity separately
/// and owns construction funding, approval and physical replacement.
pub fn prepare_relation_target_insert(
  backing : RelationDocument,
  prepared : RelationDocumentPreparedContract,
  items_path : Array[String],
  key_path : Array[String]?,
  identity : String,
  mapped_wire : String,
) -> Result[Bytes, RowSourceIssue] {
  let document = match
    project_relation_target_document(
      backing,
      prepared.declaration,
      prepared.resource,
      items_path,
      key_path,
      prepared.primary_identity,
      [],
      prepared_contract=Some(prepared),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  defer discard_relation_target_document_original(document) |> ignore
  prepare_relation_target_insert_row(
    document,
    items_path.length(),
    identity,
    None,
    mapped_wire,
  )
}

///|
/// Prepare the insert side of UPSERT from the locked original document.
/// The checked tuple supplies all key columns. Projection and a complete
/// typed search must both succeed before this constructor can append a row.
pub fn prepare_relation_target_insert_with_key(
  backing : RelationDocument,
  prepared : RelationDocumentPreparedKey,
  items_path : Array[String],
  key_path : Array[String]?,
  key_wire : String,
  mapped_wire : String,
) -> Result[Bytes, RowSourceIssue] {
  let declaration = prepared.original.declaration
  let ordered = match
    project_relation_target_document_with_key(
      backing,
      declaration,
      prepared.original.resource,
      items_path,
      key_path,
      [],
      prepared,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let document = ordered.document
  defer discard_relation_target_document_original(document) |> ignore
  let tuple = match admit_relation_target_key_wire(ordered, key_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match find_relation_target_index_with_key(ordered, declaration, tuple) {
    Ok(None) =>
      prepare_relation_target_insert_row(
        document,
        items_path.length(),
        "",
        Some(tuple),
        mapped_wire,
      )
    Ok(Some(_)) => Err(InvalidPage)
    Err(issue) => Err(issue)
  }
}

///|
fn prepare_relation_target_insert_row(
  document : RelationTargetDocument,
  path_depth : Int,
  identity : String,
  tuple : RelationTargetKey?,
  mapped_wire : String,
) -> Result[Bytes, RowSourceIssue] {
  try {
    let backing = document.backing
    let limits = document.limits
    let work = backing.work
    let bytes = backing.bytes
    let row_count = document.rows.length()
    let separator = if row_count == 0 { 0 } else { 1 }
    let room = limits.max_bytes - bytes.length() - separator
    let nodes = limits.max_nodes - backing.usage.nodes
    let depth = limits.max_depth - path_depth - 1
    if row_count >= limits.max_rows ||
      room < 1 ||
      nodes < 1 ||
      depth < 1 ||
      mapped_wire.length() > limits.max_bytes ||
      (
        tuple is None &&
        (identity.is_empty() || identity.length() > limits.max_bytes)
      ) {
      raise RelationDocumentStop(InvalidPage)
    }
    relation_document_work(work, mapped_wire.length())
    let wire_bytes = @scalar.admit_utf8_length(mapped_wire, limits.max_bytes).unwrap_or_else(() => {
        raise RelationDocumentStop(InvalidPage)
      },
    )
    relation_document_work(work, wire_bytes)
    let wire = @utf8.encode(mapped_wire)
    // Typed wire can be larger or deeper than physical JSON because it
    // carries wrappers. Bound its construction by the original request
    // envelope. The writer checks remaining file room independently.
    let parsed = @source.parse_json_bytes_preserving(wire, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }).unwrap_or_else(() => raise RelationDocumentStop(InvalidPage))
    let cursor = @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }).unwrap_or_else(() => raise RelationDocumentStop(InvalidPage))
    let wire_nodes = @decode.admission_usage(cursor).nodes
    relation_document_work(work, wire_nodes)
    let object = @decode.closed_object(cursor, document.columns).unwrap_or_else(() => {
        raise RelationDocumentStop(InvalidPage)
      },
    )
    match tuple {
      None =>
        if @decode.lookup(object, document.columns[document.identity_index])
          is Some(_) {
          raise RelationDocumentStop(ForeignSource)
        }
      Some(key) =>
        for position in key.positions {
          relation_document_work(work, wire_nodes)
          if @decode.lookup(object, document.columns[position]) is Some(_) {
            raise RelationDocumentStop(ForeignSource)
          }
        }
    }
    let writer = @encode.writer(room, nodes, depth)
    @encode.begin_object(writer)
    for index, name in document.columns {
      relation_document_work(work, wire_nodes)
      let contract = @schema.field_at(document.schema, index).unwrap().contract
      if tuple is Some(key) {
        relation_document_work(work, key.positions.length())
        if key.positions.search(index) is Some(component) {
          // An Int64 key stays exact through physical JSON number emission.
          let value = key.checked[component].value
          @encode.key(writer, name)
          match value {
            @admitted.Signed64(number) =>
              @encode.decimal_number_value(writer, number.to_string())
            _ => emit_relation_document_value(value, writer)
          }
          continue
        }
      }
      let checked = if index == document.identity_index {
        relation_document_work(work, identity.length())
        let key = @admitted.checked_text_value(identity, contract).unwrap_or_else(() => {
            raise RelationDocumentStop(Value(name))
          },
        )
        for row in document.rows {
          guard row[index].value is @admitted.Text(previous) else {
            raise RelationDocumentStop(InvalidInputSchema)
          }
          relation_document_work(work, previous.length())
          relation_document_work(work, identity.length())
          if previous == identity {
            raise RelationDocumentStop(InvalidPage)
          }
        }
        key
      } else {
        @admitted.admit_wire(contract, relation_document_field(object, name), {
          max_nodes: wire_nodes,
          max_depth: limits.max_depth,
          max_text_bytes: limits.max_bytes,
        }).unwrap_or_else(() => raise RelationDocumentStop(Value(name)))
      }
      @encode.key(writer, name)
      emit_relation_document_value(checked.value, writer)
    }
    @encode.end_object(writer)
    let row = @utf8.encode(@encode.finish(writer))
    relation_document_work(work, row.length())
    let array = @decode.cursor_span(document.row_array)
    let slot = if row_count == 0 {
      array.start_byte + 1
    } else {
      @decode.cursor_span(document.row_cursor(row_count - 1)).end_byte
    }
    if array.start_byte < 0 ||
      array.end_byte > bytes.length() ||
      slot <= array.start_byte ||
      slot >= array.end_byte ||
      bytes[array.start_byte] != b'[' ||
      bytes[array.end_byte - 1] != b']' ||
      row.length() > room {
      raise RelationDocumentStop(InvalidPage)
    }
    let inserted = row.length() + separator
    let size = bytes.length() + inserted
    relation_document_work(work, size)
    Ok(
      Bytes::makei(size, index => {
        if index < slot {
          bytes[index]
        } else if separator == 1 && index == slot {
          b','
        } else if index < slot + inserted {
          row[index - slot - separator]
        } else {
          bytes[index - inserted]
        }
      }),
    )
  } catch {
    RelationDocumentStop(issue) => Err(issue)
    _ => Err(InvalidPage)
  }
}

///|
priv struct RelationTargetUpdateLayout {
  size : Int
  replacements : Array[(Int, Int, Bytes)]
}

///|
fn plan_relation_target_update(
  document : RelationTargetDocument,
  row : RelationTargetRow,
  expected_version : String,
  value_wire : String,
  max_work : Int,
) -> Result[RelationTargetUpdateLayout, RowSourceIssue] {
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
    let original = @decode.open_object(document.row_cursor(row.index)).unwrap()
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
    Ok({ size, replacements, })
  } catch {
    RelationDocumentStop(issue) => Err(issue)
    _ => Err(InvalidPage)
  }
}

///|
/// Check the exact observed version and prospective replacement extent.
/// Preview owns only validation DATA and no returned replacement buffer.
pub fn check_relation_target_update(
  document : RelationTargetDocument,
  row : RelationTargetRow,
  expected_version : String,
  value_wire : String,
  max_work : Int,
) -> Result[Unit, RowSourceIssue] {
  plan_relation_target_update(
    document, row, expected_version, value_wire, max_work,
  ).map(_ => ())
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
  let plan = match
    plan_relation_target_update(
      document, row, expected_version, value_wire, max_work,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let mut source = 0
  let mut replacement_index = 0
  let mut replacement_offset = 0
  let output = Bytes::makei(plan.size, _ => {
    if plan.replacements.get(replacement_index)
      is Some((start, end, replacement)) &&
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
}

///|
/// Prepare replacement DATA for removing the original observed row. The file
/// owner must still bind the operation, approval and current file generation.
pub fn prepare_relation_target_delete(
  document : RelationTargetDocument,
  row : RelationTargetRow,
  expected_version : String,
  max_work : Int,
) -> Result[Bytes, RowSourceIssue] {
  if !relation_target_row_original(row) ||
    !physical_equal(document, row.document) ||
    expected_version != row.version_cid {
    return Err(ForeignSource)
  }
  let bytes = document.bytes
  let span = @decode.cursor_span(document.row_cursor(row.index))
  try {
    let work = Ref(max_work)
    // Remove the following separator when possible, otherwise the preceding
    // one. The gap between original adjacent elements contains one comma and
    // optional whitespace. Keep that whitespace in the replacement.
    let separator = if row.index + 1 < document.rows.length() {
      relation_target_separator(
        bytes,
        span.end_byte,
        @decode.cursor_span(document.row_cursor(row.index + 1)).start_byte,
        work,
      )
    } else if row.index > 0 {
      relation_target_separator(
        bytes,
        @decode.cursor_span(document.row_cursor(row.index - 1)).end_byte,
        span.start_byte,
        work,
      )
    } else {
      bytes.length()
    }
    let row_bytes = span.end_byte - span.start_byte
    let separator_bytes = if separator < bytes.length() { 1 } else { 0 }
    let size = bytes.length() - row_bytes - separator_bytes
    relation_document_work(work, size)
    Ok(
      Bytes::makei(size, index => {
        // Translate each output index through the two removed ranges in source
        // order. This also keeps equal-looking values in other collections.
        let mut source = index
        if separator < span.start_byte && source >= separator {
          source += 1
        }
        if source >= span.start_byte {
          source += row_bytes
        }
        if separator >= span.end_byte && source >= separator {
          source += 1
        }
        bytes[source]
      }),
    )
  } catch {
    RelationDocumentStop(issue) => Err(issue)
  }
}

///|
fn relation_target_separator(
  bytes : Bytes,
  start : Int,
  end : Int,
  work : Ref[Int],
) -> Int raise RelationDocumentStop {
  relation_document_work(work, end - start)
  for index in start..<end {
    if bytes[index] == b',' {
      return index
    }
  }
  raise RelationDocumentStop(InvalidPage)
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
  accept_charged_relation_document_original(
    run,
    charge,
    RelationDocumentQuery(acquisition),
    document,
    max_work,
  )
}

///|
/// The complete checked Source input uses the SAME response ticket/document
/// owner. No Query requirement is fabricated and no physical byte is refunded.
pub fn accept_charged_relation_input_document(
  run : RowRun,
  charge : RowPageCharge,
  acquisition : RowInputAcquisition,
  document : RelationTargetDocument,
  max_work : Int,
) -> Result[Int, RowHostIssue] {
  accept_charged_relation_document_original(
    run,
    charge,
    RelationDocumentInput(acquisition),
    document,
    max_work,
  )
}

///|
priv enum RelationDocumentAcquisition {
  RelationDocumentQuery(RowAcquisition)
  RelationDocumentInput(RowInputAcquisition)
}

///|
fn accept_charged_relation_document_original(
  run : RowRun,
  charge : RowPageCharge,
  original : RelationDocumentAcquisition,
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
    let original_matches = match original {
      RelationDocumentQuery(acquisition) =>
        match run.attempt.preparation {
          DirectPreparation(preparation) =>
            physical_equal(preparation, acquisition.preparation) &&
            physical_equal(read.schema, preparation.schema) &&
            physical_equal(preparation.view, document.view)
          _ => false
        }
      RelationDocumentInput(acquisition) =>
        match run.attempt.preparation {
          InputPreparation(preparation) =>
            physical_equal(preparation, acquisition.preparation) &&
            physical_equal(read.schema, preparation.schema) &&
            physical_equal(preparation.view, document.view)
          _ => false
        }
    }
    guard relation_target_original(document) &&
      original_matches &&
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
    if original is RelationDocumentInput(_) && run.physical is Some(_) {
      let selected = match row_source_value_indices(read, read.columns, rows) {
        Ok(value) => value
        Err(issue) => raise RelationDocumentStop(issue)
      }
      match fund_row_input_values(run, read, rows) {
        Ok(_) => ()
        Err(issue) => {
          abort_row_run(run)
          return Err(issue)
        }
      }
      append_row_source_values(read, read.columns, rows, selected)
    } else {
      accept_row_source_values(read, read.columns, rows)
    }
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
  let position = document.identity_index
  guard position >= 0 &&
    document.rows.get(index) is Some(row) &&
    row[position].value is @admitted.Text(identity) else {
    return None
  }
  Some(identity)
}
