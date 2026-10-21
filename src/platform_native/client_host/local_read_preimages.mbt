///|
priv struct NativeLocalReadPreimage {
  wire : String
  cid : String
}

///|
// Archive comparison DATA only. A live binding independently retains and
// checks the actual receiver; parsing these fields never reconstructs it.
priv struct NativeLocalReadMaterialOriginal {
  receiver_cid : String
  result_schema_cid : String
  ordering_evidence_cid : String
}

///|
// Historical comparison DATA only. A live File binding separately retains its
// actual Root/Writer and cannot be reconstructed from these saved strings.
priv struct NativeLocalReadFileOriginal {
  path : String
  name : String
  staging_name : String
  parent_device : String
  parent_inode : String
  writer_device : String
  writer_inode : String
} derive(Eq)

///|
// These are private originals, not an admission or a continuing capability.
// The journal must retain them before exposing references to the grant issuer.
priv struct NativeLocalReadAdmissionOriginals {
  authorization : NativeLocalReadPreimage
  ceiling : NativeLocalReadPreimage
  egress : NativeLocalReadPreimage
}

///|
fn local_read_preimage(
  crypto : @crypto.Library,
  fields : Array[(String, @host.ClientLocalReadEvidenceValue)],
  material? : NativeLocalReadMaterialOriginal? = None,
  file? : NativeLocalReadFileOriginal? = None,
) -> Result[NativeLocalReadPreimage, NativeClientRunJournalIssue] {
  if material is Some(original) {
    fields.push(("material_receiver_cid", Text(original.receiver_cid)))
    fields.push(("result_schema_cid", Text(original.result_schema_cid)))
    fields.push(("ordering_evidence_cid", Text(original.ordering_evidence_cid)))
  }
  if file is Some(original) {
    fields.push(("destination_path", Text(original.path)))
    fields.push(("destination_name", Text(original.name)))
    fields.push(("destination_staging_name", Text(original.staging_name)))
    fields.push(("destination_parent_device", Text(original.parent_device)))
    fields.push(("destination_parent_inode", Text(original.parent_inode)))
    fields.push(("destination_writer_device", Text(original.writer_device)))
    fields.push(("destination_writer_inode", Text(original.writer_inode)))
  }
  if material is Some(_) || file is Some(_) {
    fields.sort_by((left, right) => {
      @canonical_value.compare_utf16(left.0, right.0)
    })
  }
  let wire = match @host.encode_client_local_read_preimage(fields) {
    Ok(value) => value
    Err(CapacityExceeded) => return Err(CapacityExceeded)
    Err(Encoding) => return Err(Encoding)
  }
  // One concrete preimage digest attempt, separate from scope/config hashes.
  native_timing_count(40)
  let cid = match local_adoption_digest(crypto, @utf8.encode(wire)) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  Ok({ wire, cid, })
}

///|
fn NativeLocalReadPolicyBinding::read_admission_originals(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
  actual_policy_cid : String,
) -> Result[NativeLocalReadAdmissionOriginals, NativeLocalReadBindingIssue] {
  // Both actual Account decisions are made again here. Merely retaining a
  // previous allow observation cannot authorize this read.
  match self.require_request(original, facts) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !self.selection.data_policy_cids.contains(actual_policy_cid) {
    return Err(PolicyNotSelected)
  }
  let originals = match
    self.read_admission_preimages(original, facts, actual_policy_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match self.require_request(original, facts) {
    Ok(_) => Ok(originals)
    Err(issue) => Err(issue)
  }
}

///|
// Archive integrity only. This neither observes Store nor authorizes a read.
fn NativeLocalReadPolicyBinding::read_admission_preimages(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
  actual_policy_cid : String,
) -> Result[NativeLocalReadAdmissionOriginals, NativeLocalReadBindingIssue] {
  // The original stdout constructor cannot certify internal material. Its
  // separate receiver/schema/ordering and physical-loan join is mandatory.
  let material = if self.selection.sink == Material {
    match self.material_original {
      Some(value) => Some(value)
      None => return Err(MaterialUnavailable)
    }
  } else {
    None
  }
  let file = if self.selection.sink == File {
    match self.file_original {
      Some(value) => Some(value)
      None => return Err(FileOutputUnavailable)
    }
  } else {
    None
  }
  let authorization = match
    local_read_preimage(
      self.crypto,
      [
        (
          "account_configuration_cid",
          Text(self.host.session.configuration.configuration_cid()),
        ),
        ("adoption_cid", Text(self.host.adoption_cid)),
        ("attempt_id", Text(facts.request.attempt_id)),
        ("authority_scope_cid", Text(self.scope)),
        ("connection", Text(self.connection)),
        ("decisions", AllowedReads(facts.request.result_name)),
        ("domain", Text("native_local_read.authorization_context")),
        ("format", Text(facts.request.format)),
        (
          "original_request_scope_cid",
          Text(@host.client_request_scope_cid(original)),
        ),
        ("principal_id", Text(self.principal)),
        ("purpose", Text(facts.request.purpose)),
        ("read_original_cid", Text(self.selection_cid)),
        ("result_name", Text(facts.request.result_name)),
        ("run_definition_cid", Text(facts.request.run_definition_cid)),
      ],
      material~,
      file~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let ceiling = match
    local_read_preimage(
      self.crypto,
      [
        ("data_policy_cids", Texts(self.selection.data_policy_cids)),
        ("domain", Text("native_local_read.data_ceiling")),
        ("expires_at", Text(self.expires_at)),
        ("max_bytes", Quantity(self.selection.max_bytes)),
        ("max_uses", Quantity(self.selection.max_uses)),
        ("read_original_cid", Text(self.selection_cid)),
      ],
      material~,
      file~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let egress = match
    local_read_preimage(
      self.crypto,
      [
        ("attempt_id", Text(facts.request.attempt_id)),
        ("authority_scope_cid", Text(self.scope)),
        ("authorization_context_cid", Text(authorization.cid)),
        ("data_ceiling_cid", Text(ceiling.cid)),
        ("domain", Text("native_local_read.egress_admission")),
        ("effective_data_policy_cid", Text(actual_policy_cid)),
        ("expires_at", Text(self.expires_at)),
        ("format", Text(facts.request.format)),
        ("material_generation_cid", Text(facts.material_generation_cid)),
        ("max_bytes", Quantity(self.selection.max_bytes)),
        ("max_uses", Quantity(self.selection.max_uses)),
        ("principal_id", Text(self.principal)),
        ("public_index_entry_cid", Text(facts.public_index_entry_cid)),
        ("purpose", Text(facts.request.purpose)),
        ("read_original_cid", Text(self.selection_cid)),
        ("result_artifact_cid", Text(facts.result_artifact_cid)),
        ("result_definition_cid", Text(facts.result_definition_cid)),
        ("result_manifest_cid", Text(facts.result_manifest_cid)),
        ("result_name", Text(facts.request.result_name)),
        ("run_definition_cid", Text(facts.request.run_definition_cid)),
        (
          "sink",
          Text(
            if material is Some(_) {
              "material"
            } else if file is Some(_) {
              "file"
            } else {
              "stdout"
            },
          ),
        ),
      ],
      material~,
      file~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  Ok({ authorization, ceiling, egress, })
}
