///|
// Shared original projection for the semantic entrance and its work envelope.
// The completed pipeline prefix is not consumed a second time by Local.
fn source_registration_local_remaining_work(
  original : SourceRegistrationArguments,
  views : @sourceviews.PipelineInputs,
) -> Int {
  original.limits.max_work - @sourceviews.pipeline_inputs_work(views)
}

///|
pub fn source_registration_local_entry_work_bound(
  read : SourceRegistrationRead,
) -> Int? {
  guard read.state is BuildLocal(views) &&
    read.local_child is None &&
    read.arguments is Some(original) else {
    return None
  }
  Some(Int::max(0, source_registration_local_remaining_work(original, views)))
}

///|
/// The actual constructor observation, retained through failure/take/clear.
/// None is unstarted; no nested Index/snapshot work is included or filled in.
pub fn source_registration_local_entry_work(
  read : SourceRegistrationRead,
) -> Int? {
  read.local_initial_work
}

///|
// Original Local entrance plus selected Limits1H4W, child Some1H1R1W,
// retained work Some1H2W, bound Some1H2W and failure LocalInputs/Err/Done3H3R3W.
// The Local owner supplies its own packet and the actual result/work pair.
let source_local_entry_peak : @shape.CollectionConstructionExtent = {
  let child = @local_inputs.local_environment_preparation_initial_construction_extent()
  let observation = @local_inputs.local_environment_preparation_observation_extent()
  {
    record_headers: child.record_headers + observation.record_headers + 7L,
    reference_slots: child.reference_slots + observation.reference_slots + 4L,
    scalar_words: child.scalar_words + observation.scalar_words + 12L,
  }
}

///|
// Success keeps the original child, selected Limits, child Some and work Some.
let source_local_entry_held : @shape.CollectionConstructionExtent = {
  let child = @local_inputs.local_environment_preparation_retained_construction_extent()
  {
    record_headers: child.record_headers + 3L,
    reference_slots: child.reference_slots + 1L,
    scalar_words: child.scalar_words + 7L,
  }
}

///|
pub fn source_registration_local_entry_extent() -> @shape.CollectionConstructionExtent {
  source_local_entry_peak
}

///|
pub fn source_registration_local_entry_retained_extent() -> @shape.CollectionConstructionExtent {
  source_local_entry_held
}
