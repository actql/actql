///|
// Both Query and complete Source inputs enter the SAME listing protocol.
// Construct selectors/progress only after the caller's Source reservation.
fn prepare_row_listing_progress(
  profile : @environment.FileListProfile?,
  request : @sourcequery.ParameterizedRequest,
  max_pattern_units : Int,
  reference_issuer : @admitted.ReferenceIssuer?,
  rows : RowListingRows?,
  retention? : RowListingRetention? = None,
) -> Result[RowListingProgress?, RowSourceIssue] {
  guard profile is Some(profile) else { return Ok(None) }
  if reference_issuer is None {
    return Err(Value("resource"))
  }
  if rows is None {
    return Err(ListingLimitUnresolved("max_listing_items"))
  }
  let selection = match prepare_row_file_selection(request, max_pattern_units) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(
    Some(
      new_row_listing_progress(
        @environment.file_listing_limit_candidates(profile),
        resolved_rows=rows,
        selection=Some(selection),
        retention~,
      ),
    ),
  )
}

///|
// The same RowRun's retained-metadata inventory, not a second input, Ledger
// or listing permission. Usage comes from the original typed admission once.
priv struct RowListingRetention {
  max_nodes : Int
  max_text : Int
  mut nodes : Int
  mut text : Int
}

///|
// Protocol observations retained by the existing RowSourceRead. This is not
// another acquisition owner, a count proof or a durable restart receipt.
priv struct RowListingProgress {
  limits : Array[(String, Int64)]
  resolved_rows : RowListingRows?
  selection : RowFileSelection?
  tokens : Array[String]
  observations : Map[String, Array[@admitted.CheckedValue?]]
  found_paths : Array[Bool]
  retention : RowListingRetention?
  mut preflight : @source.JsonSourcePreflight?
  mut parser : @source.JsonParse?
  mut page : RowListingPage?
  mut work : Int
  mut next_token : String?
  mut request_pending : Bool
  mut attempts : Int64
  mut received_bytes : Int64
  mut examined_items : Int64
  mut elapsed_ms : Int64
  mut complete : Bool
}

///|
fn new_row_listing_progress(
  limits : Array[(String, Int64)],
  resolved_rows? : RowListingRows? = None,
  selection? : RowFileSelection? = None,
  retention? : RowListingRetention? = None,
) -> RowListingProgress {
  {
    limits: limits.copy(),
    resolved_rows,
    selection,
    retention,
    preflight: None,
    parser: None,
    tokens: [],
    observations: {},
    found_paths: match selection {
      Some(ExactPaths(paths)) => Array::make(paths.length(), false)
      _ => []
    },
    page: None,
    work: 0,
    next_token: None,
    request_pending: false,
    attempts: 0L,
    received_bytes: 0L,
    examined_items: 0L,
    elapsed_ms: 0L,
    complete: selection is Some(ExactPaths(paths)) && paths.is_empty(),
  }
}

///|
fn clear_row_listing_tokens(progress : RowListingProgress) -> Unit {
  if progress.preflight is Some(original) {
    @source.cancel_json_source_preflight(original)
    progress.preflight = None
  }
  if progress.parser is Some(original) {
    @source.cancel_json_parse(original)
    progress.parser = None
  }
  // Non-JS array backing can retain popped values. Remove each reference
  // before shrinking; cleanup must not leave the cursor history reachable.
  while !progress.tokens.is_empty() {
    progress.tokens[progress.tokens.length() - 1] = ""
    progress.tokens.pop() |> ignore
  }
  if progress.page is Some(page) && page.selector is Some(Glob(cursor)) {
    cancel_listing_glob(cursor)
  }
  progress.page = None
  progress.observations.clear()
}

///|
priv struct RowListingPage {
  items : Array[@decode.Cursor]
  next_token : String?
  mut index : Int
  mut emitted : Int
  mut cells : Array[@admitted.CheckedValue?]?
  mut prior : Array[@admitted.CheckedValue?]?
  mut column : Int
  mut equality : @admitted.CompleteEquality?
  mut selector : ListingSelectionCursor?
  mut selected : Bool?
  mut duplicate : Bool
  mut checked_path : Int
  mut retention_before : (Int, Int)?
}

///|
pub enum RowListingPagePoll {
  ListingPageContinue(work~ : Int)
  ListingPageComplete(rows~ : Int, work~ : Int)
}

///|
fn row_listing_maximum(
  progress : RowListingProgress,
  quantity : String,
) -> Result[Int64, RowSourceIssue] {
  row_listing_bound(progress.limits, progress.resolved_rows, quantity)
}

///|
// Same admitted limits before a read/frame is constructed. This is only a
// finite enforcement bound, not observation, capacity funding or authority.
fn row_listing_bound(
  limits : Array[(String, Int64)],
  resolved_rows : RowListingRows?,
  quantity : String,
) -> Result[Int64, RowSourceIssue] {
  if quantity == "max_listing_items" {
    return match resolved_rows {
      Some(value) => Ok(listing_rows_maximum(value))
      None => Err(ListingLimitUnresolved(quantity))
    }
  }
  for (name, bound) in limits {
    if name == quantity && bound > 0L {
      return Ok(bound)
    }
  }
  Err(ListingLimitUnresolved(quantity))
}

///|
fn row_listing_elapsed(
  progress : RowListingProgress,
  elapsed_ms : Int64,
) -> Result[Unit, RowSourceIssue] {
  if elapsed_ms < progress.elapsed_ms {
    return Err(ListingProtocol)
  }
  let maximum = match row_listing_maximum(progress, "max_listing_duration_ms") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  progress.elapsed_ms = elapsed_ms
  if elapsed_ms > maximum {
    Err(ListingLimit("max_listing_duration_ms"))
  } else {
    Ok(())
  }
}

///|
fn begin_row_listing_request(
  read : RowSourceRead,
  token : String?,
  elapsed_ms : Int64,
) -> Result[Unit, RowSourceIssue] {
  guard read.open && read.listing is Some(progress) else {
    return Err(ListingProtocol)
  }
  if progress.complete ||
    progress.request_pending ||
    progress.page is Some(_) ||
    token != progress.next_token {
    return fail_read(read, ListingProtocol)
  }
  for
    quantity in [
      "max_listing_items", "max_examined_items", "max_listing_pages", "max_request_attempts",
      "max_listing_bytes", "max_listing_duration_ms", "maximum_path_length",
    ] {
    if row_listing_maximum(progress, quantity) is Err(issue) {
      return fail_read(read, issue)
    }
  }
  match row_listing_elapsed(progress, elapsed_ms) {
    Ok(_) => ()
    Err(issue) => return fail_read(read, issue)
  }
  let maximum = match row_listing_maximum(progress, "max_request_attempts") {
    Ok(value) => value
    Err(issue) => return fail_read(read, issue)
  }
  if progress.attempts >= maximum {
    return fail_read(read, ListingLimit("max_request_attempts"))
  }
  progress.attempts += 1L
  progress.request_pending = true
  Ok(())
}

///|
fn row_listing_token(value : @decode.Cursor) -> Result[String?, RowSourceIssue] {
  if @decode.is_null(value) {
    return Ok(None)
  }
  match @decode.text(value) {
    Ok(text) if !text.is_empty() => Ok(Some(text))
    _ => Err(ListingProtocol)
  }
}

///|
// The Site provides its actual response items, not a successful prefix. The
// exact request cursor must match this read; NULL next_token is the terminal
// observation. Neither output row ceilings nor driver Promise resolution can
// substitute for that observation.
fn begin_row_source_listing_page(
  read : RowSourceRead,
  body : Bytes,
  elapsed_ms : Int64,
  received_bytes? : Int64 = body.length().to_int64(),
  parsed? : @source.Node? = None,
) -> Result[Unit, RowSourceIssue] {
  guard read.open && read.listing is Some(progress) else {
    return Err(ListingProtocol)
  }
  if progress.complete || !progress.request_pending || progress.page is Some(_) {
    return fail_read(read, ListingProtocol)
  }
  match row_listing_elapsed(progress, elapsed_ms) {
    Ok(_) => ()
    Err(issue) => return fail_read(read, issue)
  }
  let limits = read.page_limits
  if received_bytes < 0L {
    return fail_read(read, ListingProtocol)
  }
  for
    (quantity, previous, increment) in [
      ("max_listing_pages", read.pages, 1L),
      ("max_listing_bytes", progress.received_bytes, received_bytes),
    ] {
    let maximum = match row_listing_maximum(progress, quantity) {
      Ok(value) => value
      Err(issue) => return fail_read(read, issue)
    }
    if increment > maximum - previous {
      return fail_read(read, ListingLimit(quantity))
    }
  }
  progress.received_bytes += received_bytes
  if body.length() > limits.max_bytes {
    return fail_read(read, InvalidPage)
  }
  let node = match parsed {
    Some(original) => original
    None =>
      match
        @source.parse_json_bytes(body, {
          max_input_bytes: limits.max_bytes,
          max_nodes: limits.max_nodes,
          max_depth: limits.max_depth,
        }) {
        Ok(value) => value
        Err(_) => return fail_read(read, ListingProtocol)
      }
  }
  guard @decode.admit(node, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    })
    is Ok(root) &&
    @decode.closed_object(root, ["items", "request_token", "next_token"])
    is Ok(object) &&
    @decode.required(object, "items") is Ok(raw_items) &&
    @decode.elements(raw_items) is Ok(items) &&
    @decode.lookup(object, "request_token") is Some(raw_request) &&
    row_listing_token(raw_request) is Ok(request_token) &&
    @decode.lookup(object, "next_token") is Some(raw_next) &&
    row_listing_token(raw_next) is Ok(next_token) else {
    return fail_read(read, ListingProtocol)
  }
  if request_token != progress.next_token {
    return fail_read(read, ListingProtocol)
  }
  if next_token is Some(token) && progress.tokens.contains(token) {
    return fail_read(read, ListingProtocol)
  }
  if items.length() > read.page_limits.max_rows {
    return fail_read(read, InvalidPage)
  }
  let maximum = match row_listing_maximum(progress, "max_examined_items") {
    Ok(value) => value
    Err(issue) => return fail_read(read, issue)
  }
  if items.length().to_int64() > maximum - progress.examined_items {
    return fail_read(read, ListingLimit("max_examined_items"))
  }
  progress.examined_items += items.length().to_int64()
  read.pages += 1L
  progress.page = Some({
    items,
    next_token,
    index: 0,
    emitted: 0,
    cells: None,
    prior: None,
    column: 0,
    equality: None,
    selector: None,
    selected: None,
    duplicate: false,
    checked_path: 0,
    retention_before: None,
  })
  Ok(())
}

///|
fn listing_named_cell(
  read : RowSourceRead,
  cells : Array[@admitted.CheckedValue?],
  name : String,
) -> @admitted.CheckedValue? {
  for i in 0..<read.columns.length() {
    if read.columns[i] == name {
      return cells[i]
    }
  }
  None
}

///|
// Matcher and metadata comparisons resume in the existing read owner. The
// physical page is counted once at admission, not once per poll/quantum.
fn advance_row_source_listing_page(
  read : RowSourceRead,
  quantum : Int,
  elapsed_ms : Int64,
) -> Result[RowListingPagePoll, RowSourceIssue] {
  guard read.open &&
    read.listing is Some(progress) &&
    progress.page is Some(page) else {
    return Err(ListingProtocol)
  }
  if quantum <= 0 {
    return fail_read(read, ListingLimit("listing_work"))
  }
  if row_listing_elapsed(progress, elapsed_ms) is Err(issue) {
    return fail_read(read, issue)
  }
  let mut work = 0
  while work < quantum {
    if progress.work >= read.retention.max_work {
      return fail_read(read, ListingLimit("listing_work"))
    }
    // A row admission/selection transition is one unit. Existing value
    // admission separately enforces the per-value node/text/retention bounds.
    progress.work += 1
    work += 1
    if page.index == page.items.length() {
      if page.next_token is None &&
        progress.selection is Some(ExactPaths(paths)) {
        if page.checked_path < paths.length() {
          let i = page.checked_path
          if !progress.found_paths[i] {
            return fail_read(read, ListingMissingPath(paths[i]))
          }
          page.checked_path += 1
          continue
        }
      }
      let count = page.emitted
      progress.request_pending = false
      progress.next_token = page.next_token
      progress.page = None
      if page.next_token is Some(token) {
        progress.tokens.push(token)
      } else {
        progress.complete = true
        clear_row_listing_tokens(progress)
      }
      return Ok(ListingPageComplete(rows=count, work~))
    }
    if page.cells is None {
      page.retention_before = progress.retention.map(b => (b.nodes, b.text))
      let cells = match
        admit_row_source_object(
          read.schema,
          read.declared_fields,
          page.items[page.index],
          read.values,
          listing_retention=progress.retention,
          references=read.reference_issuer.map(issuer => {
            (
              issuer,
              {
                max_bytes: read.page_limits.max_bytes,
                max_nodes: read.page_limits.max_nodes,
                max_depth: read.page_limits.max_depth,
                max_text_units: read.page_limits.max_bytes,
              },
            )
          }),
        ) {
        Ok(value) => value
        Err(issue) => return fail_read(read, issue)
      }
      page.cells = Some(cells)
      if row_read_listing_reports(read) is Some(_) {
        match row_listing_media_projection(read) {
          Ok(_) => ()
          Err(issue) => return fail_read(read, issue)
        }
      }
      if progress.selection is Some(_) {
        guard listing_named_cell(read, cells, "resource")
          is Some({ value: @admitted.Reference(resource), .. }) &&
          @admitted.reference_available(resource) else {
          return fail_read(read, Value("resource"))
        }
        let identity = @admitted.reference_identity_cid(resource)
        page.prior = progress.observations.get(identity)
        page.duplicate = page.prior is Some(_)
        if !page.duplicate {
          progress.observations[identity] = cells
        }
      }
      continue
    }
    let cells = page.cells.unwrap()
    if page.prior is Some(prior) {
      if page.column == cells.length() {
        page.prior = None
        continue
      }
      match (cells[page.column], prior[page.column]) {
        (None, None) => {
          page.column += 1
          continue
        }
        (Some(left), Some(right)) => {
          if page.equality is None {
            page.equality = match
              @admitted.start_complete_equality(left, right, read.values) {
              Ok(value) => Some(value)
              Err(_) => return fail_read(read, ListingProtocol)
            }
          }
          match @admitted.advance_complete_equality(page.equality.unwrap(), 1) {
            EqualityContinue(work=spent) =>
              if spent != 1 {
                return fail_read(read, ListingProtocol)
              }
            EqualityComplete(equal~, work=spent) => {
              if spent < 0 || spent > 1 {
                return fail_read(read, ListingProtocol)
              }
              if !equal {
                return fail_read(read, ListingConflictingResource("metadata"))
              }
              page.column += 1
              page.equality = None
            }
            EqualityFailed(_, work=spent) => {
              if spent != 1 {
                return fail_read(read, ListingProtocol)
              }
              return fail_read(read, ListingProtocol)
            }
          }
          continue
        }
        _ => return fail_read(read, ListingConflictingResource("presence"))
      }
    }
    if page.selector is None {
      let selector = match progress.selection {
        None => Ready(true)
        Some(selection) => {
          let path = match listing_named_cell(read, cells, "path") {
            Some({ value: @admitted.Text(path), .. }) => Some(path)
            Some({ value: @admitted.Null, .. }) => None
            _ => return fail_read(read, Value("path"))
          }
          let maximum = match
            row_listing_maximum(progress, "maximum_path_length") {
            Ok(value) => value
            Err(issue) => return fail_read(read, issue)
          }
          match begin_listing_selection(selection, path, maximum) {
            Ok(value) => value
            Err(issue) => return fail_read(read, issue)
          }
        }
      }
      page.selector = Some(selector)
      continue
    }
    if page.selected is None {
      // The outer unit is the single inner transition, not a second charge.
      match page.selector.unwrap() {
        Ready(value) => page.selected = Some(value)
        Glob(cursor) =>
          match step_listing_glob(cursor, 1) {
            Ok(Continue(spent)) =>
              if spent != 1 {
                return fail_read(read, ListingProtocol)
              }
            Ok(Complete(matched, spent)) => {
              if spent != 1 {
                return fail_read(read, ListingProtocol)
              }
              page.selected = Some(matched)
            }
            Err(issue) => return fail_read(read, issue)
          }
        Exact(cursor) => {
          guard progress.selection is Some(ExactPaths(paths)) else {
            return fail_read(read, ListingProtocol)
          }
          if cursor.index == paths.length() {
            page.selected = Some(cursor.matched)
            continue
          }
          if cursor.comparison is None {
            cursor.comparison = Some(
              @admitted.start_bounded_token_comparison(
                cursor.path,
                paths[cursor.index],
              ),
            )
          }
          match
            @admitted.advance_bounded_key_comparison(
              cursor.comparison.unwrap(),
              1,
            ) {
            Ok(KeyComparisonContinue(work=spent)) =>
              if spent != 1 {
                return fail_read(read, ListingProtocol)
              }
            Ok(KeyComparisonComplete(order~, work=spent)) => {
              if spent != 1 {
                return fail_read(read, ListingProtocol)
              }
              if order == 0 {
                cursor.matched = true
                progress.found_paths[cursor.index] = true
              }
              cursor.index += 1
              cursor.comparison = None
            }
            Err(_) => return fail_read(read, ListingProtocol)
          }
        }
      }
      continue
    }
    if page.selected.unwrap() && !page.duplicate {
      let maximum = match row_listing_maximum(progress, "max_listing_items") {
        Ok(value) => value
        Err(issue) => return fail_read(read, issue)
      }
      if read.rows >= maximum {
        return fail_read(read, ListingLimit("max_listing_items"))
      }
      match
        (match row_read_listing_reports(read) {
          Some(reports) => append_row_listing_report(read, reports, cells)
          None =>
            append_row_source_cells(
              read.input,
              read.schema,
              cells,
              read.retention,
            )
        }) {
        Ok(_) => ()
        Err(issue) => return fail_read(read, issue)
      }
      read.rows += 1L
      page.emitted += 1
    }
    if page.duplicate &&
      progress.retention is Some(budget) &&
      page.retention_before is Some((nodes, text)) {
      // Only the duplicate's temporary row retires. The original metadata
      // stays charged until terminal completeness or cancellation clears it.
      budget.nodes = nodes
      budget.text = text
    }
    page.retention_before = None
    page.index += 1
    page.cells = None
    page.prior = None
    page.column = 0
    page.equality = None
    page.selector = None
    page.selected = None
    page.duplicate = false
  }
  Ok(ListingPageContinue(work~))
}
