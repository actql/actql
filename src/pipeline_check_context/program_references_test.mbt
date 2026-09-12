///|
fn reference_values_for(
  operations : @stages.CollectedOperations,
  values : @parameter.BoundValues,
  request_slots? : @request_slots.Slots? = None,
) -> @program_refs.ParameterValues {
  let source = @stages.operations_source(operations)
  let requests = match request_slots {
    Some(slots) => slots
    None => {
      let bindings = @binding_declarations.prepare(@stages.program(source), {
        max_bindings: 100,
        max_work: 100000,
      }).unwrap()
      @request_slots.collect(source, bindings, {
        max_work: 100000,
        max_slots: 1000,
      }).unwrap()
    }
  }
  let uses = []
  for i in 0..<@stages.stage_count(source) {
    let body = @stage_body.prepare(
      @stages.operations_stage_at(operations, i).unwrap(),
      {
        max_work: 1000000,
        selectors: {
          max_nodes: 10000,
          max_depth: 100,
          max_text_bytes: 100000,
          max_tokens: 1000,
          tree: {
            max_nodes: 10000,
            max_depth: 100,
            max_string_bytes: 100000,
            max_total_string_bytes: 100000,
          },
        },
      },
    ).unwrap()
    uses.push(
      @stage_body.collect_parameter_uses(body, {
        max_work: 1000000,
        max_slots: 1000,
        max_references: 1000,
        max_pointer_units: 100000,
        max_direct_text_bytes: 100000,
      }).unwrap(),
    )
  }
  let inventory = @program_refs.prepare(requests, uses, {
    max_work: 4000000,
    max_slots: 1000,
    max_references: 1000,
    max_pointer_units: 1000000,
    max_request_text_bytes: 100000,
  }).unwrap()
  let usage = @program_refs.check_declaration_usage(inventory, max_work=5000000).unwrap()
  @program_refs.bind_parameter_values(usage, values, max_work=6000000).unwrap()
}

///|
fn reference_pipeline(
  source : @stages.Source,
  i : Int,
) -> @pipeline.CheckedPipeline {
  let body = @decode.open_object(
    @syntax.stage_body(@stages.stage_at(source, i).unwrap()),
  ).unwrap()
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
      ),
    ],
    max_fields=1,
    max_name_bytes=10,
  ).unwrap()
  @pipeline.check(
    @decode.required(body, "steps").unwrap(),
    [("a", schema)],
    Some(@stages.declarations(source)),
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
fn reference_operations(
  source : @stages.Source,
  pipelines : Array[@pipeline.CheckedPipeline],
) -> @stages.CollectedOperations {
  @stages.collect_operations(source, pipelines, {
    max_work: 10000,
    max_slots: 100,
    max_references: 100,
    max_pointer_units: 10000,
    max_direct_text_bytes: 10000,
  }).unwrap()
}
