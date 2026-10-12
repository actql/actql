///|
// Private installation bridge. The existing Host checks actual Model startup,
// rows, call scope and the same Resource consumer before a synchronous fence.
// No journal receipt, restoration or transport permission is issued here.
#export_name("clientProgramParkInferOriginalModelResources")
pub fn client_program_park_infer_original_model_resources(
  active : @infer_host.Execution,
  scope : @publication_host.ClientModelReadScope,
) -> Result[@publication_host.ClientModelResourcePark, @infer_host.Issue] {
  @infer_host.park_original_model_resources(active, scope)
}

///|
#export_name("clientProgramInferOriginalModelResourceParkCurrent")
pub fn client_program_infer_original_model_resource_park_current(
  active : @infer_host.Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
) -> @publication_host.ClientModelResourcePark? {
  @infer_host.original_model_resource_park_current(active, scope, park)
}
