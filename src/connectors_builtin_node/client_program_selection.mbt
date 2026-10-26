///|
/// This selected Node package installs all Local families; RelA-only supplies a
/// different, provider-free selection without changing the common bridge body.
fn selected_sga_supported() -> Bool {
  true
}

///|
/// The same installed Graph provider implements the initial keyed constructor,
/// MATCH and bounded path subset; this is not a claim of all SGA support.
fn selected_graph_supported() -> Bool {
  true
}

///|
fn selected_graph_limits() -> @graph_storage.Limits {
  {
    max_input_rows: 100,
    max_nodes: 100,
    max_edges: 100,
    max_value_bytes: 10000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 10000,
    max_value_depth: 100,
    max_contract_work: 10000,
    max_work: 100000,
    max_workspace_slots: 10000,
  }
}

///|
fn selected_record_limits() -> @record_storage.Limits {
  {
    max_input_records: 100,
    max_records: 100,
    max_fields_per_record: 100,
    max_value_bytes: 10000,
    max_total_value_bytes: 100000,
    max_retained_value_bytes: 100000,
    max_value_nodes: 10000,
    max_value_depth: 100,
    max_contract_work: 10000,
    max_work: 100000,
    max_workspace_slots: 10000,
  }
}

///|
/// Snapshot buffers are installed resource ceilings, not persisted authority.
/// The provider adds the complete private envelope before task selection.
fn selected_graph_snapshot_policy() -> @local_sga_provider.SnapshotPolicy {
  {
    serialization: {
      max_workspace_slots: 10000,
      max_identity_bytes: 1048576,
      max_identity_nodes: 100000,
      max_identity_depth: 100,
      value_limits: { max_nodes: 10000, max_depth: 100, max_text_bytes: 10000, },
    },
    read: {
      max_nodes: 100000,
      max_depth: 100,
      max_string_bytes: 1048576,
      max_total_string_bytes: 1048576,
    },
    maximum_bytes: 1048576,
    maximum_frame_bytes: 1048576,
    workspace_bytes: 67108864L,
  }
}

///|
/// Delta input conversion and application use the installed Graph provider.
/// These are private runtime ceilings/reservations, not a count law, a saved
/// admission receipt, or a machine-independent total-memory proof.
fn selected_graph_delta_policy() -> @local_sga_provider.DeltaPolicy {
  let snapshot = selected_graph_snapshot_policy()
  {
    limits: {
      max_workspace_slots: 2000000,
      max_output_nodes: 10000,
      max_output_text_bytes: 10000,
      max_output_depth: 100,
      max_identity_bytes: snapshot.serialization.max_identity_bytes,
      // Base-body and complete-before decoding coexist with input conversion
      // and staged output. Delta uses the smaller installed value-node ceiling
      // rather than borrowing the larger standalone snapshot read ceiling.
      max_identity_nodes: snapshot.serialization.value_limits.max_nodes,
      max_identity_depth: snapshot.serialization.max_identity_depth,
      value_limits: snapshot.serialization.value_limits,
    },
    workspace_bytes: 67108864L,
  }
}

///|
/// Union's typed record append/order cursors coexist with a private previous
/// fold generation. Reserve the installed scratch before task selection; the
/// ordinary Graph input/value/work ceilings remain unchanged.
fn selected_graph_union_policy() -> @local_sga_provider.UnionPolicy {
  { max_workspace_slots: 2000000, workspace_bytes: 67108864L, }
}

///|
fn installed_client_family_providers(
  capacity : @execution.ExecutionCapacity,
) -> Array[@local.ManagedProvider] {
  let records = selected_record_limits()
  [
    @local_sga_provider.provider(
      selected_graph_limits(),
      10000L,
      capacity,
      snapshot_policy=Some(selected_graph_snapshot_policy()),
      delta_policy=Some(selected_graph_delta_policy()),
      union_policy=Some(selected_graph_union_policy()),
      mean_policy=Some(selected_graph_mean_policy()),
    ),
    @local_tea_provider.provider(records, 100000L, capacity),
    @local_tea_provider.time_series_provider(records, capacity),
    @local_tea_provider.calendar_series_provider(records, capacity),
    @local_tea_provider.calendar_bucket_provider(records, capacity),
    @local_tea_provider.interval_join_provider(records, capacity),
    @local_tea_provider.asof_join_provider(records, capacity),
    @local_tea_provider.sequence_match_provider(records, capacity),
    @local_veca_provider.provider(records, 100000L, capacity),
  ]
}

///|
fn selected_client_sga_providers(
  generated : Array[@execution.GeneratedSequence],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Array[@local.ManagedProvider]? {
  let mut retained_bytes = 0L
  let mut execution_bytes = 0L
  for sequence in generated {
    guard @execution.generated_sequence_capacity(
        sequence, execution, measurement,
      )
      is Some(sequence_capacity) else {
      return None
    }
    let retained = @execution.execution_capacity_retained_bytes(
      sequence_capacity,
    )
    let executing = @execution.execution_capacity_execution_bytes(
      sequence_capacity,
    )
    if retained > retained_bytes {
      retained_bytes = retained
    }
    if executing > execution_bytes {
      execution_bytes = executing
    }
  }
  match @execution.execution_capacity(retained_bytes, execution_bytes) {
    Some(sequence_capacity) =>
      Some([
        @local_sga_provider.provider(
          selected_graph_limits(),
          10000L,
          sequence_capacity,
          snapshot_policy=Some(selected_graph_snapshot_policy()),
          delta_policy=Some(selected_graph_delta_policy()),
          union_policy=Some(selected_graph_union_policy()),
          mean_policy=Some(selected_graph_mean_policy()),
        ),
      ])
    None => None
  }
}

///|
/// Exact mean uses a finite list and coefficient envelope on the existing
/// provider. Scratch is separate from the unchanged output/value quotas.
fn selected_graph_mean_policy() -> @local_sga_provider.MeanPolicy {
  {
    limits: {
      max_samples: 64,
      max_exact_operations: 100000,
      max_coefficient_bits: 8192,
      max_temporary_bytes: 36400,
    },
    max_workspace_slots: 2000000,
    workspace_bytes: 67108864L,
  }
}

///|
// This is fixed installed implementation DATA, not per-Run demand or a grant.
// The pure constructor correspondence fixture pins the actual factory count.
fn installed_client_family_provider_count() -> Int {
  9
}

///|
// Shared immutable recipe; neither bridge accepts a JS unit/count override.
let installed_client_module_container_units : @execution.PreparationRepresentationUnits = @local.local_module_container_inventory(
  1,
  installed_client_family_provider_count(),
).unwrap()
