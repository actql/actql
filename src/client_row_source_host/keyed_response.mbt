///|
priv struct RowKeyedProgress {
  facts : @sourcequery.KeyedSourceFacts
  request : @sourcequery.KeyedRowRequest
  indices : Array[Int]
  limits : @sourcequery.RequestLimits
  cardinality : @environment.SourceCardinality
  max_pages : Int64
  max_rows : Int64
  mut pages : Int64
  mut bytes : Int64
  mut rows : Int64
  mut work : Int
  mut complete : Bool
  mut page : RowKeyedPage?
}

///|
priv struct RowKeyedPage {
  items : Array[@decode.Cursor]
  mut index : Int
  mut cells : Array[@admitted.CheckedValue?]?
  values : Array[@admitted.Value]
  mut role : Int
  mut cursor : @sourcequery.KeyedRowResponseCursor?
  mut cursor_work : Int
  mut validated : Bool
}

///|
pub enum RowKeyedPagePoll {
  KeyedPageContinue(work~ : Int)
  KeyedPageComplete(rows~ : Int, work~ : Int)
}

///|
/// Bind the actual checked keyed input to the existing private row reader.
/// No direct QueryRequirement is manufactured and no Source grant or receipt
/// is issued. The physical attempt must still authorize and settle its I/O.
pub fn begin_declared_keyed_row_read(
  owner : @lower.BoundPrepared,
  facts : @sourcequery.KeyedSourceFacts,
  request : @sourcequery.KeyedRowRequest,
  connector_id : String,
  view : RowDeclaredView,
  page_limits : RowPageLimits,
  max_capture_rows : Int,
  retention : @execution.ValueLimits,
  limits : @sourcequery.RequestLimits,
  reference_issuer? : @admitted.ReferenceIssuer? = None,
) -> Result[RowSourceRead, RowSourceIssue] {
  if page_limits.max_bytes <= 0 ||
    page_limits.max_nodes <= 0 ||
    page_limits.max_depth <= 0 ||
    page_limits.max_rows <= 0 ||
    max_capture_rows < 0 ||
    limits.max_work < 0 ||
    limits.max_pairs < 0 ||
    limits.values.max_nodes < 0 ||
    limits.values.max_depth < 0 ||
    limits.values.max_text_bytes < 0 {
    return Err(InvalidPage)
  }
  let join = @sourcequery.keyed_source_join(facts)
  let schema = match @query.keyed_response_input_schema(owner, join, request) {
    Ok(schema) => schema
    Err(issue) => return Err(KeyedOwner(issue))
  }
  let input_index = match @query.keyed_response_input_index(owner, join) {
    Ok(value) => value
    Err(issue) => return Err(KeyedOwner(issue))
  }
  let input = @sourcequery.keyed_request_input(
    @sourcequery.parameterized_keyed_request(
      @sourcequery.keyed_join_request(join),
    ),
  )
  let declared = @sourcequery.declaration(input)
  // Resolve the same checked Catalog facts used by ordinary acquisition.
  // Provider declarations cannot replace the response schema or its policy
  // merely by repeating the selected view's name/CID.
  guard @planning.keyed_source_evidence_facts(facts) is Some(source_facts) else {
    return Err(UndeclaredSource)
  }
  if declared.connector != connector_id ||
    declared.resource != view.resource ||
    view.view_cid != @sourcequery.selected_cid(input) ||
    view.source_ref != source_facts.source_ref ||
    view.carrier_schema_cid != source_facts.carrier_schema_contract_cid ||
    view.data_policy_cid != source_facts.source_data_policy_cid {
    return Err(UndeclaredSource)
  }
  let capacity = @sourcequery.keyed_source_capacity(facts)
  if @environment.lookup_capacity_completeness(capacity) !=
    @environment.CompletePerRequestedKey {
    return Err(KeyedIncomplete)
  }
  if page_limits.max_bytes.to_int64() >
    @environment.lookup_capacity_response_bytes_per_page(capacity) ||
    max_capture_rows.to_int64() >
    @environment.lookup_capacity_rows_per_key(capacity) {
    return Err(KeyedLimit("catalog_capacity"))
  }
  let roles = @sourcequery.keyed_request_correlation(
    @sourcequery.parameterized_keyed_request(
      @sourcequery.keyed_join_request(join),
    ),
  )
  let count = @environment.source_correlation_pair_count(roles)
  if count > limits.max_pairs {
    return Err(KeyedLimit("correlation_pairs"))
  }
  let columns = []
  let indices = []
  let mut work = 0
  for i in 0..<@schema.field_count(schema) {
    let name = @schema.field_reference_name(
      @schema.field_at(schema, i).unwrap(),
    )
    if work == limits.max_work || name.length() > limits.max_work - work - 1 {
      return Err(KeyedLimit("work"))
    }
    work += name.length() + 1
    if !view.fields.contains(name) || columns.contains(name) {
      return Err(InvalidInputSchema)
    }
    columns.push(name)
  }
  for i in 0..<count {
    let name = @environment.source_correlation_pair_at(roles, i).unwrap().response.name
    let mut index = -1
    for j in 0..<columns.length() {
      if work == limits.max_work || name.length() > limits.max_work - work - 1 {
        return Err(KeyedLimit("work"))
      }
      work += name.length() + 1
      if columns[j].length() > limits.max_work - work {
        return Err(KeyedLimit("work"))
      }
      work += columns[j].length()
      if columns[j] == name {
        index = j
        break
      }
    }
    if index < 0 {
      return Err(MissingField(name))
    }
    indices.push(index)
  }
  new_row_source_read(
    owner,
    input_index,
    schema,
    columns,
    view.fields,
    page_limits,
    max_capture_rows,
    retention,
    reference_issuer,
    None,
    Some({
      facts,
      request,
      indices,
      limits,
      cardinality: @environment.source_correlation_cardinality(roles),
      max_pages: @environment.lookup_capacity_pages_per_request(capacity),
      max_rows: max_capture_rows.to_int64(),
      pages: 0L,
      bytes: 0L,
      rows: 0L,
      work,
      complete: false,
      page: None,
    }),
  )
}

///|
pub fn begin_keyed_row_page(
  read : RowSourceRead,
  bytes : Bytes,
) -> Result[Unit, RowSourceIssue] {
  if !read.open {
    return Err(Closed)
  }
  guard read.keyed is Some(progress) else { return Err(ForeignSource) }
  if progress.complete || progress.page is Some(_) {
    return Err(KeyedIncomplete)
  }
  if progress.pages == progress.max_pages {
    return fail_read(read, KeyedLimit("pages"))
  }
  // Account this physical observation exactly once, including a rejected
  // over-limit or malformed body. Polling never replays this accounting.
  progress.pages += 1L
  if bytes.length().to_int64() > 9223372036854775807L - progress.bytes {
    return fail_read(read, KeyedLimit("response_bytes"))
  }
  progress.bytes += bytes.length().to_int64()
  let limits = read.page_limits
  if bytes.length() > limits.max_bytes {
    return fail_read(read, KeyedLimit("response_bytes_per_page"))
  }
  // Use the same external DATA decoder as ordinary physical rows. Normalizing
  // arbitrary JSON keys here would irreversibly alter a typed JSON payload
  // before correlation and the declared Value contracts can inspect it.
  guard @source.parse_json_bytes_preserving(bytes, {
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
  progress.page = Some({
    items,
    index: 0,
    cells: None,
    values: [],
    role: 0,
    cursor: None,
    cursor_work: 0,
    validated: false,
  })
  Ok(())
}

///|
// Advance the existing reader, not a second page/capture owner. Quantum
// bounds state transitions; a shared comparison transition can consume two
// logical work units. Report its exact delta once, independent of quantum.
// JSON decoding and one value admission retain their existing finite limits;
// this API does not claim those synchronous boundaries are scalar cursors.
pub fn advance_keyed_row_page(
  read : RowSourceRead,
  quantum : Int,
) -> Result[RowKeyedPagePoll, RowSourceIssue] {
  if !read.open {
    return Err(Closed)
  }
  guard read.keyed is Some(progress) && progress.page is Some(page) else {
    return Err(KeyedIncomplete)
  }
  if quantum <= 0 {
    return Err(KeyedLimit("quantum"))
  }
  let initial_work = progress.work
  for _ in 0..<quantum {
    if page.cursor is Some(cursor) {
      let result = @sourcequery.advance_keyed_row_response(cursor)
      let current = @sourcequery.keyed_row_response_work(cursor)
      progress.work += current - page.cursor_work
      page.cursor_work = current
      match result {
        KeyedRowResponseContinue => continue
        KeyedRowResponseFailed(issue) =>
          return fail_read(read, KeyedResponse(issue))
        KeyedRowResponseComplete => {
          page.cursor = None
          page.validated = true
          progress.rows += 1L
          continue
        }
      }
    }
    if page.cells is Some(_) &&
      !page.validated &&
      page.role == progress.indices.length() {
      let cursor = match
        @sourcequery.start_keyed_row_response(progress.request, page.values, {
          ..progress.limits,
          max_work: progress.limits.max_work - progress.work,
        }) {
        Ok(value) => value
        Err(issue) => return fail_read(read, KeyedResponse(issue))
      }
      // Copy/start work is consumed even if cancellation precedes first poll.
      page.cursor_work = @sourcequery.keyed_row_response_work(cursor)
      progress.work += page.cursor_work
      page.cursor = Some(cursor)
      continue
    }
    if progress.work == progress.limits.max_work {
      return fail_read(read, KeyedLimit("work"))
    }
    progress.work += 1
    if page.index == page.items.length() {
      let rows = page.index
      progress.page = None
      read.pages += 1L
      read.rows += rows.to_int64()
      return Ok(KeyedPageComplete(rows~, work=progress.work - initial_work))
    }
    if page.cells is None {
      if progress.rows == progress.max_rows ||
        (
          progress.rows > 0L &&
          progress.cardinality is (@environment.One | @environment.ZeroOrOne)
        ) {
        return fail_read(read, KeyedCardinality)
      }
      let limits = read.page_limits
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
      page.cells = match
        admit_row_source_object(
          read.schema,
          read.declared_fields,
          page.items[page.index],
          read.values,
          references~,
        ) {
        Ok(value) => Some(value)
        Err(issue) => return fail_read(read, issue)
      }
      continue
    }
    let cells = page.cells.unwrap()
    if !page.validated {
      let index = progress.indices[page.role]
      guard cells.get(index) is Some(Some(cell)) else {
        return fail_read(read, KeyedCardinality)
      }
      page.values.push(cell.value)
      page.role += 1
      continue
    }
    match
      append_row_source_cells(read.input, read.schema, cells, read.retention) {
      Ok(_) => ()
      Err(issue) => return fail_read(read, issue)
    }
    page.index += 1
    page.cells = None
    page.values.clear()
    page.role = 0
    page.cursor_work = 0
    page.validated = false
  }
  Ok(KeyedPageContinue(work=progress.work - initial_work))
}

///|
fn cancel_keyed_row_page(progress : RowKeyedProgress) -> Unit {
  if progress.page is Some(page) {
    if page.cursor is Some(cursor) {
      @sourcequery.cancel_keyed_row_response(cursor)
    }
    page.cursor = None
    page.cells = None
    page.values.clear()
    progress.page = None
  }
}

///|
pub fn accept_keyed_row_page(
  read : RowSourceRead,
  bytes : Bytes,
) -> Result[Int, RowSourceIssue] {
  match begin_keyed_row_page(read, bytes) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_keyed_row_page(read, 64) {
      Ok(KeyedPageContinue(..)) => ()
      Ok(KeyedPageComplete(rows~, ..)) => return Ok(rows)
      Err(issue) => return Err(issue)
    }
  }
  Err(KeyedIncomplete)
}

///|
/// The existing physical attempt calls this only on protocol completion, not
/// on page size or output LIMIT. This is private row completion, not the later
/// trusted transport/evidence settlement required for Source consumption.
pub fn complete_keyed_row_read(
  read : RowSourceRead,
) -> Result[@execution.CapturedRows, RowSourceIssue] {
  if !read.open {
    return Err(Closed)
  }
  guard read.keyed is Some(progress) else { return Err(ForeignSource) }
  if progress.page is Some(_) {
    return Err(KeyedIncomplete)
  }
  if progress.cardinality is (@environment.One | @environment.OneOrMany) &&
    progress.rows == 0L {
    return fail_read(read, KeyedCardinality)
  }
  progress.complete = true
  finish_row_source_read(read)
}

///|
pub fn cancel_keyed_row_read(read : RowSourceRead) -> Bool {
  if read.keyed is None {
    return false
  }
  cancel_row_source_read(read)
}

///|
pub fn keyed_row_read_usage(read : RowSourceRead) -> (Int, Int64, Int64) {
  match read.keyed {
    Some(progress) => (progress.work, progress.pages, progress.bytes)
    None => (0, 0L, 0L)
  }
}

///|
/// The original checked occurrence retained by this exact reader. These are
/// static Catalog facts, including after failure; they do not prove physical
/// settlement or permit reading a closed input. No equal wire/CID replacement
/// can stand in for this owner when reserving a selected acquisition attempt.
pub fn keyed_row_read_facts(
  read : RowSourceRead,
) -> @sourcequery.KeyedSourceFacts? {
  read.keyed.map(progress => progress.facts)
}
