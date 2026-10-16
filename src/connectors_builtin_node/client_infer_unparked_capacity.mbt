///|
// The installed operation supplies its own captured active/Scope. This Bool
// observes existing same-Owner bytes; it is no dispatch/Store authority.
#export_name("clientProgramInferOriginalUnparkedReadCapacityAvailable")
pub fn client_program_infer_original_unparked_read_capacity_available(
  active : @infer_host.Execution,
  scope : @publication_host.ClientModelReadScope,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Bool {
  @infer_host.original_model_unparked_read_capacity_available(
    active, scope, retained_bytes, execution_bytes,
  )
}
