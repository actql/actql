///|
priv enum RowFileSelection {
  AllFiles
  ExactPaths(Array[String])
  GlobFiles(ListingGlob)
}

///|
// Read the common Request owner's already bound values; do not decode a
// connector's description of what it chose or impose SQL raw-origin on data.
fn prepare_row_file_selection(
  request : @sourcequery.ParameterizedRequest,
  max_pattern_units : Int,
) -> Result[RowFileSelection, RowSourceIssue] {
  let mut selected : RowFileSelection? = None
  for i in 0..<@sourcequery.parameterized_request_field_count(request) {
    let field = @sourcequery.parameterized_request_field_at(request, i).unwrap()
    let name = field.field.slot.field_name
    if name != "paths" && name != "glob" {
      continue
    }
    let value = match field.value {
      CheckedLiteral(value) => value.value
      BoundParameter(parameter) => parameter.value.value
      UnboundHostBinding(_) => return Err(ListingProtocol)
    }
    if value is @admitted.Null {
      continue
    }
    if selected is Some(_) {
      return Err(ListingProtocol)
    }
    selected = match (name, value) {
      ("glob", @admitted.Text(pattern)) => {
        let glob = match compile_listing_glob(pattern, max_pattern_units) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        Some(GlobFiles(glob))
      }
      ("paths", @admitted.Array(values)) => {
        let paths : Array[String] = []
        for index in 0..<@admitted.element_count(values) {
          guard @admitted.element_at(values, index)
            is Some(@admitted.Text(path)) else {
            return Err(ListingProtocol)
          }
          // Keep declared occurrences without a synchronous comparison scan.
          // Output deduplication uses issued Resource identity, not path text.
          paths.push(path)
        }
        Some(ExactPaths(paths))
      }
      _ => return Err(ListingProtocol)
    }
  }
  Ok(selected.unwrap_or(AllFiles))
}

///|
priv enum ListingSelectionCursor {
  Glob(ListingGlobCursor)
  Exact(ListingExactCursor)
  Ready(Bool)
}

///|
priv struct ListingExactCursor {
  path : String
  mut index : Int
  mut comparison : @admitted.BoundedKeyComparison?
  mut matched : Bool
}

///|
fn begin_listing_selection(
  selection : RowFileSelection,
  path : String?,
  max_units : Int64,
) -> Result[ListingSelectionCursor, RowSourceIssue] {
  if path is Some(text) && text.length().to_int64() > max_units {
    return Err(ListingLimit("maximum_path_length"))
  }
  match (selection, path) {
    (AllFiles, _) => Ok(Ready(true))
    (_, None) => Ok(Ready(false))
    (GlobFiles(glob), Some(path)) =>
      begin_listing_glob(glob, path, max_units).map(cursor => Glob(cursor))
    (ExactPaths(_), Some(path)) =>
      Ok(Exact({ path, index: 0, comparison: None, matched: false, }))
  }
}
