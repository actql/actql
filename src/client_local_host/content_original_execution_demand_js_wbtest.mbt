///|
test "same checked Content input shape selects original row and column demand before prefix construction" {
  // Exact existing installed caller ceilings, with the SAME checked generation
  // bound selected before the workspace. This component supplies no physical
  // Resource admission or normal Host/Store acceptance.
  let workspace : ClientSerializationWorkspaceLimits = {
    generation_bytes: 10000000,
    generation_nodes: 100000,
    generation_depth: 64,
    generation_frames: 256,
    identity_slots: 4000800,
    reference_bytes: 16384,
    reference_nodes: 256,
    reference_depth: 32,
    contract_bytes: 1000000,
    contract_nodes: 100000,
    contract_depth: 64,
    export_limits: {
      max_result_fields: 10,
      max_result_mapping_work: 1000,
      max_result_order_work: 10000,
      max_result_workspace_entries: 100,
      max_rows: 10000,
      values: {
        max_nodes: 1000000,
        max_text_bytes: 10000000,
        max_depth: 64,
        max_work: 1000000,
      },
      payload_wire: {
        max_bytes: 10000000,
        max_nodes: 1000000,
        max_depth: 64,
        max_columns: 100,
        max_order_work: 1000000,
      },
      logical_wire: {
        max_bytes: 10000000,
        max_nodes: 1000003,
        max_depth: 66,
        max_columns: 100,
        max_order_work: 1000000,
      },
      schema: {
        max_fields: 100,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 64,
      },
      max_batch_bytes: 65536,
    },
  }
  let ordinary = client_local_preparation_initial_limits(
    client_local_resource_policy(),
  ).unwrap()
  let generic = client_serialization_workspace_capacity(workspace).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(generic) >
    ordinary.execution_bytes,
  )
  let f = request_serialized_model_fixture(single_capture=true)
  let fields = client_serialization_json_leaf_field_count(
    f.graph.serialization.unwrap(),
  )
  // The original barrier keeps all three checked input columns, including
  // columns not selected for the output byte body. Do not narrow to [id].
  assert_eq(fields, 3)
  let rows = f.graph.serialization.unwrap().max_rows
  assert_eq(rows, 1)
  let wire_nodes = 1 + rows * (1 + fields)
  let value_nodes = 1 + rows * (1 + 2 * fields)
  let output = workspace.export_limits
  let selected : ClientSerializationWorkspaceLimits = {
    ..workspace,
    generation_bytes: f.graph.serialization.unwrap().max_bytes,
    identity_slots: 2 * wire_nodes +
    (wire_nodes + 3) +
    fields * 8 +
    2 * output.values.max_depth +
    4,
    export_limits: {
      ..output,
      max_rows: rows,
      values: { ..output.values, max_nodes: value_nodes, },
      payload_wire: {
        ..output.payload_wire,
        max_nodes: wire_nodes,
        max_columns: fields,
      },
      logical_wire: {
        ..output.logical_wire,
        max_nodes: wire_nodes + 3,
        max_columns: fields,
      },
    },
  }
  let capacity = client_serialization_workspace_capacity(selected).unwrap()
  let values : @execution.ValueLimits = {
    max_nodes: 100000,
    max_text_bytes: 1000000,
    max_depth: 64,
    max_work: 1000000,
  }
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 10000,
      metadata_entries: 100000,
      retained_entries: 100000,
      operation_entries: 100000,
      input_values: values,
      output_values: values,
    },
    max_work: 1000000,
    max_frames: 256,
  }
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 1000000,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 64,
  }
  let prefix = prepare_request_model_serialization_plan(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
    execution,
    measurement,
    Some(capacity),
    None,
  ).unwrap()
  println(
    "CONTENT_DEMAND workspace_retained=" +
    @execution.execution_capacity_retained_bytes(capacity).to_string() +
    " workspace_execution=" +
    @execution.execution_capacity_execution_bytes(capacity).to_string() +
    " prefix_total_execution=" +
    prefix.limits.execution_bytes.to_string(),
  )
  // Continue the actual Request composition, not only the isolated workspace.
  // Source admission/transport are this existing explicit component fixture;
  // no normal Account/HTTP/read or observed row count is substituted.
  let selected_module = prepare_request_model_capture_module(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
    f.compilation,
    [f.declaration.unwrap()],
    original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
    [4096L],
    [2048L],
    f.contracts,
    true,
    0,
    _ => [],
  ).unwrap()
  let model = prepare_installed_mock_model_capture_plan_binding(
    selected_module,
    f.compiled,
    f.definition,
    f.occurrence,
    f.graph,
    effect_model_plan_limits,
    500L,
    700L,
    20,
    20,
    20,
    content_prefix=Some(prefix),
  ).unwrap()
  println(
    "CONTENT_MODEL_DEMAND module_execution=" +
    selected_module.limits.execution_bytes.to_string() +
    " plan_execution=" +
    model.limits.execution_bytes.to_string(),
  )
  // The actual installed contract quantities now share the original proof
  // codec bound. Enter the SAME Scope, adopt once and retire its originals.
  let scope = prepare_request_model_read_scope(f.parent, f.input, model).unwrap()
  complete_request_model_preparation(f.parent, f.input, model).unwrap()
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  let run = begin_request_model_managed_run(f.parent, f.request, scope).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      f.compiled,
      f.definition,
      f.graph,
      true,
    ).unwrap(),
  )
  assert_true(
    cleanup_installed_managed_serialization_prefix(run, prefix).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
  assert_true(
    @execution.execution_capacity_execution_bytes(capacity) <
    ordinary.execution_bytes,
  )
  assert_true(prefix.limits.execution_bytes < ordinary.execution_bytes)
  assert_true(model.limits.execution_bytes < ordinary.execution_bytes)
}
