///|
/// One declaration-derived Run Ledger for Direct capture, keyed RowRuns,
/// lookup assembly and the existing Local task providers. No capture receipt
/// or sampled row count is needed to reserve this finite inventory.
pub fn prepare_keyed_captured_local_installed_ledger(
  prepared : @publication_host.PreparedClientProgram,
  direct : ClientInstalledCaptureCapacity,
  keyed : @publication_host.ClientKeyedAcquisition,
  keyed_capacity : @row_source_host.RowKeyedCapacity,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  max_bytes : Int,
  max_work : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  serialization? : (Int, Int, Int64, Int64)? = None,
  infer? : (Int, Int, Int64, Int64)? = None,
  captured_content? : Bool = false,
) -> @resources.Ledger? {
  keyed_captured_local_installed_limits(
    prepared,
    direct,
    keyed,
    keyed_capacity,
    transport_bytes,
    transport_execution_bytes,
    max_bytes,
    max_work,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    serialization~,
    infer~,
    captured_content~,
  ).bind(limits => @resources.create_ledger(limits).to_option())
}

///|
// Shared demand calculation for the existing standalone entry and the
// same-original managed Run borrower. Quoting never publishes another Ledger
// or supplies physical backing, permission, or a child cleanup acknowledgement.
fn keyed_captured_local_installed_limits(
  prepared : @publication_host.PreparedClientProgram,
  direct : ClientInstalledCaptureCapacity,
  keyed : @publication_host.ClientKeyedAcquisition,
  keyed_capacity : @row_source_host.RowKeyedCapacity,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  max_bytes : Int,
  max_work : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  serialization? : (Int, Int, Int64, Int64)? = None,
  infer? : (Int, Int, Int64, Int64)? = None,
  captured_content? : Bool = false,
) -> @resources.LedgerLimits? {
  keyed_captured_local_installed_requirements(
    prepared,
    direct,
    keyed,
    keyed_capacity,
    transport_bytes,
    transport_execution_bytes,
    max_bytes,
    max_work,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    serialization~,
    infer~,
    captured_content~,
  ).map(value => value.0)
}

///|
// One calculation returns the original checked coordinates and request bound
// along with limits. Retaining those completed facts avoids another graph/
// lookup-capacity derivation in the installed keyed Content constructor.
fn keyed_captured_local_installed_requirements(
  prepared : @publication_host.PreparedClientProgram,
  direct : ClientInstalledCaptureCapacity,
  keyed : @publication_host.ClientKeyedAcquisition,
  keyed_capacity : @row_source_host.RowKeyedCapacity,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  max_bytes : Int,
  max_work : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  serialization? : (Int, Int, Int64, Int64)? = None,
  infer? : (Int, Int, Int64, Int64)? = None,
  captured_content? : Bool = false,
  original_requirement? : @planning.QueryRequirement? = None,
) -> (@resources.LedgerLimits, Int, Int, Int64)? {
  guard @publication_host.client_keyed_acquisition_matches_program(
      keyed, prepared,
    ) &&
    @publication_host.client_keyed_direct_acquisition_coordinates(keyed)
    is Some((stage, input, _)) &&
    @publication_host.client_keyed_acquisition_coordinates(keyed)
    is Some((_, keyed_task, _)) &&
    @row_source_host.keyed_row_capacity_matches(
      keyed_capacity,
      @publication_host.client_keyed_acquisition_owner(keyed),
      @publication_host.client_keyed_acquisition_facts(keyed),
    ) &&
    (match original_requirement {
      None =>
        prepare_local_query_requirement(
          prepared, stage, input, installed_contracts, values_body, fragment_body,
          ordered_body,
        ).to_option()
      Some(requirement) =>
        if physical_equal(requirement, direct.requirement) &&
          @publication_host.client_query_requirement_matches_program(
            prepared, stage, input, requirement,
          ) &&
          values_body == installed_contracts.original.values_body &&
          fragment_body == installed_contracts.original.fragment_body &&
          ordered_body == installed_contracts.original.ordered_body {
          Some(requirement)
        } else {
          None
        }
    })
    is Some(requirement) &&
    @planning.query_requirement_cid(requirement) ==
    @planning.query_requirement_cid(direct.requirement) &&
    @publication_host.client_keyed_lookup_capacity(keyed, max_bytes, max_work)
    is Some((_, key_runs, lookup_retained, lookup_execution)) else {
    return None
  }
  let graph = @publication_host.prepared_client_graph(prepared)
  let count = @strategy.graph_task_count(graph)
  if (serialization is Some(_) && infer is Some(_)) ||
    count < (if serialization is Some(_) || infer is Some(_) { 1 } else { 2 }) ||
    keyed_task <
    (if serialization is Some(_) || infer is Some(_) { 0 } else { 1 }) ||
    keyed_task >= count ||
    key_runs >
    (2147483647 - count - (if captured_content { 2 } else { 1 })).to_int64() ||
    transport_bytes.length() != 2 ||
    transport_execution_bytes.length() != 2 {
    return None
  }
  let limits : @resources.LedgerLimits = match (serialization, infer) {
    (Some((task, step, retained, execution)), None) => {
      // The Content caller derived the whole prefix/workspace envelope from
      // the selected common provider before I/O. Recheck its original barrier;
      // a sampled row count or another task cannot substitute this inventory.
      guard retained >= 0L &&
        execution >= 0L &&
        @publication_host.client_keyed_acquisition_reaches_serialization(
          prepared, keyed, task, step,
        ) &&
        @publication_host.prepare_client_serialization(
          prepared,
          task,
          step,
          max_work=10000,
        )
        is Ok(_) &&
        @publication_host.client_keyed_acquisition_coordinates(keyed)
        is Some((_, _, join)) &&
        join < step else {
        return None
      }
      {
        planning_work: 100000,
        attempts: 1,
        holdings: 0,
        transfer_bytes: 0L,
        retained_bytes: retained,
        execution_bytes: execution,
      }
    }
    (None, Some((task, step, retained, execution))) => {
      // The Model owner derives its input, output and suffix envelope before
      // acquisition. Bind it to this original single keyed Model occurrence;
      // a serialization barrier or an equal-looking Program cannot replace it.
      guard count == 1 &&
        task == 0 &&
        keyed_task == task &&
        retained >= 0L &&
        execution >= 0L &&
        @publication_host.prepared_client_composed_infer_occurrence(prepared)
        is Some(occurrence) &&
        @publication_host.client_infer_occurrence_coordinates(occurrence).0 ==
        task &&
        @publication_host.client_infer_occurrence_coordinates(occurrence).2 ==
        step &&
        @publication_host.client_keyed_acquisition_coordinates(keyed)
        is Some((_, _, join)) &&
        join < step else {
        return None
      }
      {
        planning_work: 100000,
        attempts: 1,
        holdings: 0,
        transfer_bytes: 0L,
        retained_bytes: retained,
        execution_bytes: execution,
      }
    }
    (None, None) => {
      guard prepare_client_local_sequences_owned(
          Pure(prepared),
          installed_contracts,
          values_body,
          fragment_body,
          ordered_body,
        ).to_option()
        is Some(sequences) else {
        return None
      }
      let compute = []
      for task in 1..<count {
        compute.push(sequences[task])
      }
      let inputs = Array::make(count - 1, 0)
      for index in 0..<@strategy.graph_data_count(graph) {
        let edge = @strategy.graph_data_at(graph, index).unwrap()
        let consumer = @strategy.data_edge_consumer(edge) - 1
        if consumer >= 0 && consumer < inputs.length() {
          inputs[consumer] += 1
        }
      }
      // The right Source is a supplied port, not a synthetic completed task.
      inputs[keyed_task - 1] += 1
      guard client_local_sequence_capacity(
          compute,
          count,
          retained_inputs=Some(inputs),
          max_rows=@publication_host.prepared_client_values_max_rows(prepared),
        )
        is Some((limits, _, _)) else {
        return None
      }
      limits
    }
    _ => return None
  }
  let (child_retained, child_execution) = @row_source_host.keyed_row_capacity_bytes(
    keyed_capacity,
  )
  let mut retained = limits.retained_bytes
  let mut executing = limits.execution_bytes
  let mut transfer = limits.transfer_bytes
  if captured_content {
    guard @publication_host.client_captured_content_workspace_capacity(
        max_bytes,
        inventory_count=key_runs.to_int(),
      )
      is Some((capture_retained, capture_execution)) &&
      capture_retained <= 9223372036854775807L - retained &&
      capture_execution <= 9223372036854775807L - executing else {
      return None
    }
    retained += capture_retained
    executing += capture_execution
  }
  let retained_parts = [direct.retained_bytes, lookup_retained, child_retained]
  let execution_parts = [
    direct.execution_bytes,
    lookup_execution,
    child_execution,
    transport_execution_bytes[0],
    transport_execution_bytes[1],
  ]
  // Keep all completed per-key holdings. Execution workspaces can overlap
  // assembly; the conservative sum is not an allocator/RSS guarantee.
  for index, bytes in retained_parts {
    let multiplier = if index == 2 { key_runs } else { 1L }
    if bytes < 0L ||
      (
        multiplier > 0L &&
        bytes > (9223372036854775807L - retained) / multiplier
      ) {
      return None
    }
    retained += bytes * multiplier
  }
  for bytes in execution_parts {
    if bytes < 0L || bytes > 9223372036854775807L - executing {
      return None
    }
    executing += bytes
  }
  for index, bytes in transport_bytes {
    let multiplier = if index == 1 { key_runs } else { 1L }
    if bytes < 0L ||
      (
        multiplier > 0L &&
        bytes > (9223372036854775807L - transfer) / multiplier
      ) {
      return None
    }
    transfer += bytes * multiplier
  }
  Some(
    (
      {
        planning_work: limits.planning_work,
        attempts: count +
        key_runs.to_int() +
        (if captured_content { 2 } else { 1 }),
        holdings: count + key_runs.to_int() + 1,
        transfer_bytes: transfer,
        retained_bytes: retained,
        execution_bytes: executing,
      },
      stage,
      input,
      key_runs,
    ),
  )
}
