///|
pub(all) enum ClientModelOriginalPreparationReadIssue {
  Origin(ClientModelOriginalOriginIssue)
  Envelope(@publication.PublicationContractIssue)
  Decode
  State(@resources.OriginalStateDocumentIssue)
} derive(Eq, Debug)

///|
// Connect the closed saved preparation envelope to the EXISTING resource
// Reader and original live read. No separately supplied inner body can be
// substituted: the Reader source comes only from this admitted outer document.
// The caller advances this Reader, compares every block with the same original
// read through client_model_read_state_block_matches, and retires its document.
// A completed Reader or all matching blocks still grant no Store custody,
// original-state restoration, current-cut or Model-send permission.
//
// Before entry the same original read/bootstrap envelope must cover the saved
// canonical tree, extracted text, new bounded source/admission tree, Reader
// control, getter/census/hash frames and their simultaneous backing. Returning
// the existing Reader adds no Owner/Ledger or reservation. Codec bounds and the
// nominal layout check below are NOT adoption of a physical numeric profile.
// The trusted physical caller obtains storage from the SAME live Evidence
// port's actual opaque-handle recheck, never from document/configuration data.
pub fn read_client_model_original_preparation_base(
  read : ClientModelReadPreparation,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  document : @publication.ModelOriginalResourceDocument,
  layout : ClientNodeModelPreparationLayout?,
  installation : @environment.ModelResponseProfileInstallation,
  runtime_artifact_cid : String,
  layout_artifact_cid : String,
  probability : @environment.DecisionProbabilityProfile?,
  storage : @publication.RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
  max_work : Int,
) -> Result[
  @resources.OriginalStateDocumentRead,
  ClientModelOriginalPreparationReadIssue,
] {
  if !physical_equal(read.origin, scope.origin) ||
    !client_model_read_origin_matches(read, compiled, definition, plan) {
    return Err(Origin(ForeignRun))
  }
  if !client_model_read_available(read, compiled, definition, plan) {
    return Err(Origin(Unavailable))
  }
  match
    check_client_model_original_storage_origin(
      scope, compiled, definition, plan, document, layout, installation, runtime_artifact_cid,
      layout_artifact_cid, probability, storage,
    ) {
    Err(issue) => return Err(Origin(issue))
    Ok(_) => ()
  }
  guard layout is Some(bound) else { return Err(Origin(Unavailable)) }
  if !client_model_read_preparation_available(
      read,
      compiled,
      definition,
      plan,
      bound.execution_bytes,
      retained_bytes=bound.retained_bytes,
    ) {
    return Err(Origin(Unavailable))
  }
  // Invalid structural limits are rejected before allocating payload text or
  // an admission tree. Counts/work come from the original caller, not the body.
  if max_bytes < 0 ||
    max_nodes < 1 ||
    max_depth < 0 ||
    max_reservations < 1 ||
    max_holdings < 0 ||
    max_delegations < 0 ||
    max_work < 0 {
    return Err(State(@resources.InvalidBounds))
  }
  let wire = match
    @publication.model_original_preparation_resource_wire(
      document, max_bytes, max_nodes, max_depth,
    ) {
    Ok(wire) => wire
    Err(issue) => return Err(Envelope(issue))
  }
  let node = match
    @source.parse_json(wire, {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(node) => node
    Err(_) => return Err(Decode)
  }
  let source = match
    @decode.admit(node, {
      max_nodes,
      max_depth,
      max_string_bytes: max_bytes,
      max_total_string_bytes: max_bytes,
    }) {
    Ok(source) => source
    Err(_) => return Err(Decode)
  }
  @resources.start_original_state_document_read(
    source, max_reservations, max_holdings, max_delegations, max_work,
  ).map_err(issue => State(issue))
}
