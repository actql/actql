///|
/// The original installed Run acknowledges its read child's physical cleanup.
/// Authenticate the retained original binding even after its consumer stopped;
/// availability is not cleanup authority. Whole-Run census cleanup remains a
/// separate existing operation, and failed cleanup retains the same read.
pub fn settle_client_model_read_checked(
  value : ClientModelReadPreparation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  physical_cleanup_complete : Bool,
) -> Result[Unit, ClientModelReadPreparationIssue] {
  if !client_model_read_origin_matches(value, compiled, definition, plan) {
    return Err(ForeignRun)
  }
  settle_client_model_read(value, physical_cleanup_complete)
}
