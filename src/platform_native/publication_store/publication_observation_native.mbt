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
  expected_attempt? : String? = None,
  lease_current? : (() -> Bool)? = None,
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
    if expected_attempt is Some(attempt) {
      if info.publication_attempt_cid != attempt {
        return Err(StateCollision)
      }
      guard lease_current is Some(current) && current() else {
        return Err(RecoveryRequired)
      }
      match self.verify_recovered_payload_digest_in_scope(info, current) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
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

///|
// Read the original sealed file without opening a Result delivery. Keep only
// one bounded chunk plus the hash, and preserve the exact child on refusal.
fn Store::verify_recovered_payload_digest_in_scope(
  self : Store,
  info : NativePublicationPayloadInfo,
  current : () -> Bool,
) -> Result[Unit, NativePublicationStoreIssue] {
  let reader = match
    self.root.open_reader_with_custody(info.object_name, info.generation) {
    Ok(value) => value
    Err(failure) =>
      return self.fail_payload_verification(
        Open(failure),
        Filesystem(failure.issue()),
      )
  }
  let hash = @sha.hasher()
  let chunk_bytes = Int64::min(16384L, Int64::max(1L, info.generation.size)).to_int()
  let mut consumed = 0L
  while true {
    if !current() {
      return self.fail_payload_verification(Reader(reader), RecoveryRequired)
    }
    let chunk = match reader.next(chunk_bytes) {
      Ok(value) => value
      Err(issue) =>
        return self.fail_payload_verification(Reader(reader), Filesystem(issue))
    }
    consumed += chunk.bytes.length().to_int64()
    if consumed > info.generation.size ||
      (!chunk.eof && chunk.bytes.length() == 0) {
      return self.fail_payload_verification(Reader(reader), DigestMismatch)
    }
    @sha.update(hash, chunk.bytes) catch {
      _ => return self.fail_payload_verification(Reader(reader), StateCollision)
    }
    if chunk.eof {
      break
    }
  }
  match reader.finish() {
    Ok(_) => ()
    Err(issue) =>
      return self.fail_payload_verification(Reader(reader), Filesystem(issue))
  }
  let digest = @sha.finish_hex(hash) catch { _ => return Err(StateCollision) }
  if consumed != info.generation.size ||
    info.physical_digest != "sha256:" + digest {
    return Err(DigestMismatch)
  }
  Ok(())
}

///|
fn Store::fail_payload_verification(
  self : Store,
  cleanup : NativePayloadVerificationCleanup,
  primary : NativePublicationStoreIssue,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.pending_payload_verification = Some(cleanup)
  match self.finish_payload_verification_cleanup() {
    Ok(_) => Err(primary)
    Err(issue) => Err(OperationCleanup(Some(primary), issue))
  }
}

///|
fn Store::finish_payload_verification_cleanup(
  self : Store,
) -> Result[Unit, NativePublicationStoreIssue] {
  let result = match self.pending_payload_verification {
    None => return Ok(())
    Some(Open(failure)) => failure.retry_cleanup()
    Some(Reader(reader)) => reader.close()
  }
  match result {
    Ok(_) => {
      self.pending_payload_verification = None
      Ok(())
    }
    Err(issue) => Err(Filesystem(issue))
  }
}
