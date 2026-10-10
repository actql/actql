///|
/// Delivery of an original approved Resolution to the original retained
/// holder. The transported claim identifies the delivery, not current
/// permission: the receiver must observe and fence the existing resume Owner.
struct RemoteEffectResumeDelivery {
  report : RemoteEffectCheckpointReport
  resolution : @checkpoint.VerifiedResolution
  claim : @checkpoint.ResumeClaim
  body : String
}

///|
pub fn prepare_remote_effect_resume_delivery(
  report : RemoteEffectCheckpointReport,
  resolution : @checkpoint.VerifiedResolution,
  claim : @checkpoint.ResumeClaim,
  limits : @checkpoint.WireLimits,
) -> Result[RemoteEffectResumeDelivery, DispatchIssue] {
  if claim.claimant.is_empty() ||
    @utf8.encode(claim.claimant).length() > 256 ||
    claim.generation <= 0L ||
    resolution.decision != @checkpoint.Approved ||
    resolution.checkpoint_cid != report.checkpoint.checkpoint_cid ||
    resolution.resume_intent_id !=
    @checkpoint.resume_intent_id(
      resolution.checkpoint_cid,
      resolution.resolution_cid,
      limits,
    ) ||
    resolution.resume_intent_id is None ||
    effect_checkpoint_report(report.dispatch, report.checkpoint, limits)
    is Err(_) {
    return Err(InvalidDispatch)
  }
  // The common Resolution Owner admits the wrapper identity and approved
  // decision. Physical Host signature verification and current independent
  // Reviewer authorization remain mandatory at the Native receiving boundary.
  guard @checkpoint.resumed_approval(resolution.wire, limits) is Ok(approval) &&
    approval.checkpoint_cid == resolution.checkpoint_cid &&
    approval.resolution_cid == resolution.resolution_cid &&
    approval.verified_resolution_cid == resolution.verified_resolution_cid else {
    return Err(InvalidDispatch)
  }
  let writer = @encode.writer(limits.max_wire_bytes, 32, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("checkpoint_cid", resolution.checkpoint_cid),
        ("claimant", claim.claimant),
        ("dispatch_request_cid", report.dispatch.dispatch_request_cid),
        ("generation", claim.generation.to_string()),
        ("report_cid", report.report_cid),
        ("resolution_cid", resolution.resolution_cid),
        ("resolution_wire", resolution.wire),
        ("resume_intent_id", resolution.resume_intent_id.unwrap()),
        ("version", "actql-remote-effect-resume-delivery/0.1"),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    Ok({ report, resolution, claim, body: @encode.finish(writer), })
  } catch {
    _ => Err(InvalidDispatch)
  }
}

///|
/// Reconstruct against the receiver's original report and independently
/// installed authentication. Submitted Checkpoints, keys or claims cannot
/// replace those Owners. This parser performs no Provider write or cleanup.
pub fn admit_remote_effect_resume_delivery_json(
  body : String,
  original : RemoteEffectCheckpointReport,
  authentication : @checkpoint.HostAuthentication,
  reviewers : Array[@checkpoint.ReviewerAuthority],
  limits : @checkpoint.WireLimits,
) -> Result[RemoteEffectResumeDelivery, DispatchIssue] {
  try {
    let fields = evidence_object(
      evidence_root(body, limits.max_wire_bytes, 32, 2),
      [
        "checkpoint_cid", "claimant", "dispatch_request_cid", "generation", "report_cid",
        "resolution_cid", "resolution_wire", "resume_intent_id", "version",
      ],
    )
    if evidence_text(fields, "version") !=
      "actql-remote-effect-resume-delivery/0.1" ||
      evidence_text(fields, "checkpoint_cid") !=
      original.checkpoint.checkpoint_cid ||
      evidence_text(fields, "dispatch_request_cid") !=
      original.dispatch.dispatch_request_cid ||
      evidence_text(fields, "report_cid") != original.report_cid {
      raise EvidenceJsonStop
    }
    let attested = match
      @checkpoint.admit_attested_effect_resolution(
        original.checkpoint,
        evidence_text(fields, "resolution_wire"),
        authentication,
        reviewers,
        limits,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let delivery = match
      prepare_remote_effect_resume_delivery(
        original,
        attested.resolution,
        {
          claimant: evidence_text(fields, "claimant"),
          generation: evidence_text_int64(fields, "generation"),
        },
        limits,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    // Byte equality also rejects substituted Resolution/intent identities,
    // extra fields, duplicate keys, alternate integer forms and reserialization.
    if delivery.body != body {
      raise EvidenceJsonStop
    }
    Ok(delivery)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_effect_resume_delivery_json(
  delivery : RemoteEffectResumeDelivery,
) -> String {
  delivery.body
}

///|
pub fn remote_effect_resume_delivery_resolution(
  delivery : RemoteEffectResumeDelivery,
) -> @checkpoint.VerifiedResolution {
  delivery.resolution
}

///|
pub fn remote_effect_resume_delivery_claim(
  delivery : RemoteEffectResumeDelivery,
) -> @checkpoint.ResumeClaim {
  delivery.claim
}

///|
pub fn remote_effect_resume_delivery_dispatch(
  delivery : RemoteEffectResumeDelivery,
) -> DispatchRequest {
  delivery.report.dispatch
}
