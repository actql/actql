///|
/// The original execution supplies its actual Model/CallScope to this existing
/// Common issuer. Byte DATA neither exports a Ledger nor grants Model dispatch.
#export_name("clientProgramReserveOriginalInferPublicationCapacity")
pub fn client_program_reserve_original_infer_publication_capacity(
  active : @infer_host.Execution,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[@model.OriginalModelPublicationCapacity, @infer_host.Issue] {
  @infer_host.reserve_original_infer_publication_capacity(
    active, retained_bytes, execution_bytes,
  )
}

///|
#export_name("clientProgramGrowOriginalInferPublicationCapacity")
pub fn client_program_grow_original_infer_publication_capacity(
  active : @infer_host.Execution,
  capacity : @model.OriginalModelPublicationCapacity,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, @infer_host.Issue] {
  @infer_host.grow_original_infer_publication_capacity(
    active, capacity, retained_bytes, execution_bytes,
  )
}

///|
/// Physical publication retirement remains the caller's responsibility. No
/// caller Bool or journal observation is used to fabricate this nominal loan.
#export_name("clientProgramReleaseOriginalInferPublicationCapacity")
pub fn client_program_release_original_infer_publication_capacity(
  capacity : @model.OriginalModelPublicationCapacity,
) -> Result[Bool, @infer_host.Issue] {
  @infer_host.release_original_infer_publication_capacity(capacity)
}

///|
#export_name("clientProgramStartOriginalInferObservationIssuance")
pub fn client_program_start_original_infer_observation_issuance(
  active : @infer_host.Execution,
  capacity : @model.OriginalModelPublicationCapacity,
  max_slots : Int,
  max_wire_bytes : Int,
  max_work : Int,
  generations : Array[@publication_host.ClientSerializationGeneration],
) -> Result[@infer_host.ObservationIssuance, @infer_host.Issue] {
  @infer_host.start_original_observation_issuance(
    active,
    capacity,
    { max_slots, max_wire_bytes, max_work, },
    generations~,
  )
}

///|
#export_name("clientProgramStartCompleteOriginalInferObservationIssuance")
pub fn client_program_start_complete_original_infer_observation_issuance(
  active : Array[@infer_host.Execution],
  capacity : @model.OriginalModelPublicationCapacity,
  max_slots : Int,
  max_wire_bytes : Int,
  max_work : Int,
  generations : Array[@publication_host.ClientSerializationGeneration],
) -> Result[@infer_host.ObservationIssuance, @infer_host.Issue] {
  @infer_host.start_complete_original_observation_issuance(
    active,
    capacity,
    { max_slots, max_wire_bytes, max_work, },
    generations~,
  )
}
