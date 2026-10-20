///|
/// Bounded, owned DATA from the actual Mock file. It supplies no read/write
/// grant, file identity, physical currentness, claim or cleanup acknowledgement.
/// The existing installed file Owner must bind those independently.
pub struct MockTargetDocument {
  priv mut original : MockTargetDocument?
  priv declaration : RowDeclaration
  priv bytes : Bytes
  priv root : @decode.Cursor
  priv columns : Array[String]
  priv rows : Array[Array[@admitted.CheckedValue]]
  priv limits : RowPageLimits
}

///|
/// One original row within that admitted document, not a target-read grant.
pub struct MockTargetRow {
  priv mut original : MockTargetRow?
  priv document : MockTargetDocument
  priv index : Int
  priv before_wire : String
  priv version_cid : String
}

///|
fn mock_target_original(document : MockTargetDocument) -> Bool {
  document.original is Some(original) && physical_equal(document, original)
}

///|
fn mock_target_row_original(row : MockTargetRow) -> Bool {
  row.original is Some(original) &&
  physical_equal(row, original) &&
  mock_target_original(row.document)
}

///|
/// Validate every row and both original declarations before exposing a target.
/// The caller covers the input/copy/parser/typed rows simultaneously. Copy the
/// bytes rather than retaining a mutable caller view across later awaits.
pub fn admit_mock_churn_risk_target_document(
  salesforce : RowDeclaration,
  snowflake : RowDeclaration,
  bytes : Bytes,
  limits : RowPageLimits,
  max_work : Int,
) -> Result[MockTargetDocument, RowSourceIssue] {
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_rows < 0 ||
    bytes.length() > limits.max_bytes ||
    bytes.length() > max_work {
    return Err(InvalidPage)
  }
  let work = Ref(max_work)
  let declarations : RowDeclarationLimits = {
    max_bytes: limits.max_bytes,
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
    max_views: 1,
    max_fields: 5,
  }
  let schema = try {
    mock_rows_work(work, bytes.length())
    mock_rows_schema(salesforce, false, declarations, work)
  } catch {
    MockRowsStop(issue) => return Err(issue)
  }
  let original = Bytes::makei(bytes.length(), index => bytes[index])
  let columns = salesforce.views[0].fields.copy()
  let (rows, root) = match
    mock_churn_risk_selected_document(
      schema,
      columns,
      limits,
      {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_text_bytes: limits.max_bytes,
      },
      salesforce,
      salesforce,
      snowflake,
      original,
      work.val,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let document : MockTargetDocument = {
    original: None,
    declaration: salesforce,
    bytes: original,
    root,
    columns,
    rows,
    limits,
  }
  document.original = Some(document)
  Ok(document)
}

///|
fn emit_mock_target_row(
  document : MockTargetDocument,
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
fn mock_target_row_cursor(
  document : MockTargetDocument,
  index : Int,
) -> @decode.Cursor raise MockRowsStop {
  let root = @decode.closed_object(document.root, ["salesforce", "snowflake"]).unwrap_or_else(() => {
      raise MockRowsStop(InvalidPage)
    },
  )
  let source = @decode.closed_object(mock_rows_field(root, "salesforce"), [
    "Account",
  ]).unwrap_or_else(() => raise MockRowsStop(InvalidPage))
  let table = @decode.closed_object(mock_rows_field(source, "Account"), [
    "key", "rows",
  ]).unwrap_or_else(() => raise MockRowsStop(InvalidPage))
  let rows = @decode.elements(mock_rows_field(table, "rows")).unwrap_or_else(() => {
    raise MockRowsStop(InvalidPage)
  })
  rows.get(index).unwrap_or_else(() => raise MockRowsStop(InvalidPage))
}

///|
pub fn observe_mock_churn_risk_target(
  document : MockTargetDocument,
  declaration : RowDeclaration,
  identity : String,
) -> Result[MockTargetRow, RowSourceIssue] {
  if !mock_target_original(document) ||
    !physical_equal(declaration, document.declaration) {
    return Err(ForeignSource)
  }
  guard document.columns.search_by(name => name == "id") is Some(id_index) else {
    return Err(InvalidInputSchema)
  }
  let index = document.rows.search_by(row => {
    row[id_index].value is @admitted.Text(value) && value == identity
  })
  guard index is Some(index) else { return Err(InvalidPage) }
  try {
    let limits = document.limits
    let writer = @encode.writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_mock_target_row(document, index, writer)
    let before_wire = @encode.finish(writer)
    // The value version describes this complete actual row, not authority.
    // The file Owner separately binds its installation, selector, original
    // bytes and conditional replacement; another document cannot supply it.
    let hash = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_mock_target_row(document, index, hash)
    let version_cid = "sha256:" + @encode.finish_hash(hash)
    let row : MockTargetRow = {
      original: None,
      document,
      index,
      before_wire,
      version_cid,
    }
    row.original = Some(row)
    Ok(row)
  } catch {
    _ => Err(InvalidPage)
  }
}

///|
pub fn mock_churn_risk_target_before(row : MockTargetRow) -> String? {
  if mock_target_row_original(row) {
    Some(row.before_wire)
  } else {
    None
  }
}

///|
pub fn mock_churn_risk_target_version(row : MockTargetRow) -> String? {
  if mock_target_row_original(row) {
    Some(row.version_cid)
  } else {
    None
  }
}

///|
/// Prepare exact file bytes for the already checked UPDATE Mapping. This is
/// not a send: the file Owner must conditionally replace its actual original
/// only after current authorization, approval and the durable row claim.
pub fn prepare_mock_churn_risk_target_update(
  document : MockTargetDocument,
  row : MockTargetRow,
  expected_version : String,
  value_wire : String,
  max_work : Int,
) -> Result[Bytes, RowSourceIssue] {
  if !mock_target_row_original(row) ||
    !physical_equal(document, row.document) ||
    expected_version != row.version_cid {
    return Err(ForeignSource)
  }
  try {
    let work = Ref(max_work)
    let wire = @utf8.encode(value_wire)
    mock_rows_work(work, wire.length())
    let limits = document.limits
    if wire.length() > limits.max_bytes {
      raise MockRowsStop(InvalidPage)
    }
    let node = @source.parse_json_bytes_preserving(wire, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }).unwrap_or_else(() => raise MockRowsStop(InvalidPage))
    let cursor = @decode.admit(node, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }).unwrap_or_else(() => raise MockRowsStop(InvalidPage))
    mock_rows_work(work, @decode.admission_usage(cursor).nodes)
    let names = ["Churn_Risk__c", "Risk_Reason__c"]
    let changes = @decode.closed_object(cursor, names).unwrap_or_else(() => {
      raise MockRowsStop(InvalidPage)
    })
    let original = @decode.closed_object(
      mock_target_row_cursor(document, row.index),
      document.columns,
    ).unwrap_or_else(() => raise MockRowsStop(InvalidPage))
    let replacements = []
    for name in names {
      // The existing fixed Mapping has reject-null on both writable fields.
      let text = @decode.text(mock_rows_field(changes, name)).unwrap_or_else(() => {
        raise MockRowsStop(Value(name))
      })
      let writer = @encode.writer(limits.max_bytes, 1, 1)
      @encode.string_value(writer, text)
      let bytes = @utf8.encode(@encode.finish(writer))
      let span = @decode.cursor_span(mock_rows_field(original, name))
      replacements.push((span.start_byte, span.end_byte, bytes))
    }
    if replacements[0].0 > replacements[1].0 {
      let first = replacements[0]
      replacements[0] = replacements[1]
      replacements[1] = first
    }
    let (a, b) = (replacements[0], replacements[1])
    if a.0 < 0 ||
      a.1 <= a.0 ||
      a.1 > b.0 ||
      b.1 <= b.0 ||
      b.1 > document.bytes.length() {
      raise MockRowsStop(InvalidPage)
    }
    let base = document.bytes.length() - (a.1 - a.0) - (b.1 - b.0)
    if base > limits.max_bytes ||
      a.2.length() > limits.max_bytes - base ||
      b.2.length() > limits.max_bytes - base - a.2.length() {
      raise MockRowsStop(InvalidPage)
    }
    let size = base + a.2.length() + b.2.length()
    mock_rows_work(work, size)
    let end_a = a.0 + a.2.length()
    let before_b = end_a + b.0 - a.1
    let end_b = before_b + b.2.length()
    let output = Bytes::makei(size, index => {
      if index < a.0 {
        document.bytes[index]
      } else if index < end_a {
        a.2[index - a.0]
      } else if index < before_b {
        document.bytes[a.1 + index - end_a]
      } else if index < end_b {
        b.2[index - before_b]
      } else {
        document.bytes[b.1 + index - end_b]
      }
    })
    Ok(output)
  } catch {
    MockRowsStop(issue) => Err(issue)
    _ => Err(InvalidPage)
  }
}
