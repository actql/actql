///|
/// Common output contract for a trusted realization. Contains no evaluator
/// contexts, counters, storage or success evidence. An admitted registry and
/// owned semantic sequence do not authorize publication by themselves.
struct CompletionPreparation {
  contracts : RegisteredRelationContracts
  sequence : @lower.PreparedSequence
  retained_ids : Array[String]
  selected_step : Int?
}

///|
pub fn prepare_completion(
  contracts : RegisteredRelationContracts,
  sequence : @lower.PreparedSequence,
  retained_ids : Array[String],
  max_work : Int,
  max_entries : Int,
) -> Result[CompletionPreparation, SequenceRunIssue] {
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
    Err(issue) => return Err(Wiring(issue))
    Ok(_) => ()
  }
  if !reserve_slots(workspace, retained_ids.length()) ||
    !spend_control(control, retained_ids.length()) {
    return Err(InputLimit)
  }
  Ok({
    contracts,
    sequence,
    retained_ids: retained_ids.copy(),
    selected_step: None,
  })
}

///|
/// A read-only projection; existing Local preparation has already validated
/// and defensively copied these fields. No contexts escape into this contract.
pub fn generated_completion_preparation(
  generated : GeneratedSequence,
) -> CompletionPreparation {
  {
    contracts: generated.contracts,
    sequence: generated.sequence,
    retained_ids: generated.retained_ids,
    selected_step: match generated.selected_steps {
      Some([step]) => Some(step)
      _ => None
    },
  }
}

///|
/// Original checked coordinate selected for one internal physical task.
pub fn completion_preparation_selected_step(
  value : CompletionPreparation,
) -> Int? {
  value.selected_step
}

///|
pub fn completion_preparation_owner(
  value : CompletionPreparation,
) -> @lower.BoundPrepared {
  @lower.sequence_owner(value.sequence)
}

///|
pub fn completion_preparation_sequence(
  value : CompletionPreparation,
) -> @lower.PreparedSequence {
  value.sequence
}
