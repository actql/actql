///|
/// Original next-phase work, excluding completed collection and selection.
/// Counts/limits never enter from a replacement caller or reconstructed Source.
pub fn source_registration_pipeline_work_bound(
  read : SourceRegistrationRead,
) -> Int? {
  guard read.state is BuildRegistrations(resolved) &&
    read.arguments is Some(original) else {
    return None
  }
  Some(
    @sourceviews.pipeline_preparation_work_bound(
      resolved,
      original.limits.max_work,
    ),
  )
}

///|
pub fn source_registration_pipeline_quotation_extent() -> @shape.CollectionConstructionExtent {
  @sourceviews.pipeline_preparation_quotation_extent()
}

///|
// The original observation pair plus success BuildLocal1H1R1W and failure
// Registration/Err/RegistrationDone3H3R3W. Alternatives are co-counted;
// PipelineInputs/group/entry bodies come from their actual constructor quote.
let source_pipeline_driver_extent : @shape.CollectionConstructionExtent = {
  let pair = @sourceviews.pipeline_preparation_observation_control_extent()
  {
    record_headers: pair.record_headers + 4L,
    reference_slots: pair.reference_slots + 4L,
    scalar_words: pair.scalar_words + 4L,
  }
}

///|
let source_pipeline_driver_retained_extent : @shape.CollectionConstructionExtent = {
  record_headers: 1L,
  reference_slots: 1L,
  scalar_words: 1L,
}

///|
pub fn source_registration_pipeline_driver_extent() -> @shape.CollectionConstructionExtent {
  source_pipeline_driver_extent
}

///|
pub fn source_registration_pipeline_driver_retained_extent() -> @shape.CollectionConstructionExtent {
  source_pipeline_driver_retained_extent
}
