///|
pub(all) enum ClientEffectSourceDispatchIssue {
  Binding(ClientEffectCompiledRunIssue)
  Fragment(ClientTaskFragmentIssue)
  Input(ClientTaskDispatchIssue)
  UnsupportedGraph
  ForeignRequest
  ForeignDispatch
  ForeignInput
  Protocol(@remote.DispatchIssue)
}

///|
/// Select the initial Source task from the retained Effect compilation. The
/// private graph view never escapes as an Effect-free prepared Program.
fn client_effect_source_fragment(
  compilation : ClientEffectCompilation,
) -> Result[ClientTaskFragmentNode, ClientEffectSourceDispatchIssue] {
  let prepared = compilation.compiled.owner
  let graph = prepared_client_graph(prepared)
  guard @strategy.graph_task_count(graph) == 2 &&
    @strategy.graph_captured_prefix(graph) == 1 &&
    @strategy.checked_effect_source_count(compilation.owner.graph) == 1 &&
    @strategy.graph_result_count(graph) == 1 &&
    @strategy.graph_result_task(graph, 0) == Some(1) &&
    @strategy.graph_task_target(graph, 0) is None &&
    @strategy.graph_task_input_count(graph, 1) == Some(1) &&
    @strategy.graph_data_count(graph) == 1 &&
    @strategy.graph_data_at(graph, 0) is Some(edge) else {
    return Err(UnsupportedGraph)
  }
  if @strategy.data_edge_producer(edge) != 0 ||
    @strategy.data_edge_consumer(edge) != 1 ||
    @strategy.data_edge_input(edge) != 0 {
    return Err(UnsupportedGraph)
  }
  issue_prepared_client_task_fragment(
    prepared,
    0,
    client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).map_err(issue => Fragment(issue))
}

///|
/// Issue a checked task fragment from the reconstructed original Effect Run.
/// The private computation view does not escape as an Effect-free Program.
/// This identity grants neither a start claim nor approval or physical input.
pub fn issue_client_effect_task_fragment(
  materials : ClientEffectRunMaterials,
  task : Int,
) -> Result[ClientTaskFragmentNode, ClientEffectSourceDispatchIssue] {
  match
    bind_client_effect_compiled_run(
      materials.prepared,
      materials.allowed,
      materials.run_definition,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Binding(issue))
  }
  if !physical_equal(materials.compilation, materials.allowed.compilation) {
    return Err(ForeignDispatch)
  }
  let source = match client_effect_source_fragment(materials.compilation) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if task == 0 {
    return Ok(source)
  }
  if task != 1 {
    return Err(UnsupportedGraph)
  }
  issue_prepared_client_task_fragment(
    materials.compilation.compiled.owner,
    task,
    client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).map_err(issue => Fragment(issue))
}

///|
/// The original Effect Owner supplies the logical Source identity. No path,
/// credential, approval or acquisition is created here.
pub fn prepare_client_effect_source_input_binding(
  compilation : ClientEffectCompilation,
  request? : ClientRequestIdentity? = None,
) -> Result[@remote.RemoteInputBinding, ClientEffectSourceDispatchIssue] {
  match client_effect_source_fragment(compilation) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let source = match
    prepare_client_task_input_binding(compilation.compiled.owner, 0).map_err(issue => {
      ClientEffectSourceDispatchIssue::Input(issue)
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !compilation.normalization_profile {
    return Ok(source)
  }
  guard request is Some(original) else { return Err(ForeignRequest) }
  if client_request_input_cid(original) != source_free_caller_input_intent_cid() {
    return Err(ForeignRequest)
  }
  match prepared_client_effect_request_scope(compilation.owner, original) {
    Ok(_) => ()
    Err(_) => return Err(ForeignRequest)
  }
  let wire = match client_request_identity_record_wire(original) {
    Ok(value) => value
    Err(_) => return Err(ForeignRequest)
  }
  let body = try {
    let writer = @encode.writer(8192, 4, 1)
    @encode.begin_object(writer)
    @encode.key(writer, "original_request_json")
    @encode.string_value(writer, wire)
    @encode.key(writer, "source_binding_json")
    @encode.string_value(writer, @remote.remote_input_binding_body(source))
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-effect-source-input-binding/0.1")
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(ForeignInput)
  }
  @remote.prepare_remote_input_binding(body, 8192).map_err(issue => {
    Protocol(issue)
  })
}

///|
/// Read request custody from the separately issued Source binding, not from
/// candidate materials. Its exact CID must belong to the trusted dispatch.
/// This projection is not a signature or current delegation/approval check.
pub fn client_effect_source_binding_request(
  binding : @remote.RemoteInputBinding,
  dispatch : @remote.DispatchRequest,
) -> Result[ClientRequestIdentity?, ClientEffectSourceDispatchIssue] {
  if !@remote.remote_input_binding_matches_dispatch(binding, dispatch) {
    return Err(ForeignInput)
  }
  let source = match
    @source.parse_json_bytes_preserving(
      @utf8.encode(@remote.remote_input_binding_body(binding)),
      { max_input_bytes: 8192, max_nodes: 16, max_depth: 2, },
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignInput)
  }
  let root = match
    @decode.admit(source, {
      max_nodes: 16,
      max_depth: 2,
      max_string_bytes: 8192,
      max_total_string_bytes: 8192,
    }) {
    Ok(value) => value
    Err(_) => return Err(ForeignInput)
  }
  if @decode.closed_object(root, ["source_contract_cid", "source_ref"]) is Ok(_) {
    return Ok(None)
  }
  let fields = match
    @decode.closed_object(root, [
      "original_request_json", "source_binding_json", "version",
    ]) {
    Ok(value) => value
    Err(_) => return Err(ForeignInput)
  }
  let text = name => {
    @decode.lookup(fields, name).bind(cursor => @decode.text(cursor).to_option())
  }
  guard text("version") == Some("actql-effect-source-input-binding/0.1") &&
    text("original_request_json") is Some(wire) &&
    text("source_binding_json") is Some(_) else {
    return Err(ForeignInput)
  }
  let original = match admit_client_request_identity_record_wire(wire) {
    Ok(value) => value
    Err(_) => return Err(ForeignRequest)
  }
  if client_request_authority_scope_cid(original) !=
    @remote.dispatch_request_journal_key(dispatch)[0] {
    return Err(ForeignRequest)
  }
  Ok(Some(original))
}

///|
/// Issue only the initial checked Source dispatch of the original Effect Run.
/// The Coordinator must save the full envelope before sending. Source authority
/// does not approve an Effect; current Site delegation is checked at receipt.
pub fn prepare_client_effect_source_dispatch(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
  task_attempt : Int,
  dispatch_id : String,
  selected : ClientValuesSiteSelection,
) -> Result[@remote.DispatchRequest, ClientEffectSourceDispatchIssue] {
  let input = match
    prepare_client_effect_source_input_binding(
      allowed.compilation,
      request=Some(request),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  client_effect_checked_task_dispatch(
    allowed, definition, request, 0, task_attempt, dispatch_id, selected, input,
  )
}

///|
fn client_effect_checked_task_dispatch(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
  task : Int,
  task_attempt : Int,
  dispatch_id : String,
  selected : ClientValuesSiteSelection,
  input : @remote.RemoteInputBinding,
) -> Result[@remote.DispatchRequest, ClientEffectSourceDispatchIssue] {
  let compilation = allowed.compilation
  match
    bind_client_effect_compiled_run(compilation.owner, allowed, definition) {
    Ok(_) => ()
    Err(issue) => return Err(Binding(issue))
  }
  let identity = prepared_client_effect_identity(compilation.owner)
  if client_request_program_cid(request) != identity.program_definition_cid ||
    client_request_parameters_cid(request) != identity.parameter_values_cid ||
    client_request_input_cid(request) != source_free_caller_input_intent_cid() {
    return Err(ForeignRequest)
  }
  let source_fragment = match client_effect_source_fragment(compilation) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let fragment = if task == 0 {
    source_fragment
  } else if task == 1 {
    match
      issue_prepared_client_task_fragment(
        compilation.compiled.owner,
        1,
        client_standard_values_sequence_limits(),
        1000000,
        100000,
        100,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Fragment(issue))
    }
  } else {
    return Err(UnsupportedGraph)
  }
  @remote.prepare_dispatch_request(
    client_request_authority_scope_cid(request),
    @publication.publication_contract_identity(definition),
    client_task_fragment_node_id(fragment),
    task_attempt,
    dispatch_id,
    selected.site_key,
    selected.site_generation,
    selected.runtime_bundle_cid,
    selected.connector_registration,
    selected.connector_revision,
    selected.strategy_revision,
    @remote.remote_input_binding_cid(input),
    selected.obligations_cid,
    selected.budget_cid,
    selected.evidence_issuer_capability_cid,
    selected.grant_cid,
  ).map_err(issue => Protocol(issue))
}

///|
/// Bind a received Source dispatch to the reconstructed original Effect Owner.
/// Current authority and lifetime are independent receiver checks. A consumer
/// dispatch cannot acquire input under this initial Source binding.
pub fn bind_client_effect_source_dispatch(
  materials : ClientEffectRunMaterials,
  request : @remote.DispatchRequest,
  input : @remote.RemoteInputBinding,
) -> Result[PreparedClientEffectRun, ClientEffectSourceDispatchIssue] {
  if client_effect_run_materials_request_for_dispatch(materials, request)
    is Err(_) {
    return Err(ForeignRequest)
  }
  let bound = match
    bind_client_effect_compiled_run(
      materials.prepared,
      materials.allowed,
      materials.run_definition,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  // Public material fields must still belong to the same opaque compilation.
  if !physical_equal(materials.compilation, materials.allowed.compilation) {
    return Err(ForeignDispatch)
  }
  let fragment = match client_effect_source_fragment(materials.compilation) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @remote.dispatch_request_task_scope(request) !=
    (
      @publication.publication_contract_identity(materials.run_definition),
      client_task_fragment_node_id(fragment),
    ) {
    return Err(ForeignDispatch)
  }
  let expected = match
    prepare_client_effect_source_input_binding(
      materials.compilation,
      request=materials.request,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @remote.remote_input_binding_body(input) !=
    @remote.remote_input_binding_body(expected) ||
    !@remote.remote_input_binding_matches_dispatch(input, request) {
    return Err(ForeignInput)
  }
  Ok({ ..bound, source_dispatch: Some(request), })
}

///|
/// The exact producer request admitted before physical Source acquisition.
/// This projection grants no start, capture, transfer or approval authority.
pub fn prepared_client_effect_run_source_dispatch(
  bound : PreparedClientEffectRun,
) -> @remote.DispatchRequest? {
  bound.source_dispatch
}
