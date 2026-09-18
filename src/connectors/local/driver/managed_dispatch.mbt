///|
/// Pure prepared Local managed task. Physical representation access starts
/// only after common selection, reservation and task registration.
struct LocalManagedDispatchConfiguration[T] {
  run : @strategy.CapturedDAG
  task : Int
  choice : @connector.ManagedFixedComputeChoice[T]
  prepared : @connector.PreparedManagedCompute[T, @execution.GeneratedSequence]
  sequence : @execution.GeneratedSequence
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
  imports : @local.LocalImportLimits
  capacity : @connector.ExecutionCapacity
  join_output_ceilings : Array[(Int, Int64)]
  aggregate_output_ceilings : Array[@connector.AggregateOutputCeiling]
}

///|
pub struct LocalManagedInputTransfer[T] {
  input : @execution.ManagedProducerRead[T]
  append : (String) -> Result[Unit, LocalDispatchIssue]
  finish : () -> Result[Unit, LocalDispatchIssue]
}

///|
pub struct LocalManagedDispatchOperations[T] {
  inputs : Array[LocalManagedInputTransfer[T]]
  execute : () -> Result[Unit, LocalDispatchIssue]
  settle : () -> Result[Unit, LocalDispatchIssue]
  complete : (T, Int64, () -> Bool) -> Result[
    @execution.ManagedCompletedOutput[T],
    LocalDispatchIssue,
  ]
  output_rows : () -> Int
  output_row : (Int) -> Result[String, LocalDispatchIssue]
  material : () -> @execution.ManagedRetainedOutput[T]?
  storage_bytes : Int64
  close : () -> Unit
  cleanup_refresh : () -> Bool
}

///|
/// Exact physical transfer unit used by the managed row wire. MoonBit String
/// length is UTF-16 code units and cannot be charged as transported bytes.
fn managed_row_transfer_bytes(
  row : String,
  max_bytes : Int,
) -> Result[Int64, LocalDispatchIssue] {
  @scalar.admit_utf8_length64(row, max_bytes.to_int64()).map_err(_ => {
    Configuration(InputUnavailable)
  })
}

///|
pub fn[T] prepare_local_managed_dispatch(
  installed : LocalDispatchModule,
  outputs : Array[@execution.ManagedCompletedOutput[T]],
  obligations : @execution.ManagedObligations,
  _output_file_bytes : Int64,
) -> Result[LocalManagedDispatchConfiguration[T]?, LocalDispatchIssue] {
  guard @strategy.next_captured_task(installed.run) is Some(task) &&
    installed.import_policy is Some((imports, _)) else {
    return Ok(None)
  }
  let inputs = []
  for index, output in outputs {
    match
      @strategy.captured_managed_task_input(
        installed.run,
        task,
        output,
        @local.local_module_max_work(installed.implementation),
        imports.wire.max_bytes,
        input_index=index,
      ) {
      Ok(value) => inputs.push(value)
      Err(issue) => return Err(Execution(issue))
    }
  }
  guard @strategy.graph_task_owner(
      @strategy.captured_dag_graph(installed.run),
      task,
    )
    is Some(owner) else {
    return Err(Execution(ForeignCandidate))
  }
  let request = match
    @connector.prepare_managed_fixed_compute_request_for_owner(
      owner,
      inputs,
      @local.local_module_managed_capacity(installed.implementation),
      obligations,
    ) {
    Ok(value) => value
    Err(
      LogicalIdentityUnsupported
      | CommonFragmentUnsupported
      | UnsupportedInputShape
    ) => return Ok(None)
    Err(issue) => return Err(Configuration(issue))
  }
  let estimates = match local_managed_estimate_lines(installed, task, inputs) {
    Ok(value) => value
    Err(_) => return Err(Configuration(InvalidLimits))
  }
  let (prepared, choice) = match
    @local.prepare_local_module_managed_compute_with_estimates(
      installed.implementation,
      task - 1,
      request,
      estimates,
    ) {
    Ok(value) => value
    Err(
      Candidate(
        LogicalIdentityUnsupported
        | CommonFragmentUnsupported
        | UnsupportedInputShape
        | ComputeUnsupported
      )
    ) => return Ok(None)
    Err(issue) => return Err(Preparation(issue))
  }
  guard @connector.managed_fixed_compute_choice_payload(choice, prepared)
    is Some(sequence) &&
    @execution.generated_sequence_capacity(
      sequence,
      @local.local_module_execution_limits(installed.implementation),
      @local.local_module_measurement_limits(installed.implementation),
    )
    is Some(base) &&
    @local.local_import_retention_capacity(imports) is Some(per_input) else {
    return Err(Configuration(InvalidLimits))
  }
  let count = inputs.length().to_int64()
  if per_input > 0L && count > 9223372036854775807L / per_input {
    return Err(Configuration(InvalidLimits))
  }
  let imported = count * per_input
  if base.retained_bytes > 9223372036854775807L - base.execution_bytes ||
    imported > 9223372036854775807L - base.execution_bytes - base.retained_bytes ||
    (
      count > 0L &&
      imports.wire.max_bytes.to_int64() > 9223372036854775807L / count
    ) {
    return Err(Configuration(InvalidLimits))
  }
  let join_output_ceilings = []
  guard @strategy.captured_task_join_output_count(installed.run, task)
    is Some(join_count) else {
    return Err(Configuration(InvalidLimits))
  }
  if join_count > 1 {
    return Ok(None)
  }
  for index in 0..<join_count {
    guard @strategy.captured_task_join_output_at(installed.run, task, index)
      is Some(ceiling) else {
      return Err(Configuration(InvalidLimits))
    }
    join_output_ceilings.push(ceiling)
  }
  let aggregate_output_ceilings = []
  guard @strategy.captured_task_aggregate_output_count(installed.run, task)
    is Some(aggregate_count) else {
    return Err(Configuration(InvalidLimits))
  }
  for index in 0..<aggregate_count {
    guard @strategy.captured_task_aggregate_output_at(
        installed.run,
        task,
        index,
      )
      is Some(ceiling) else {
      return Err(Configuration(InvalidLimits))
    }
    aggregate_output_ceilings.push(ceiling)
  }
  Ok(
    Some({
      run: installed.run,
      task,
      choice,
      prepared,
      sequence,
      execution: @local.local_module_execution_limits(installed.implementation),
      measurement: @local.local_module_measurement_limits(
        installed.implementation,
      ),
      imports,
      capacity: {
        transfer_bytes: count * imports.wire.max_bytes.to_int64(),
        retained_bytes: base.retained_bytes,
        // The checked output view, independent copy and imported input may
        // overlap until the copy commits and every bridge is closed.
        scratch_bytes: base.execution_bytes + base.retained_bytes + imported,
        execution_bytes: base.execution_bytes + base.retained_bytes + imported,
      },
      join_output_ceilings,
      aggregate_output_ceilings,
    }),
  )
}

///|
/// Exact duration selected by the installed Local cost policy. None means the
/// candidate remains unknown and must not enter automatic multi-Site ranking.
pub fn[T] local_managed_dispatch_duration(
  setup : LocalManagedDispatchConfiguration[T],
) -> Int64? {
  match
    @connector.managed_fixed_compute_candidate_duration(
      @connector.prepared_managed_compute_candidate(setup.prepared),
    ) {
    @cost.Complete(value) => Some(value)
    @cost.Unknown => None
  }
}

///|
/// Safe Site sub-scope bounds for the selected managed execution. The Run
/// ledger remains the aggregate authority; these bounds prevent one Site from
/// consuming capacity assigned to another Site.
pub fn[T] local_managed_dispatch_site_capacity(
  setup : LocalManagedDispatchConfiguration[T],
) -> (Int64, Int64)? {
  Some((setup.capacity.retained_bytes, setup.capacity.execution_bytes))
}

///|
pub fn[T] start_local_managed_dispatch(
  setup : LocalManagedDispatchConfiguration[T],
) -> Result[LocalManagedDispatchOperations[T], LocalDispatchIssue] {
  let live = Ref(true)
  let settled = Ref(false)
  let disposed = Ref(false)
  let bridges : Array[@execution.ManagedProducerBridge[T]] = []
  let reads : Array[@execution.ProducerRead?] = []
  let ordinary : Ref[@execution.CompletedOutput?] = Ref(None)
  let retained : Ref[@execution.ManagedRetainedOutput[T]?] = Ref(None)
  let request = @connector.managed_fixed_compute_candidate_request(
    @connector.prepared_managed_compute_candidate(setup.prepared),
  )
  let managed_inputs = @connector.managed_fixed_compute_request_inputs(request)
  let bound = match
    @connector.bind_prepared_managed_execution(
      setup.choice,
      setup.prepared,
      setup.capacity,
      setup.join_output_ceilings,
      fn(_sequence) {
        for input in managed_inputs {
          let bridge = match
            @execution.prepare_managed_producer_bridge(
              input,
              setup.imports.max_rows,
              setup.imports.values,
              setup.imports.wire.max_nodes,
              setup.imports.wire.max_bytes,
            ) {
            Ok(value) => value
            Err(_) => return Err(@strategy.RunIssue::Compute(InputUnavailable))
          }
          bridges.push(bridge)
          reads.push(None)
        }
        let operations : @connector.ManagedExecutionOperations[
          @strategy.RunIssue,
        ] = {
          cancel: fn() {
            live.val = false
            for bridge in bridges {
              @execution.close_managed_producer_bridge(bridge)
            }
          },
          dispose: fn() {
            disposed.val = true
            live.val = false
            for bridge in bridges {
              @execution.close_managed_producer_bridge(bridge)
            }
          },
          settled: fn() { settled.val = true },
          retention_released: fn() {
            retained.val is None ||
            retained.val
            .map(value => {
              @execution.managed_retained_output_payload(value) is None
            })
            .unwrap()
          },
          released: fn() { () },
          ready: fn() {
            if live.val && settled.val && !disposed.val {
              Ok(())
            } else {
              Err(@strategy.RunIssue::NotReady)
            }
          },
        }
        Ok(((), operations))
      },
      aggregate_output_ceilings=setup.aggregate_output_ceilings,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Configuration(issue))
  }
  let execution = match
    @strategy.start_captured_managed_execution(setup.run, setup.task, bound) {
    Ok((_, value)) => value
    Err(issue) => return Err(Execution(issue))
  }
  guard @strategy.task_execution_managed_attempt(setup.run, execution)
    is Some(execution_attempt) else {
    return Err(Execution(ForeignCandidate))
  }
  let transfers = Array::makei(bridges.length(), index => {
    let bridge = bridges[index]
    LocalManagedInputTransfer::{
      input: managed_inputs[index],
      append: fn(row) {
        let bytes = match
          managed_row_transfer_bytes(row, setup.imports.wire.max_bytes) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        match
          @strategy.charge_task_execution_transfer(setup.run, execution, bytes) {
          Err(issue) => Err(Execution(Physical(issue)))
          Ok(_) =>
            @execution.append_managed_producer_bridge_wire(
              bridge,
              row,
              setup.imports.row,
            ).map_err(_ => Configuration(InputUnavailable))
        }
      },
      finish: fn() {
        match
          @execution.finish_managed_producer_bridge(
            bridge,
            setup.imports.wire.max_nodes,
            setup.imports.wire.max_bytes,
          ) {
          Ok(value) => {
            reads[index] = Some(value)
            Ok(())
          }
          Err(_) => Err(Configuration(InputUnavailable))
        }
      },
    }
  })
  let output_target = @lower.preparation_output_target(
    @lower.bound_preparation(
      @connector.managed_fixed_compute_request_owner(request),
    ),
  )
  Ok({
    inputs: transfers,
    execute: fn() {
      if !live.val || disposed.val || reads.any(value => value is None) {
        return Err(Configuration(InputUnavailable))
      }
      let exact = reads.map(value => value.unwrap())
      let output = match
        @local.execute_local_managed_fixed_compute(
          setup.choice,
          setup.prepared,
          exact,
          setup.execution,
          setup.measurement,
          join_output_ceiling=setup.join_output_ceilings.get(0),
          aggregate_output_ceilings=setup.aggregate_output_ceilings,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Configuration(issue))
      }
      let independent = match
        @execution.copy_completed_output_independent(
          output,
          setup.execution.rows.max_rows,
          setup.imports.wire.max_columns,
        ) {
        Ok(value) => value
        Err(issue) => return Err(ManagedCopy(issue))
      }
      ordinary.val = Some(independent)
      for bridge in bridges {
        @execution.close_managed_producer_bridge(bridge)
      }
      Ok(())
    },
    settle: fn() {
      @strategy.settle_task_execution(setup.run, execution, true).map_err(issue => {
        Execution(Physical(issue))
      })
    },
    complete: fn(payload, storage_bytes, available) {
      guard ordinary.val is Some(output) &&
        output_target is Some(target) &&
        storage_bytes == setup.capacity.retained_bytes &&
        available() else {
        return Err(Configuration(InvalidLimits))
      }
      let values = match
        @execution.prepare_managed_output_values(
          @connector.managed_fixed_compute_request_owner(request),
          target,
          @connector.managed_fixed_compute_request_capacity(request).max_rows,
          setup.execution.rows.output_values,
          @connector.managed_fixed_compute_request_capacity(request).max_value_bytes,
          setup.measurement,
        ) {
        Ok(value) => value
        Err(issue) => return Err(ManagedValues(issue))
      }
      let receipt_ref : Ref[@execution.ManagedOutputValueReceipt?] = Ref(None)
      let retention = match
        @execution.prepare_managed_output_retention_port(values, fn(
          proof : (@execution.ManagedOutputValueReceipt, T, Int64, () -> Bool),
        ) {
          let (receipt, proof_payload, bytes, proof_available) = proof
          if receipt_ref.val is Some(expected) &&
            physical_equal(receipt, expected) &&
            bytes == storage_bytes &&
            proof_available() &&
            available() {
            Some((receipt, proof_payload, bytes, proof_available))
          } else {
            None
          }
        }) {
        Ok(value) => value
        Err(_) => return Err(Configuration(InvalidLimits))
      }
      for row in 0..<@execution.completed_row_count(output) {
        match
          @execution.append_completed_projection_managed_wire(
            values,
            output,
            row,
            setup.imports.wire,
            setup.imports.row,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(ManagedValues(issue))
        }
      }
      let receipt = match @execution.finish_managed_output_values(values) {
        Ok(value) => value
        Err(_) => return Err(Configuration(InvalidLimits))
      }
      receipt_ref.val = Some(receipt)
      let material = match
        @execution.retain_managed_output(
          retention,
          (receipt, payload, storage_bytes, available),
        ) {
        Ok(value) => value
        Err(issue) => return Err(ManagedRetention(issue))
      }
      let completion = match
        @execution.prepare_managed_completion_port(
          @execution.selected_managed_execution_profile(),
          @execution.generated_completion_preparation(setup.sequence),
          target,
          setup.imports.wire.max_nodes,
          setup.imports.wire.max_bytes,
          fn(candidate : @execution.ManagedRetainedOutput[T]) {
            if physical_equal(candidate, material) {
              Some(material)
            } else {
              None
            }
          },
          managed_inputs~,
          obligations=@connector.managed_fixed_compute_request_obligations(
            request,
          ),
          attempt=execution_attempt,
        ) {
        Ok(value) => value
        Err(issue) => return Err(ManagedCompletion(issue))
      }
      let completed = match
        @execution.complete_managed_output(completion, material) {
        Ok(value) => value
        Err(_) => return Err(Configuration(InvalidLimits))
      }
      let allocation = match
        @strategy.retain_task_execution_allocation(
          setup.run,
          execution,
          storage_bytes,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Execution(Physical(issue)))
      }
      match
        @strategy.complete_managed_task_execution(
          setup.run,
          execution,
          completed,
          allocation~,
          managed_inputs~,
        ) {
        Err(issue) => {
          @strategy.release_task_execution_allocation(allocation) |> ignore
          Err(Execution(issue))
        }
        Ok(_) => {
          retained.val = Some(material)
          Ok(completed)
        }
      }
    },
    output_rows: fn() {
      ordinary.val.map(@execution.completed_row_count).unwrap_or(0)
    },
    output_row: fn(row) {
      guard ordinary.val is Some(output) else {
        return Err(Configuration(InputUnavailable))
      }
      @execution.completed_output_row_wire(
        output,
        row,
        setup.imports.row.max_bytes,
        setup.imports.row.max_nodes,
        setup.imports.row.max_depth,
      ).map_err(_ => Configuration(InputUnavailable))
    },
    material: fn() { retained.val },
    storage_bytes: setup.capacity.retained_bytes,
    close: fn() { @strategy.close_task_execution(setup.run, execution) },
    cleanup_refresh: fn() {
      @strategy.refresh_task_execution_cleanup(setup.run, execution).unwrap_or(
        false,
      )
    },
  })
}

///|
pub fn start_local_managed_dispatch_node(
  setup : LocalManagedDispatchConfiguration[Int],
) -> Result[LocalManagedDispatchOperations[Int], LocalDispatchIssue] {
  start_local_managed_dispatch(setup)
}
