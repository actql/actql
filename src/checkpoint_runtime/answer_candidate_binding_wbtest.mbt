///|
// A Summary is only candidate DATA. The real sealed original is issued first
// and remains independently required by the existing Runtime decoder below.
fn answer_binding_summary(original : SealedCheckpoint) -> String {
  let request = original.checkpoint
  let subject = match request.subject {
    PrepareAttempt(prepare_attempt_id~) =>
      Json::object({
        "kind": Json::string("prepare_attempt"),
        "prepareAttemptId": Json::string(prepare_attempt_id),
        "requestId": Json::string("independent-request"),
      })
    RunUnit(run_id~, unit_id=_, run_definition_cid~) =>
      Json::object({
        "kind": Json::string("run_unit"),
        "runId": Json::string(run_id),
        "runDefinitionCid": Json::string(run_definition_cid),
      })
  }
  wire_of(
    canonical_of(
      Json::object({
        "checkpointCid": Json::string(original.checkpoint_cid),
        "checkpointId": Json::string(request.checkpoint_id),
        "createdAt": Json::string(request.created_at),
        "expiresAt": Json::string(request.expires_at),
        "humanSummary": Json::string(request.human_summary),
        "kind": Json::string(checkpoint_kind_token(request.kind)),
        "phase": Json::string(
          if request.phase == Preflight {
            "preflight"
          } else {
            "commit"
          },
        ),
        "requiredArtifact": Json::object({
          "cid": Json::string(request.required_artifact_cid),
          "type": Json::string(checkpoint_artifact_type(request.kind)),
        }),
        "requirements": Json::array(
          request.requirements.map(value => {
            Json::string(checkpoint_requirement_token(value))
          }),
        ),
        "reviewProjectionCid": Json::string(request.review_projection_cid),
        "subject": subject,
      }),
      limits(),
    ).unwrap(),
    limits(),
  ).unwrap()
}

///|
test "candidate documents bind to actual sealed preparation and Effect originals without issuing authority" {
  for request in [run_scope_request(), effect_request()] {
    let original = sealed_of(request)
    let prepared = @document.prepare_answer_candidate(
      answer_binding_summary(original),
      "approved",
      "reviewer-key",
      "alice",
      Some(cid("5")),
      "2026-09-25T11:00:00.000Z",
      document_limits(limits()),
    ).unwrap()
    // Zero bytes exercise representation and original binding, not crypto or
    // current authorization. No authentication result or approval is fabricated.
    let resolution = @document.prepare_answer_resolution(
      prepared,
      Some(proof_preparation_encoding_signature),
    ).unwrap()
    let (checkpoint_cid, wire, evidence) = @document.finish_answer_candidate(
      resolution, proof_preparation_encoding_signature,
    ).unwrap()
    assert_eq(checkpoint_cid, original.checkpoint_cid)
    let decoded = decode_resolution(
      parse_wire(wire, limits()).unwrap(),
      original,
      limits(),
    ) catch {
      _ => fail("existing original Resolution binding refused")
    }
    assert_eq(
      decoded.proof_preimage,
      @document.answer_resolution_preimage(resolution),
    )
    let evidence_cid = decoded.approval_evidence_cid.unwrap()
    let checked = check_evidence(
      evidence,
      evidence_cid,
      original,
      "alice",
      cid("5"),
      limits(),
      None,
    ) catch {
      _ => fail("existing original Evidence binding refused")
    }
    assert_eq(wire_of(checked, limits()), Some(evidence))
    let foreign = sealed_of({ ..request, checkpoint_id: "foreign-checkpoint", })
    let refused = try {
      ignore(
        decode_resolution(
          parse_wire(wire, limits()).unwrap(),
          foreign,
          limits(),
        ),
      )
      false
    } catch {
      ResolutionFailed(CheckpointBindingMismatch(_)) => true
      _ => false
    }
    assert_true(refused)
  }
}
