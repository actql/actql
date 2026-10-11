///|
// Private installed adapter ports. These observations neither enable an async
// profile nor grant transport authority; the original Model owner does both.
#export_name("clientProgramBindInferModelEntryPersistence")
pub fn client_program_bind_infer_model_entry_persistence(
  active : @infer_host.Execution,
  prepared : @model.ModelPreparedCallSet,
  admission : @publication_host.ClientInferDispatchAdmission,
  begin : (@model.ModelCallEntry) -> @model.ModelCallEntryPersistence?,
) -> Result[Unit, @infer_host.InvocationBindingIssue] {
  @infer_host.bind_model_entry_persistence(active, prepared, admission, begin)
}

///|
#export_name("clientProgramCreateInferCallEntryPersistence")
pub fn client_program_create_infer_call_entry_persistence(
  entry : @model.ModelCallEntry,
  prepared : @model.ModelPreparedCallSet,
  poll : () -> @model.ModelEntryPersistenceObservation,
) -> @model.ModelCallEntryPersistence? {
  @model.model_call_entry_persistence(entry, prepared, poll)
}

///|
#export_name("clientProgramInferCallEntryPersistencePending")
pub fn client_program_infer_call_entry_persistence_pending() -> @model.ModelEntryPersistenceObservation {
  @model.Pending
}

///|
#export_name("clientProgramInferCallEntryPersistenceUnknown")
pub fn client_program_infer_call_entry_persistence_unknown() -> @model.ModelEntryPersistenceObservation {
  @model.Unknown
}

///|
#export_name("clientProgramInferCallEntryPersistenceSaved")
pub fn client_program_infer_call_entry_persistence_saved(
  acknowledgement : @model.ModelCallEntryAcknowledgement,
) -> @model.ModelEntryPersistenceObservation {
  @model.Saved(acknowledgement)
}
