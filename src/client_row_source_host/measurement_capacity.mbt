///|
// Canonical measurement names/order metadata on the same admitted schema.
// Names Array has n references. Column tuples each own a record, borrowed
// String reference and index; current/spare/old growth backing has at most 3n
// references. Eight fixed records and 16 reference/scalar slots cover the
// order cursor, comparison/control, array headers and one pending item. Wire
// writer/hash payload remains in the original bounded wire/record envelope.
fn row_schema_measurement_capacity(schema : @schema.Schema) -> (Int64, Int64)? {
  let n = @schema.field_count(schema).to_int64()
  let mut name_headers = 0L
  let mut utf16 = 0L
  for index in 0..<@schema.field_count(schema) {
    let field = @schema.field_at(schema, index).unwrap()
    let extent = @schema.reference_name_construction_extent(field.name)
    name_headers += extent.scratch.record_headers
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
  guard @execution.preparation_representation_cost({
      record_headers: n + 8L + name_headers,
      reference_slots: n * 5L + 16L,
      scalar_words: n + 16L,
      owned_utf16_units: utf16,
      owned_wire_bytes: 0L,
    })
    is Some(measurement) &&
    @execution.preparation_representation_cost({
      // Query evidence retains this complete input's name Array. Its final
      // backing has less than 2n slots; names are borrowed unless qualified.
      record_headers: 2L + name_headers,
      reference_slots: n * 2L,
      scalar_words: 0L,
      owned_utf16_units: utf16,
      owned_wire_bytes: 0L,
    })
    is Some(records) else {
    return None
  }
  // The measurement's 5n refs dominate the record builder's 3n growth peak;
  // measurement temporaries retire before record construction starts.
  Some((measurement, records))
}

///|
// Input is the SAME checked declaration schema bound by prepare_row_source.
// Capture is its original checked SELECT port, not an arbitrary Host maximum.
// Scan/capture measurements are sequential. Later identity metadata overlaps
// the original evidence record names, so both are funded before provider I/O.
fn row_capture_measurement_geometry(
  preparation : RowSourcePreparation,
) -> (Int, Int64, Int64, Int)? {
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
    row_schema_measurement_capacity(input)
    is Some((input_workspace, record_retained)) &&
    row_schema_measurement_capacity(output) is Some((output_workspace, _)) else {
    return None
  }
  guard @execution.checked_preparation_add_product(
      Int64::max(input_workspace, output_workspace),
      record_retained,
      1L,
    )
    is Some(working) else {
    return None
  }
  Some(
    (
      Int::max(@schema.field_count(input), @schema.field_count(output)),
      working,
      record_retained,
      @schema.field_count(output),
    ),
  )
}

///|
/// Geometry from the SAME live completed RowRun and cached captured source.
/// Query and Whole input variants keep their own original schema owners.
/// This neither issues evidence nor grants read, publication or stop authority.
pub fn row_capture_schema_columns(
  capture : RowSourceCapture,
  source : @query.CapturedInputSource,
) -> Int? {
  guard row_capture_source(capture) is Ok(original) &&
    physical_equal(original, source) else {
    return None
  }
  match (capture.run.configuration, capture.observation) {
    (DirectConfiguration(configuration), QueryObservation(_)) =>
      Some(configuration.capture_columns)
    (InputConfiguration(acquisition), InputObservation(_)) =>
      Some(acquisition.preparation.columns.length())
    _ => None
  }
}
