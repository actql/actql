///|
priv struct NativeLocalReadPreimage {
  wire : String
  cid : String
}

///|
// Pure encoding/digest DATA in the existing command capture. Exact typed
// inputs distinguish purposes, policies and physical destination originals;
// the result is neither an Account outcome nor an admission/cleanup ACK.
priv struct NativeLocalReadPreimageObservation {
  crypto : @crypto.Library
  fields : Array[(String, @host.ClientLocalReadEvidenceValue)]
  value : NativeLocalReadPreimage
}

///|
fn local_read_preimage_fields_equal(
  left : Array[(String, @host.ClientLocalReadEvidenceValue)],
  right : Array[(String, @host.ClientLocalReadEvidenceValue)],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index = 0; index < left.length(); index = index + 1 {
    let (left_name, left_value) = left[index]
    let (right_name, right_value) = right[index]
    if left_name != right_name {
      return false
    }
    let same = match (left_value, right_value) {
      (Text(a), Text(b)) | (AllowedReads(a), AllowedReads(b)) => a == b
      (Quantity(a), Quantity(b)) => a == b
      (Texts(a), Texts(b)) => a == b
      _ => false
    }
    if !same {
      return false
    }
  }
  true
}

///|
fn local_read_preimage_original_fields(
  fields : Array[(String, @host.ClientLocalReadEvidenceValue)],
) -> Array[(String, @host.ClientLocalReadEvidenceValue)] {
  fields.map(entry => {
    let (name, value) = entry
    let original = match value {
      // Retain the actual elements, not an alias that a later input mutation
      // could make equal to itself while its old wire/CID remains unchanged.
      Texts(values) => @host.Texts(values.map(value => value))
      _ => value
    }
    (name, original)
  })
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
  capture? : NativeLocalJournalCapture? = None,
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
  if capture is Some(owner) {
    if owner.closing ||
      owner.read_operation_issue is Some(_) ||
      (owner.read_callback_active && !owner.read_facts_valid) {
      if owner.read_callback_active {
        if owner.read_operation_issue is None {
          owner.read_operation_issue = Some(OriginalResourceScopePending)
        }
        owner.clear_read_operation_facts()
      }
      return Err(CustodyLost)
    }
    if owner.read_callback_active {
      guard owner.opening is JournalAcquired(host) &&
        owner.read_facts_valid &&
        host.journal.operation_active else {
        owner.read_operation_issue = Some(OriginalResourceScopePending)
        owner.clear_read_operation_facts()
        return Err(CustodyLost)
      }
      for observed in owner.read_preimages {
        if physical_equal(observed.crypto, crypto) &&
          local_read_preimage_fields_equal(observed.fields, fields) {
          // Separate pure retained-value hits from actual encode/digest work.
          native_timing_count(44)
          return Ok(observed.value)
        }
      }
    }
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
  let value = { wire, cid, }
  if capture is Some(owner) &&
    owner.read_callback_active &&
    owner.read_facts_valid &&
    owner.read_operation_issue is None {
    owner.read_preimages.push({
      crypto,
      fields: local_read_preimage_original_fields(fields),
      value,
    })
  }
  Ok(value)
}

///|
fn NativeLocalReadPolicyBinding::read_admission_originals(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
  actual_policy_cid : String,
) -> Result[NativeLocalReadAdmissionOriginals, NativeLocalReadBindingIssue] {
  // Admit the distinct current Run-read and named-Result-read tuples at entry.
  // Encoding and hashing immutable preimages invoke no application callback
  // or external dispatch, so they consume that same observation.
  match self.require_request(original, facts) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.read_admission_preimages(original, facts, actual_policy_cid)
}

///|
// Archive integrity only. This neither observes Store nor authorizes a read.
fn NativeLocalReadPolicyBinding::read_admission_preimages(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
  actual_policy_cid : String,
) -> Result[NativeLocalReadAdmissionOriginals, NativeLocalReadBindingIssue] {
  let policy_cids = match
    self.selected_policy_cids(original, facts, actual_policy_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
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
      capture=self.capture,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let ceiling = match
    local_read_preimage(
      self.crypto,
      [
        ("data_policy_cids", Texts(policy_cids)),
        ("domain", Text("native_local_read.data_ceiling")),
        ("expires_at", Text(self.expires_at)),
        ("max_bytes", Quantity(self.selection.max_bytes)),
        ("max_uses", Quantity(self.selection.max_uses)),
        ("read_original_cid", Text(self.selection_cid)),
      ],
      material~,
      file~,
      capture=self.capture,
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
      capture=self.capture,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  Ok({ authorization, ceiling, egress, })
}
