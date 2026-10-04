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
  contracts : Array[@contract.Contract]
}

///|
pub fn prepare_row_source(
  requirement : @planning.QueryRequirement,
  declaration : RowDeclaration,
) -> Result[RowSourcePreparation, RowSourceIssue] {
  let (source_ref, source_contract_cid) = @planning.query_requirement_source(
    requirement,
  )
  guard row_declaration_view(declaration, source_ref) is Some(view) else {
    return Err(UndeclaredSource)
  }
  if view.view_cid != source_contract_cid {
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
  if input_declaration.connector != declaration.connector_id ||
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
  let contracts = []
  for index in 0..<@schema.field_count(schema) {
    let field = @schema.field_at(schema, index).unwrap()
    let name = @schema.field_reference_name(field)
    if !view.fields.contains(name) || columns.contains(name) {
      return Err(InvalidInputSchema)
    }
    columns.push(name)
    contracts.push(@schema.field_contract(field))
  }
  if columns.is_empty() {
    return Err(InvalidInputSchema)
  }
  Ok({ requirement, view, owner, input_index, columns, contracts, })
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
/// A row must carry every declared field the checked input uses; a key that
/// is not a declared field refuses the page; `null` is admitted only where
/// the checked contract is nullable.
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
    guard @decode.object_field_names(item) is Ok(names) &&
      @decode.open_object(item) is Ok(object) else {
      return fail_read(read, InvalidPage)
    }
    for name in names {
      if !preparation.view.fields.contains(name) {
        return fail_read(read, UnexpectedField(name))
      }
    }
    let row = []
    for index, name in preparation.columns {
      guard @decode.lookup(object, name) is Some(cell) else {
        return fail_read(read, MissingField(name))
      }
      match @admitted.admit(preparation.contracts[index], cell, read.values) {
        Ok(value) => row.push(value)
        Err(_) => return fail_read(read, Value(name))
      }
    }
    match @execution.append_admitted_input(read.input, row) {
      Ok(_) => ()
      Err(issue) => return fail_read(read, Capture(issue))
    }
  }
  read.pages = read.pages + 1
  read.rows = read.rows + items.length()
  Ok(items.length())
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
