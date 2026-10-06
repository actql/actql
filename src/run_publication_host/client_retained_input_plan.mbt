///|
/// Join a received Native plan to the checked original producer and current
/// trusted movement Owners. Admission grants no receiver reservation, borrow
/// or consumer start. The caller must save it under its existing revision
/// fence and revalidate before delivery across any asynchronous boundary.
pub fn validate_client_retained_input_plan(
  producer : ClientRetainedInputProducer,
  intent : @remote.RemoteRetainedInputIntent,
  plan : @remote.RemoteRetainedInputPlan,
  current : ClientRetainedInputCurrent,
) -> Result[Unit, ClientRetainedTaskInputIssue] {
  match validate_client_retained_input_intent(producer, intent) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let request = @remote.remote_retained_input_plan_transfer(plan)
  let expected = match
    @remote.prepare_remote_retained_input_plan(
      intent,
      client_retained_input_producer_subject(producer),
      client_retained_input_producer_evidence(producer),
      request,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignTransfer)
  }
  if @remote.remote_retained_input_plan_identity(plan) !=
    @remote.remote_retained_input_plan_identity(expected) ||
    @remote.remote_retained_input_plan_json(plan) !=
    @remote.remote_retained_input_plan_json(expected) {
    return Err(ForeignTransfer)
  }
  match
    validate_client_retained_input_transfer_current(producer, request, current) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  // A trusted callback can observe a later producer revision. Historical
  // proof must not survive a concurrent cleanup or replaced occurrence.
  validate_client_retained_input_intent(producer, intent)
}
