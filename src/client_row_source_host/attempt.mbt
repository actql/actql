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
  RequestEncoding(@sourcequery.RequestWireIssue)
  ListingProtocol
  ListingIncomplete
  ListingLimit(String)
  ListingLimitUnresolved(String)
  ListingGlobInvalid
  ListingMissingPath(String)
  ListingConflictingResource(String)
  KeyedOwner(@query.KeyedInputRequestIssue)
  KeyedResponse(@sourcequery.KeyedRowResponseIssue)
  KeyedIncomplete
  KeyedCardinality
  KeyedLimit(String)
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
  request : @sourcequery.ParameterizedRequest
  file_listing : @environment.FileListProfile?
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
    is Some(@sourcequery.Direct(mode, request)) else {
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
  let file_listing = @environment.source_request_file_listing(
    @sourcequery.selected_contract(@sourcequery.mode_input(mode)),
  )
  Ok({
    requirement,
    view,
    owner,
    input_index,
    columns,
    schema,
    request,
    file_listing,
  })
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
struct RowSourceRead {
  schema : @schema.Schema
  columns : Array[String]
  declared_fields : Array[String]
  input : @execution.AdmittedInput
  page_limits : RowPageLimits
  values : @admitted.Limits
  retention : @execution.ValueLimits
  reference_issuer : @admitted.ReferenceIssuer?
  listing : RowListingProgress?
  keyed : RowKeyedProgress?
  mut pages : Int64
  mut rows : Int64
  mut open : Bool
}

///|
fn begin_row_source_read(
  preparation : RowSourcePreparation,
  page_limits : RowPageLimits,
  max_capture_rows : Int,
  retention : @execution.ValueLimits,
  reference_issuer? : @admitted.ReferenceIssuer? = None,
  listing_rows? : RowListingRows? = None,
) -> Result[RowSourceRead, RowSourceIssue] {
  if page_limits.max_bytes <= 0 ||
    page_limits.max_nodes <= 0 ||
    page_limits.max_depth <= 0 ||
    page_limits.max_rows <= 0 {
    return Err(InvalidPage)
  }
  let listing = match
    prepare_row_listing_progress(
      preparation.file_listing,
      preparation.request,
      page_limits.max_bytes,
      reference_issuer,
      listing_rows,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  new_row_source_read(
    preparation.owner,
    preparation.input_index,
    preparation.schema,
    preparation.columns,
    preparation.view.fields,
    page_limits,
    max_capture_rows,
    retention,
    reference_issuer,
    listing,
    None,
  )
}

///|
// Direct and keyed transport use the same admitted-input and cancellation
// owner. Neither this private reader nor its CapturedRows grants Source I/O or
// consumption evidence; the selected attempt still has to settle transport.
fn new_row_source_read(
  owner : @lower.BoundPrepared,
  input_index : Int,
  schema : @schema.Schema,
  columns : Array[String],
  declared_fields : Array[String],
  page_limits : RowPageLimits,
  max_capture_rows : Int,
  retention : @execution.ValueLimits,
  reference_issuer : @admitted.ReferenceIssuer?,
  listing : RowListingProgress?,
  keyed : RowKeyedProgress?,
) -> Result[RowSourceRead, RowSourceIssue] {
  match
    @execution.prepare_admitted_input(
      owner, input_index, max_capture_rows, retention,
    ) {
    Ok(input) =>
      Ok({
        schema,
        columns,
        declared_fields,
        input,
        page_limits,
        values: {
          max_nodes: retention.max_nodes,
          max_depth: retention.max_depth,
          max_text_bytes: retention.max_text_bytes,
        },
        retention,
        reference_issuer,
        listing,
        keyed,
        pages: 0L,
        rows: 0L,
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
  if read.listing is Some(listing) {
    clear_row_listing_tokens(listing)
    listing.next_token = None
    listing.request_pending = false
  }
  if read.keyed is Some(progress) {
    cancel_keyed_row_page(progress)
  }
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
  parsed? : @source.Node? = None,
) -> Result[Int, RowSourceIssue] {
  if !read.open {
    return Err(Closed)
  }
  if read.listing is Some(_) {
    return fail_read(read, ListingProtocol)
  }
  if read.keyed is Some(_) {
    return accept_keyed_row_page(read, bytes)
  }
  let limits = read.page_limits
  if bytes.length() > limits.max_bytes {
    return fail_read(read, InvalidPage)
  }
  // A physical page carries external DATA, not authored identifiers. Keep
  // JSON payload keys exact before their checked Value contract is known.
  // The existing row/typed-object readers still enforce the declared fields.
  let node = match parsed {
    Some(value) => value
    None =>
      match
        @source.parse_json_bytes_preserving(bytes, {
          max_input_bytes: limits.max_bytes,
          max_nodes: limits.max_nodes,
          max_depth: limits.max_depth,
        }) {
        Ok(value) => value
        Err(_) => return fail_read(read, InvalidPage)
      }
  }
  guard @decode.admit(node, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    })
    is Ok(root) &&
    @decode.elements(root) is Ok(items) else {
    return fail_read(read, InvalidPage)
  }
  accept_row_source_items(read, items)
}

///|
fn accept_row_source_items(
  read : RowSourceRead,
  items : Array[@decode.Cursor],
) -> Result[Int, RowSourceIssue] {
  if read.keyed is Some(_) {
    return fail_read(read, KeyedIncomplete)
  }
  let limits = read.page_limits
  if items.length() > limits.max_rows {
    return fail_read(read, InvalidPage)
  }
  for item in items {
    let references : (@admitted.ReferenceIssuer, @admitted.ReferenceLimits)? = read.reference_issuer.map(issuer => {
        (
          issuer,
          {
            max_bytes: limits.max_bytes,
            max_nodes: limits.max_nodes,
            max_depth: limits.max_depth,
            max_text_units: limits.max_bytes,
          },
        )
      },
    )
    match
      append_row_source_object(
        read.input,
        read.schema,
        read.declared_fields,
        item,
        read.values,
        read.retention,
        references~,
      ) {
      Ok(_) => ()
      Err(issue) => return fail_read(read, issue)
    }
  }
  read.pages += 1L
  read.rows += items.length().to_int64()
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
  references? : (@admitted.ReferenceIssuer, @admitted.ReferenceLimits)? = None,
) -> Result[Unit, RowSourceIssue] {
  let cells = match
    admit_row_source_object(schema, declared_fields, item, values, references~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  append_row_source_cells(input, schema, cells, retention)
}

///|
// Validate all physical observations before selection. Excluded rows must not
// bypass the checked schema or the Host's reference admission and authority.
fn admit_row_source_object(
  schema : @schema.Schema,
  declared_fields : Array[String],
  item : @decode.Cursor,
  values : @admitted.Limits,
  references? : (@admitted.ReferenceIssuer, @admitted.ReferenceLimits)? = None,
  listing_retention? : RowListingRetention? = None,
) -> Result[Array[@admitted.CheckedValue?], RowSourceIssue] {
  guard @decode.object_field_names(item) is Ok(names) &&
    @decode.open_object(item) is Ok(object) else {
    return Err(InvalidPage)
  }
  for name in names {
    if !declared_fields.contains(name) {
      return Err(UnexpectedField(name))
    }
  }
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
        // Restrict construction before admission, including excluded rows.
        // Both paths call the same original typed owner exactly once.
        let remaining = match listing_retention {
          None => values
          Some(budget) =>
            {
              ..values,
              max_nodes: Int::min(
                values.max_nodes,
                budget.max_nodes - budget.nodes,
              ),
              max_text_bytes: Int::min(
                values.max_text_bytes,
                budget.max_text - budget.text,
              ),
            }
        }
        let admitted = match references {
          Some((issuer, limits)) => {
            let reference_limits = match listing_retention {
              None => limits
              Some(_) =>
                {
                  ..limits,
                  max_nodes: Int::min(limits.max_nodes, remaining.max_nodes),
                  max_text_units: Int::min(
                    limits.max_text_units,
                    remaining.max_text_bytes,
                  ),
                }
            }
            @admitted.admit_host_usage(
              issuer,
              field.contract,
              cell,
              remaining,
              reference_limits,
            )
          }
          None => @admitted.admit_usage(field.contract, cell, remaining)
        }
        let (checked, nodes, text) = match admitted {
          Ok(value) => value
          Err(_) => return Err(Value(name))
        }
        if listing_retention is Some(budget) {
          budget.nodes += nodes
          budget.text += text
        }
        cells.push(Some(checked))
      }
    }
  }
  Ok(cells)
}

///|
fn append_row_source_cells(
  input : @execution.AdmittedInput,
  schema : @schema.Schema,
  cells : Array[@admitted.CheckedValue?],
  retention : @execution.ValueLimits,
) -> Result[Unit, RowSourceIssue] {
  if @schema.all_fields_required(schema) {
    @execution.append_admitted_input(input, cells.map(cell => cell.unwrap())).map_err(issue => {
        Capture(issue)
      },
    )
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
  if read.listing is Some(listing) && !listing.complete {
    return fail_read(read, ListingIncomplete)
  }
  if read.keyed is Some(progress) && !progress.complete {
    return fail_read(read, KeyedIncomplete)
  }
  read.open = false
  if read.listing is None ||
    !(read.listing.unwrap().resolved_rows is Some(ReportListingRows(_, _))) {
    // Preserve ordinary acquisition and protocol-only fixtures unchanged.
    return @execution.finish_admitted_input(read.input).map_err(issue => {
      Capture(issue)
    })
  }
  match @execution.finish_admitted_input(read.input) {
    Ok(scan) =>
      match finish_row_listing_reports(read, scan) {
        Ok(_) => Ok(scan)
        Err(issue) => Err(issue)
      }
    Err(issue) => Err(Capture(issue))
  }
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
    // This primitive descriptor does not supply a classified policy.
    // Classified evidence is generated from the admitted declaration owner.
    classification: "unknown",
  }
}

///|
/// Admit already-typed provider values into the same input owner as JSON
/// pages. append_admitted_input checks exact contract identity (including
/// decimal precision/scale), width and retention limits before retaining a row.
fn row_source_value_indices(
  read : RowSourceRead,
  columns : Array[String],
  rows : Array[Array[@admitted.CheckedValue]],
) -> Result[Array[Int], RowSourceIssue] {
  if !read.open {
    return Err(Closed)
  }
  if read.listing is Some(_) {
    return fail_read(read, ListingProtocol)
  }
  // Typed provider pages have no physical byte observation. Until that receipt
  // is supplied by the keyed transport, they cannot bypass its response gate.
  if read.keyed is Some(_) {
    return fail_read(read, InvalidPage)
  }
  if columns.length() != read.columns.length() ||
    rows.length() > read.page_limits.max_rows {
    return fail_read(read, InvalidPage)
  }
  let indices = []
  for name in read.columns {
    let found = columns.search(name)
    guard found is Some(index) && !indices.contains(index) else {
      return fail_read(read, InvalidPage)
    }
    indices.push(index)
  }
  Ok(indices)
}

///|
fn append_row_source_values(
  read : RowSourceRead,
  columns : Array[String],
  rows : Array[Array[@admitted.CheckedValue]],
  indices : Array[Int],
) -> Result[Int, RowSourceIssue] {
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
  read.pages += 1L
  read.rows += rows.length().to_int64()
  Ok(rows.length())
}

///|
fn accept_row_source_values(
  read : RowSourceRead,
  columns : Array[String],
  rows : Array[Array[@admitted.CheckedValue]],
) -> Result[Int, RowSourceIssue] {
  let indices = match row_source_value_indices(read, columns, rows) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  append_row_source_values(read, columns, rows, indices)
}
