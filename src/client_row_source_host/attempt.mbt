// The provider-neutral row acquisition attempt. A connector's Site driver
// pushes pages of JSON rows; this owner admits each value against the exact
// checked input schema, then runs the same custody, residual, retention,
// evidence and capture steps every broad acquisition uses. Rows never become
// a captured source unless the whole attempt completed and was settled.

///|
pub(all) enum RowSourceIssue {
  ForeignSource
  UndeclaredSource
  InvalidInputSchema
  InvalidPage
  MissingField(String)
  UnexpectedField(String)
  Value(String)
  Presence(@execution.RelationPresenceIssue)
  Capture(@execution.CaptureIssue)
  Closed
} derive(Debug)

///|
/// One exact checked source bound to a declared view: the columns of the
/// checked input, in order, by declared field name.
struct RowSourcePreparation {
  requirement : @planning.QueryRequirement
  view : RowDeclaredView
  owner : @lower.BoundPrepared
  input_index : Int
  columns : Array[String]
  schema : @schema.Schema
}

///|
pub fn prepare_row_source(
  requirement : @planning.QueryRequirement,
  declaration : RowDeclaration,
) -> Result[RowSourcePreparation, RowSourceIssue] {
  let source_ref = @planning.query_requirement_source(requirement).0
  guard row_declaration_view(declaration, source_ref) is Some(view) else {
    return Err(UndeclaredSource)
  }
  prepare_declared_row_source(requirement, declaration.connector_id, view)
}

///|
/// Bind a provider's regenerated declared view to the exact checked input.
/// This is preparation only: it grants no I/O or capture authority and never
/// substitutes a caller-supplied schema for the checked contracts.
pub fn prepare_declared_row_source(
  requirement : @planning.QueryRequirement,
  connector_id : String,
  view : RowDeclaredView,
) -> Result[RowSourcePreparation, RowSourceIssue] {
  let (source_ref, source_contract_cid) = @planning.query_requirement_source(
    requirement,
  )
  if view.source_ref != source_ref || view.view_cid != source_contract_cid {
    return Err(UndeclaredSource)
  }
  let sequence = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  let query = @query.query_sequence_requirement(sequence)
  let requests = @sourcequery.query_acquisition_owner(query)
  guard @sourcequery.pipeline_request_at(
      requests,
      @sourcequery.query_acquisition_source_index(query),
    )
    is Some(@sourcequery.Direct(mode, _)) else {
    return Err(ForeignSource)
  }
  let input_declaration = @sourcequery.declaration(
    @sourcequery.mode_input(mode),
  )
  if input_declaration.connector != connector_id ||
    input_declaration.resource != view.resource {
    return Err(ForeignSource)
  }
  let owner = @query.query_sequence_owner(sequence)
  guard @sourcequery.query_acquisition_input(query)
    is @pipeline.Input(input_index) &&
    @lower.preparation_input_schema(
      @lower.bound_preparation(owner),
      input_index,
    )
    is Some(schema) else {
    return Err(InvalidInputSchema)
  }
  let columns = []
  for index in 0..<@schema.field_count(schema) {
    let field = @schema.field_at(schema, index).unwrap()
    let name = @schema.field_reference_name(field)
    if !view.fields.contains(name) || columns.contains(name) {
      return Err(InvalidInputSchema)
    }
    columns.push(name)
  }
  if columns.is_empty() {
    return Err(InvalidInputSchema)
  }
  Ok({ requirement, view, owner, input_index, columns, schema, })
}

///|
pub fn row_source_requirement(
  preparation : RowSourcePreparation,
) -> @planning.QueryRequirement {
  preparation.requirement
}

///|
pub fn row_source_columns(preparation : RowSourcePreparation) -> Array[String] {
  preparation.columns
}

///|
pub(all) struct RowPageLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
} derive(Eq, Debug)

///|
/// Admitted rows of one attempt. Each page is admitted whole before the next
/// is requested; no partial CapturedRows is exposed on failure.
priv struct RowSourceRead {
  preparation : RowSourcePreparation
  input : @execution.AdmittedInput
  page_limits : RowPageLimits
  values : @admitted.Limits
  retention : @execution.ValueLimits
  mut pages : Int
  mut rows : Int
  mut open : Bool
}

///|
fn begin_row_source_read(
  preparation : RowSourcePreparation,
  page_limits : RowPageLimits,
  max_capture_rows : Int,
  retention : @execution.ValueLimits,
) -> Result[RowSourceRead, RowSourceIssue] {
  if page_limits.max_bytes <= 0 ||
    page_limits.max_nodes <= 0 ||
    page_limits.max_depth <= 0 ||
    page_limits.max_rows <= 0 {
    return Err(InvalidPage)
  }
  match
    @execution.prepare_admitted_input(
      preparation.owner,
      preparation.input_index,
      max_capture_rows,
      retention,
    ) {
    Ok(input) =>
      Ok({
        preparation,
        input,
        page_limits,
        values: {
          max_nodes: retention.max_nodes,
          max_depth: retention.max_depth,
          max_text_bytes: retention.max_text_bytes,
        },
        retention,
        pages: 0,
        rows: 0,
        open: true,
      })
    Err(issue) => Err(Capture(issue))
  }
}

///|
fn cancel_row_source_read(read : RowSourceRead) -> Bool {
  if !read.open {
    return false
  }
  read.open = false
  @execution.cancel_admitted_input(read.input) |> ignore
  true
}

///|
fn[T] fail_read(
  read : RowSourceRead,
  issue : RowSourceIssue,
) -> Result[T, RowSourceIssue] {
  cancel_row_source_read(read) |> ignore
  Err(issue)
}

///|
/// Admit one page: a JSON array of objects keyed by declared field names.
/// Required columns cannot disappear. Conditional columns retain omission
/// separately from NULL under the exact checked input schema. Undeclared keys
/// and values outside that schema still refuse the whole acquisition.
fn accept_row_source_page(
  read : RowSourceRead,
  bytes : Bytes,
) -> Result[Int, RowSourceIssue] {
  if !read.open {
    return Err(Closed)
  }
  let limits = read.page_limits
  if bytes.length() > limits.max_bytes {
    return fail_read(read, InvalidPage)
  }
  guard @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    })
    is Ok(node) &&
    @decode.admit(node, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    })
    is Ok(root) &&
    @decode.elements(root) is Ok(items) else {
    return fail_read(read, InvalidPage)
  }
  if items.length() > limits.max_rows {
    return fail_read(read, InvalidPage)
  }
  let preparation = read.preparation
  for item in items {
    match
      append_row_source_object(
        read.input,
        preparation.schema,
        preparation.view.fields,
        item,
        read.values,
        read.retention,
      ) {
      Ok(_) => ()
      Err(issue) => return fail_read(read, issue)
    }
  }
  read.pages = read.pages + 1
  read.rows = read.rows + items.length()
  Ok(items.length())
}

///|
// Keep page admission on the existing exact-input owner. A physical reader
// never supplies presence guarantees, substitutes contracts or manufactures
// NULL for an omitted cell. Dense sources retain their existing copy path.
fn append_row_source_object(
  input : @execution.AdmittedInput,
  schema : @schema.Schema,
  declared_fields : Array[String],
  item : @decode.Cursor,
  values : @admitted.Limits,
  retention : @execution.ValueLimits,
) -> Result[Unit, RowSourceIssue] {
  guard @decode.object_field_names(item) is Ok(names) &&
    @decode.open_object(item) is Ok(object) else {
    return Err(InvalidPage)
  }
  for name in names {
    if !declared_fields.contains(name) {
      return Err(UnexpectedField(name))
    }
  }
  let dense = @schema.all_fields_required(schema)
  let row : Array[@admitted.CheckedValue] = []
  let cells : Array[@admitted.CheckedValue?] = []
  for index in 0..<@schema.field_count(schema) {
    let field = @schema.field_at(schema, index).unwrap()
    let name = @schema.field_reference_name(field)
    match @decode.lookup(object, name) {
      None => {
        if @schema.field_presence(field) == @schema.Required {
          return Err(MissingField(name))
        }
        cells.push(None)
      }
      Some(cell) => {
        let checked = match @admitted.admit(field.contract, cell, values) {
          Ok(value) => value
          Err(_) => return Err(Value(name))
        }
        if dense {
          row.push(checked)
        } else {
          cells.push(Some(checked))
        }
      }
    }
  }
  if dense {
    @execution.append_admitted_input(input, row).map_err(issue => Capture(issue))
  } else {
    let admitted = match
      @execution.admit_relation_row(schema, cells, retention) {
      Ok(value) => value
      Err(issue) => return Err(Presence(issue))
    }
    @execution.append_admitted_input_presence(input, admitted).map_err(issue => {
      Capture(issue)
    })
  }
}

///|
fn finish_row_source_read(
  read : RowSourceRead,
) -> Result[@execution.CapturedRows, RowSourceIssue] {
  if !read.open {
    return Err(Closed)
  }
  read.open = false
  @execution.finish_admitted_input(read.input).map_err(issue => Capture(issue))
}

///|
fn execute_row_source_residual(
  preparation : RowSourcePreparation,
  input : @execution.CapturedRows,
  limits : @execution.SequenceExecutionLimits,
  measurement : @query.QueryGuardMeasureLimits,
) -> Result[
  (@execution.CompletedSequence, (Int, Int, Int)),
  @query.QueryGuardIssue,
] {
  let sequence = @planning.query_material_owner(
    @planning.query_requirement_material(preparation.requirement),
  )
  let receipt = match @query.bind_query_receipt(sequence, input) {
    Ok(value) => value
    Err(issue) => return Err(Execution(issue))
  }
  let guards = @planning.query_requirement_guards(preparation.requirement)
  @query.execute_query_receipt_guarded(
    sequence,
    receipt,
    limits,
    max_output_rows=guards.max_rows,
    max_value_bytes=guards.max_value_bytes,
    measurement,
  )
}

///|
/// Preserve a declared view's existing identity; provider adapters obtain
/// these facts from their regenerated declaration, never from returned rows.
pub fn declared_row_view(
  resource : String,
  source_ref : String,
  view_cid : String,
  fields : Array[String],
  carrier_schema_cid : String,
  data_policy_cid : String,
) -> RowDeclaredView {
  {
    resource,
    source_ref,
    view_cid,
    fields: fields.copy(),
    carrier_schema_cid,
    data_policy_cid,
  }
}

///|
/// Admit already-typed provider values into the same input owner as JSON
/// pages. append_admitted_input checks exact contract identity (including
/// decimal precision/scale), width and retention limits before retaining a row.
fn accept_row_source_values(
  read : RowSourceRead,
  columns : Array[String],
  rows : Array[Array[@admitted.CheckedValue]],
) -> Result[Int, RowSourceIssue] {
  if !read.open {
    return Err(Closed)
  }
  if columns.length() != read.preparation.columns.length() ||
    rows.length() > read.page_limits.max_rows {
    return fail_read(read, InvalidPage)
  }
  let indices = []
  for name in read.preparation.columns {
    let found = columns.search(name)
    guard found is Some(index) && !indices.contains(index) else {
      return fail_read(read, InvalidPage)
    }
    indices.push(index)
  }
  for row in rows {
    if row.length() != columns.length() {
      return fail_read(read, InvalidPage)
    }
    match
      @execution.append_admitted_input(
        read.input,
        indices.map(index => row[index]),
      ) {
      Ok(_) => ()
      Err(issue) => return fail_read(read, Capture(issue))
    }
  }
  read.pages += 1
  read.rows += rows.length()
  Ok(rows.length())
}
