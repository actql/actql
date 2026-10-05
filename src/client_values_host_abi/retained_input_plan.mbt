///|
#export_name("clientValuesHostPrepareRetainedInputIntent")
pub fn client_values_host_prepare_retained_input_intent(
  producer : @host.ClientRetainedInputProducer,
  destination_grant_cid : String,
  route_capability_cid : String,
  source_grant_cid : String,
  transfer_attempt : String,
  transfer_expires_unix_ms : Int64,
  transfer_max_bytes : Int64,
) -> Result[
  @remote.RemoteRetainedInputIntent,
  @host.ClientRetainedTaskInputIssue,
] {
  @host.prepare_client_retained_input_intent(producer, {
    destination_grant_cid,
    route_capability_cid,
    source_grant_cid,
    transfer_attempt,
    transfer_expires_unix_ms,
    transfer_max_bytes,
  })
}

///|
#export_name("clientValuesHostAdmitRetainedInputIntent")
pub fn client_values_host_admit_retained_input_intent(
  producer : @host.ClientRetainedInputProducer,
  body : String,
  cid : String,
) -> Result[
  @remote.RemoteRetainedInputIntent,
  @host.ClientRetainedTaskInputIssue,
] {
  let intent = match
    @remote.admit_remote_retained_input_intent_json(
      body,
      cid,
      @host.client_retained_input_producer_dispatch(producer),
    ) {
    Ok(value) => value
    Err(_) => return Err(@host.InvalidBinding)
  }
  @host.validate_client_retained_input_intent(producer, intent).map(_ => intent)
}

///|
/// Historical wire is not authority to send it or start a consumer.
#export_name("clientValuesHostRetainedInputIntentFacts")
pub fn client_values_host_retained_input_intent_facts(
  intent : @remote.RemoteRetainedInputIntent,
) -> Array[String] {
  [
    @remote.remote_retained_input_intent_identity(intent),
    @remote.remote_retained_input_intent_json(intent),
  ]
}

///|
#export_name("clientValuesHostRetainedInputPlanEnvelope")
pub fn client_values_host_retained_input_plan_envelope(
  producer : @host.ClientRetainedInputProducer,
  intent : @remote.RemoteRetainedInputIntent,
) -> Result[String, @host.ClientRetainedTaskInputIssue] {
  match @host.validate_client_retained_input_intent(producer, intent) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match @remote.remote_poll_retained_input_plan_json(intent) {
    Ok(value) => Ok(value)
    Err(_) => Err(@host.Encoding)
  }
}

///|
/// Trusted live ports are shared with binding admission. The plan stage has
/// no receiver record yet, so it must not invent a committed Transfer.
pub struct ClientValuesHostRetainedInputPlan {
  producer : @host.ClientRetainedInputProducer
  intent : @remote.RemoteRetainedInputIntent
  plan : @remote.RemoteRetainedInputPlan
  current : @host.ClientRetainedInputCurrent
}

///|
#export_name("clientValuesHostAdmitRetainedInputPlan")
pub fn client_values_host_admit_retained_input_plan(
  producer : @host.ClientRetainedInputProducer,
  intent : @remote.RemoteRetainedInputIntent,
  body : String,
  cid : String,
  site_current : (String, String, String) -> Bool,
  authority : () -> String,
  now_unix_ms : () -> Int64,
  authorized : (String, String) -> Bool,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[
  ClientValuesHostRetainedInputPlan,
  @host.ClientRetainedTaskInputIssue,
] {
  let plan = match
    @remote.admit_remote_retained_input_plan_json(
      body, cid, intent, max_chunks, max_manifest_bytes, max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(@host.ForeignTransfer)
  }
  let current = @host.install_client_retained_input_owner_current(
    site_current,
    authority,
    now_unix_ms,
    (producer, request) => {
      match @transfer.request_json(request) {
        Ok(wire) =>
          authorized(
            @remote.dispatch_request_identity(
              @host.client_retained_input_producer_dispatch(producer),
            ),
            wire,
          )
        Err(_) => false
      }
    },
  )
  @host.validate_client_retained_input_plan(producer, intent, plan, current).map(_ => {
      producer,
      intent,
      plan,
      current,
    },
  )
}

///|
#export_name("clientValuesHostValidateRetainedInputPlan")
pub fn client_values_host_validate_retained_input_plan(
  value : ClientValuesHostRetainedInputPlan,
) -> Result[Unit, @host.ClientRetainedTaskInputIssue] {
  @host.validate_client_retained_input_plan(
    value.producer,
    value.intent,
    value.plan,
    value.current,
  )
}

///|
/// Immutable evidence only. No payload reader, holding or borrow is issued.
#export_name("clientValuesHostRetainedInputPlanFacts")
pub fn client_values_host_retained_input_plan_facts(
  value : ClientValuesHostRetainedInputPlan,
) -> Result[Array[String], @host.ClientRetainedTaskInputIssue] {
  let request = @remote.remote_retained_input_plan_transfer(value.plan)
  let wire = match @transfer.request_json(request) {
    Ok(value) => value
    Err(_) => return Err(@host.Encoding)
  }
  let manifest = match @transfer.request_manifest_json(request) {
    Ok(value) => value
    Err(_) => return Err(@host.Encoding)
  }
  Ok([
    @remote.remote_retained_input_plan_identity(value.plan),
    @remote.remote_retained_input_plan_json(value.plan),
    @transfer.request_cid(request),
    wire,
    @transfer.request_manifest(request).manifest_cid,
    manifest,
  ])
}
