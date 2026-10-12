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
