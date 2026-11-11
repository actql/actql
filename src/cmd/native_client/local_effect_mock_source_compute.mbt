///|
// A borrowed provider child on the SAME Model Read, never another resource
// owner or Run. Its real cleanup must precede Source/Read retirement.
priv struct LocalNativeMockModelRoot {
  task : Int
  sequence : @execution.GeneratedSequence
  inputs : Array[@local_compute.ManagedProviderInput]
  bindings : Array[(Int, Int, @execution.ProducerRead)]
  mut child : @local_compute.ManagedProviderExecution?
  mut output : @execution.CompletedOutput?
  mut completed : @execution.CompletedSegmentInputs?
}

///|
fn[T] Result::native_model_source_compute(
  self : Result[T, @compute_sdk.FixedComputeIssue],
  original : LocalCommandPreparationOriginal,
) -> T raise ClientStop {
  match self {
    Ok(value) => value
    Err(issue) => {
      original.retain_primary(
        CommandBusinessModel(
          @local_host.Model(@infer.Input(@local_values.Local(issue))),
        ),
      )
      stop("LocalOriginalModelSourceComputeUnavailable")
    }
  }
}

///|
// Run the original checked Source SELECT tasks once, then bind their genuine
// Results to the Model receiver. Raw Source rows cannot stand in for a Result.
fn LocalCommandBusinessPreparation::prepare_mock_model_source_results(
  self : Self,
  state : LocalNativeMockEffectPlan,
  plan : @local_values.ClientInstalledEffectManagedPlan,
  work : @local_host.NativeClientMockModelWork,
) -> Array[@local_compute.ManagedProviderInput] raise ClientStop {
  let held = state.model_read.unwrap_or_else(() => {
    stop("LocalOriginalModelSourceComputeUnavailable")
  })
  let limits = state.first._retained_models[0]._retained_limits
  for index, captured in state.captured_inputs {
    self.original.with_business_request(self.capture, () => {
      let source = @row_host.row_captured_input_source(captured).unwrap()
      let (task, sequence) = @local_values.prepared_installed_effect_source_sequence(
        plan, index,
      ).unwrap_or_else(() => stop("LocalOriginalModelSourceComputeUnavailable"))
      let execution = {
        ..limits.input,
        max_work: limits.input.max_work - held.root_work.to_int(),
      }
      guard @local_compute.local_bounded_relation_provider(
          execution,
          limits.measurement,
          sequence,
        )
        is Some(provider) &&
        @local_compute.managed_provider_capacity(provider, sequence)
        is Some(capacity) &&
        @local_values.client_composed_source_root_control_bytes(sequence)
        is Some(controls) else {
        stop("LocalOriginalModelSourceComputeUnavailable")
      }
      let retained = @execution.checked_preparation_add_product(
          held.retained,
          controls,
          1L,
        )
        .bind(base => {
          @execution.checked_preparation_add_product(
            base,
            @execution.execution_capacity_retained_bytes(capacity),
            1L,
          )
        })
        .unwrap_or_else(() => stop("LocalOriginalModelSourceComputeUnavailable"))
      let peak = @execution.checked_preparation_add_product(
          held.execution,
          controls,
          1L,
        )
        .bind(base => {
          @execution.checked_preparation_add_product(
            base,
            @execution.execution_capacity_execution_bytes(capacity),
            1L,
          )
        })
        .unwrap_or_else(() => stop("LocalOriginalModelSourceComputeUnavailable"))
      held.grow(state, retained, peak, self.original)
      let root : LocalNativeMockModelRoot = {
        task,
        sequence,
        inputs: [],
        bindings: [],
        child: None,
        output: None,
        completed: None,
      }
      held.roots.push(root)
      let owner = @execution.generated_sequence_owner(sequence)
      for position in 0..<@execution.generated_sequence_step_count(sequence) {
        let step = @execution.generated_sequence_step_index_at(
          sequence, position,
        ).unwrap()
        let node = @test_lower.node_at(
          @test_lower.bound_preparation(owner),
          step,
        ).unwrap()
        for port in 0..<@test_lower.node_input_count(node) {
          if @test_lower.node_input_target(node, port)
            is Some(@pipeline.Step(previous)) &&
            previous < step {
            continue
          }
          let bound = @query.bind_captured_source_operation(
            source, owner, step, port,
          ).unwrap_or_else(() => {
            stop("LocalOriginalModelSourceComputeUnavailable")
          })
          let read = @execution.prepare_producer_read(
            owner,
            bound,
            limits.input.rows.operation_entries,
            limits.measurement.max_bytes,
          ).unwrap_or_else(() => {
            stop("LocalOriginalModelSourceComputeUnavailable")
          })
          root.bindings.push((step, port, read))
          root.inputs.push(@local_compute.managed_provider_relation_input(read))
        }
      }
      let child = @local_compute.start_managed_provider_with_inputs_and_execution(
        provider,
        sequence,
        root.inputs,
        execution.rows.max_rows,
        limits.measurement.max_bytes,
        execution,
      ).native_model_source_compute(self.original)
      root.child = Some(child)
    })
    let root = held.roots[index]
    let child = root.child.unwrap()
    let mut done = false
    while !done {
      match work.observe_step_in_original_read() {
        Ok(_) => ()
        Err(issue) => {
          self.original.retain_primary(CommandBusinessModel(issue))
          stop("LocalOriginalModelSourceComputeUnavailable")
        }
      }
      let poll = self.original.with_business_request(self.capture, () => {
        let poll = @local_compute.advance_managed_provider(child, 31).native_model_source_compute(
          self.original,
        )
        if poll is @local_compute.Complete(output, ..) {
          root.output = Some(output)
          root.completed = Some(
            @execution.retain_completed_segment_inputs(
              root.output.unwrap(),
              root.sequence,
              root.bindings,
              limits.output_work,
            ).unwrap_or_else(() => {
              stop("LocalOriginalModelSourceComputeUnavailable")
            }),
          )
          let used = @local_compute.managed_provider_cumulative_work(child).unwrap_or_else(() => {
              stop("LocalOriginalModelSourceComputeUnavailable")
            },
          )
          if used < 0L ||
            used > limits.input.max_work.to_int64() - held.root_work {
            stop("LocalOriginalModelSourceComputeUnavailable")
          }
          held.root_work += used
        }
        poll
      })
      match poll {
        @local_compute.Complete(_, ..) => done = true
        @local_compute.Continue(..)
        | @local_compute.Settling(_, ..)
        | @local_compute.Waiting(..) => ()
        @local_compute.Failed(issue, ..) =>
          Err(issue).native_model_source_compute(self.original)
        _ => stop("LocalOriginalModelSourceComputeUnavailable")
      }
    }
  }
  self.original.with_business_request(self.capture, () => {
    let model_sequence = @local_values.prepared_installed_effect_model_sequence(
      plan,
      state.graph,
    ).unwrap_or_else(() => stop("LocalOriginalModelSourceComputeUnavailable"))
    let controls = @local_values.client_composed_source_root_control_bytes(
      model_sequence,
    ).unwrap_or_else(() => stop("LocalOriginalModelSourceComputeUnavailable"))
    let retained = @execution.checked_preparation_add_product(
      held.retained,
      controls,
      1L,
    ).unwrap_or_else(() => stop("LocalOriginalModelSourceComputeUnavailable"))
    let peak = @execution.checked_preparation_add_product(
      held.execution,
      controls,
      1L,
    ).unwrap_or_else(() => stop("LocalOriginalModelSourceComputeUnavailable"))
    held.grow(state, retained, peak, self.original)
    let inputs = []
    let model_owner = @run_host.client_infer_occurrence_preparation(
      state.graph.occurrence,
    )
    let graph = @strategy.checked_effect_computation_graph(
      @run_host.prepared_client_effect_computation_graph(
        state._retained_prepared,
      ),
    )
    let (task, _, _) = @run_host.client_infer_occurrence_coordinates(
      state.graph.occurrence,
    )
    for index in 0..<@strategy.graph_data_count(graph) {
      let edge = @strategy.graph_data_at(graph, index).unwrap()
      if @strategy.data_edge_consumer(edge) != task {
        continue
      }
      let producer = @strategy.data_edge_producer(edge)
      let root = held.roots
        .iter()
        .find_first(root => root.task == producer)
        .unwrap_or_else(() => stop("LocalOriginalModelSourceComputeUnavailable"))
      let output = @execution.completed_segment_inputs_output(
        root.completed.unwrap(),
        root.sequence,
        root.bindings,
      ).unwrap_or_else(() => stop("LocalOriginalModelSourceComputeUnavailable"))
      let bound = @execution.bind_completed_input(
        model_owner,
        @strategy.data_edge_input(edge),
        @execution.generated_sequence_owner(root.sequence),
        output,
      ).unwrap_or_else(() => stop("LocalOriginalModelSourceComputeUnavailable"))
      let read = @execution.prepare_producer_read(
        model_owner,
        bound,
        limits.input.rows.operation_entries,
        limits.measurement.max_bytes,
      ).unwrap_or_else(() => stop("LocalOriginalModelSourceComputeUnavailable"))
      inputs.push(@local_compute.managed_provider_relation_input(read))
    }
    inputs
  })
}
