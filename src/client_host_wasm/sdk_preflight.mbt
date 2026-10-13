///|
priv struct PublicationPreflightInput {
  namespace_id : String
  policy : String
  target : String
  requested_at : String
  attempt_id : String
  fence : String
  idempotency : String?
  started_at : String
  retentions : Array[@publication.PublicationContract]
}

///|
/// SDK input supplies physical attempt/clock observations only. Original
/// Account/Store, checked inventory and the saved finite packet supply every
/// policy/retention selection; no new expiry or public grant is issued here.
fn publication_preflight_input(
  value : Instance,
  compute : StoredNativeCompute,
  original_run : StoredRun,
  plan : @local_run.LocalRunPlan,
  cursor : @decode.Cursor,
) -> Result[PublicationPreflightInput, Int] {
  guard value.run_configurations.get(original_run.configuration)
    is Some(original) else {
    return Err(-2)
  }
  if original.sdk is Some(sdk) {
    guard original_run.finite_policy is Some(packet) &&
      compute.origin is SourceFree(_, start) &&
      value.physical_starts.get(start) is Some({ sdk_step: Some(step), .. }) else {
      return Err(-2)
    }
    let code = validate_sdk_start_claim(value, step, plan)
    if code != 0 {
      return Err(code)
    }
    guard @decode.closed_object(cursor, [
        "now", "attempt_id", "fence_cid", "external_idempotency_key",
      ])
      is Ok(object) &&
      required_number(object, "now") is Some(now) &&
      now >= 0.0 &&
      now <= 9007199254740991.0 &&
      now.floor() == now &&
      @values.epoch_milliseconds_timestamp(now.to_int64()) is Some(at) &&
      required_text(object, "attempt_id") is Some(attempt_id) &&
      required_text(object, "fence_cid") is Some(fence) &&
      optional_text(object, "external_idempotency_key") is Ok(idempotency) else {
      return Err(-31)
    }
    let count = @strategy.graph_result_count(
      @host.prepared_client_graph(@local_run.local_run_prepared(plan)),
    )
    if count <= 0 || count > value.workspace_slots {
      return Err(-4)
    }
    let retention = @host.client_local_run_policy_original_retention(packet)
    if @host.validate_client_local_run_policy_original_run(
        @host.client_local_run_policy_original_body(packet),
        @local_run.local_run_request(plan),
        @local_run.local_run_definition(plan),
      )
      is Err(_) {
      return Err(-31)
    }
    return Ok({
      namespace_id: original.run_namespace,
      policy: original.account.configuration_cid(),
      target: sdk.store_authority_cid,
      requested_at: at,
      attempt_id,
      fence,
      idempotency,
      started_at: at,
      retentions: Array::make(count, retention),
    })
  }
  // Preserve the original trusted non-SDK transport. SDK calls cannot fall
  // back to its caller-supplied policy/target/retention fields.
  guard @decode.closed_object(cursor, [
      "namespace_id", "publication_policy_cid", "publication_target_cid", "requested_at",
      "attempt_id", "fence_cid", "external_idempotency_key", "started_at", "retentions",
    ])
    is Ok(object) &&
    required_text(object, "namespace_id") is Some(namespace_id) &&
    required_text(object, "publication_policy_cid") is Some(policy) &&
    required_text(object, "publication_target_cid") is Some(target) &&
    required_text(object, "requested_at") is Some(requested_at) &&
    required_text(object, "attempt_id") is Some(attempt_id) &&
    required_text(object, "fence_cid") is Some(fence) &&
    optional_text(object, "external_idempotency_key") is Ok(idempotency) &&
    required_text(object, "started_at") is Some(started_at) &&
    @decode.required(object, "retentions") is Ok(retentions_cursor) &&
    @decode.elements(retentions_cursor) is Ok(retention_values) &&
    retention_values.length() > 0 &&
    retention_values.length() <= value.workspace_slots else {
    return Err(-31)
  }
  let retentions : Array[@publication.PublicationContract] = []
  for cursor in retention_values {
    guard @decode.text(cursor) is Ok(wire) &&
      @publication.admit_publication_contract(
        "result_retention_policy", wire, 65536, 4096, 64,
      )
      is Ok(retention) else {
      return Err(-31)
    }
    retentions.push(retention)
  }
  Ok({
    namespace_id,
    policy,
    target,
    requested_at,
    attempt_id,
    fence,
    idempotency,
    started_at,
    retentions,
  })
}
