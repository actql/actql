///|
/// A data projection, not a Source completion, publication or physical ACK.
pub fn object_page_row_count(page : ObjectPage) -> Int {
  page.rows.length()
}

///|
/// Emit the already admitted cells through Common's typed wire. In particular,
/// decimal values stay canonical fixed-scale text; no binary64 or provider
/// spelling is introduced between this projection and the RowRun owner.
/// Output bounds cover the complete row envelope independently of input bounds.
pub fn encode_object_page_rows(
  page : ObjectPage,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ObjectPageIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  // The record's top-level id is the Source key. A property with that same
  // name cannot silently overwrite it or create duplicate row fields.
  if page.names.contains("id") {
    return Err(DuplicateSelection("id"))
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_array(writer)
    for row in page.rows {
      @encode.begin_object(writer)
      @encode.key(writer, "id")
      @encode.string_value(writer, row.id)
      for index, name in page.names {
        @encode.key(writer, name)
        @admitted.emit_checked_wire_value(row.values[index], writer)
      }
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
    _ => {
      @encode.cancel_writer(writer)
      Err(InvalidResponse)
    }
  }
}
