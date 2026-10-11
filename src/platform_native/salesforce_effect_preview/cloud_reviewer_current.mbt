///|
/// Trusted configured TLS control endpoint and selected Site scope. Query
/// framing supplies no authority; Cloud independently selects original custody.
pub(all) struct NativeEffectCloudReviewerScope {
  site_key : String
  site_generation : Int64
  workspace_id : String
  authority_scope_cid : String
  installation : String
}

///|
pub(all) struct NativeEffectCloudReviewerRead {
  control : NativeEffectCloudCurrentRead
  scope : NativeEffectCloudReviewerScope
}

///|
priv struct CloudReviewerSnapshot {
  registration : NativeEffectReviewerRegistration
  observation : NativeEffectResumeObservation
}

///|
fn cloud_reviewer_reply(
  body : Bytes,
  expected : CloudResumeExpected,
  query_id : String,
  installed : NativeEffectCloudReviewerScope,
  now_ms : Int64,
  limits : @checkpoint.WireLimits,
) -> CloudReviewerSnapshot? {
  let source = match
    @source.parse_json_bytes_preserving(body, {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  try {
    let root = cloud_resume_decoded(
      @decode.admit(source, {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_string_bytes: limits.max_wire_bytes,
        max_total_string_bytes: limits.max_wire_bytes,
      }),
    )
    let fields = cloud_resume_decoded(
      @decode.closed_object(root, [
        "version", "siteKey", "siteGeneration", "current", "reviewer",
      ]),
    )
    if cloud_resume_text(fields, "version") !=
      "actql-cloud-effect-resume-reviewer-current/0.1" ||
      cloud_resume_text(fields, "siteKey") != installed.site_key ||
      cloud_resume_integer(fields, "siteGeneration") !=
      installed.site_generation ||
      installed.site_generation <= 0L ||
      installed.site_generation > 9007199254740991L {
      raise InvalidRead
    }
    let observed = match
      cloud_resume_reply_cursor(
        cloud_resume_decoded(@decode.required(fields, "current")),
        expected,
        query_id,
        now_ms,
      ) {
      Some(value) => value
      None => raise InvalidRead
    }
    let reviewer = cloud_resume_decoded(
      @decode.closed_object(
        cloud_resume_decoded(@decode.required(fields, "reviewer")),
        [
          "scheme", "checkpointCid", "installation", "workspaceId", "authorityScopeCid",
          "principalId", "reviewerId", "keyId", "publicKeyBase64", "approvalAuthorityScopeCid",
          "authorityContextCid", "policyCid",
        ],
      ),
    )
    if cloud_resume_text(reviewer, "scheme") != "ed25519-v1" ||
      cloud_resume_text(reviewer, "checkpointCid") != expected.checkpoint_cid ||
      cloud_resume_text(reviewer, "workspaceId") != installed.workspace_id ||
      cloud_resume_text(reviewer, "authorityScopeCid") !=
      installed.authority_scope_cid ||
      cloud_resume_text(reviewer, "installation") != installed.installation {
      raise InvalidRead
    }
    let principal_id = cloud_resume_text(reviewer, "principalId")
    let key_id = cloud_resume_text(reviewer, "keyId")
    let reviewer_id = cloud_resume_text(reviewer, "reviewerId")
    let scope = cloud_resume_text(reviewer, "approvalAuthorityScopeCid")
    let context = cloud_resume_text(reviewer, "authorityContextCid")
    let policy = cloud_resume_text(reviewer, "policyCid")
    if !cloud_resume_query_label(principal_id) ||
      !native_reviewer_identifier(key_id) ||
      !native_reviewer_identifier(reviewer_id) ||
      !native_reviewer_cid(scope) ||
      !native_reviewer_cid(context) ||
      !native_reviewer_cid(policy) {
      raise InvalidRead
    }
    let raw = cloud_resume_text(reviewer, "publicKeyBase64")
    let key = @base64.decode(raw[:]) catch { _ => raise InvalidRead }
    if key.length() != 32 || @base64.encode(key) != raw {
      raise InvalidRead
    }
    // Ed25519 SubjectPublicKeyInfo, using the existing Native PEM verifier.
    // No wire-supplied algorithm/DER/secret is accepted.
    let der = b"\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00" + key
    let pem = "-----BEGIN PUBLIC KEY-----\n" +
      @base64.encode(der) +
      "\n-----END PUBLIC KEY-----\n"
    Some({
      observation: observed,
      registration: {
        selection: { principal_id, checkpoint_cid: expected.checkpoint_cid, },
        key_id,
        reviewer_id,
        public_key_pem: pem,
        approval_authority_scope_cid: scope,
        authority_context_cid: context,
        policy_cid: policy,
      },
    })
  } catch {
    InvalidRead => None
  }
}

///|
/// Framing only, bound to the original retained report. Full Resolution,
/// Reviewer and Host admission still follows in authenticate_remote_reviewer.
fn cloud_reviewer_expected(
  body : String,
  report : @remote.RemoteEffectCheckpointReport,
  limits : @checkpoint.WireLimits,
) -> CloudResumeExpected? {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(body), {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  try {
    let root = cloud_resume_decoded(
      @decode.admit(source, {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_string_bytes: limits.max_wire_bytes,
        max_total_string_bytes: limits.max_wire_bytes,
      }),
    )
    let fields = cloud_resume_decoded(
      @decode.closed_object(root, [
        "checkpoint_cid", "claimant", "dispatch_request_cid", "generation", "report_cid",
        "resolution_cid", "resolution_wire", "resume_intent_id", "version",
      ]),
    )
    let dispatch_cid = cloud_resume_text(fields, "dispatch_request_cid")
    let report_cid = cloud_resume_text(fields, "report_cid")
    let checkpoint_cid = cloud_resume_text(fields, "checkpoint_cid")
    let resolution_cid = cloud_resume_text(fields, "resolution_cid")
    let intent_id = cloud_resume_text(fields, "resume_intent_id")
    let checkpoint = @remote.remote_effect_checkpoint_report_checkpoint(report)
    if cloud_resume_text(fields, "version") !=
      "actql-remote-effect-resume-delivery/0.1" ||
      report_cid != @remote.remote_effect_checkpoint_report_identity(report) ||
      dispatch_cid !=
      @remote.dispatch_request_identity(
        @remote.remote_effect_checkpoint_report_dispatch(report),
      ) ||
      checkpoint_cid != checkpoint.checkpoint_cid ||
      !native_reviewer_cid(resolution_cid) ||
      !native_reviewer_cid(intent_id) {
      raise InvalidRead
    }
    Some({
      dispatch_cid,
      report_cid,
      checkpoint_cid,
      resolution_cid,
      intent_id,
      claim: {
        claimant: cloud_resume_text(fields, "claimant"),
        generation: cloud_resume_integer(fields, "generation"),
      },
    })
  } catch {
    InvalidRead => None
  }
}

///|
/// Install the existing Native verifier from one scoped trusted Cloud read.
/// The original principal is returned by Cloud custody, never inferred from
/// the signer or Site operator. Every verification rereads the same current
/// context/claim; this creates no approval or Provider permit and sends no work.
pub fn NativeResidentEffectReview::cloud_reviewer_installation(
  self : NativeResidentEffectReview,
  body : String,
  installed : NativeEffectCloudReviewerRead,
  crypto : @signature.Library,
  limits : @checkpoint.WireLimits,
) -> Result[
  (String, NativeEffectReviewerInstallation),
  NativeResidentEffectResolutionIssue,
] {
  guard self.current() &&
    (installed.control.current_site)() &&
    installed.control.url.has_prefix("https://") &&
    installed.control.url.has_suffix("/outbound/effect-resume-reviewer-current") &&
    self.retention is Some(retention) else {
    return Err(AuthorityDenied)
  }
  let report = match retention.report() {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  if self.confirm_original_review_report(report, limits, true) is Err(_) {
    return Err(Unavailable)
  }
  guard cloud_reviewer_expected(body, report, limits) is Some(expected) else {
    return Err(AttestationRejected)
  }
  let execution_scope = @remote.dispatch_request_execution_scope(
    @remote.remote_effect_checkpoint_report_dispatch(report),
  )
  if execution_scope[0] != installed.scope.site_key ||
    execution_scope[1] != installed.scope.site_generation.to_string() {
    return Err(AttestationRejected)
  }
  let mut previous_query : String? = None
  let read = () => {
    if !self.current() || !(installed.control.current_site)() {
      return None
    }
    let query_id = (installed.control.next_query_id)()
    if previous_query == Some(query_id) {
      return None
    }
    previous_query = Some(query_id)
    guard cloud_resume_query_body(expected, query_id, limits)
      is Some(query_body) else {
      return None
    }
    let reply = match
      installed.control.client.post_json(installed.control.url, query_body) {
      Ok(value) if value.status == 200 => value
      _ => return None
    }
    let snapshot = cloud_reviewer_reply(
      reply.body,
      expected,
      query_id,
      installed.scope,
      (installed.control.now_ms)(),
      limits,
    )
    if !self.current() || !(installed.control.current_site)() {
      return None
    }
    snapshot
  }
  guard read() is Some(original) else { return Err(Unavailable) }
  let registration = original.registration
  Ok(
    (
      registration.selection.principal_id,
      {
        crypto,
        current_site: () => self.current() && (installed.control.current_site)(),
        read_current: (selected, key_id) => {
          if selected != registration.selection || key_id != registration.key_id {
            return None
          }
          guard read() is Some(current) else { return None }
          if current.registration != registration ||
            @checkpoint.decide_resume_fence(
              current.observation.view,
              current.observation.claim,
              (installed.control.now_ms)(),
            ) !=
            @checkpoint.FenceCurrent {
            return None
          }
          Some(current.registration)
        },
      },
    ),
  )
}

///|
/// Use the same Native signature/Host/checkpoint admission with the scoped
/// original-principal Cloud context. The returned authentication alone cannot
/// claim execution, send an Effect, publish a Result or discharge cleanup.
pub fn NativeResidentEffectReview::authenticate_remote_reviewer_with_cloud(
  self : NativeResidentEffectReview,
  body : String,
  installed : NativeEffectCloudReviewerRead,
  crypto : @signature.Library,
  host_authorities : Array[NativeEffectHostAuthority],
  current_authority : () -> Bool,
  now : () -> String,
  limits : @checkpoint.WireLimits,
) -> Result[@checkpoint.HostAuthentication, NativeResidentEffectResolutionIssue] {
  let (principal, installation) = match
    self.cloud_reviewer_installation(body, installed, crypto, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.authenticate_remote_reviewer(
    body, principal, installation, host_authorities, current_authority, now,
  )
}
