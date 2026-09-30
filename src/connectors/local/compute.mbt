///|
/// Resolve the exact physical task target without changing the checked owner.
/// A selected Step or prefix does not inherit the Stage's final output target.
fn local_fixed_task_target(
  sequence : @execution.GeneratedSequence,
  owner : @lower.BoundPrepared,
) -> @pipeline.Target? {
  let prepared = @lower.bound_preparation(owner)
  let selected_count = @execution.generated_sequence_step_count(sequence)
  if selected_count < @lower.node_count(prepared) {
    return @execution.generated_sequence_step_index_at(
      sequence,
      selected_count - 1,
    ).map(step => @pipeline.Step(step))
  }
  @lower.preparation_output_target(prepared)
}

///|
/// A retained Store file is a Relation representation. Carrier outputs keep
/// their typed managed generation instead of being relabelled as row files.
pub fn local_sequence_outputs_carrier(
  sequence : @execution.GeneratedSequence,
) -> Bool {
  let prepared = @lower.bound_preparation(
    @execution.generated_sequence_owner(sequence),
  )
  guard local_fixed_task_target(
      sequence,
      @execution.generated_sequence_owner(sequence),
    )
    is Some(target) &&
    @lower.preparation_carrier_at(prepared, target) is Some(output) else {
    return false
  }
  @carrier.kind(output) != @carrier.RelationKind
}

///|
/// A task may produce and consume a Carrier before its final Relation view.
/// Retained row files cannot represent that intermediate typed generation.
pub fn local_sequence_contains_carrier_step(
  sequence : @execution.GeneratedSequence,
) -> Bool {
  let prepared = @lower.bound_preparation(
    @execution.generated_sequence_owner(sequence),
  )
  for index in 0..<@execution.generated_sequence_step_count(sequence) {
    if @execution.generated_sequence_step_index_at(sequence, index)
      is Some(step) &&
      @lower.preparation_carrier_at(prepared, @pipeline.Step(step))
      is Some(output) &&
      @carrier.kind(output) != @carrier.RelationKind {
      return true
    }
  }
  false
}

///|
/// A Carrier input requires its typed managed view even when the output is a
/// Relation. A row-only materializing attempt cannot consume that view.
pub fn local_sequence_has_carrier_input(
  sequence : @execution.GeneratedSequence,
) -> Bool {
  let prepared = @lower.bound_preparation(
    @execution.generated_sequence_owner(sequence),
  )
  for index in 0..<@lower.preparation_input_count(prepared) {
    if @lower.preparation_input_carrier(prepared, index) is Some(input) &&
      @carrier.kind(input) != @carrier.RelationKind {
      return true
    }
  }
  false
}

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
  let numeric_reductions = local_sequence_numeric_reductions(sequence)
  @connector.bind_compute_candidate(
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
  provider_supported? : Bool = false,
) -> Result[
  @connector.PreparedManagedCompute[T, @execution.GeneratedSequence],
  @connector.FixedComputeIssue,
] {
  // Managed Local work runs only through a bounded provider.
  if !provider_supported {
    return Err(UnsupportedInputShape)
  }
  if !local_managed_identity_obligations_supported(
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
  let numeric_reductions = local_sequence_numeric_reductions(sequence)
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
fn local_sequence_numeric_reductions(
  sequence : @execution.GeneratedSequence,
) -> Array[@connector.NumericReductionSupport] {
  if local_managed_sequence_requires_numeric(sequence) {
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
}

///|
/// Local registers only the two identity implementations it can bind to the
/// exact retained Relation output. Other domains remain unsupported rather
/// than being relabelled or silently omitted.
fn local_managed_identity_obligations_supported(
  obligations : @execution.ManagedObligations,
) -> Bool {
  for requirement in @execution.managed_obligations_identities(obligations) {
    if requirement.need is @execution.EstablishedBy(_) {
      match (requirement.domain, requirement.subject, requirement.occurrence) {
        (@execution.OrderedRows, @execution.TaskOutput, None) => ()
        (@execution.LogicalRelation, @execution.NamedResult, Some(_)) => ()
        _ => return false
      }
    }
  }
  true
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
      @lower.TimeSeriesStep(_) => false
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
      @lower.IntervalJoinStep(kernel) =>
        @execution.generated_interval_search_ceiling(
          sequence,
          @lower.interval_join_step(kernel),
        )
        is Some(_)
      @lower.AsOfJoinStep(kernel) =>
        @execution.generated_asof_search_ceiling(
          sequence,
          @lower.asof_join_step(kernel),
        )
        is Some(_)
      @lower.SequenceMatchStep(_) => true
      @lower.NestStep(_) => true
      @lower.GraphBasicStep(_) => false
      @lower.GraphStructuralStep(_) => false
      @lower.GraphUnionStep(_) => false
      @lower.GraphMeanStep(_) => false
      @lower.GraphMatchStep(_) => false
      @lower.GraphReachStep(_) => false
      @lower.GraphSubgraphStep(_) => false
      @lower.GraphTraverseStep(_) => false
      @lower.GraphShortestStep(_) => false
      @lower.GraphRelationStep(_) => false
      @lower.GraphConstructionStep(_) => false
      @lower.VectorStep(_) => false
      @lower.EventStep(_) => false
      @lower.CarrierProjectionStep(_) => false
    }
  })
}

///|
/// Apply every selected task ceiling and the attempt's numeric executor to a
/// managed sequence. Bounded providers and the checked evaluator start from
/// the same constrained sequence.
pub fn constrain_local_managed_sequence(
  sequence : @execution.GeneratedSequence,
  join_output_ceilings? : Array[(Int, Int64)] = [],
  expansion_output_ceilings? : Array[(Int, Int64)] = [],
  interval_search_ceilings? : Array[(Int, Int64)] = [],
  asof_search_ceilings? : Array[(Int, Int64)] = [],
  sequence_match_ceilings? : Array[(Int, Int64, Int64)] = [],
  aggregate_output_ceilings? : Array[@connector.AggregateOutputCeiling] = [],
  analytic_envelopes? : Array[@connector.AnalyticEnvelope] = [],
  numeric? : @execution.NumericAggregateExecution? = None,
) -> Result[@execution.GeneratedSequence, @connector.FixedComputeIssue] {
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
  for (step, ceiling) in expansion_output_ceilings {
    constrained = match
      @execution.constrain_generated_expansion_output(
        constrained, step, ceiling,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Execution(issue))
    }
  }
  for (step, ceiling) in interval_search_ceilings {
    constrained = match
      @execution.constrain_generated_interval_search(constrained, step, ceiling) {
      Ok(value) => value
      Err(issue) => return Err(Execution(issue))
    }
  }
  for (step, ceiling) in asof_search_ceilings {
    constrained = match
      @execution.constrain_generated_asof_search(constrained, step, ceiling) {
      Ok(value) => value
      Err(issue) => return Err(Execution(issue))
    }
  }
  for (step, matches, output) in sequence_match_ceilings {
    constrained = match
      @execution.constrain_generated_sequence_match_limits(
        constrained, step, matches, output,
      ) {
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
  Ok(constrained)
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
  guard local_fixed_task_target(
      sequence,
      @connector.fixed_compute_request_owner(request),
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
  execute_local_fixed_compute_with_usage(
    choice,
    prepared,
    limits,
    measurement~,
    join_output_ceiling~,
    join_output_ceilings~,
    representations?,
  ).map(value => value.0)
}

///|
/// The usage is an observation of the admitted fixed input and output guard,
/// not an estimate or an additional execution of the sequence.
pub fn execute_local_fixed_compute_with_usage(
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[@execution.GeneratedSequence],
  limits : @execution.SequenceExecutionLimits,
  measurement~ : @execution.FixedInputGuardMeasureLimits,
  join_output_ceiling? : (Int, Int64)? = None,
  join_output_ceilings? : Array[(Int, Int64)] = [],
  representations? : Array[@execution.CompletedOutput?],
) -> Result[
  (@execution.CompletedSequence, (Int, Int, Int)),
  @connector.FixedComputeIssue,
] {
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
  guard local_fixed_task_target(
      sequence,
      @connector.fixed_compute_request_owner(request),
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
  @execution.execute_fixed_producers_guarded_with_usage(
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
