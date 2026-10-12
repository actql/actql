///|
/// Project the admitted original Task, not SDK defaults or a caller's body.
/// This projection is not provider compatibility, funding or send authority.
#export_name("clientProgramModelRequestGeneration")
pub fn client_program_model_request_generation(
  request : @model.ModelRequest,
) -> (String, Double, Double, Int64, Int64?)? {
  guard @check_environment.model_task_generation_config(request.task)
    is Some(generation) else {
    return None
  }
  Some(
    (
      @check_environment.model_task_model_selector(request.task),
      generation.temperature,
      generation.top_p,
      generation.max_output_tokens,
      generation.seed_requested,
    ),
  )
}
