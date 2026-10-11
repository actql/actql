///|
/// Independent operator installation for the authenticated Cloud control
/// read. The client must use the configured Cloud TLS trust and Site
/// credential; neither its URL nor its credentials come from delivery wire.
/// The fresh challenge and local clock are trusted caller ports. This owns
/// no Run, approval, Ledger, Provider credential or cleanup responsibility.
pub(all) struct NativeEffectCloudCurrentRead {
  client : @http.Client
  url : String
  current_site : () -> Bool
  next_query_id : () -> String
  now_ms : () -> Int64
}

///|
priv struct CloudResumeExpected {
  dispatch_cid : String
  report_cid : String
  checkpoint_cid : String
  resolution_cid : String
  intent_id : String
  claim : @checkpoint.ResumeClaim
}

///|
priv suberror CloudResumeReadStop {
  InvalidRead
}

///|
fn[T] cloud_resume_decoded(
  value : Result[T, @decode.Issue],
) -> T raise CloudResumeReadStop {
  match value {
    Ok(value) => value
    Err(_) => raise InvalidRead
  }
}

///|
fn cloud_resume_text(
  object : @decode.ObjectView,
  name : String,
) -> String raise CloudResumeReadStop {
  cloud_resume_decoded(
    @decode.text(cloud_resume_decoded(@decode.required(object, name))),
  )
}

///|
fn cloud_resume_integer(
  object : @decode.ObjectView,
  name : String,
) -> Int64 raise CloudResumeReadStop {
  cloud_resume_decoded(
    @decode.safe_integer(cloud_resume_decoded(@decode.required(object, name))),
  )
}

///|
fn cloud_resume_query_label(value : String) -> Bool {
  if value.is_empty() || @utf8.encode(value).length() > 256 {
    return false
  }
  for character in value {
    let code = character.to_int()
    if code < 32 || code == 127 {
      return false
    }
  }
  true
}

///|
fn cloud_resume_query_body(
  expected : CloudResumeExpected,
  query_id : String,
  limits : @checkpoint.WireLimits,
) -> Bytes? {
  if !cloud_resume_query_label(query_id) ||
    !cloud_resume_query_label(expected.claim.claimant) ||
    expected.claim.generation <= 0L ||
    expected.claim.generation > 9007199254740991L {
    return None
  }
  let writer = @encode.writer(
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return None
  }
  try {
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("version", "actql-cloud-effect-resume-query/0.1"),
        ("queryId", query_id),
        ("dispatchCid", expected.dispatch_cid),
        ("reportCid", expected.report_cid),
        ("checkpointCid", expected.checkpoint_cid),
        ("resolutionCid", expected.resolution_cid),
        ("intentId", expected.intent_id),
        ("claimant", expected.claim.claimant),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "generation")
    @encode.decimal_number_value(writer, expected.claim.generation.to_string())
    @encode.end_object(writer)
    Some(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => None
  }
}

///|
/// Private framing decoder invoked only after the configured authenticated
/// HTTP read. No public arbitrary-wire-to-observation admission is exported.
/// Local time and the returned existing claimed view feed the common fence;
/// the server's diagnostic observedAt never supplies the caller's clock.
fn cloud_resume_reply(
  body : Bytes,
  expected : CloudResumeExpected,
  query_id : String,
  now_ms : Int64,
  limits : @checkpoint.WireLimits,
) -> NativeEffectResumeObservation? {
  if now_ms < 0L || now_ms > 9007199254740991L {
    return None
  }
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
    cloud_resume_reply_cursor(root, expected, query_id, now_ms)
  } catch {
    InvalidRead => None
  }
}

///|
fn cloud_resume_reply_cursor(
  root : @decode.Cursor,
  expected : CloudResumeExpected,
  query_id : String,
  now_ms : Int64,
) -> NativeEffectResumeObservation? {
  if now_ms < 0L || now_ms > 9007199254740991L {
    return None
  }
  try {
    let fields = cloud_resume_decoded(
      @decode.closed_object(root, [
        "version", "queryId", "dispatchCid", "reportCid", "claim", "observedAt",
      ]),
    )
    if cloud_resume_text(fields, "version") !=
      "actql-cloud-effect-resume-current/0.1" ||
      cloud_resume_text(fields, "queryId") != query_id ||
      cloud_resume_text(fields, "dispatchCid") != expected.dispatch_cid ||
      cloud_resume_text(fields, "reportCid") != expected.report_cid ||
      cloud_resume_text(fields, "observedAt").length() != 24 {
      raise InvalidRead
    }
    let claim_fields = cloud_resume_decoded(
      @decode.closed_object(
        cloud_resume_decoded(@decode.required(fields, "claim")),
        [
          "intentId", "checkpointCid", "resolutionCid", "state", "generation", "claimant",
          "leaseExpiresMs", "mode",
        ],
      ),
    )
    let generation = cloud_resume_integer(claim_fields, "generation")
    let claimant = cloud_resume_text(claim_fields, "claimant")
    let lease_expires_ms = cloud_resume_integer(claim_fields, "leaseExpiresMs")
    if cloud_resume_text(claim_fields, "intentId") != expected.intent_id ||
      cloud_resume_text(claim_fields, "checkpointCid") !=
      expected.checkpoint_cid ||
      cloud_resume_text(claim_fields, "resolutionCid") !=
      expected.resolution_cid ||
      cloud_resume_text(claim_fields, "state") != "claimed" ||
      cloud_resume_text(claim_fields, "mode") != "resume" ||
      claimant != expected.claim.claimant ||
      generation != expected.claim.generation {
      raise InvalidRead
    }
    let view : @checkpoint.ResumeIntentView = {
      state: @checkpoint.ResumeClaimed,
      generation,
      claimant,
      lease_expires_ms,
    }
    if @checkpoint.decide_resume_fence(view, expected.claim, now_ms) !=
      @checkpoint.FenceCurrent {
      raise InvalidRead
    }
    Some({
      checkpoint_cid: expected.checkpoint_cid,
      resolution_cid: expected.resolution_cid,
      resume_intent_id: expected.intent_id,
      view,
      claim: expected.claim,
      now_ms,
      settlement_only: false,
    })
  } catch {
    InvalidRead => None
  }
}

///|
/// Bind an installed real control read to this Review's original report,
/// durable ACK and independently authenticated Resolution. The closure does
/// a fresh HTTP read on every invocation and never renews or sends an Effect.
/// Plug it into the existing observe_resume port; Host, Reviewer, physical
/// Site and Provider authorization remain separately required by that Owner.
pub fn NativeResidentEffectReview::cloud_resume_observer(
  self : NativeResidentEffectReview,
  body : String,
  authentication : @checkpoint.HostAuthentication,
  reviewers : Array[@checkpoint.ReviewerAuthority],
  control : NativeEffectCloudCurrentRead,
  limits : @checkpoint.WireLimits,
) -> Result[
  () -> NativeEffectResumeObservation?,
  NativeResidentEffectWriteIssue,
] {
  guard self.current() &&
    (control.current_site)() &&
    self.retention is Some(retention) else {
    return Err(AuthorityDenied)
  }
  let report = match retention.report() {
    Ok(value) => value
    Err(_) => return Err(Unavailable)
  }
  if self.confirm_original_review_report(report, limits, true) is Err(_) {
    return Err(Unavailable)
  }
  let delivery = match
    @remote.admit_remote_effect_resume_delivery_json(
      body, report, authentication, reviewers, limits,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignRequest)
  }
  let resolution = @remote.remote_effect_resume_delivery_resolution(delivery)
  guard resolution.resume_intent_id is Some(intent_id) else {
    return Err(ForeignRequest)
  }
  let expected : CloudResumeExpected = {
    dispatch_cid: @remote.dispatch_request_identity(
      @remote.remote_effect_resume_delivery_dispatch(delivery),
    ),
    report_cid: @remote.remote_effect_checkpoint_report_identity(report),
    checkpoint_cid: resolution.checkpoint_cid,
    resolution_cid: resolution.resolution_cid,
    intent_id,
    claim: @remote.remote_effect_resume_delivery_claim(delivery),
  }
  let mut previous_query : String? = None
  Ok(() => {
    if !self.current() || !(control.current_site)() {
      return None
    }
    let query_id = (control.next_query_id)()
    if previous_query == Some(query_id) {
      return None
    }
    previous_query = Some(query_id)
    guard cloud_resume_query_body(expected, query_id, limits)
      is Some(query_body) else {
      return None
    }
    let reply = match control.client.post_json(control.url, query_body) {
      Ok(value) if value.status == 200 => value
      _ => return None
    }
    let observed = cloud_resume_reply(
      reply.body,
      expected,
      query_id,
      (control.now_ms)(),
      limits,
    )
    if !self.current() || !(control.current_site)() {
      return None
    }
    observed
  })
}

///|
/// Use the original row Owner with an independently installed Cloud read.
/// The installation's signing/Reviewer/Provider roles are unchanged; only
/// its current resume port is supplied by the authenticated original read.
pub fn NativeResidentEffectReview::execute_remote_approved_row_with_cloud_current(
  self : NativeResidentEffectReview,
  body : String,
  configuration : NativeResidentEffectResumeConfiguration,
  control : NativeEffectCloudCurrentRead,
  current_site : () -> Bool,
) -> Result[
  (@publication.PublicationContract, @effect.EffectLedgerEntry),
  NativeResidentEffectWriteIssue,
] {
  let observe_resume = match
    self.cloud_resume_observer(
      body,
      configuration.authentication,
      configuration.reviewers,
      control,
      configuration.limits.ledger,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.execute_remote_approved_row(
    body,
    { ..configuration, observe_resume, },
    current_site,
  )
}
