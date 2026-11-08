///|
// Canonical measurement names/order metadata on the same admitted schema.
// Names Array has n references. Column tuples each own a record, borrowed
// String reference and index; current/spare/old growth backing has at most 3n
// references. Eight fixed records and 16 reference/scalar slots cover the
// order cursor, comparison/control, array headers and one pending item. Wire
// writer/hash payload remains in the original bounded wire/record envelope.
fn row_measurement_workspace(schema : @schema.Schema) -> Int64? {
  let n = @schema.field_count(schema).to_int64()
  let mut headers = n + 8L
  let mut utf16 = 0L
  for index in 0..<@schema.field_count(schema) {
    let field = @schema.field_at(schema, index).unwrap()
    let extent = @schema.reference_name_construction_extent(field.name)
    headers += extent.scratch.record_headers
    guard @execution.checked_preparation_add_product(
        utf16,
        extent.scratch_utf16_units,
        1L,
      )
      is Some(next) else {
      return None
    }
    utf16 = next
  }
  @execution.preparation_representation_cost({
    record_headers: headers,
    reference_slots: n * 5L + 16L,
    scalar_words: n + 16L,
    owned_utf16_units: utf16,
    owned_wire_bytes: 0L,
  })
}

///|
// Input is the SAME checked declaration schema bound by prepare_row_source.
// Capture is its original checked SELECT port, not an arbitrary Host maximum.
// The two measurements are sequential; their variable workspaces do not sum.
fn row_capture_measurement_geometry(
  preparation : RowSourcePreparation,
) -> (Int, Int64)? {
  let owner = @lower.bound_preparation(preparation.owner)
  guard @lower.preparation_input_schema(owner, preparation.input_index)
    is Some(input) &&
    @schema.field_count(input) == preparation.columns.length() else {
    return None
  }
  let sequence = @planning.query_material_owner(
    @planning.query_requirement_material(preparation.requirement),
  )
  let query = @query.query_sequence_requirement(sequence)
  guard @lower.preparation_schema_at(
      owner,
      @sourcequery.query_acquisition_capture(query),
    )
    is Some(output) &&
    row_measurement_workspace(input) is Some(input_workspace) &&
    row_measurement_workspace(output) is Some(output_workspace) else {
    return None
  }
  Some(
    (
      Int::max(@schema.field_count(input), @schema.field_count(output)),
      Int64::max(input_workspace, output_workspace),
    ),
  )
}
