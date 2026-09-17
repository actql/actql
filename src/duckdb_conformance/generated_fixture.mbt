///|
// Fixed conformance construction through the real registry and fragment verifier.
fn fixture_generated(
  owner : @lower.BoundPrepared,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  filter : Bool,
  fragment_start? : Int = 0,
) -> @execution.GeneratedSequence raise {
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
  let direct_count = @lower.sequence_step(sequence, 0)
    is Some(@lower.RowStep(kernel)) &&
    @lower.kernel_count_group(kernel) is Some(_)
  let direct_join = @lower.sequence_step(sequence, 0)
    is Some(@lower.JoinStep(_))
  let projection_only = Ref(@lower.sequence_count(sequence) > 0)
  for index in 0..<@lower.sequence_count(sequence) {
    if !(@lower.sequence_step(sequence, index) is Some(@lower.RowStep(kernel)) &&
      @lower.kernel_is_projection(kernel)) {
      projection_only.val = false
    }
  }
  let contexts = if filter &&
    !direct_count &&
    !direct_join &&
    !projection_only.val {
    let pipeline = @lower.prepare_fragment_pipeline(sequence, fragment_start, {
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
    [context]
  } else {
    []
  }
  @execution.prepare_generated_sequence(
    registered,
    sequence,
    contexts,
    [
      @lower.node_id(
        @lower.node_at(
          @lower.bound_preparation(owner),
          @pipeline.step_count(@lower.pipeline(@lower.bound_preparation(owner))) -
          1,
        ).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
}
