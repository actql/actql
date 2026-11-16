///|
#export_name("clientProgramRecoveredContentIssuerKind")
pub fn client_program_recovered_content_issuer_kind(
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_text_units : Int,
) -> Result[String, @publication.GeneratedContentReferenceIssue] {
  @publication.recovered_content_issuer_kind(wire, {
    max_bytes,
    max_nodes,
    max_depth,
    max_text_units,
  })
}

///|
#export_name("clientProgramEffectKeyedOriginalSourceEvidenceFacts")
pub fn client_program_effect_keyed_original_source_evidence_facts(
  original : @publication_host.ClientEffectKeyedOriginal,
  owner : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[Array[String], @publication_host.ClientEffectCommandContentIssue] {
  @publication_host.client_effect_keyed_original_source_evidence_facts(
    original, owner, request,
  )
}

///|
#export_name("clientProgramRecoveredSourceContentCandidate")
pub fn client_program_recovered_source_content_candidate(
  original : @publication_host.ClientEffectKeyedOriginal,
  owner : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  reference_wire : String,
  binding_wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_text_units : Int,
) -> Result[
  @publication_host.ClientCapturedContent,
  @publication.GeneratedContentReferenceIssue,
] {
  @publication_host.prepare_client_recovered_source_content_candidate(
    original,
    owner,
    request,
    reference_wire,
    binding_wire,
    { max_bytes, max_nodes, max_depth, max_text_units, },
  )
}

///|
#export_name("clientProgramRecoverSourceEffectCommandContent")
pub fn client_program_recover_source_effect_command_content(
  original : @publication_host.ClientEffectKeyedOriginal,
  owner : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  captured : @publication.PublicationContract,
  preview : @publication.EffectPreviewIdentity,
  invocation : @publication.PublicationContract,
  source : @publication.CapturedEffectSourceArtifact,
  store_authority_cid : String,
  member_index : Int,
  row : Int,
  input_name : String,
  candidate : @publication_host.ClientCapturedContent,
  content : @admitted.CheckedValue,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.RecoveredClientEffectSourceCommandContent,
  @publication_host.ClientEffectCommandContentIssue,
] {
  @publication_host.readmit_client_effect_source_command_content(
    original, owner, request, definition, captured, preview, invocation, source,
    store_authority_cid, member_index, row, input_name, candidate, content, max_fields,
    max_work, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramRecoveredSourceEffectCommandContentCurrent")
pub fn client_program_recovered_source_effect_command_content_current(
  value : @publication_host.RecoveredClientEffectSourceCommandContent,
) -> Bool {
  @publication_host.recovered_client_effect_source_command_content_current(
    value,
  )
}

///|
#export_name("clientProgramRecoveredSourceEffectCommandContentMatches")
pub fn client_program_recovered_source_effect_command_content_matches(
  value : @publication_host.RecoveredClientEffectSourceCommandContent,
  original : @publication_host.ClientEffectKeyedOriginal,
  owner : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  captured : @publication.PublicationContract,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row : Int,
  input_name : String,
) -> Bool {
  @publication_host.recovered_client_effect_source_command_content_matches(
    value, original, owner, request, definition, captured, preview, member_index,
    row, input_name,
  )
}

///|
#export_name("clientProgramRecoveredSourceEffectCommandContentMatchesIssued")
pub fn client_program_recovered_source_effect_command_content_matches_issued(
  value : @publication_host.RecoveredClientEffectSourceCommandContent,
  content : @admitted.CheckedValue,
) -> Bool {
  @publication_host.recovered_client_effect_source_command_content_matches_issued(
    value, content,
  )
}

///|
#export_name("clientProgramRecoveredSourceEffectCommandContentWire")
pub fn client_program_recovered_source_effect_command_content_wire(
  value : @publication_host.RecoveredClientEffectSourceCommandContent,
) -> Result[String, @publication_host.ClientEffectCommandContentIssue] {
  @publication_host.recovered_client_effect_source_command_content_wire(value)
}

///|
#export_name("clientProgramRecoveredSourceEffectCommandContentRelease")
pub fn client_program_recovered_source_effect_command_content_release(
  value : @publication_host.RecoveredClientEffectSourceCommandContent,
) -> Unit {
  @publication_host.release_recovered_client_effect_source_command_content(
    value,
  )
}

///|
#export_name("clientProgramRecoveredSourceContentConstructionCapacity")
pub fn client_program_recovered_source_content_construction_capacity(
  reference_wire : String,
  binding_wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_text_units : Int,
  role : String,
) -> @execution.ExecutionCapacity? {
  @publication_host.recovered_source_content_construction_capacity(
    reference_wire,
    binding_wire,
    { max_bytes, max_nodes, max_depth, max_text_units, },
    role,
  )
}
