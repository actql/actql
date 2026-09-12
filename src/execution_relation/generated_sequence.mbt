///|
/// Owned internal composition of generated, checked fragments. This is not a
/// Program permission token or an entry for externally supplied AoA JSON.
priv struct GeneratedSequence {
  contracts : RegisteredRelationContracts
  sequence : @lower.PreparedSequence
  contexts : Array[FragmentRuntimeContext]
  retained_ids : Array[String]
}

///|
/// Immutable quantities, never counters shared between invocations.
priv struct SequenceExecutionLimits {
  rows : SequenceRunLimits
  max_work : Int
  max_frames : Int
}

///|
fn prepare_generated_sequence(
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
    Ok(_) => Ok({ contracts, sequence, contexts, retained_ids, })
    Err(issue) => Err(issue)
  }
}

///|
/// There is deliberately no component-mode switch and no separate ordered
/// configuration. Input obligations remain checked by the sole sequence driver.
fn execute_generated_sequence(
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
  )
}
