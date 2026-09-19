///|
/// Local connector inventory: preparation, receiving admission, computation, retained
/// output, cleanup. The existing driver still enforces selected fragment limits.
pub fn local_fixed_compute_candidate(
  registration : @connector.CapabilityRegistration,
  request : @connector.FixedComputeRequest,
  sequence : @execution.GeneratedSequence,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : @connector.QueryQuantities,
  max_entries : Int,
) -> Result[
  @connector.PreparedCompute[@execution.GeneratedSequence],
  @connector.FixedComputeIssue,
] {
  if @connector.fixed_compute_request_capacity(request).common_fragment
    is Some(common) &&
    !@execution.generated_satisfies_requirements(sequence, common) {
    return Err(ForeignPreparation)
  }
  if !physical_equal(
      @execution.generated_sequence_owner(sequence),
      @connector.fixed_compute_request_owner(request),
    ) {
    return Err(ForeignPreparation)
  }
  @connector.bind_compute_candidate(
    registration, request, sequence, 5, estimates, quantities, max_entries,
  )
}

///|
/// Initial managed Local candidate. It reuses the installed checked sequence
/// and accepts the finite select/filter/derive/sort/take surface under the
/// CID-free managed profile. Identity establishment is a separate registered
/// reference capability in this milestone.
pub fn[T] local_managed_fixed_compute_candidate(
  registration : @connector.CapabilityRegistration,
  request : @connector.ManagedFixedComputeRequest[T],
  sequence : @execution.GeneratedSequence,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : @connector.QueryQuantities,
  max_entries : Int,
) -> Result[
  @connector.PreparedManagedCompute[T, @execution.GeneratedSequence],
  @connector.FixedComputeIssue,
] {
  if !local_managed_sequence_supported(sequence) {
    return Err(UnsupportedInputShape)
  }
  if @execution.managed_obligations_require_logical_identity(
      @connector.managed_fixed_compute_request_obligations(request),
    ) {
    return Err(LogicalIdentityUnsupported)
  }
  if @connector.managed_fixed_compute_request_capacity(request).common_fragment
    is Some(common) &&
    !@execution.generated_satisfies_requirements(sequence, common) {
    return Err(ForeignPreparation)
  }
  if !physical_equal(
      @execution.generated_sequence_owner(sequence),
      @connector.managed_fixed_compute_request_owner(request),
    ) {
    return Err(ForeignPreparation)
  }
  let numeric_reductions = if local_managed_sequence_requires_numeric(sequence) {
    let profile = @numeric.builtin_profile()
    [
      @connector.numeric_reduction_support(
        @numeric.cid(profile),
        @numeric.member_cid_at(profile, 0).unwrap(),
      ).unwrap(),
    ]
  } else {
    []
  }
  @connector.bind_managed_compute_candidate(
    registration,
    request,
    sequence,
    5,
    estimates,
    quantities,
    max_entries,
    numeric_reductions~,
  )
}

///|
fn local_managed_sequence_requires_numeric(
  sequence : @execution.GeneratedSequence,
) -> Bool {
  let mut required = false
  @execution.generated_sequence_all_steps(sequence, fn(step) {
    match step {
      @lower.RowStep(kernel) =>
        match @lower.kernel_group(kernel) {
          None => {
            match @lower.kernel_analytic(kernel) {
              Some(analytic) =>
                if !@execution.analytic_execution_supported(analytic) &&
                  @execution.analytic_execution_supported_with_numeric(analytic) {
                  required = true
                }
              None => ()
            }
            match @lower.kernel_pivot(kernel) {
              Some(pivot) =>
                if !@execution.pivot_execution_supported(pivot) &&
                  @execution.pivot_execution_supported_with_numeric(pivot) {
                  required = true
                }
              None => ()
            }
          }
          Some(group) =>
            for index in 0..<@lower.group_aggregate_count(group) {
              if @lower.group_aggregate_requires_numeric_observation(
                  @lower.group_aggregate_at(group, index).unwrap(),
                ) {
                required = true
              }
            }
        }
      _ => ()
    }
    true
  })
  |> ignore
  required
}

///|
/// Finite Local capability over common checked row kernels. Adding a new
/// lowering or evaluator body cannot broaden Local selection implicitly.
pub fn local_managed_sequence_supported(
  sequence : @execution.GeneratedSequence,
) -> Bool {
  @execution.generated_sequence_all_steps(sequence, fn(step) {
    match step {
      @lower.ValuesStep(_) => true
      @lower.WindowStep(_) => true
      @lower.RowStep(kernel) =>
        match @lower.kernel_body(kernel) {
          SnapshotMap(_)
          | OrderedBindings(_)
          | Filter(_)
          | AssertAll(_)
          | AssertUnique(_)
          | JsonPick(_, _, _)
          | Select(_)
          | Limit(_, _, _)
          | TopK(_, _)
          | PartitionedTopK(_, _)
          | Unnest(_, _, _, _, _)
          | Unpivot(_, _, _, _)
          | StableSort(_)
          | Lag(_, _)
          | Watermark(_, _, _, _)
          | DistinctRows
          | DedupeRows
          | CountGroups(_) => true
          Groups(group) =>
            @execution.group_execution_supported_with_numeric(group)
          AnalyticRows(analytic) =>
            @execution.analytic_execution_supported_with_numeric(analytic)
          Pivot(pivot) =>
            @execution.pivot_execution_supported_with_numeric(pivot)
        }
      @lower.AppendStep(_) => true
      @lower.SetStep(_) => true
      @lower.CrossJoinStep(_) => true
      @lower.JoinStep(_) => true
      @lower.NestStep(_) => true
      @lower.GraphBasicStep(_) => false
      @lower.GraphStructuralStep(_) => false
      @lower.GraphUnionStep(_) => false
      @lower.GraphMeanStep(_) => false
      @lower.GraphRelationStep(_) => false
    }
  })
}

///|
/// Execute the same checked Local evaluator after registered representation
/// providers have produced scoped ordinary reads for every managed input.
pub fn[T] execute_local_managed_fixed_compute(
  choice : @connector.ManagedFixedComputeChoice[T],
  prepared : @connector.PreparedManagedCompute[T, @execution.GeneratedSequence],
  inputs : Array[@execution.ProducerRead],
  limits : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  join_output_ceilings? : Array[(Int, Int64)] = [],
  aggregate_output_ceilings? : Array[@connector.AggregateOutputCeiling] = [],
  analytic_envelopes? : Array[@connector.AnalyticEnvelope] = [],
  numeric? : @execution.NumericAggregateExecution? = None,
) -> Result[@execution.CompletedOutput, @connector.FixedComputeIssue] {
  guard @connector.managed_fixed_compute_choice_payload(choice, prepared)
    is Some(sequence) else {
    return Err(NotSelected)
  }
  let request = @connector.managed_fixed_compute_candidate_request(
    @connector.prepared_managed_compute_candidate(prepared),
  )
  let managed = @connector.managed_fixed_compute_request_inputs(request)
  if managed.length() != inputs.length() {
    return Err(UnsupportedInputShape)
  }
  for index, input in inputs {
    if !physical_equal(
        @execution.producer_read_receiver(input),
        @execution.managed_producer_read_receiver(managed[index]),
      ) ||
      @execution.producer_read_input_index(input) != index ||
      !@execution.producer_read_available(input) {
      return Err(ForeignPreparation)
    }
  }
  let mut constrained = sequence
  if numeric is Some(execution) {
    constrained = @execution.bind_generated_numeric_execution(
      constrained, execution,
    )
  }
  for (step, ceiling) in join_output_ceilings {
    constrained = match
      @execution.constrain_generated_join_output(constrained, step, ceiling) {
      Ok(value) => value
      Err(issue) => return Err(Execution(issue))
    }
  }
  for ceiling in aggregate_output_ceilings {
    let unit = match @connector.aggregate_output_ceiling_unit(ceiling) {
      @connector.ArrayItems => @execution.array_items_output_unit()
      @connector.StringBytes => @execution.string_bytes_output_unit()
      @connector.NestGroupedBytes => @execution.nest_grouped_bytes_output_unit()
      @connector.NestAttachedBytes =>
        @execution.nest_attached_bytes_output_unit()
    }
    constrained = match
      @execution.constrain_generated_aggregate_output(
        constrained,
        @connector.aggregate_output_ceiling_step(ceiling),
        @connector.aggregate_output_ceiling_name(ceiling),
        unit,
        @connector.aggregate_output_ceiling_maximum(ceiling),
      ) {
      Ok(value) => value
      Err(issue) => return Err(Execution(issue))
    }
  }
  for envelope in analytic_envelopes {
    constrained = match
      @execution.constrain_generated_analytic_envelope(
        constrained,
        @connector.analytic_envelope_step(envelope),
        @connector.analytic_envelope_input_wire_bytes(envelope),
        @connector.analytic_envelope_output_wire_bytes(envelope),
        @connector.analytic_envelope_partition_wire_bytes(envelope),
        @connector.analytic_envelope_frame_memberships(envelope),
        @connector.analytic_envelope_output_rows(envelope),
      ) {
      Ok(value) => value
      Err(issue) => return Err(Execution(issue))
    }
  }
  guard @lower.preparation_output_target(
      @lower.bound_preparation(
        @connector.managed_fixed_compute_request_owner(request),
      ),
    )
    is Some(target) else {
    return Err(UnsupportedInputShape)
  }
  match
    @execution.execute_fixed_producers_guarded(
      constrained,
      inputs,
      target,
      limits,
      max_rows=@connector.managed_fixed_compute_request_capacity(request).max_rows,
      max_value_bytes=@connector.managed_fixed_compute_request_capacity(request).max_value_bytes,
      measurement,
    ) {
    Err(issue) =>
      Err(
        match issue {
          Execution(failure) => Execution(failure)
          _ => Guard(issue)
        },
      )
    Ok(completed) =>
      match @execution.completed_output(completed, target) {
        Some(output) => Ok(output)
        None => Err(UnsupportedInputShape)
      }
  }
}

///|
/// Prepare this connector's execution and capacity without running admission or
/// calculation. The common task driver owns reservation and success publication.
pub fn prepare_local_compute_execution(
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[@execution.GeneratedSequence],
  limits : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  join_output_ceiling? : (Int, Int64)? = None,
  join_output_ceilings? : Array[(Int, Int64)] = [],
) -> Result[@connector.SynchronousCompute, @connector.FixedComputeIssue] {
  guard @connector.fixed_compute_choice_payload(choice, prepared)
    is Some(sequence) else {
    return Err(NotSelected)
  }
  guard @execution.generated_sequence_capacity(sequence, limits, measurement)
    is Some(capacity) else {
    return Err(InvalidLimits)
  }
  let request = @connector.fixed_compute_candidate_request(
    @connector.prepared_compute_candidate(prepared),
  )
  guard @lower.preparation_output_target(
      @lower.bound_preparation(@connector.fixed_compute_request_owner(request)),
    )
    is Some(target) else {
    return Err(UnsupportedInputShape)
  }
  let ceilings = join_output_ceilings.copy()
  if join_output_ceiling is Some(ceiling) {
    ceilings.push(ceiling)
  }
  @connector.bind_synchronous_compute(
    choice,
    prepared,
    {
      retained_bytes: capacity.retained_bytes,
      execution_bytes: capacity.execution_bytes,
    },
    ceilings,
    fn(_sequence) {
      match
        execute_local_fixed_compute(
          choice,
          prepared,
          limits,
          measurement~,
          join_output_ceilings=ceilings,
        ) {
        Err(issue) => Err(Compute(issue))
        Ok(completed) =>
          match @execution.completed_output(completed, target) {
            Some(output) => Ok(output)
            None => Err(MissingOutput)
          }
      }
    },
  )
}

///|
pub fn execute_local_fixed_compute(
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[@execution.GeneratedSequence],
  limits : @execution.SequenceExecutionLimits,
  measurement~ : @execution.FixedInputGuardMeasureLimits,
  join_output_ceiling? : (Int, Int64)? = None,
  join_output_ceilings? : Array[(Int, Int64)] = [],
  representations? : Array[@execution.CompletedOutput?],
) -> Result[@execution.CompletedSequence, @connector.FixedComputeIssue] {
  guard @connector.fixed_compute_choice_payload(choice, prepared)
    is Some(sequence) else {
    return Err(NotSelected)
  }
  let request = @connector.fixed_compute_candidate_request(
    @connector.prepared_compute_candidate(prepared),
  )
  let ceilings = join_output_ceilings.copy()
  if join_output_ceiling is Some(ceiling) {
    ceilings.push(ceiling)
  }
  let mut sequence = sequence
  for (step, ceiling) in ceilings {
    sequence = match
      @execution.constrain_generated_join_output(sequence, step, ceiling) {
      Ok(value) => value
      Err(issue) => return Err(Execution(issue))
    }
  }
  guard @lower.preparation_output_target(
      @lower.bound_preparation(@connector.fixed_compute_request_owner(request)),
    )
    is Some(target) else {
    return Err(UnsupportedInputShape)
  }
  let inputs = @connector.fixed_compute_request_inputs(request)
  if representations is Some(copies) {
    if copies.length() != inputs.length() {
      return Err(UnsupportedInputShape)
    }
    for index, copy in copies {
      if copy is Some(output) {
        match @execution.rebind_producer_representation(inputs[index], output) {
          Ok(read) => inputs[index] = read
          Err(_) => return Err(ForeignPreparation)
        }
      }
    }
  }
  @execution.execute_fixed_producers_guarded(
    sequence,
    inputs,
    target,
    limits,
    max_rows=@connector.fixed_compute_request_capacity(request).max_rows,
    max_value_bytes=@connector.fixed_compute_request_capacity(request).max_value_bytes,
    measurement,
  ).map_err(issue => {
    match issue {
      Execution(failure) => @connector.FixedComputeIssue::Execution(failure)
      _ => Guard(issue)
    }
  })
}
