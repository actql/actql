///|
struct ParsedClientPublicationBinding {
  binding_cid : String
  effective_max : Int64
  resolved_limit_cid : String
  subject_ref : String
  kind : String
  measure : String
  result_name : String
  unit_definition_cid : String
  unit : String
  version : String
} derive(Eq, Debug)

///|
pub(all) enum ClientPublicationBindingAdmissionIssue {
  MissingPublication
  InvalidBinding
  MismatchedBinding
  Encoding
} derive(Eq, Debug)

///|
fn binding_text(object : @decode.ObjectView, key : String) -> String? {
  match @decode.required(object, key) {
    Err(_) => None
    Ok(value) =>
      match @decode.text(value) {
        Err(_) => None
        Ok(text) => Some(text)
      }
  }
}

///|
fn binding_integer(object : @decode.ObjectView, key : String) -> Int64? {
  match @decode.required(object, key) {
    Err(_) => None
    Ok(value) =>
      match @decode.safe_integer(value) {
        Err(_) => None
        Ok(number) => Some(number)
      }
  }
}

///|
fn parse_client_publication_binding(
  body : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> ParsedClientPublicationBinding? {
  if max_wire_bytes < 0 || body.length() > max_wire_bytes {
    return None
  }
  let bytes = @utf8.encode(body)
  guard @source.parse_json_bytes(bytes, {
      max_input_bytes: max_wire_bytes,
      max_nodes,
      max_depth,
    })
    is Ok(parsed) else {
    return None
  }
  guard @decode.admit(parsed, {
      max_nodes,
      max_depth,
      max_string_bytes: max_wire_bytes,
      max_total_string_bytes: max_wire_bytes,
    })
    is Ok(root) else {
    return None
  }
  guard @decode.closed_object(root, [
      "binding_cid", "effective_max", "resolved_limit_cid", "subject_ref", "target",
      "unit", "version",
    ])
    is Ok(object) else {
    return None
  }
  guard @decode.required(object, "target") is Ok(target_cursor) else {
    return None
  }
  guard @decode.closed_object(target_cursor, [
      "kind", "measure", "result_name", "unit_definition_cid",
    ])
    is Ok(target) else {
    return None
  }
  guard binding_text(object, "binding_cid") is Some(binding_cid) else {
    return None
  }
  guard binding_integer(object, "effective_max") is Some(effective_max) else {
    return None
  }
  guard binding_text(object, "resolved_limit_cid") is Some(resolved_limit_cid) else {
    return None
  }
  guard binding_text(object, "subject_ref") is Some(subject_ref) else {
    return None
  }
  guard binding_text(target, "kind") is Some(kind) else { return None }
  guard binding_text(target, "measure") is Some(measure) else { return None }
  guard binding_text(target, "result_name") is Some(result_name) else {
    return None
  }
  guard binding_text(target, "unit_definition_cid") is Some(unit_definition_cid) else {
    return None
  }
  guard binding_text(object, "unit") is Some(unit) else { return None }
  guard binding_text(object, "version") is Some(version) else { return None }
  Some({
    binding_cid,
    effective_max,
    resolved_limit_cid,
    subject_ref,
    kind,
    measure,
    result_name,
    unit_definition_cid,
    unit,
    version,
  })
}

///|
/// Validate saved private Plan material against a freshly checked Unit port.
/// This checks one binding, not completeness of the whole Plan's limit set.
pub fn admit_prepared_client_publication_binding(
  value : PreparedClientProgram,
  unit : Int,
  index : Int,
  scope : ClientPublicationLimitScope,
  body : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientPublicationBindingAdmissionIssue] {
  let expected = match
    emit_prepared_client_publication_binding(
      value, unit, index, scope, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(body) => body
    Err(MissingPublication) => return Err(MissingPublication)
    Err(MismatchedCheckedLimit) => return Err(MismatchedBinding)
    Err(Encoding) => return Err(Encoding)
  }
  guard parse_client_publication_binding(
      expected, max_wire_bytes, max_nodes, max_depth,
    )
    is Some(expected_fields) else {
    return Err(Encoding)
  }
  guard parse_client_publication_binding(
      body, max_wire_bytes, max_nodes, max_depth,
    )
    is Some(actual_fields) else {
    return Err(InvalidBinding)
  }
  if actual_fields != expected_fields {
    return Err(MismatchedBinding)
  }
  Ok(())
}
