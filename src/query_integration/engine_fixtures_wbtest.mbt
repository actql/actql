// Public construction fixtures: no engine storage or mutable context access.

///|
fn typed_receiver(
  owner : @lower.BoundPrepared,
  source : String,
  target? : @pipeline.Target = Step(1),
) -> @lower.BoundPrepared {
  let pipeline = @pipeline.check_with_evidence(
    input_cursor(source),
    [
      (
        "prior",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(owner)),
            target,
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(input_cursor("\"prior\"")),
    {
      max_steps: 100,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn input_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="supplied.json",
    ).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn row_wire_limits() -> @execution.RowWireLimits {
  {
    max_columns: 100,
    max_order_work: 10000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
}

///|
fn compute_test_sequence(
  owner : @lower.BoundPrepared,
) -> @execution.GeneratedSequence raise {
  let sequence = prepared_sequence(owner)
  let contexts = if @pipeline.step_count(
      @lower.pipeline(@lower.bound_preparation(owner)),
    ) ==
    3 {
    [sequence_fragment_context(sequence, 1, 2L)]
  } else {
    []
  }
  let last = @pipeline.step_count(
      @lower.pipeline(@lower.bound_preparation(owner)),
    ) -
    1
  let node = @lower.node_at(@lower.bound_preparation(owner), last).unwrap()
  @execution.prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    contexts,
    [@lower.node_id(node)],
    100000,
    10000,
  ).unwrap()
}

///|
fn compute_test_limits() -> @execution.SequenceExecutionLimits {
  { rows: run_limits(), max_work: 100000, max_frames: 100, }
}

///|
fn run_limits() -> @execution.SequenceRunLimits {
  {
    max_rows: 100,
    metadata_entries: 10000,
    retained_entries: 10000,
    operation_entries: 10000,
    input_values: {
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 100,
      max_work: 100000,
    },
    output_values: {
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 100,
      max_work: 100000,
    },
  }
}

///|
fn prepared_sequence(owner : @lower.BoundPrepared) -> @lower.PreparedSequence {
  @lower.prepare_sequence(owner, {
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
}

///|
fn registered_relation_contracts() -> @execution.RegisteredRelationContracts raise {
  @execution.admit_relation_registry(
    registered_body(),
    registered_values(),
    registry_limits(),
  ).unwrap()
}

///|
fn sequence_fragment_context(
  sequence : @lower.PreparedSequence,
  step : Int,
  rows : Int64,
) -> @execution.FragmentRuntimeContext raise {
  let logical : @lower.FragmentRowLimits = {
    max_input_rows: rows,
    max_value_bytes: 1000L,
    max_live_value_bytes: 10000L,
    max_work: 100000L,
  }
  let pipeline = @lower.prepare_fragment_pipeline(sequence, step, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  let ordered = match @lower.sequence_step(sequence, step) {
    Some(@lower.RowStep(kernel)) =>
      if @lower.kernel_body(kernel) is @lower.OrderedBindings(_) {
        Some(
          @execution.admit_ordered_contract(
            registered_relation_contracts(),
            registered_ordered(),
            registry_limits(),
          ).unwrap(),
        )
      } else {
        None
      }
    _ => None
  }
  let request = @lower.prepare_fragment_request(
    pipeline,
    10L,
    1000L,
    row_limits=if ordered is Some(_) { Some(logical) } else { None },
  ).unwrap()
  @execution.prepare_runtime_fragment(
    request,
    test_fragment_contract(),
    material_demands(),
    registry_limits(),
    logical,
    ordered~,
  ).unwrap()
}

///|
fn registry_limits() -> @execution.RegistryLimits {
  { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, }
}

///|
fn test_fragment_contract() -> @execution.FragmentContract raise {
  @execution.admit_fragment_contract(
    registered_relation_contracts(),
    registered_fragment(),
    registry_limits(),
  ).unwrap()
}

///|
fn material_demands() -> @lower.DemandLimits {
  {
    max_roots: 100,
    max_nodes: 1000,
    max_work: 100000,
    max_text_bytes: 100000,
    max_links: 10000,
  }
}
