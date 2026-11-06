///|
/// Completed immutable Compute constructor data, not another Plan/resource
/// owner. Pure/Effect callers retain the same sequence/configuration originals.
priv struct ClientInstalledComputePreparation {
  sequences : Array[@execution.GeneratedSequence]
  capacity_plan : ClientLocalCapacityPlan
  configuration : ClientPreparedLocalConfiguration
  limits : @resources.LedgerLimits
  // Preserve the already computed tail envelope before capture peaks are
  // folded into limits. Later phase composition must not reconstruct a Plan
  // or try to recover this value by subtracting from an unrelated maximum.
  tail_execution_bytes : Int64
}

///|
// Additional resident scalar of the same transient constructor record. The
// original Request backs it before that record is built, on both entrances.
let installed_compute_tail_inventory_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 1L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
fn prepare_installed_compute_preparation(
  owner : ClientLocalSequenceOwner,
  source_free : ClientInstalledManagedSourceFreePreparation?,
  sequences : Array[@execution.GeneratedSequence],
  captures : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  retained_output : Bool,
  provider_factory : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
  runtime_admission? : Bool = false,
) -> Result[ClientInstalledComputePreparation, ClientInstalledManagedRunIssue] {
  let graph = installed_managed_owner_graph(owner)
  let (compute_sequences, capacity_plan, local_capacity) = match source_free {
    Some(original) =>
      (
        original.sequences,
        original.capacity_plan,
        {
          limits: original.limits,
          provider_retained: original.provider_retained_bytes,
          provider_execution: original.provider_execution_bytes,
          simultaneous: None,
        },
      )
    None => {
      let first = @strategy.graph_captured_prefix(graph)
      let tail = []
      for task in first..<sequences.length() {
        tail.push(sequences[task])
      }
      let max_rows = match owner {
        Pure(prepared) =>
          @publication_host.prepared_client_values_max_rows(prepared)
        Effect(_) =>
          @publication_host.client_standard_values_sequence_limits().max_rows
      }
      let configuration = client_local_capacity_plan(
        tail,
        max_rows,
        // Retain the same checked leaf proof for Compute and publication.
        // Source or Effect purpose does not erase immutable input schemas.
        // Nested/unproved fields still retain the existing general envelope.
        scalar_values=true,
        graph=Some(graph),
        graph_offset=first,
      )
      let inputs = Array::make(tail.length(), 0)
      for task in first..<sequences.length() {
        guard @strategy.graph_task_input_count(graph, task) is Some(count) else {
          return Err(Unsupported)
        }
        inputs[task - first] = count
      }
      guard client_local_sequence_capacity_original(
          tail,
          @strategy.graph_task_count(graph),
          capacity_plan=Some(configuration),
          retained_inputs=Some(inputs),
          max_rows~,
          // Preparation-owned Runs reserve each actual provider/import/output
          // on their original finite Ledger. A whole-Run maximum is only an
          // estimate; legacy quote callers keep their strict inventory.
          runtime_admission~,
        )
        is Some(capacity) else {
        return Err(Unsupported)
      }
      (tail, configuration, capacity)
    }
  }
  let configuration = match
    prepare_client_local_configuration(
      graph,
      capacity_plan,
      ExecutionRows,
      local_capacity.provider_retained,
      local_capacity.provider_execution,
      retained_output,
      provider_factory,
    ) {
    Some(value) => value
    None => return Err(Unsupported)
  }
  let actual_local_capacity = match
    client_prepared_local_configuration_capacity(
      configuration,
      local_capacity.limits,
    ) {
    Some(value) => value
    None => return Err(Unsupported)
  }
  let compute_limits = match source_free {
    Some(_) => {
      if !captures.is_empty() ||
        !transport_bytes.is_empty() ||
        !transport_execution_bytes.is_empty() {
        return Err(Unsupported)
      }
      actual_local_capacity.limits
    }
    None => {
      if @strategy.graph_captured_prefix(graph) == 0 {
        return Err(Unsupported)
      }
      guard multi_captured_capacity_limits_selected(
          graph,
          captures.map(value => (value.retained_bytes, value.execution_bytes)),
          transport_bytes,
          transport_execution_bytes,
          sequences,
          local_capacity=Some(actual_local_capacity),
        )
        is Some(limits) else {
        return Err(Unsupported)
      }
      limits
    }
  }

  Ok({
    sequences: compute_sequences,
    capacity_plan,
    configuration,
    limits: compute_limits,
    tail_execution_bytes: actual_local_capacity.limits.execution_bytes,
  })
}
