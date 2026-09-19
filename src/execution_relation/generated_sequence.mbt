///|
/// Owned internal composition of generated, checked fragments. This is not a
/// Program permission token or an entry for externally supplied AoA JSON.
struct GeneratedSequence {
  contracts : RegisteredRelationContracts
  sequence : @lower.PreparedSequence
  contexts : Array[FragmentRuntimeContext]
  retained_ids : Array[String]
  join_ceilings : Array[(Int, Int64)]
  aggregate_outputs : Array[SelectedAggregateOutput]
  analytic_envelopes : Array[SelectedAnalyticEnvelope]
  nest_item_ceilings : Array[(Int, Int64)]
  nest_grouped_byte_ceilings : Array[(Int, Int64)]
  nest_attached_byte_ceilings : Array[(Int, Int64)]
  numeric : NumericAggregateExecution?
}

///|
/// Immutable quantities, never counters shared between invocations.
pub(all) struct SequenceExecutionLimits {
  rows : SequenceRunLimits
  max_work : Int
  max_frames : Int
}

///|
fn selected_join_ceiling_at(
  ceilings : Array[(Int, Int64)],
  step : Int,
) -> (Int, Int64)? {
  let mut selected : Int64? = None
  for (candidate, maximum) in ceilings {
    if candidate == step {
      selected = Some(
        match selected {
          Some(prior) => Int64::min(prior, maximum)
          None => maximum
        },
      )
    }
  }
  selected.map(maximum => (step, maximum))
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
        join_ceilings: [],
        aggregate_outputs: [],
        analytic_envelopes: [],
        nest_item_ceilings: [],
        nest_grouped_byte_ceilings: [],
        nest_attached_byte_ceilings: [],
        numeric: None,
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
    join_ceilings=generated.join_ceilings,
    aggregate_outputs=generated.aggregate_outputs,
    analytic_envelopes=generated.analytic_envelopes,
    nest_item_ceilings=generated.nest_item_ceilings,
    nest_grouped_byte_ceilings=generated.nest_grouped_byte_ceilings,
    nest_attached_byte_ceilings=generated.nest_attached_byte_ceilings,
    numeric=generated.numeric,
  )
}

///|
/// Narrow one exact nest array occurrence. Repeated selection cannot weaken
/// an authored guard or an earlier selected ceiling.
pub fn constrain_generated_nest_items(
  generated : GeneratedSequence,
  step : Int,
  maximum : Int64,
) -> Result[GeneratedSequence, SequenceRunIssue] {
  if maximum < 0L {
    return Err(InvalidLimits)
  }
  guard @lower.sequence_step(generated.sequence, step)
    is Some(@lower.NestStep(kernel)) else {
    return Err(InputSet)
  }
  if @lower.nest_kernel_item_limit(kernel) is Some(authored) &&
    maximum > authored {
    return Err(InputSet)
  }
  let ceilings = generated.nest_item_ceilings.copy()
  for index, (prior_step, prior) in ceilings {
    if prior_step == step {
      ceilings[index] = (step, Int64::min(prior, maximum))
      return Ok({ ..generated, nest_item_ceilings: ceilings, })
    }
  }
  ceilings.push((step, maximum))
  Ok({ ..generated, nest_item_ceilings: ceilings, })
}

///|
/// Attach one attempt-local numeric executor without changing checked meaning,
/// input ownership, selected ceilings, or any other execution constraint.
pub fn bind_generated_numeric_execution(
  generated : GeneratedSequence,
  numeric : NumericAggregateExecution,
) -> GeneratedSequence {
  { ..generated, numeric: Some(numeric), }
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
  let ceilings = generated.join_ceilings.copy()
  let mut replaced = false
  for index, (prior_step, prior) in ceilings {
    if prior_step == step {
      ceilings[index] = (step, Int64::min(prior, ceiling))
      replaced = true
      break
    }
  }
  if !replaced {
    ceilings.push((step, ceiling))
  }
  Ok({ ..generated, join_ceilings: ceilings, })
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
  guard @lower.sequence_step(generated.sequence, step) is Some(prepared) else {
    return Err(InputSet)
  }
  if prepared is @lower.NestStep(kernel) {
    if aggregate != @lower.nest_kernel_into(kernel) {
      return Err(InputSet)
    }
    let ceilings = match unit {
      ArrayItems => generated.nest_item_ceilings.copy()
      NestGroupedBytes => generated.nest_grouped_byte_ceilings.copy()
      NestAttachedBytes => generated.nest_attached_byte_ceilings.copy()
      StringBytes => return Err(InputSet)
    }
    if unit == ArrayItems &&
      @lower.nest_kernel_item_limit(kernel) is Some(authored) &&
      maximum > authored {
      return Err(InputSet)
    }
    for (prior_step, _) in ceilings {
      if prior_step == step {
        return Err(InputSet)
      }
    }
    ceilings.push((step, maximum))
    return Ok(
      match unit {
        ArrayItems => { ..generated, nest_item_ceilings: ceilings, }
        NestGroupedBytes =>
          { ..generated, nest_grouped_byte_ceilings: ceilings, }
        NestAttachedBytes =>
          { ..generated, nest_attached_byte_ceilings: ceilings, }
        StringBytes => return Err(InputSet)
      },
    )
  }
  guard prepared is @lower.RowStep(kernel) else { return Err(InputSet) }
  let mut matched : @lower.PreparedAggregate? = None
  match @lower.kernel_group(kernel) {
    Some(group) =>
      for index in 0..<@lower.group_aggregate_count(group) {
        let candidate = @lower.group_aggregate_at(group, index).unwrap()
        if @lower.group_aggregate_name(candidate) == aggregate {
          if matched is Some(_) {
            return Err(InputSet)
          }
          matched = Some(candidate)
        }
      }
    None =>
      match @lower.kernel_analytic(kernel) {
        Some(analytic) =>
          for index in 0..<@lower.analytic_call_count(analytic) {
            let call = @lower.analytic_call_at(analytic, index).unwrap()
            if @lower.analytic_call_name(call) == aggregate {
              guard @lower.analytic_call_function(call)
                is @lower.PreparedFrameAggregate(candidate) else {
                return Err(InputSet)
              }
              if matched is Some(_) {
                return Err(InputSet)
              }
              matched = Some(candidate)
            }
          }
        None => return Err(InputSet)
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
/// Narrow one exact analytic operation. All scopes remain distinct and none
/// can be substituted by the request's general row or value ceilings.
pub fn constrain_generated_analytic_envelope(
  generated : GeneratedSequence,
  step : Int,
  input_wire_bytes : Int64,
  output_wire_bytes : Int64,
  partition_wire_bytes : Int64,
  frame_memberships : Int64,
  output_rows : Int64,
) -> Result[GeneratedSequence, SequenceRunIssue] {
  if step < 0 ||
    input_wire_bytes < 0L ||
    output_wire_bytes < 0L ||
    partition_wire_bytes < 0L ||
    frame_memberships < 0L ||
    output_rows < 0L {
    return Err(InvalidLimits)
  }
  guard @lower.sequence_step(generated.sequence, step)
    is Some(@lower.RowStep(kernel)) &&
    @lower.kernel_analytic(kernel) is Some(_) else {
    return Err(InputSet)
  }
  for prior in generated.analytic_envelopes {
    if prior.step == step {
      return Err(InputSet)
    }
  }
  let analytic_envelopes = generated.analytic_envelopes.copy()
  analytic_envelopes.push({
    step,
    input_wire_bytes,
    output_wire_bytes,
    partition_wire_bytes,
    frame_memberships,
    output_rows,
  })
  Ok({ ..generated, analytic_envelopes, })
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
      | @lower.SetStep(_)
      | @lower.NestStep(_)
      | @lower.GraphStructuralStep(_)
      | @lower.GraphUnionStep(_) => false
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
