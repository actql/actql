///|
/// Reobserve the same Store's original sealed generations and all binding
/// facts. This opens no payload stream, creates no attempt and grants no read
/// authority. Physical/capacity/cleanup responsibility stays with this Store.
/// No caller-selected authority CID can replace the Store's original authority.
pub fn Store::observe_publication_payload_facts(
  self : Store,
  bindings : Array[@publication.PublicationContract],
  binding_schema_wires : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.observe_publication_payload_facts_in_scope(
      bindings, binding_schema_wires, max_wire_bytes, max_nodes, max_depth,
    )
  })
}

///|
fn Store::observe_publication_payload_facts_in_scope(
  self : Store,
  bindings : Array[@publication.PublicationContract],
  binding_schema_wires : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  if bindings.length() != binding_schema_wires.length() {
    return Err(InvalidConfiguration)
  }
  for index, binding in bindings {
    let projected = match
      delivery_issuance(
        @publication.project_durable_result_binding_read(binding),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let info = match
      self.inspect_payload_in_scope(projected.material_generation_cid) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if !info.physical_digest.has_prefix("sha256:") {
      return Err(DigestMismatch)
    }
    let facts : @publication.DeliveryPayloadFacts = {
      store_authority_cid: self.authority_cid,
      material_generation_cid: info.material_generation_cid,
      logical_result_cid: info.logical_relation_cid,
      result_schema_cid: info.result_schema_cid,
      ordering_evidence_cid: info.ordering_evidence_cid,
      codec_contract_cid: info.durable_codec_cid,
      result_fields: projected.result_fields,
      result_schema_wire: binding_schema_wires[index],
      row_count: info.row_count,
      byte_count: info.generation.size,
      physical_sha256: info.physical_digest[7:].to_owned(),
    }
    match
      delivery_issuance(
        @publication.validate_durable_result_binding_facts(
          binding, facts, max_wire_bytes, max_nodes, max_depth,
        ),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  Ok(())
}
