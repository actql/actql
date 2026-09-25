///|
/// Closed protocol values embedded by Run Receipt and Captured Run. They are
/// admitted independently so a later publisher cannot invent or rewrite Run
/// admission and observation evidence while constructing the outer chain.
struct RunEvidenceValue {
  name : String
  identity : String
  wire : String
  value : @json.CanonicalValue
}

///|
pub(all) enum RunEvidenceValueIssue {
  UnknownRunEvidence
  RunEvidenceInvalidLimits
  RunEvidenceInvalidWire
  RunEvidenceInvalidShape
  RunEvidenceIdentityAlreadyPresent
  RunEvidenceIdentityMissing
  RunEvidenceIdentityMismatch
  RunEvidenceEncoding
  RunEvidenceReferenceMismatch(String)
  RunEvidenceContract(PublicationContractIssue)
} derive(Eq, Debug)

///|
fn run_evidence_identity_field(name : String) -> String? {
  match name {
    "invocation_bindings" => Some("invocation_bindings_cid")
    "bound_invocation_template" => Some("bound_invocation_template_cid")
    "prepared_invocation" => Some("prepared_invocation_cid")
    "run_authorization" => Some("run_authorization_cid")
    "observation_set" => Some("observation_set_cid")
    "normalization_journal" => Some("journal_cid")
    "source_evidence" => Some("source_evidence_cid")
    "source_input_logical" => Some("input_logical_cid")
    "authoring_context" => Some("authoring_context_cid")
    "model_invocation_evidence" => Some("model_invocation_evidence_cid")
    _ => None
  }
}

///|
fn run_evidence_value(
  name : String,
  identity_field : String,
  value : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[RunEvidenceValue, RunEvidenceValueIssue] {
  guard optional_string(@json.object_field(value, identity_field))
    is Some(identity) else {
    return Err(RunEvidenceIdentityMissing)
  }
  guard @json.object_without_field(value, identity_field) is Some(preimage) else {
    return Err(RunEvidenceIdentityMissing)
  }
  let expected = @json.cid_value(preimage, max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(RunEvidenceEncoding)
  }
  if expected != identity {
    return Err(RunEvidenceIdentityMismatch)
  }
  let wire = @json.stringify_value(value, max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(RunEvidenceEncoding)
  }
  Ok({ name, identity, wire, value, })
}

///|
/// Establish a closed embedded value and its self identity from a body that
/// omits exactly the registered identity field.
pub fn seal_run_evidence_value(
  name : String,
  body_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[RunEvidenceValue, RunEvidenceValueIssue] {
  guard run_evidence_identity_field(name) is Some(identity_field) else {
    return Err(UnknownRunEvidence)
  }
  if max_wire_bytes < 1 || max_nodes < 2 || max_depth < 1 {
    return Err(RunEvidenceInvalidLimits)
  }
  let body = match
    parse_contract_wire(body_wire, max_wire_bytes, max_nodes - 1, max_depth) {
    Ok(value) => value
    Err(_) => return Err(RunEvidenceInvalidWire)
  }
  if @json.object_field(body, identity_field) is Some(_) {
    return Err(RunEvidenceIdentityAlreadyPresent)
  }
  if !validate_generated_protocol_shape(
      name,
      body,
      false,
      max_wire_bytes,
      max_nodes - 1,
      max_depth,
    ) {
    return Err(RunEvidenceInvalidShape)
  }
  let identity = @json.cid_value(body, max_wire_bytes, max_nodes - 1, max_depth) catch {
    _ => return Err(RunEvidenceEncoding)
  }
  guard @json.object_with_string_field(body, identity_field, identity)
    is Some(complete) else {
    return Err(RunEvidenceInvalidShape)
  }
  if !validate_generated_protocol_shape(
      name, complete, true, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(RunEvidenceInvalidShape)
  }
  run_evidence_value(
    name, identity_field, complete, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Admit existing complete evidence without repairing absent fields or
/// replacing its self identity.
pub fn admit_run_evidence_value(
  name : String,
  complete_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[RunEvidenceValue, RunEvidenceValueIssue] {
  guard run_evidence_identity_field(name) is Some(identity_field) else {
    return Err(UnknownRunEvidence)
  }
  if max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(RunEvidenceInvalidLimits)
  }
  let complete = match
    parse_contract_wire(complete_wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(RunEvidenceInvalidWire)
  }
  if !validate_generated_protocol_shape(
      name, complete, true, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(RunEvidenceInvalidShape)
  }
  run_evidence_value(
    name, identity_field, complete, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
pub fn run_evidence_value_name(value : RunEvidenceValue) -> String {
  value.name
}

///|
pub fn run_evidence_value_identity(value : RunEvidenceValue) -> String {
  value.identity
}

///|
pub fn run_evidence_value_json(value : RunEvidenceValue) -> String {
  value.wire
}

///|
/// Establish the Run-bound Invocation only after the exact ObservationSet has
/// been captured and admitted against its Bound Invocation Template.
pub fn issue_run_invocation(
  template : RunEvidenceValue,
  observation : RunEvidenceValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, RunEvidenceValueIssue] {
  if template.name != "bound_invocation_template" ||
    observation.name != "observation_set" {
    return Err(UnknownRunEvidence)
  }
  if contract_string_from_value(observation.value, "invocation_template_cid") !=
    Some(template.identity) {
    return Err(
      RunEvidenceReferenceMismatch("observation.invocation_template_cid"),
    )
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(RunEvidenceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "invocation_template_cid")
    @encode.string_value(writer, template.identity)
    @encode.key(writer, "observation_set_cid")
    @encode.string_value(writer, observation.identity)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-run-invocation/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(RunEvidenceEncoding)
  }
  let body = @encode.finish(writer) catch {
    _ => return Err(RunEvidenceEncoding)
  }
  match
    seal_publication_contract(
      "run_invocation", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(RunEvidenceContract(issue))
  }
}

///|
fn contract_string_from_value(
  value : @json.CanonicalValue,
  name : String,
) -> String? {
  optional_string(@json.object_field(value, name))
}
