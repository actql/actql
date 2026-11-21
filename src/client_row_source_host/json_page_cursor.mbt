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
    seen: Default::default(),
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
    page_index != progress.page_index ||
    row_count != progress.row_count {
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
/// Select only the outgoing request's declared page-size DATA from the SAME
/// checked progress. The independent response/parse ceiling remains the one
/// returned by row_source_cursor_remaining_rows; a requested size is not a
/// new row grant or a stricter response rule. No state advances here.
pub fn row_source_cursor_request_rows(
  progress : RowSourceCursorProgress,
  page_index : Int,
  row_count : Int,
  page_size : Int?,
) -> Result[Int, RowSourceCursorIssue] {
  let remaining = match
    row_source_cursor_remaining_rows(progress, page_index, row_count) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match page_size {
    None => Ok(remaining)
    Some(limit) =>
      if limit <= 0 {
        Err(InvalidLimits)
      } else {
        Ok(Int::min(limit, remaining))
      }
  }
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
  advance_checked_cursor(
    progress,
    page_index,
    row_count,
    remaining,
    rows.row_count,
    envelope.next_cursor,
  )
}

///|
/// Join scalar facts projected from an original finite provider page. Its
/// codec owns the response envelope and row data. Progress retains only the
/// next cursor and applies the same bounds as the generic JSON path.
pub fn advance_row_source_cursor_progress_from_provider_page(
  progress : RowSourceCursorProgress,
  page_index : Int,
  row_count : Int,
  page_rows : Int,
  next : String?,
) -> Result[Bool, RowSourceCursorIssue] {
  let remaining = match
    row_source_cursor_remaining_rows(progress, page_index, row_count) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // This provider family consumes its valid prefix and checks currentness
  // before asking for the next page. A full prefix still cannot authorize or
  // send another request: remaining_rows refuses before that boundary.
  advance_checked_cursor(
    progress,
    page_index,
    row_count,
    remaining,
    page_rows,
    next,
    retain_exhausted_prefix=true,
  )
}

///|
fn advance_checked_cursor(
  progress : RowSourceCursorProgress,
  page_index : Int,
  row_count : Int,
  remaining : Int,
  page_rows : Int,
  next : String?,
  retain_exhausted_prefix? : Bool = false,
) -> Result[Bool, RowSourceCursorIssue] {
  if page_rows < 0 || page_rows > remaining {
    return Err(RowLimit)
  }
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
    if !retain_exhausted_prefix && page_rows >= progress.max_rows - row_count {
      return Err(RowLimit)
    }
    progress.seen[cursor] = true
  }
  // The checked subtraction above bounds both additions without overflow.
  progress.page_index = page_index + 1
  progress.row_count = row_count + page_rows
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
