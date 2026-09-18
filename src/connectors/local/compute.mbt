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
  @connector.bind_managed_compute_candidate(
    registration, request, sequence, 5, estimates, quantities, max_entries,
  )
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
          | DistinctRows
          | DedupeRows
          | CountGroups(_) => true
          Pivot(pivot) =>
            match @lower.pivot_function(pivot) {
              @relation.Count
              | @relation.Min
              | @relation.Max
              | @relation.First => true
              @relation.Sum =>
                match @relation.pivot(@lower.pivot_checked(pivot)) {
                  Some(checked) =>
                    @relation.pivot_result(checked).shape
                    is @contract.Decimal(precision=38, ..)
                  None => false
                }
              _ => false
            }
        }
      @lower.AppendStep(_) => true
      @lower.JoinStep(_) => false
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
  join_output_ceiling? : (Int, Int64)? = None,
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
  let constrained = match join_output_ceiling {
    None => sequence
    Some((step, ceiling)) =>
      match
        @execution.constrain_generated_join_output(sequence, step, ceiling) {
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
  @connector.bind_synchronous_compute(
    choice,
    prepared,
    {
      retained_bytes: capacity.retained_bytes,
      execution_bytes: capacity.execution_bytes,
    },
    match join_output_ceiling {
      None => []
      Some(ceiling) => [ceiling]
    },
    fn(_sequence) {
      match
        execute_local_fixed_compute(
          choice,
          prepared,
          limits,
          measurement~,
          join_output_ceiling~,
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
  representations? : Array[@execution.CompletedOutput?],
) -> Result[@execution.CompletedSequence, @connector.FixedComputeIssue] {
  guard @connector.fixed_compute_choice_payload(choice, prepared)
    is Some(sequence) else {
    return Err(NotSelected)
  }
  let request = @connector.fixed_compute_candidate_request(
    @connector.prepared_compute_candidate(prepared),
  )
  let sequence = match join_output_ceiling {
    None => sequence
    Some((step, ceiling)) =>
      match
        @execution.constrain_generated_join_output(sequence, step, ceiling) {
        Ok(sequence) => sequence
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
