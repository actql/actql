///|
/// Owned internal composition of generated, checked fragments. This is not a
/// Program permission token or an entry for externally supplied AoA JSON.
struct GeneratedSequence {
  contracts : RegisteredRelationContracts
  sequence : @lower.PreparedSequence
  contexts : Array[FragmentRuntimeContext]
  retained_ids : Array[String]
  join_ceiling : (Int, Int64)?
  aggregate_outputs : Array[SelectedAggregateOutput]
}

///|
/// Immutable quantities, never counters shared between invocations.
pub(all) struct SequenceExecutionLimits {
  rows : SequenceRunLimits
  max_work : Int
  max_frames : Int
}

///|
pub fn prepare_generated_sequence(
  contracts : RegisteredRelationContracts,
  sequence : @lower.PreparedSequence,
  contexts : Array[FragmentRuntimeContext],
  retained_ids : Array[String],
  max_work : Int,
  max_entries : Int,
) -> Result[GeneratedSequence, SequenceRunIssue] {
  if max_work < 0 || max_entries < 0 {
    return Err(InvalidLimits)
  }
  let control = { remaining: max_work, max_frames: 0, }
  let workspace = { limit: max_entries, live: 0, peak: 0, }
  match
    prepare_wiring(
      @lower.sequence_owner(sequence),
      retained_ids,
      control,
      workspace,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Wiring(issue))
  }
  // Wiring requires a fresh workspace; its retained allocation remains charged
  // while the owned containers and context preflight are allocated afterward.
  if !reserve_slots(workspace, contexts.length()) ||
    !reserve_slots(workspace, retained_ids.length()) ||
    !spend_control(control, contexts.length()) ||
    !spend_control(control, retained_ids.length()) {
    return Err(InputLimit)
  }
  let contexts = contexts.copy()
  let retained_ids = retained_ids.copy()
  match
    attach_fragment_budgets(
      contracts,
      sequence,
      contexts,
      Map([]),
      control,
      workspace,
    ) {
    Ok(_) =>
      Ok({
        contracts,
        sequence,
        contexts,
        retained_ids,
        join_ceiling: None,
        aggregate_outputs: [],
      })
    Err(issue) => Err(issue)
  }
}

///|
/// There is deliberately no component-mode switch and no separate ordered
/// configuration. Input obligations remain checked by the sole sequence driver.
pub fn execute_generated_sequence(
  generated : GeneratedSequence,
  supplied : Array[CapturedRows],
  limits : SequenceExecutionLimits,
  produced? : Array[BoundProducerInput] = [],
) -> Result[CompletedSequence, SequenceRunIssue] {
  evaluate_sequence_components(
    generated.contracts,
    generated.sequence,
    supplied,
    generated.retained_ids,
    limits.rows,
    { remaining: limits.max_work, max_frames: limits.max_frames, },
    produced~,
    fragments=Some(generated.contexts),
    join_ceiling=generated.join_ceiling,
    aggregate_outputs=generated.aggregate_outputs,
  )
}

///|
/// Narrow one join's output only. Input admission, other operations and checked
/// identities are unchanged. Repeated application cannot weaken the ceiling.
pub fn constrain_generated_join_output(
  generated : GeneratedSequence,
  step : Int,
  ceiling : Int64,
) -> Result[GeneratedSequence, SequenceRunIssue] {
  if ceiling < 0L {
    return Err(InvalidLimits)
  }
  guard @lower.sequence_step(generated.sequence, step) is Some(value) &&
    (value is @lower.JoinStep(_) || value is @lower.CrossJoinStep(_)) else {
    return Err(InputSet)
  }
  let ceiling = match generated.join_ceiling {
    None => ceiling
    Some((prior_step, prior)) => {
      if prior_step != step {
        return Err(InputSet)
      }
      Int64::min(prior, ceiling)
    }
  }
  Ok({ ..generated, join_ceiling: Some((step, ceiling)), })
}

///|
/// Narrow one exact collection aggregate. A selected limit may strengthen an
/// authored guard but cannot weaken it or apply to another aggregate unit.
pub fn constrain_generated_aggregate_output(
  generated : GeneratedSequence,
  step : Int,
  aggregate : String,
  unit : AggregateOutputUnit,
  maximum : Int64,
) -> Result[GeneratedSequence, SequenceRunIssue] {
  if maximum < 0L {
    return Err(InvalidLimits)
  }
  guard @lower.sequence_step(generated.sequence, step)
    is Some(@lower.RowStep(kernel)) &&
    @lower.kernel_group(kernel) is Some(group) else {
    return Err(InputSet)
  }
  let mut matched : @lower.PreparedAggregate? = None
  for index in 0..<@lower.group_aggregate_count(group) {
    let candidate = @lower.group_aggregate_at(group, index).unwrap()
    if @lower.group_aggregate_name(candidate) == aggregate {
      if matched is Some(_) {
        return Err(InputSet)
      }
      matched = Some(candidate)
    }
  }
  guard matched is Some(candidate) && aggregate_output_matches(candidate, unit) else {
    return Err(InputSet)
  }
  if authored_aggregate_output_limit(candidate, unit) is Some(authored) &&
    maximum > authored {
    return Err(InputSet)
  }
  for prior in generated.aggregate_outputs {
    if prior.step == step && prior.aggregate == aggregate && prior.unit == unit {
      return Err(InputSet)
    }
  }
  let aggregate_outputs = generated.aggregate_outputs.copy()
  aggregate_outputs.push({ step, aggregate, unit, maximum, })
  Ok({ ..generated, aggregate_outputs, })
}

///|
/// Read-only access to the exact owner of this prepared execution.
pub fn generated_sequence_owner(
  generated : GeneratedSequence,
) -> @lower.BoundPrepared {
  @lower.sequence_owner(generated.sequence)
}

///|
pub fn generated_retained_count(generated : GeneratedSequence) -> Int {
  generated.retained_ids.length()
}

///|
/// Finite Local-managed support predicate. It recognizes only a non-empty
/// sequence of checked projection kernels; adding another operation never
/// silently broadens this initial product connection.
pub fn generated_sequence_is_projection_only(
  generated : GeneratedSequence,
) -> Bool {
  generated_sequence_all_row_kernels(generated, fn(body) {
    body is @lower.Select(_)
  })
}

///|
/// Allocation-free typed capability inspection. It never exposes the owned
/// sequence, and rejects values, joins, or an empty sequence before invoking
/// the caller's finite body predicate.
pub fn generated_sequence_all_row_kernels(
  generated : GeneratedSequence,
  accepts : (@lower.KernelBody) -> Bool,
) -> Bool {
  generated_sequence_all_steps(generated, fn(step) {
    match step {
      @lower.RowStep(kernel) => accepts(@lower.kernel_body(kernel))
      @lower.ValuesStep(_)
      | @lower.WindowStep(_)
      | @lower.JoinStep(_)
      | @lower.CrossJoinStep(_)
      | @lower.AppendStep(_)
      | @lower.SetStep(_) => false
    }
  })
}

///|
/// Allocation-free typed capability inspection over the prepared step view.
/// The owned sequence and its mutable construction arrays never escape.
pub fn generated_sequence_all_steps(
  generated : GeneratedSequence,
  accepts : (@lower.PreparedStep) -> Bool,
) -> Bool {
  let count = @lower.sequence_count(generated.sequence)
  if count == 0 {
    return false
  }
  for index in 0..<count {
    guard @lower.sequence_step(generated.sequence, index) is Some(step) &&
      accepts(step) else {
      return false
    }
  }
  true
}

///|
/// Bounded, non-copying inspection; never exposes the retained array.
pub fn generated_retained_at(
  generated : GeneratedSequence,
  index : Int,
) -> String? {
  if index < 0 || index >= generated.retained_ids.length() {
    None
  } else {
    Some(generated.retained_ids[index])
  }
}
