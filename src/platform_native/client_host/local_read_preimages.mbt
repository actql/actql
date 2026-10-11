///|
priv enum NativeLocalReadEvidenceValue {
  Text(String)
  Quantity(Int)
  Texts(Array[String])
  AllowedReads(String)
}

///|
priv struct NativeLocalReadPreimage {
  wire : String
  cid : String
}

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
  fields : Array[(String, NativeLocalReadEvidenceValue)],
) -> Result[NativeLocalReadPreimage, NativeClientRunJournalIssue] {
  try {
    let writer = @encode.writer(16384, 256, 8)
    @encode.begin_object(writer)
    let mut previous : String? = None
    for (name, value) in fields {
      if previous is Some(prior) && prior >= name {
        return Err(Encoding)
      }
      previous = Some(name)
      @encode.key(writer, name)
      match value {
        Text(value) => @encode.string_value(writer, value)
        Quantity(value) =>
          @encode.decimal_number_value(writer, value.to_string())
        Texts(values) => {
          @encode.begin_array(writer)
          for value in values {
            @encode.string_value(writer, value)
          }
          @encode.end_array(writer)
        }
        AllowedReads(result_name) => {
          @encode.begin_array(writer)
          for resource in ["run", "result/" + result_name] {
            @encode.begin_object(writer)
            @encode.key(writer, "operation")
            @encode.string_value(writer, "read")
            @encode.key(writer, "outcome")
            @encode.string_value(writer, "allow")
            @encode.key(writer, "resource")
            @encode.string_value(writer, resource)
            @encode.end_object(writer)
          }
          @encode.end_array(writer)
        }
      }
    }
    @encode.end_object(writer)
    let wire = @encode.finish(writer)
    let cid = match local_adoption_digest(crypto, @utf8.encode(wire)) {
      Ok(value) => value
      Err(_) => return Err(Encoding)
    }
    Ok({ wire, cid, })
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
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
  let authorization = match
    local_read_preimage(self.crypto, [
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
      ("read_original_cid", Text(self.file.content_cid)),
      ("result_name", Text(facts.request.result_name)),
      ("run_definition_cid", Text(facts.request.run_definition_cid)),
    ]) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let ceiling = match
    local_read_preimage(self.crypto, [
      ("data_policy_cids", Texts(self.selection.data_policy_cids)),
      ("domain", Text("native_local_read.data_ceiling")),
      ("expires_at", Text(self.selection.expires_at)),
      ("max_bytes", Quantity(self.selection.max_bytes)),
      ("max_uses", Quantity(self.selection.max_uses)),
      ("read_original_cid", Text(self.file.content_cid)),
    ]) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let egress = match
    local_read_preimage(self.crypto, [
      ("attempt_id", Text(facts.request.attempt_id)),
      ("authority_scope_cid", Text(self.scope)),
      ("authorization_context_cid", Text(authorization.cid)),
      ("data_ceiling_cid", Text(ceiling.cid)),
      ("domain", Text("native_local_read.egress_admission")),
      ("effective_data_policy_cid", Text(actual_policy_cid)),
      ("expires_at", Text(self.selection.expires_at)),
      ("format", Text(facts.request.format)),
      ("material_generation_cid", Text(facts.material_generation_cid)),
      ("max_bytes", Quantity(self.selection.max_bytes)),
      ("max_uses", Quantity(self.selection.max_uses)),
      ("principal_id", Text(self.principal)),
      ("public_index_entry_cid", Text(facts.public_index_entry_cid)),
      ("purpose", Text(facts.request.purpose)),
      ("read_original_cid", Text(self.file.content_cid)),
      ("result_artifact_cid", Text(facts.result_artifact_cid)),
      ("result_definition_cid", Text(facts.result_definition_cid)),
      ("result_manifest_cid", Text(facts.result_manifest_cid)),
      ("result_name", Text(facts.request.result_name)),
      ("run_definition_cid", Text(facts.request.run_definition_cid)),
      ("sink", Text("stdout")),
    ]) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  Ok({ authorization, ceiling, egress, })
}
