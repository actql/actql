///|
/// Pure canonical DATA projection. The original Host owner separately proves
/// complete cancellation, unpublished Results and its current retirement duty.
#export_name("clientProgramConfirmedCancelledUnpublishedRunState")
pub fn client_program_confirmed_cancelled_unpublished_run_state(
  run_id : String,
  updated_at : String,
  declared_results : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @publication.RunStateIssue] {
  @publication.issue_confirmed_cancelled_unpublished_run_state_wire(
    run_id, updated_at, declared_results, max_wire_bytes, max_nodes, max_depth,
  )
}
