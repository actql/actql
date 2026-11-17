///|
/// Bounded provider-neutral pagination DATA. The managed RowRun still owns
/// response charges, schema admission, currentness, I/O and physical cleanup.
/// Only cursor strings are retained; parsed pages and response backing are not.
struct RowSourceCursorProgress {
  origin : Ref[Unit]
  max_pages : Int
  max_rows : Int
  max_page_rows : Int
  max_cursor_bytes : Int
  seen : Map[String, Bool]
  mut page_index : Int
  mut row_count : Int
  mut cursor : String?
  mut done : Bool
}

///|
pub(all) enum RowSourceCursorIssue {
  InvalidLimits
  ProgressMismatch
  Completed
  PageLimit
  RowLimit
  CursorLimit
  CursorCycle
  ForeignPage
  NoNextCursor
} derive(Eq, Debug)

///|
/// Limits are ceilings for DATA, not authority or a Resource reservation.
/// At most max_pages - 1 bounded cursor strings can be retained before EOF.
pub fn prepare_row_source_cursor_progress(
  max_pages : Int,
  max_rows : Int,
  max_page_rows : Int,
  max_cursor_bytes : Int,
) -> Result[RowSourceCursorProgress, RowSourceCursorIssue] {
  if max_pages < 1 || max_rows < 1 || max_page_rows < 1 || max_cursor_bytes < 0 {
    return Err(InvalidLimits)
  }
  Ok({
    origin: projected_json_page_origin,
    max_pages,
    max_rows,
    max_page_rows,
    max_cursor_bytes,
    seen: Map::new(),
    page_index: 0,
    row_count: 0,
    cursor: None,
    done: false,
  })
}

///|
/// Join the managed reader's actual progress before a request or page parse.
/// A continuation cannot substitute another page index or consumed row count.
pub fn row_source_cursor_remaining_rows(
  progress : RowSourceCursorProgress,
  page_index : Int,
  row_count : Int,
) -> Result[Int, RowSourceCursorIssue] {
  if !physical_equal(progress.origin, projected_json_page_origin) ||
    page_index != progress.page_index || row_count != progress.row_count {
    return Err(ProgressMismatch)
  }
  if progress.done {
    return Err(Completed)
  }
  if page_index >= progress.max_pages {
    return Err(PageLimit)
  }
  if row_count >= progress.max_rows {
    return Err(RowLimit)
  }
  Ok(Int::min(progress.max_page_rows, progress.max_rows - row_count))
}

///|
/// The original envelope fixes continuation. An optional pure transform may
/// replace rows, but its separately parsed page supplies only the actual count.
/// All checks precede mutation; an error does not consume a page or cursor.
pub fn advance_row_source_cursor_progress(
  progress : RowSourceCursorProgress,
  page_index : Int,
  row_count : Int,
  envelope : RowSourceProjectedJsonPage,
  rows : RowSourceProjectedJsonPage,
) -> Result[Bool, RowSourceCursorIssue] {
  let remaining = match
    row_source_cursor_remaining_rows(progress, page_index, row_count) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !physical_equal(envelope.origin, projected_json_page_origin) ||
    !physical_equal(rows.origin, projected_json_page_origin) {
    return Err(ForeignPage)
  }
  if rows.row_count < 0 || rows.row_count > remaining {
    return Err(RowLimit)
  }
  let next = envelope.next_cursor
  if next is Some(cursor) {
    if @scalar.admit_utf8_length(cursor, progress.max_cursor_bytes) is Err(_) {
      return Err(CursorLimit)
    }
    if progress.seen.contains(cursor) {
      return Err(CursorCycle)
    }
    if page_index >= progress.max_pages - 1 {
      return Err(PageLimit)
    }
    if rows.row_count >= progress.max_rows - row_count {
      return Err(RowLimit)
    }
    progress.seen[cursor] = true
  }
  // The checked subtraction above bounds both additions without overflow.
  progress.page_index = page_index + 1
  progress.row_count = row_count + rows.row_count
  progress.cursor = next
  progress.done = next is None
  Ok(progress.done)
}

///|
pub fn row_source_cursor_has_next(progress : RowSourceCursorProgress) -> Bool {
  physical_equal(progress.origin, projected_json_page_origin) &&
  progress.cursor is Some(_)
}

///|
pub fn row_source_cursor_next(
  progress : RowSourceCursorProgress,
) -> Result[String, RowSourceCursorIssue] {
  if !physical_equal(progress.origin, projected_json_page_origin) {
    return Err(ProgressMismatch)
  }
  match progress.cursor {
    Some(cursor) => Ok(cursor)
    None => Err(NoNextCursor)
  }
}
