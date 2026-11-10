///|
/// Exact row/column authority from one export. This is private custody of the
/// original opaque references, not a second issuer or a part of content CID.
/// Optional slots allow bounded retirement to scrub Native/Wasm array backing.
priv struct CompletedExportReferences {
  workspace : RowWorkspace
  mut rows : Array[Array[Array[@admitted.ReferenceValue?]]]
  mut complete : Bool
  mut revoked : Bool
}

///|
/// Borrow one original Content occurrence from the exact successful export.
/// Coordinates select the admitted export view, not a caller's envelope/CID.
/// The caller must keep its original Result pin and physical Store custody;
/// this read neither reissues a Reference nor admits byte acquisition.
pub fn completed_relation_export_content_reference(
  value : CompletedRelationExportReceipt,
  row : Int,
  column : Int,
) -> @admitted.ReferenceValue? {
  guard value.rows.source is Some(source) &&
    completed_output_available(source) &&
    @schema.field_at(value.rows.content.schema, column) is Some(field) &&
    field.contract.shape is @contract.ContentRef(..) &&
    value.rows.references is Some(references) &&
    original_export_content_reference(references, row, column)
    is Some(reference) else {
    return None
  }
  guard value.rows.source is Some(current_source) &&
    physical_equal(current_source, source) &&
    value.rows.references is Some(current_references) &&
    physical_equal(current_references, references) else {
    return None
  }
  Some(reference)
}

///|
/// Borrow the original export's Content identity occurrences, including nested
/// cells, without traversing rows again or restoring References from wire.
/// The caller backs the bounded result array before entry. Identity metadata
/// is not current byte availability, read permission or retained Ref custody.
pub fn completed_relation_export_content_reference_cids(
  value : CompletedRelationExportReceipt,
  max_references : Int,
  max_work : Int,
) -> Result[Array[String], CompletedExportIssue] {
  completed_export_content_reference_cids(value.rows, max_references, max_work)
}

///|
fn completed_export_content_reference_cids(
  value : CompletedOutputExportReceipt,
  max_references : Int,
  max_work : Int,
) -> Result[Array[String], CompletedExportIssue] {
  if max_references < 0 || max_work < 1 {
    return Err(Wire(InvalidLimits))
  }
  guard !value.binding &&
    value.source is Some(source) &&
    value.references is Some(references) &&
    references.complete &&
    !references.revoked &&
    completed_output_available(source) else {
    return Err(Unavailable)
  }
  // This is the only external current callback. It can retire the export;
  // the following walk reads retained immutable metadata with no callbacks.
  guard !value.binding &&
    value.source.map(current => physical_equal(current, source)) == Some(true) &&
    value.references.map(current => physical_equal(current, references)) ==
    Some(true) &&
    references.complete &&
    !references.revoked else {
    return Err(Unavailable)
  }
  let result : Array[String] = []
  let mut remaining = max_work
  for row in references.rows {
    if remaining == 0 {
      return Err(Wire(OrderLimit))
    }
    remaining -= 1
    for cell in row {
      if remaining == 0 {
        return Err(Wire(OrderLimit))
      }
      remaining -= 1
      for slot in cell {
        if remaining == 0 {
          return Err(Wire(OrderLimit))
        }
        remaining -= 1
        if slot is Some(reference) &&
          @admitted.reference_content_metadata(reference) is Some(_) {
          if result.length() == max_references {
            return Err(Wire(Encoding(@encode.OutputLimit)))
          }
          result.push(@admitted.reference_identity_cid(reference))
        }
      }
    }
  }
  Ok(result)
}

///|
/// Both the transient export and its explicit retained successor use this
/// same per-cell inventory. Reading it never creates another Reference.
fn original_export_content_reference(
  references : CompletedExportReferences,
  row : Int,
  column : Int,
) -> @admitted.ReferenceValue? {
  guard references.complete &&
    !references.revoked &&
    references.rows.get(row) is Some(cells) &&
    cells.get(column) is Some(cell) &&
    cell.length() == 1 &&
    cell[0] is Some(reference) &&
    @admitted.reference_content_metadata(reference) is Some(_) &&
    @admitted.reference_available(reference) else {
    return None
  }
  // Availability calls the original Host. A callback may retire this export
  // while still returning true; do not cache its pre-callback custody check.
  guard references.complete &&
    !references.revoked &&
    references.rows.get(row) is Some(current_cells) &&
    current_cells.get(column) is Some(current_cell) &&
    current_cell.length() == 1 &&
    current_cell[0] is Some(current_reference) &&
    physical_equal(current_reference, reference) else {
    return None
  }
  Some(reference)
}

///|
/// Resolve the checked source field in the exact export view. The bounded
/// scan borrows the existing names; it neither copies their inventory nor
/// interprets a caller's row/Reference envelope.
pub fn completed_relation_export_content_field(
  value : CompletedRelationExportReceipt,
  row : Int,
  field : @schema.Field,
  max_fields : Int,
  max_work : Int,
) -> Result[@admitted.ReferenceValue, CompletedExportIssue] {
  original_export_content_field(
    value.fields,
    row,
    field,
    max_fields,
    max_work,
    column => completed_relation_export_content_reference(value, row, column),
  )
}

///|
fn original_export_content_field(
  names : Array[String],
  row : Int,
  field : @schema.Field,
  max_fields : Int,
  max_work : Int,
  read : (Int) -> @admitted.ReferenceValue?,
) -> Result[@admitted.ReferenceValue, CompletedExportIssue] {
  if row < 0 || max_fields < 0 || max_work < 0 {
    return Err(Admission(InvalidCaptureLimits))
  }
  guard field.contract.shape is @contract.ContentRef(..) else {
    return Err(InvalidTarget)
  }
  if names.length() > max_fields || names.length() > max_work {
    return Err(Admission(CaptureLimit))
  }
  let expected = @schema.field_reference_name(field)
  let mut remaining = max_work - names.length()
  for column, name in names {
    if name.length() > remaining {
      return Err(Admission(CaptureLimit))
    }
    remaining -= name.length()
    if expected.length() > remaining {
      return Err(Admission(CaptureLimit))
    }
    remaining -= expected.length()
    if name == expected {
      guard read(column) is Some(reference) else { return Err(Unavailable) }
      if !@admitted.reference_compatible(reference, field.contract) {
        return Err(ForeignMaterial)
      }
      return Ok(reference)
    }
  }
  Err(InvalidTarget)
}

///|
/// Row and column entries are bounded by admitted row/key nodes, and authority
/// entries by admitted value nodes. Logical value work is not charged twice.
fn prepare_completed_export_references(
  limits : ValueLimits,
) -> Result[CompletedExportReferences, CompletedExportIssue] {
  guard checked_row_slots_add(limits.max_nodes, limits.max_nodes) is Some(slots) else {
    return Err(Admission(InvalidCaptureLimits))
  }
  Ok({
    workspace: row_workspace(slots),
    rows: [],
    complete: false,
    revoked: false,
  })
}

///|
fn advance_completed_export_reference_reclamation(
  value : CompletedExportReferences,
  quantum : Int,
) -> Bool {
  if !value.revoked || quantum <= 0 {
    return false
  }
  for _ in 0..<quantum {
    guard value.rows.last() is Some(row) else {
      value.rows = []
      return value.workspace.live == 0
    }
    if row.last() is Some(cell) {
      if cell.is_empty() {
        row[row.length() - 1] = []
        row.pop() |> ignore
      } else {
        cell[cell.length() - 1] = None
        cell.pop() |> ignore
      }
    } else {
      value.rows[value.rows.length() - 1] = []
      value.rows.pop() |> ignore
    }
    release_slots(value.workspace, 1)
  }
  if value.rows.is_empty() {
    value.rows = []
    value.workspace.live == 0
  } else {
    false
  }
}

///|
/// Re-admission borrows only this exact exported row, never a search through
/// other rows or old cell buffers. The parser's own finite row budget bounds
/// the temporary immutable authority view used by its existing reissuer.
fn completed_export_reference_row(
  value : CompletedExportReferences,
  row : Int,
  max_nodes : Int,
) -> Array[Array[@admitted.ReferenceValue]]? {
  if !value.complete || value.revoked || max_nodes < 0 {
    return None
  }
  guard value.rows.get(row) is Some(cells) && cells.length() <= max_nodes else {
    return None
  }
  let mut remaining = max_nodes - cells.length()
  let result = []
  for cell in cells {
    if cell.length() > remaining {
      return None
    }
    remaining -= cell.length()
    let references = []
    for item in cell {
      guard item is Some(reference) else { return None }
      references.push(reference)
    }
    result.push(references)
  }
  Some(result)
}

///|
/// Revocation of an unfinished export is immediate; retirement is separately
/// driven before its existing owner may return the retained allowance.
pub fn advance_cancel_completed_output_export(
  value : CompletedOutputExport,
  quantum : Int,
) -> Bool {
  cancel_completed_output_export(value)
  if value.reading {
    return false
  }
  match value.references {
    None => true
    Some(references) =>
      advance_completed_export_reference_reclamation(references, quantum)
  }
}

///|
pub fn advance_cancel_completed_export_receipt(
  value : CompletedOutputExportReceipt,
  quantum : Int,
) -> Bool {
  cancel_completed_export_receipt(value)
  if value.binding {
    return false
  }
  match value.references {
    None => true
    Some(references) =>
      advance_completed_export_reference_reclamation(references, quantum)
  }
}

///|
/// Attached authority requires an unavailable physical Store. Reference-free
/// material has no authority roots to retire; this does not establish physical
/// release, which remains a separate obligation of its existing Store owner.
pub fn advance_retained_output_reference_reclamation(
  material : RetainedOutputMaterial,
  quantum : Int,
) -> Bool {
  match material.references {
    None => true
    Some(references) => {
      if (material.available)() {
        return false
      }
      references.revoked = true
      advance_completed_export_reference_reclamation(references, quantum)
    }
  }
}
