// This provider owns the request and observation semantics for a bounded
// create operation. The common Host owns approval, capture, claims, sends,
// recovery and cleanup. There is no Read or Compute contribution here.

///|
fn field(fields : Array[@source.Field], name : String) -> @source.Value? {
  for item in fields {
    if item.key == name {
      return Some(item.value.value)
    }
  }
  None
}

///|
#export_name("externalEffectRequestJson")
pub fn external_effect_request_json(key : String, note : String) -> String {
  if key.is_empty() ||
    key.length() > external_effect_key_units ||
    note.is_empty() ||
    note.length() > external_effect_note_units {
    return ({ "refused": "InvalidExternalEffectRequest" } : Json).stringify()
  }
  let body : Json = { "key": key.to_json(), "note": note.to_json() }
  ({ "body": body.stringify().to_json() } : Json).stringify()
}

///|
#export_name("externalEffectObservationJson")
pub fn external_effect_observation_json(
  status : Int,
  body : Bytes,
  expected_key : String,
) -> String {
  let unknown = external_effect_unknown().stringify()
  guard @source.parse_json_bytes_preserving(body, {
      max_input_bytes: external_effect_response_bytes,
      max_nodes: external_effect_response_nodes,
      max_depth: external_effect_response_depth,
    })
    is Ok(node) else {
    return unknown
  }
  guard node.value is Object(fields) else { return unknown }
  if status == 201 && fields.length() == 2 {
    guard field(fields, "id") is Some(String(id)) &&
      !id.is_empty() &&
      id.length() <= external_effect_key_units &&
      field(fields, "key") is Some(String(key)) &&
      key == expected_key else {
      return unknown
    }
    return external_effect_success(id).stringify()
  }
  if status == 400 && fields.length() == 1 {
    guard field(fields, "error") is Some(String(code)) && code == "invalid_note" else {
      return unknown
    }
    return external_effect_failure().stringify()
  }
  unknown
}

///|
fn external_effect_success(id : String) -> Json {
  {
    "kind": "typed-success-response",
    "outcome": { "state": "applied", "result": { "id": id.to_json() } },
  }
}

///|
fn external_effect_failure() -> Json {
  {
    "kind": "typed-failure-response",
    "outcome": {
      "state": "failed",
      "error": {
        "code": "ExternalNoteRejected",
        "message": "The note was rejected",
      },
    },
  }
}

///|
fn external_effect_unknown() -> Json {
  { "kind": "unclassified-response" }
}
