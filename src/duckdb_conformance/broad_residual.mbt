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
    let registry_limits : @execution.RegistryLimits = {
      max_body_bytes: 100000,
      max_body_nodes: 10000,
      max_body_depth: 100,
    }
    let registered = @execution.admit_relation_registry(
      fixture_contract(registry_json),
      fixture_contract(values_json),
      registry_limits,
    ).unwrap()
    let fragment = @execution.admit_fragment_contract(
      registered,
      fixture_contract(fragment_json),
      registry_limits,
    ).unwrap()
    let owner = @execution.captured_owner(input)
    let sequence = @lower.prepare_sequence(owner, {
      max_steps: 100,
      max_rows: 100,
      max_cells: 10000,
      max_bindings: 100,
      max_name_bytes: 10000,
      expressions: {
        max_nodes: 10000,
        max_work: 100000,
        max_depth: 100,
        max_literal_nodes: 10000,
        max_literal_text_bytes: 10000,
      },
    }).unwrap()
    let pipeline = @lower.prepare_fragment_pipeline(sequence, 0, {
      max_roots: 100,
      max_pointer_bytes: 10000,
      max_work: 100000,
    }).unwrap()
    let request = @lower.prepare_fragment_request(pipeline, 100L, 1000L).unwrap()
    let context = @execution.prepare_runtime_fragment(
      request,
      fragment,
      {
        max_roots: 100,
        max_nodes: 1000,
        max_work: 100000,
        max_text_bytes: 100000,
        max_links: 10000,
      },
      registry_limits,
      {
        max_input_rows: 100L,
        max_value_bytes: 1000L,
        max_live_value_bytes: 10000L,
        max_work: 100000L,
      },
    ).unwrap()
    let generated = @execution.prepare_generated_sequence(
      registered,
      sequence,
      [context],
      [
        @lower.node_id(
          @lower.node_at(@lower.bound_preparation(owner), 1).unwrap(),
        ),
      ],
      100000,
      10000,
    ).unwrap()
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
