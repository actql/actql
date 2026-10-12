///|
/// Project one lookup reference from an admitted, physically stored index.
/// The original completed view supplies scope and request identity. This is
/// not full-chain validation, current publisher authority or Store completion.
/// The caller retains the original Store snapshot and index/response loan.
pub fn PublicationCommitPreparation::view_inspected_index_reference(
  preparation : PublicationCommitPreparation,
  view : PublicationCommitReadView,
  reference_identity : String,
  stored_index : PublicationContract,
  field : Int,
) -> Result[String, PublicationCommitIssue] {
  let original = match preparation.read_view_inputs(view) {
    Ok(inputs) => inputs
    Err(issue) => return Err(issue)
  }
  if field < 0 || field > 1 {
    return Err(CommitEncoding)
  }
  if stored_index.name != "public_index_entry" ||
    stored_index.identity != reference_identity {
    return Err(CommitReferenceMismatch("stored_index.identity"))
  }
  let chain = original.computation
  let original_key = match
    publication_index_storage_key(
      original.index_entry,
      chain.max_wire_bytes,
      chain.max_nodes,
      chain.max_depth,
    ) {
    Ok(key) => key
    Err(_) => return Err(CommitEncoding)
  }
  let stored_key = match
    publication_index_storage_key(
      stored_index,
      chain.max_wire_bytes,
      chain.max_nodes,
      chain.max_depth,
    ) {
    Ok(key) => key
    Err(_) => return Err(CommitEncoding)
  }
  if stored_key != original_key ||
    contract_string(stored_index, "publication_request_cid") !=
    Some(original.request.identity) {
    return Err(CommitReferenceMismatch("stored_index.scope"))
  }
  // Borrow fixed references only. Do not copy or scan the binding inventory,
  // compare committed content, or substitute the candidate's attempt/time.
  match
    contract_string(
      stored_index,
      if field == 0 {
        "publication_request_cid"
      } else {
        "publication_attempt_cid"
      },
    ) {
    Some(identity) => Ok(identity)
    None => Err(CommitReferenceMismatch("stored_index.references"))
  }
}
