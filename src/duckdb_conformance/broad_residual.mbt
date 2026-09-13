///|
fn fixture_contract(text : String) -> @identity.CanonicalValue raise {
  @identity.from_json(@json.parse(text), 10000, 100, 100000)
}

///|
// Fixed conformance entry: contract material is checked against product pins;
// completion is produced only by the existing guarded execution driver.
#export_name("broadResidual")
pub fn broad_residual(
  value : BroadFixture,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  output_rows : Int,
) -> String {
  guard value.captured is Some(input) else { return "null" }
  try {
    let generated = fixture_generated(
      @execution.captured_owner(input),
      registry_json,
      values_json,
      fragment_json,
      true,
    )
    let values : @execution.ValueLimits = {
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 100,
      max_work: 100000,
    }
    let result = @execution.execute_fixed_input_guarded(
      generated,
      input,
      @pipeline.Step(1),
      {
        rows: {
          max_rows: 100,
          metadata_entries: 10000,
          retained_entries: 10000,
          operation_entries: 10000,
          input_values: values,
          output_values: values,
        },
        max_work: 100000,
        max_frames: 100,
      },
      max_output_rows=output_rows,
      max_value_bytes=1000,
      record_values=true,
      { max_work: 10000, max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    )
    guard result is Ok((completed, _)) else { return "null" }
    let output = @execution.completed_output(completed, @pipeline.Step(1)).unwrap()
    let identity = @execution.identify_completed_rows(output, {
      max_columns: 10,
      max_order_work: 10000,
      max_bytes: 100000,
      max_nodes: 1000,
      max_depth: 10,
    }).unwrap()
    @execution.row_wire_cid(identity)
  } catch {
    _ => "null"
  }
}
