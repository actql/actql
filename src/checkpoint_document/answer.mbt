///|
pub(all) enum CandidateIssue {
  InvalidLimits
  InvalidWire
  InvalidField(String)
  InvalidShape
  UnsupportedProfile
  InvalidRequirements
  OutsideWindow
  Encoding
} derive(Eq, Debug)

///|
priv suberror CandidateStop {
  CandidateStop(CandidateIssue)
}

///|
/// Immutable candidate DATA only. No sealed Checkpoint, durable custody,
/// current reviewer, signing permission or Run can be obtained from this value.
pub struct AnswerPreparation {
  summary : @json.CanonicalValue
  approval : @json.CanonicalValue?
  approval_preimage : String?
  decision : String
  actor : String
  key_id : String
  decided_at : String
  effect : Bool
  run_subject : Bool
  limits : Limits
}

///|
/// The same candidate's unsigned Resolution and optional signed Evidence.
/// The external application still owns actual signature callbacks and keys.
pub struct AnswerResolution {
  body : @json.CanonicalValue
  preimage : String
  evidence_wire : String
  checkpoint_cid : String
  key_id : String
  limits : Limits
}

///|
// Match the existing Summary schema's scalar counts without allocating a
// codepoint array or normalizing DATA. parse_wire already admits scalar text.
fn candidate_text_fits(text : String, maximum : Int, control_id : Bool) -> Bool {
  let mut count = 0
  for scalar in text.iter() {
    if count == maximum {
      return false
    }
    count += 1
    let code = scalar.to_int()
    if control_id && (code < 32 || code == 127) {
      return false
    }
  }
  true
}

///|
fn candidate_field(
  value : @json.CanonicalValue,
  key : String,
) -> String raise CandidateStop {
  guard string_field(value, key) is Some(text) &&
    candidate_text_fits(text, 256, true) &&
    canonical_text(text) else {
    raise CandidateStop(InvalidField(key))
  }
  text
}

///|
fn candidate_cid(
  value : @json.CanonicalValue,
  key : String,
) -> String raise CandidateStop {
  let text = candidate_field(value, key)
  if !valid_cid(text) {
    raise CandidateStop(InvalidField(key))
  }
  text
}

///|
fn candidate_object(
  value : @json.CanonicalValue,
  key : String,
) -> @json.CanonicalValue raise CandidateStop {
  guard @json.object_field(value, key) is Some(object) &&
    @json.object_fields(object) is Some(_) else {
    raise CandidateStop(InvalidField(key))
  }
  object
}

///|
fn candidate_shape(
  value : @json.CanonicalValue,
  required : Array[String],
  optional : Array[String],
) -> Unit raise CandidateStop {
  if closed_shape(value, required, optional) is Some(_) {
    raise CandidateStop(InvalidShape)
  }
}

///|
fn signer_token(value : String) -> Bool {
  if value.is_empty() || value.length() > 128 {
    return false
  }
  for unit in value {
    let code = unit.to_int()
    if !((code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      (code >= 48 && code <= 57) ||
      unit == '.' ||
      unit == '_' ||
      unit == ':' ||
      unit == '-') {
      return false
    }
  }
  true
}

///|
fn candidate_canonical(
  value : Json,
  limits : Limits,
) -> @json.CanonicalValue raise CandidateStop {
  guard canonical_of(value, limits) is Some(body) else {
    raise CandidateStop(Encoding)
  }
  body
}

///|
fn candidate_identity(
  value : @json.CanonicalValue,
  limits : Limits,
) -> String raise CandidateStop {
  guard cid_of(value, limits) is Some(cid) else {
    raise CandidateStop(Encoding)
  }
  cid
}

///|
/// Prepare unsigned candidate documents from the complete public Summary DATA.
/// Missing private continuation/unit material is never manufactured or used to
/// reconstruct a SealedCheckpoint. Host admission remains independent.
pub fn prepare_answer_candidate(
  summary_wire : String,
  decision : String,
  key_id : String,
  actor : String,
  authority_scope_cid : String?,
  decided_at : String,
  limits : Limits,
) -> Result[AnswerPreparation, CandidateIssue] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  if decision != "approved" && decision != "rejected" {
    return Err(InvalidField("decision"))
  }
  if !signer_token(key_id) || !signer_token(actor) {
    return Err(InvalidField("signer"))
  }
  guard parse_wire(summary_wire, limits) is Some(summary) else {
    return Err(InvalidWire)
  }
  try {
    candidate_shape(
      summary,
      [
        "checkpointId", "checkpointCid", "kind", "phase", "subject", "requiredArtifact",
        "reviewProjectionCid", "requirements", "createdAt", "expiresAt", "humanSummary",
      ],
      ["preparedInvocationCid"],
    )
    ignore(candidate_field(summary, "checkpointId"))
    ignore(candidate_cid(summary, "checkpointCid"))
    ignore(candidate_cid(summary, "reviewProjectionCid"))
    guard string_field(summary, "humanSummary") is Some(display) &&
      candidate_text_fits(display, 1024, false) else {
      raise CandidateStop(InvalidField("humanSummary"))
    }
    let kind = candidate_field(summary, "kind")
    let phase = candidate_field(summary, "phase")
    let subject = candidate_object(summary, "subject")
    let subject_kind = candidate_field(subject, "kind")
    guard candidate_profile_flags(subject_kind, phase, kind)
      is Some((effect, run_subject, separate_prepared)) else {
      raise CandidateStop(UnsupportedProfile)
    }
    if run_subject {
      candidate_shape(subject, ["kind", "runId", "runDefinitionCid"], [])
      ignore(candidate_field(subject, "runId"))
      ignore(candidate_cid(subject, "runDefinitionCid"))
    } else {
      candidate_shape(subject, ["kind", "prepareAttemptId", "requestId"], [])
      ignore(candidate_field(subject, "prepareAttemptId"))
      ignore(candidate_field(subject, "requestId"))
    }
    let artifact = candidate_object(summary, "requiredArtifact")
    candidate_shape(artifact, ["type", "cid"], [])
    let required_cid = candidate_cid(artifact, "cid")
    if artifact_type(kind) != Some(candidate_field(artifact, "type")) {
      raise CandidateStop(UnsupportedProfile)
    }
    guard @json.object_field(summary, "requirements")
      is Some(@json.Array(items)) &&
      requirement_max_arity(kind) is Some(maximum) &&
      @json.array_count(items) <= maximum else {
      raise CandidateStop(InvalidRequirements)
    }
    guard string_list_field(summary, "requirements") is Some(requirements) &&
      requirements_valid(kind, requirements) else {
      raise CandidateStop(InvalidRequirements)
    }
    let prepared_cid = if separate_prepared {
      candidate_cid(summary, "preparedInvocationCid")
    } else {
      if @json.object_field(summary, "preparedInvocationCid") is Some(_) {
        raise CandidateStop(UnsupportedProfile)
      }
      required_cid
    }
    let created_at = candidate_field(summary, "createdAt")
    let expires_at = candidate_field(summary, "expiresAt")
    if !valid_timestamp(created_at) ||
      !valid_timestamp(expires_at) ||
      !valid_timestamp(decided_at) {
      raise CandidateStop(InvalidField("time"))
    }
    if created_at >= expires_at ||
      decided_at < created_at ||
      decided_at >= expires_at {
      raise CandidateStop(OutsideWindow)
    }
    let approval = if decision == "rejected" {
      None
    } else {
      let fields : Map[String, Json] = {
        "version": Json::string(
          if effect {
            "actql-approval-attestation/0.1"
          } else {
            "actql-run-scope-approval/0.1"
          },
        ),
        "review_projection_cid": Json::string(
          candidate_cid(summary, "reviewProjectionCid"),
        ),
        "approver": Json::string(actor),
        "approved_at": Json::string(decided_at),
      }
      if effect {
        guard authority_scope_cid is Some(authority) && valid_cid(authority) else {
          raise CandidateStop(InvalidField("authority_scope_cid"))
        }
        fields["effect_preview_cid"] = Json::string(required_cid)
        fields["authority_scope_cid"] = Json::string(authority)
        fields["claims"] = string_array_json(requirements)
      } else {
        fields["prepared_invocation_cid"] = Json::string(prepared_cid)
        fields["claim"] = Json::string("invocation_scope_approved")
        fields["expires_at"] = Json::string(expires_at)
      }
      Some(candidate_canonical(Json::object(fields), limits))
    }
    let approval_preimage = match approval {
      Some(body) => Some(candidate_identity(body, limits))
      None => None
    }
    Ok({
      summary,
      approval,
      approval_preimage,
      decision,
      actor,
      key_id,
      decided_at,
      effect,
      run_subject,
      limits,
    })
  } catch {
    CandidateStop(issue) => Err(issue)
  }
}

///|
/// Sign UTF-8 bytes of this CID text, never the raw JSON document.
pub fn answer_candidate_approval_preimage(value : AnswerPreparation) -> String? {
  value.approval_preimage
}

///|
fn candidate_with_value(
  body : @json.CanonicalValue,
  key : String,
  child : @json.CanonicalValue,
  limits : Limits,
) -> @json.CanonicalValue raise CandidateStop {
  guard @json.object_fields(body) is Some(fields) else {
    raise CandidateStop(Encoding)
  }
  try {
    let material = @json.start_material(
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    errdefer @json.cancel_material(material)
    @json.material_begin_object(material)
    let mut inserted = false
    for (name, value) in fields {
      if name == key {
        raise @json.DuplicateKey(key)
      }
      if !inserted && @canonical.compare_utf16(key, name) < 0 {
        @json.material_key(material, key)
        while !@json.advance_material(material) {
          ()
        }
        @json.material_value(material, child)
        while !@json.advance_material(material) {
          ()
        }
        inserted = true
      }
      @json.material_key(material, name)
      while !@json.advance_material(material) {
        ()
      }
      @json.material_value(material, value)
      while !@json.advance_material(material) {
        ()
      }
    }
    if !inserted {
      @json.material_key(material, key)
      while !@json.advance_material(material) {
        ()
      }
      @json.material_value(material, child)
      while !@json.advance_material(material) {
        ()
      }
    }
    @json.material_end_object(material)
    @json.finish_material(material).0
  } catch {
    _ => raise CandidateStop(Encoding)
  }
}

///|
fn candidate_with_proof(
  body : @json.CanonicalValue,
  key_id : String,
  signature : String,
  self_field : String,
  limits : Limits,
) -> @json.CanonicalValue raise CandidateStop {
  if !reviewer_signature_valid(signature) {
    raise CandidateStop(InvalidField("proof.signature"))
  }
  let proof = candidate_canonical(
    Json::object({
      "scheme": Json::string("ed25519-v1"),
      "key_id": Json::string(key_id),
      "signature": Json::string(signature),
    }),
    limits,
  )
  let signed = candidate_with_value(body, "proof", proof, limits)
  let identity = candidate_identity(signed, limits)
  guard @json.object_with_string_field(signed, self_field, identity)
    is Some(complete) else {
    raise CandidateStop(Encoding)
  }
  complete
}

///|
/// Only an approved candidate consumes an actual approval signature. Rejection
/// carries no Evidence and cannot spend an unrelated signature as approval.
pub fn prepare_answer_resolution(
  value : AnswerPreparation,
  approval_signature : String?,
) -> Result[AnswerResolution, CandidateIssue] {
  try {
    let mut evidence_wire = ""
    let fields : Map[String, Json] = {
      "version": Json::string("actql-checkpoint-resolution/0.1"),
      "resolution_id": Json::string(
        "resolution-" +
        candidate_field(value.summary, "checkpointId") +
        "-" +
        value.decision,
      ),
      "checkpoint_id": Json::string(
        candidate_field(value.summary, "checkpointId"),
      ),
      "checkpoint_cid": Json::string(
        candidate_cid(value.summary, "checkpointCid"),
      ),
      "decision": Json::string(value.decision),
      "actor": Json::string(value.actor),
      "decided_at": Json::string(value.decided_at),
      "required_artifact_cid": Json::string(
        candidate_cid(
          candidate_object(value.summary, "requiredArtifact"),
          "cid",
        ),
      ),
      "review_projection_cid": Json::string(
        candidate_cid(value.summary, "reviewProjectionCid"),
      ),
    }
    let subject = candidate_object(value.summary, "subject")
    if value.run_subject {
      fields["run_id"] = Json::string(candidate_field(subject, "runId"))
      fields["run_definition_cid"] = Json::string(
        candidate_cid(subject, "runDefinitionCid"),
      )
    } else {
      fields["prepare_attempt_id"] = Json::string(
        candidate_field(subject, "prepareAttemptId"),
      )
    }
    match (value.approval, approval_signature) {
      (None, None) => ()
      (Some(body), Some(signature)) => {
        let signed = candidate_with_proof(
          body,
          value.key_id,
          signature,
          if value.effect {
            "attestation_cid"
          } else {
            "run_scope_approval_cid"
          },
          value.limits,
        )
        let evidence = candidate_canonical(
          Json::object({
            "version": Json::string("actql-checkpoint-approval-evidence/0.1"),
            "kind": Json::string(candidate_field(value.summary, "kind")),
            "checkpoint_cid": Json::string(
              candidate_cid(value.summary, "checkpointCid"),
            ),
            "review_projection_cid": Json::string(
              candidate_cid(value.summary, "reviewProjectionCid"),
            ),
          }),
          value.limits,
        )
        let evidence = candidate_with_value(
          evidence,
          "compatibility_approval",
          signed,
          value.limits,
        )
        fields["approval_evidence_cid"] = Json::string(
          candidate_identity(evidence, value.limits),
        )
        guard wire_of(evidence, value.limits) is Some(wire) else {
          raise CandidateStop(Encoding)
        }
        evidence_wire = wire
      }
      _ => raise CandidateStop(InvalidField("approval_signature"))
    }
    let body = candidate_canonical(Json::object(fields), value.limits)
    Ok({
      body,
      preimage: candidate_identity(body, value.limits),
      evidence_wire,
      checkpoint_cid: candidate_cid(value.summary, "checkpointCid"),
      key_id: value.key_id,
      limits: value.limits,
    })
  } catch {
    CandidateStop(issue) => Err(issue)
  }
}

///|
pub fn answer_resolution_preimage(value : AnswerResolution) -> String {
  value.preimage
}

///|
/// Return existing wire candidates. Same Host verification, current admission
/// and durable commit are mandatory; this function never issues their witness.
pub fn finish_answer_candidate(
  value : AnswerResolution,
  signature : String,
) -> Result[(String, String, String), CandidateIssue] {
  try {
    let body = candidate_with_proof(
      value.body,
      value.key_id,
      signature,
      "resolution_cid",
      value.limits,
    )
    guard wire_of(body, value.limits) is Some(wire) else {
      raise CandidateStop(Encoding)
    }
    Ok((value.checkpoint_cid, wire, value.evidence_wire))
  } catch {
    CandidateStop(issue) => Err(issue)
  }
}
