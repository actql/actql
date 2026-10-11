///|
/// Installed trusted Cloud/Site coordinates, not a proposed principal or an
/// Account permission. The expiry floor comes from the authenticated installer.
pub(all) struct NativeEffectCloudHostIdentityScope {
  site_key : String
  site_generation : Int64
  workspace_id : String
  authority_scope_cid : String
  installation : String
  expires_ms : Int64
}

///|
pub(all) struct NativeEffectCloudHostIdentityRead {
  control : NativeEffectCloudCurrentRead
  scope : NativeEffectCloudHostIdentityScope
  limits : @checkpoint.WireLimits
}

///|
/// Ephemeral original submit identity facts from the configured authenticated
/// private read. It is not an Account Allow or reusable authority token.
struct NativeEffectCloudHostIdentity {
  principal_id : String
  expires_ms : Int64
}

///|
pub fn NativeEffectCloudHostIdentity::principal_id(
  self : NativeEffectCloudHostIdentity,
) -> String {
  self.principal_id
}

///|
priv struct CloudHostIdentityExpected {
  dispatch_cid : String
  run_cid : String
  task_key : String
  runtime_cid : String
}

///|
fn cloud_host_identity_limits(limits : @checkpoint.WireLimits) -> Bool {
  limits.max_wire_bytes > 0 &&
  limits.max_wire_bytes <= 65536 &&
  limits.max_nodes > 0 &&
  limits.max_nodes <= 4096 &&
  limits.max_depth > 0 &&
  limits.max_depth <= 32
}

///|
fn cloud_host_identity_query(
  expected : CloudHostIdentityExpected,
  query_id : String,
  limits : @checkpoint.WireLimits,
) -> Bytes? {
  if !cloud_host_identity_limits(limits) ||
    !cloud_resume_query_label(query_id) ||
    !native_reviewer_cid(expected.dispatch_cid) {
    return None
  }
  let writer = @encode.writer(
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return None
  }
  try {
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("version", "actql-cloud-effect-host-identity-query/0.1"),
        ("queryId", query_id),
        ("dispatchCid", expected.dispatch_cid),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    Some(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => None
  }
}

///|
/// Closed framing only after an installed authenticated HTTP response. There
/// is deliberately no public arbitrary-wire identity admission function.
fn cloud_host_identity_reply(
  body : Bytes,
  expected : CloudHostIdentityExpected,
  query_id : String,
  scope : NativeEffectCloudHostIdentityScope,
  now_ms : Int64,
  limits : @checkpoint.WireLimits,
) -> NativeEffectCloudHostIdentity? {
  if !cloud_host_identity_limits(limits) ||
    now_ms < 0L ||
    now_ms > 9007199254740991L ||
    scope.expires_ms <= now_ms ||
    scope.expires_ms > 9007199254740991L ||
    scope.site_generation <= 0L ||
    scope.site_generation > 9007199254740991L {
    return None
  }
  let source = match
    @source.parse_json_bytes_preserving(body, {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  try {
    let root = cloud_resume_decoded(
      @decode.admit(source, {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_string_bytes: limits.max_wire_bytes,
        max_total_string_bytes: limits.max_wire_bytes,
      }),
    )
    let fields = cloud_resume_decoded(
      @decode.closed_object(root, [
        "version", "queryId", "dispatchCid", "taskKey", "workspaceId", "authorityScopeCid",
        "runDefinitionCid", "principalId", "siteKey", "siteGeneration", "runtimeBundleCid",
        "installation", "observedAt", "expiresAt",
      ]),
    )
    if cloud_resume_text(fields, "version") !=
      "actql-cloud-effect-host-identity-current/0.1" ||
      cloud_resume_text(fields, "queryId") != query_id ||
      cloud_resume_text(fields, "dispatchCid") != expected.dispatch_cid ||
      cloud_resume_text(fields, "runDefinitionCid") != expected.run_cid ||
      cloud_resume_text(fields, "taskKey") != expected.task_key ||
      cloud_resume_text(fields, "runtimeBundleCid") != expected.runtime_cid ||
      cloud_resume_text(fields, "workspaceId") != scope.workspace_id ||
      cloud_resume_text(fields, "authorityScopeCid") !=
      scope.authority_scope_cid ||
      cloud_resume_text(fields, "siteKey") != scope.site_key ||
      cloud_resume_integer(fields, "siteGeneration") != scope.site_generation ||
      cloud_resume_text(fields, "installation") != scope.installation {
      raise InvalidRead
    }
    let principal_id = cloud_resume_text(fields, "principalId")
    if principal_id.length() != 34 ||
      !principal_id.has_prefix("p_") ||
      !principal_id
      .unsafe_substring(start=2, end=principal_id.length())
      .iter()
      .all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
      raise InvalidRead
    }
    guard @values.timestamp_epoch_milliseconds(
        cloud_resume_text(fields, "observedAt"),
      )
      is Some(observed) &&
      @values.timestamp_epoch_milliseconds(
        cloud_resume_text(fields, "expiresAt"),
      )
      is Some(expires) &&
      observed <= now_ms &&
      observed < expires &&
      now_ms < expires &&
      expires <= scope.expires_ms else {
      raise InvalidRead
    }
    Some({ principal_id, expires_ms: expires, })
  } catch {
    InvalidRead => None
  }
}

///|
/// Select the dispatch from the actual opaque consumer and the original Run
/// and request from its producer Owner. No transported materials refresh them.
fn cloud_host_identity_original(
  consumer : @resident.ResidentRetainedConsumer,
  producer : @resident.ResidentEffectProducerExecuted,
  journal : @journal.Journal,
  scope : NativeEffectCloudHostIdentityScope,
) -> CloudHostIdentityExpected? {
  guard consumer.effect_original_dispatch(journal) is Some(dispatch) &&
    consumer.effect_computation(journal) is Some(computation) &&
    computation.effect_materials_for_capture() is Some(consumer_materials) &&
    producer.materials_for_capture(journal) is Some(materials) &&
    producer.request_for_capture(journal) is Some(request) &&
    consumer_materials.request == Some(request) &&
    materials.request == Some(request) else {
    return None
  }
  let (run_cid, task_key) = @remote.dispatch_request_task_scope(dispatch)
  let execution = @remote.dispatch_request_execution_scope(dispatch)
  if execution[0] != scope.site_key ||
    execution[1] != scope.site_generation.to_string() ||
    run_cid !=
    @publication.publication_contract_identity(materials.run_definition) ||
    run_cid !=
    @publication.publication_contract_identity(
      consumer_materials.run_definition,
    ) {
    return None
  }
  Some({
    dispatch_cid: @remote.dispatch_request_identity(dispatch),
    run_cid,
    task_key,
    runtime_cid: execution[2],
  })
}

///|
/// Fresh read only. This uses the same installed TLS/Site client as control
/// observations. Original physical custody and current Site are checked before
/// and after HTTP; any failure returns unavailable without reprepare or retry.
/// Actual Account read/write decisions remain the installing Host's job.
pub fn NativeEffectCloudHostIdentityRead::read_original_consumer(
  self : NativeEffectCloudHostIdentityRead,
  consumer : @resident.ResidentRetainedConsumer,
  producer : @resident.ResidentEffectProducerExecuted,
  journal : @journal.Journal,
) -> NativeEffectCloudHostIdentity? {
  guard (self.control.current_site)() &&
    cloud_host_identity_original(consumer, producer, journal, self.scope)
    is Some(expected) else {
    return None
  }
  let query_id = (self.control.next_query_id)()
  guard cloud_host_identity_query(expected, query_id, self.limits) is Some(body) else {
    return None
  }
  let reply = match self.control.client.post_json(self.control.url, body) {
    Ok(reply) if reply.status == 200 => reply
    _ => return None
  }
  let selected = cloud_host_identity_reply(
    reply.body,
    expected,
    query_id,
    self.scope,
    (self.control.now_ms)(),
    self.limits,
  )
  guard (self.control.current_site)() &&
    cloud_host_identity_original(consumer, producer, journal, self.scope)
    is Some(current) &&
    current.dispatch_cid == expected.dispatch_cid &&
    current.run_cid == expected.run_cid &&
    current.task_key == expected.task_key &&
    current.runtime_cid == expected.runtime_cid else {
    return None
  }
  let final_now = (self.control.now_ms)()
  guard selected is Some(identity) &&
    final_now >= 0L &&
    final_now < identity.expires_ms else {
    return None
  }
  Some(identity)
}
