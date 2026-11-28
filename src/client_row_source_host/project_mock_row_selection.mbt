///|
/// The original declared record view and its paths in the Project data file.
/// A physical reader still has to bind the selected file and a current Read.
pub struct ProjectMockRowSelection {
  view : RowDeclaredView
  items_path : Array[String]
  key_path : Array[String]
  primary_identity : String
}

///|
/// Existing Mock record-file profile, shared by the physical adapters.
pub fn project_mock_row_page_limits() -> RowPageLimits {
  { max_bytes: 1048576, max_nodes: 4096, max_depth: 32, max_rows: 100, }
}

///|
fn project_mock_row_path(value : Json?) -> Array[String]? {
  guard value is Some(Array(items)) &&
    items.length() > 0 &&
    items.length() <= 16 else {
    return None
  }
  let path = Array(capacity=items.length())
  for item in items {
    guard item is String(text) &&
      !text.is_empty() &&
      text.length() <= 4096 &&
      !text.contains("\u{0000}") else {
      return None
    }
    path.push(text)
  }
  Some(path)
}

///|
/// Read the same four authored physical roles for one original record view.
pub fn project_mock_row_selection(
  original : Json,
  view : RowDeclaredView,
) -> Result[ProjectMockRowSelection, RowHostIssue] {
  guard original is Object(fields) &&
    fields.length() == 4 &&
    project_mock_declaration_text(original, "resource") == Some(view.resource) &&
    project_mock_declaration_text(original, "primary_identity")
    is Some(primary_identity) &&
    primary_identity.length() <= 4096 &&
    project_mock_row_path(fields.get("items_path")) is Some(items_path) &&
    project_mock_row_path(fields.get("key_path")) is Some(key_path) else {
    return Err(InvalidSpecification)
  }
  Ok({ view, items_path, key_path, primary_identity, })
}

///|
/// Structural overlap under the SAME declared data file. A collection cannot
/// be independently replaced when either path is a prefix of the other.
fn project_mock_collection_paths_overlap(
  selected : Array[String],
  prior : Array[String],
) -> Bool {
  for index in 0..<Int::min(selected.length(), prior.length()) {
    if selected[index] != prior[index] {
      return false
    }
  }
  true
}

///|
fn[E] prepare_funded_project_mock_row_selections(
  entry : Json,
  declaration : RowDeclaration,
  prepare : (@execution.PreparationRepresentationUnits) -> Result[Unit, E],
  refusal : (RowHostIssue) -> E,
) -> Result[Array[ProjectMockRowSelection], E] {
  guard entry is Object(fields) else {
    return Err(refusal(InvalidSpecification))
  }
  // Listing/content uses a distinct ResourceRef issuer. This record selector
  // cannot stand in for that provider's declared file binding.
  match fields.get("file_bindings") {
    None => ()
    Some(Array(bindings)) if bindings.is_empty() => ()
    _ => return Err(refusal(InvalidSpecification))
  }
  let original = match fields.get("data") {
    None => return Ok([])
    Some(Array(values)) => values
    _ => return Err(refusal(InvalidSpecification))
  }
  if original.length() > declaration.views.length() {
    return Err(refusal(InvalidSpecification))
  }
  let n = original.length().to_int64()
  // The exact result array and at most two 16-element path arrays per
  // selection borrow the original entry's text. Reserve even a failed path or
  // foreign view's partially constructed selection on this original.
  if prepare({
      record_headers: 4L + 24L * n,
      reference_slots: 4L + 72L * n,
      scalar_words: 4L + 20L * n,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Err(issue) {
    return Err(issue)
  }
  let rows : Array[ProjectMockRowSelection] = Array(capacity=original.length())
  for row in original {
    guard project_mock_declaration_text(row, "resource") is Some(resource) &&
      declaration.views.iter().find_first(view => view.resource == resource)
      is Some(view) &&
      !rows.any(prior => prior.view.resource == resource) else {
      return Err(refusal(InvalidSpecification))
    }
    match project_mock_row_selection(row, view) {
      Ok(selection) => rows.push(selection)
      Err(issue) => return Err(refusal(issue))
    }
  }
  Ok(rows)
}

///|
fn project_mock_writes_resource(
  writes : Array[ProjectMockWriteDeclaration],
  resource : String,
) -> Bool {
  for write in writes {
    if write.mapping.resource == resource {
      return true
    }
  }
  false
}

///|
fn[R] project_mock_conflicts_with_writes(
  path : Array[String],
  rows : Array[R],
  writes : Array[ProjectMockWriteDeclaration],
  end : Int,
  resource : (R) -> String,
  collection : (R) -> Array[String],
) -> Bool {
  if writes.is_empty() {
    return false
  }
  for index in 0..<end {
    let earlier = rows[index]
    if project_mock_collection_paths_overlap(path, collection(earlier)) &&
      project_mock_writes_resource(writes, resource(earlier)) {
      return true
    }
  }
  false
}

///|
/// Check writable selections before independently replacing collections in
/// the same physical data file. Read-only siblings do not create a conflict.
pub fn[R, S] check_project_mock_writable_collections(
  rows : Array[R],
  writes : Array[ProjectMockWriteDeclaration],
  previous : Array[S],
  resource : (R) -> String,
  collection : (R) -> Array[String],
  earlier_rows : (S) -> Array[R],
  earlier_writes : (S) -> Array[ProjectMockWriteDeclaration],
) -> Bool {
  if writes.is_empty() {
    return true
  }
  for index, row in rows {
    if !project_mock_writes_resource(writes, resource(row)) {
      continue
    }
    let path = collection(row)
    if project_mock_conflicts_with_writes(
        path, rows, writes, index, resource, collection,
      ) {
      return false
    }
    for source in previous {
      let prior = earlier_rows(source)
      if project_mock_conflicts_with_writes(
          path,
          prior,
          earlier_writes(source),
          prior.length(),
          resource,
          collection,
        ) {
        return false
      }
    }
  }
  true
}
