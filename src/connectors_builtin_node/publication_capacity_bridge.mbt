///|
/// Four-field physical size projection; no contract or execution authority.
#export_name("strategyResultPublicationContractByteBounds")
pub fn strategy_result_publication_contract_byte_bounds(
  input_relation_cids : Array[String],
  max_schema_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Array[Int] {
  @publication.result_publication_contract_byte_bounds(
    input_relation_cids, max_schema_bytes, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("strategyOrdinaryPublicationFrontierByteBounds")
pub fn strategy_ordinary_publication_frontier_byte_bounds(
  request : @publication.PublicationContract,
  result_count : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Array[Int] {
  @publication.ordinary_publication_frontier_byte_bounds(
    request, result_count, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("strategyOrdinaryPublicationManifestByteBound")
pub fn strategy_ordinary_publication_manifest_byte_bound(
  request : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Int {
  @publication.ordinary_publication_manifest_byte_bound(
    request, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("strategyOrdinaryPublicationReceiptByteBound")
pub fn strategy_ordinary_publication_receipt_byte_bound(
  admission : @publication.RunPublicationAdmission,
  request : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  normalization : @publication.RunEvidenceValue,
  binding_names : Array[String],
  binding_digests : Array[String],
  sources : Array[@publication.RunEvidenceValue],
  models : Array[@publication.RunEvidenceValue],
  barriers : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Int {
  @publication.ordinary_publication_receipt_byte_bound(
    admission, request, invocation, observation, normalization, binding_names, binding_digests,
    sources, models, barriers, max_wire_bytes, max_nodes, max_depth,
  )
}
