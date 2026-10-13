///|
fn original_keyed_content_workspace() -> ClientSerializationWorkspaceLimits {
  let original = content_workspace_fixture()
  {
    ..original,
    generation_bytes: 4470,
    generation_nodes: 1000,
    generation_depth: 32,
    generation_frames: 100,
    export_limits: { ..original.export_limits, max_rows: 3, },
  }
}

///|
test "Pure keyed Content family retains the actual checked boundary without entering Store during capacity selection" {
  let (_, prepared, _, _, _, keyed, _) = original_keyed_run_fixture(
    relation_versions=true,
    serialization_max_bytes=4470,
  )
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 3,
      max_metadata_bytes: 10000,
      max_retained_bytes: 10000,
      max_operation_entries: 10000,
      values: source_capture_values(),
    },
    max_work: 100000,
    max_frames: 100,
  }
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let entries = Ref(0)
  let physical : ClientLocalContentPhysicalPort = {
    cancel: () => {
      entries.val += 1
      true
    },
    stopped: () => {
      entries.val += 1
      true
    },
    cleanup: () => {
      entries.val += 1
      Ok(true)
    },
  }
  let family = client_content_local_provider(
    prepared,
    0,
    7,
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    execution,
    measurement,
    original_keyed_content_workspace(),
    physical,
    _ => {
      entries.val += 1
      true
    },
  ).unwrap()
  let sequences = prepare_client_local_sequences(
    prepared,
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let boundary = @execution.select_generated_sequence_step(sequences[0], 7).unwrap()
  assert_true(
    @execution.generated_sequence_step_at(boundary, 0)
    is Some(@lower.SerializationBoundary(7)),
  )
  assert_true(@local.managed_provider_capacity(family, boundary) is Some(_))
  let capacity = client_original_keyed_content_suffix_capacity(
    prepared,
    keyed,
    0,
    7,
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    execution,
    measurement,
    original_keyed_content_workspace(),
    physical,
    _ => {
      entries.val += 1
      true
    },
  ).unwrap()
  assert_true(@execution.execution_capacity_retained_bytes(capacity) > 0L)
  assert_true(@execution.execution_capacity_execution_bytes(capacity) > 0L)
  assert_eq(entries.val, 0)
  let (_, foreign, _, _, _, _, _) = original_keyed_run_fixture(
    relation_versions=true,
    serialization_max_bytes=4470,
  )
  let other = prepare_client_local_sequences(
    foreign,
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let other = @execution.select_generated_sequence_step(other[0], 7).unwrap()
  assert_true(@local.managed_provider_capacity(family, other) is None)
  assert_true(
    client_original_keyed_content_suffix_capacity(
      foreign,
      keyed,
      0,
      7,
      source_query_original_registry,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      execution,
      measurement,
      original_keyed_content_workspace(),
      physical,
      _ => {
        entries.val += 1
        true
      },
    )
    is None,
  )
  assert_eq(entries.val, 0)
}
