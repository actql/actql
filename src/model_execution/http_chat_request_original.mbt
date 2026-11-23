///|
/// Exact codec output retained by the Host's already funded preflight.
/// The original request and admitted installation remain nominal.
pub struct PreparedModelHttpChatRequest {
  priv request : ModelRequest
  priv provider : AdmittedStructuredModelProvider
  priv body : Bytes
}

///|
/// A funded preflight child on one selected physical model and checked Request.
/// The existing Chat cursor owns all temporary projection state.
pub struct ModelHttpChatProjection {
  priv provider : AdmittedStructuredModelProvider
  priv cursor : OpenAIChatProjection
}

///|
/// Verify the precise portable route against the already admitted provider.
/// The Native installer separately retains its physical Runtime and Read.
pub fn model_http_chat_installation_matches(
  provider : AdmittedStructuredModelProvider,
  installation : @environment.ModelResponseProfileInstallation,
) -> Bool {
  let selected = provider.capability
  selected.resolved.adapter_kind == "portable-http" &&
  selected.resolved.api_mode == "chat-completions" &&
  installation.sdk is None &&
  installation.http_method == "POST" &&
  !installation.streaming &&
  installation.completion_basis == "generation_finish" &&
  selected.resolved.endpoint.has_prefix("https://") &&
  check_structured_model_selection(
    selected,
    selected.resolved,
    provider.original.execution,
    installation,
  )
  is Ok(_)
}

///|
/// Enter this preparation only after the original Model Read funds the codec,
/// its cursor and the simultaneous UTF-8 output.
pub fn start_model_http_chat_request_projection(
  provider : AdmittedStructuredModelProvider,
  request : ModelRequest,
  installation : @environment.ModelResponseProfileInstallation,
  max_frames : Int,
) -> Result[ModelHttpChatProjection, OpenAIChatProjectionIssue] {
  let selected = provider.capability
  if !model_http_chat_installation_matches(provider, installation) {
    return Err(ForeignRequest)
  }
  let bounds = @environment.model_response_profile_limits(selected.profile)
  start_openai_chat_projection(
    provider.original,
    request,
    bounds.request_bytes,
    bounds.parse_nodes,
    bounds.parse_depth,
    max_frames,
    bounds.parse_work,
  ).map(cursor => { provider, cursor, })
}

///|
/// Advance the original projection. Only its completed portable request may
/// escape to the physical Plan. Finishing or refusing spends this child.
pub fn advance_model_http_chat_request_projection(
  value : ModelHttpChatProjection,
) -> Result[PreparedModelHttpChatRequest?, OpenAIChatProjectionIssue] {
  let cursor = value.cursor
  match advance_openai_chat_projection(cursor) {
    Ok(None) => Ok(None)
    Ok(Some(_)) => {
      guard cursor.request is Some(request) else {
        retire_openai_chat_projection(cursor)
        return Err(ForeignRequest)
      }
      let provider = value.provider
      let model_id = provider.capability.resolved.model_id
      finish_openai_chat_http_projection(cursor, model_id).bind(material => {
        let body = @utf8.encode(material.0)
        if body.length() > cursor.max_bytes {
          Err(Limit)
        } else {
          Ok(Some({ request, provider, body, }))
        }
      })
    }
    Err(issue) => {
      retire_openai_chat_projection(cursor)
      Err(issue)
    }
  }
}

///|
pub fn retire_model_http_chat_request_projection(
  value : ModelHttpChatProjection,
) -> Unit {
  retire_openai_chat_projection(value.cursor)
}

///|
/// Convenience for an already funded non-driving caller. Native execution
/// uses this same child through the original Model preflight.
pub fn prepare_model_http_chat_request(
  provider : AdmittedStructuredModelProvider,
  request : ModelRequest,
  installation : @environment.ModelResponseProfileInstallation,
  max_frames : Int,
) -> Result[PreparedModelHttpChatRequest, OpenAIChatProjectionIssue] {
  let original = match
    start_model_http_chat_request_projection(
      provider, request, installation, max_frames,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_model_http_chat_request_projection(original) {
      Ok(Some(value)) => return Ok(value)
      Ok(None) => ()
      Err(issue) => return Err(issue)
    }
  } nobreak {
    Err(Limit)
  }
}

///|
/// Borrow the nonsecret reference within the resolved portable installation.
/// This is used at construction, before retaining the original file handle.
pub fn model_http_original_credential_reference(
  provider : AdmittedStructuredModelProvider,
  configuration_wire : String,
) -> String? {
  let selected = provider.capability
  if selected.resolved.adapter_kind != "portable-http" ||
    selected.resolved.api_mode != "chat-completions" {
    return None
  }
  @publication_host.client_model_original_credential_reference(
    selected.binding,
    selected.provider.provider_id,
    configuration_wire,
  )
}

///|
/// Borrow the same bytes for the exact request and the exact installed
/// selection. This cannot encode or adopt a replacement body at dispatch.
pub fn prepared_model_http_chat_material(
  original : PreparedModelHttpChatRequest,
  request : ModelRequest,
  provider : AdmittedStructuredModelProvider,
) -> (String, @environment.ModelResponseProfile, Bytes)? {
  if !physical_equal(original.request, request) ||
    !physical_equal(original.provider, provider) {
    return None
  }
  let capability = provider.capability
  Some((capability.resolved.endpoint, capability.profile, original.body))
}

///|
/// Bind the exact retained body to the initialized portable physical plan.
/// The installed port registers the Call under the consumed Entry, then the
/// owning Native Read rechecks that same Entry before any HTTP operation.
pub fn prepared_model_http_chat_plan(
  original : PreparedModelHttpChatRequest,
  installation : @environment.ModelResponseProfileInstallation,
  quantities : @resources.QuantityAmounts,
  start : (ModelCallEntry) -> ModelPhysicalCall?,
  measured_transfer? : Bool = false,
) -> Result[ModelPhysicalRequestPlan, ModelExecutionIssue] {
  let capability = original.provider.capability
  let execution = original.provider.original.execution
  if check_structured_model_selection(
      capability,
      capability.resolved,
      execution,
      installation,
    )
    is Err(_) {
    return Err(InvalidProvider)
  }
  prepare_structured_model_physical_plan(
    original.request,
    original.body.length().to_int64(),
    quantities,
    capability.profile,
    installation,
    if measured_transfer {
      AsynchronousMeasuredHttpChat(original, start)
    } else {
      AsynchronousHttpChat(original, start)
    },
    None,
    [],
  )
}

///|
/// Verify the actual durable scope before late dispatch callbacks. Even two
/// admitted selections with the same Task and Profile can name another model.
pub fn check_prepared_model_http_chat_dispatch_current(
  call : ModelPhysicalCall,
  original : PreparedModelHttpChatRequest,
  raw : @publication_host.ClientModelRawCaptureRegistration,
) -> Result[Unit, ModelPhysicalDispatchReadIssue] {
  let capability = original.provider.capability
  let request = original.request
  guard call.original_binding is Some(binding) &&
    binding.plan.invocation
    is (AsynchronousHttpChat(prepared, _)
    | AsynchronousMeasuredHttpChat(prepared, _)) &&
    physical_equal(prepared, original) &&
    model_physical_call_dispatch_entry(call, request, capability.profile, raw)
    is Some(entry) &&
    entry.prepared.scope is Some(scope) &&
    @publication.model_invocation_scope_provider_cid(scope) ==
    @publication.run_evidence_value_identity(capability.binding) &&
    entry.prepared.owner.state.source is Provider(provider) &&
    physical_equal(provider, capability.provider) else {
    return Err(Dispatch(CallEntryRefused))
  }
  check_model_physical_call_dispatch_current(
    call,
    request,
    capability.profile,
    raw,
  )
}
