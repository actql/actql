///|
/// Cleanup failure preserves the exact existing owner for retry. Neither an
/// input close nor a Review close is formal dispatch cleanup or release.
fn close_holder_effect_review(task : HolderTaskCustody) -> Bool {
  if task.effect_review is Some(review) {
    if review.retry_cleanup() is Err(_) {
      return false
    }
    task.effect_review = None
  }
  if task.effect_review_cleanup is Some(pending) {
    if !pending.close() {
      return false
    }
    task.effect_review_cleanup = None
  }
  if task.effect_catalog_review is Some(catalog) {
    if !catalog.close() {
      return false
    }
    task.effect_catalog_review = None
  }
  true
}

///|
/// Independent Host checkpoint parameters. The artifact destination is not an
/// input: it is selected after the original Owner has issued a saved report.
priv struct HolderEffectReviewPublication {
  crypto : @signature.Library
  key : Bytes
  checkpoint_id : String
  created_at : String
  expires_at : String
  limits : @checkpoint.WireLimits
  current : () -> Bool
  access : (Int, @effect_catalog.SingleWriteRequest) -> Result[
    @effect_review.NativeSalesforceTargetAccess,
    @effect_review.NativeSalesforcePreviewIssue,
  ]
}

///|
/// Use the same configured Site/generation route as observations. Only a
/// sealed Checkpoint from the original report supplies the final path member;
/// no candidate URL, future checkpoint identity or new hash is accepted.
fn holder_effect_review_artifact_url(
  observation_url : String,
  checkpoint : @checkpoint.SealedCheckpoint,
) -> String? {
  let suffix = "/outbound/observations"
  if !observation_url.has_prefix("https://") ||
    !observation_url.has_suffix(suffix) {
    return None
  }
  Some(
    observation_url.unsafe_substring(
      start=0,
      end=observation_url.length() - suffix.length(),
    ) +
    "/effect-reviews/" +
    checkpoint.checkpoint_cid,
  )
}

///|
/// Publish only the exact live task's prepared Review. Prepare/save precedes
/// route selection. The existing upload Owner confirms the original typed ACK
/// before sending artifact bytes; each failure keeps the same Review custody.
fn publish_holder_effect_review(
  task : HolderTaskCustody,
  configuration : HolderEffectReviewPublication,
  resources : HolderOutputResources,
  authorize_evidence_read : () -> Bool,
) -> Bool {
  guard !task.released &&
    !task.release_requested &&
    task.effect_review is Some(review) &&
    review.dispatch_identity() ==
    @remote.dispatch_request_identity(task.request) else {
    return false
  }
  let current = () => {
    !task.released &&
    !task.release_requested &&
    authorize_evidence_read() &&
    (configuration.current)()
  }
  let original = (fn() -> @remote.RemoteEffectCheckpointReport? {
    guard current() else { return None }
    guard review.observe(configuration.access) is Ok(_) && current() else {
      return None
    }
    let original = match
      review.persist_and_retain_report(
        resources.store,
        configuration.crypto,
        configuration.key,
        configuration.checkpoint_id,
        configuration.created_at,
        configuration.expires_at,
        configuration.limits,
      ) {
      Ok(original) => original
      Err(_) => return None
    }
    // Select the route only after the original Owner has issued and retained
    // its report. A failed current check leaves all custody with that Owner.
    guard current() &&
      holder_effect_review_artifact_url(
        resources.observation_url,
        @remote.remote_effect_checkpoint_report_checkpoint(original),
      )
      is Some(artifact_url) &&
      current() else {
      return None
    }
    guard review.upload_review_projection(
        resources.control,
        resources.observation_url,
        artifact_url,
        current,
      )
      is Ok(_) else {
      return None
    }
    Some(original)
  })()
  match original {
    Some(original) => {
      report("effect-review-reported", [
        ("request_cid", review.dispatch_identity()),
        (
          "report_cid",
          @remote.remote_effect_checkpoint_report_identity(original),
        ),
      ])
      true
    }
    None => {
      report("effect-review-pending", [
        ("request_cid", review.dispatch_identity()),
        ("reason", "original-custody"),
      ])
      false
    }
  }
}

///|
/// Drive only completed local custody under independently installed policy.
/// This runs at completion or from the control process's local progress tick,
/// never from a remote query. No task index or configuration comes in the tick.
fn drive_holder_effect_review(
  task : HolderTaskCustody,
  tasks : Map[String, HolderTaskCustody],
  journal : @journal.Journal,
  resources : HolderOutputResources,
  installation : (HolderEffectOriginalPolicyContext) -> HolderEffectCatalogReviewCustody?,
  authorize_evidence_read : () -> Bool,
) -> Bool {
  guard !task.released &&
    !task.release_requested &&
    task.executed is Some(_) &&
    task.consumer is Some(_) &&
    authorize_evidence_read() else {
    return false
  }
  if task.effect_review is None {
    guard holder_effect_original_policy_context(task, tasks, journal)
      is Some(original) else {
      return false
    }
    if task.effect_catalog_review is None {
      // Retain acquired handles even when authority changes during setup.
      // Refusing adoption cannot abandon the installation's cleanup owner.
      guard installation(original) is Some(installed) else { return false }
      task.effect_catalog_review = Some(installed)
    }
    guard task.effect_catalog_review is Some(installed) &&
      prepare_holder_effect_catalog_review(
        task, original, journal, resources, installed, authorize_evidence_read,
      ) else {
      report("effect-review-pending", [
        ("request_cid", @remote.dispatch_request_identity(task.request)),
        ("reason", "original-custody"),
      ])
      return false
    }
  }
  // Publication belongs to this exact task's original installation. A later
  // progress tick cannot select a replacement policy or Checkpoint lifetime.
  guard task.effect_catalog_review is Some(installed) else { return false }
  publish_holder_effect_review(
    task,
    installed.publication,
    resources,
    authorize_evidence_read,
  )
}

///|
/// Selection is exact dispatch custody, not only the common Run or request ID.
/// A missing original Review cannot be replaced by the query's report bytes.
fn holder_effect_current_task(
  tasks : Map[String, HolderTaskCustody],
  request : @remote.DispatchRequest,
) -> HolderTaskCustody? {
  let identity = @remote.dispatch_request_identity(request)
  guard tasks.get(identity) is Some(task) &&
    @remote.dispatch_request_identity(task.request) == identity &&
    !task.released else {
    return None
  }
  Some(task)
}

///|
/// Resume only an already retained original Review under independent current
/// Host roles and resume observations. A terminal row receipt is not dispatch
/// completion, Result publication, formal release or physical cleanup.
fn execute_holder_effect_resume(
  task : HolderTaskCustody,
  body : String,
  installation : @effect_review.NativeResidentEffectCloudResumeInstallation,
  control : @effect_review.NativeEffectCloudCurrentRead,
  reviewer_control : @effect_review.NativeEffectCloudCurrentRead,
  current_site : () -> Bool,
) -> Bool {
  let current = () => {
    !task.released && !task.release_requested && current_site()
  }
  guard current() &&
    task.effect_review is Some(review) &&
    review.dispatch_identity() ==
    @remote.dispatch_request_identity(task.request) else {
    return false
  }
  match
    review.execute_remote_approved_row_with_cloud_reviewer(
      body, installation, control, reviewer_control, current,
    ) {
    Ok(_) => {
      report("effect-row-settled", [
        ("request_cid", @remote.dispatch_request_identity(task.request)),
      ])
      true
    }
    Err(_) => {
      report("effect-resume-pending", [
        ("request_cid", @remote.dispatch_request_identity(task.request)),
        ("reason", "original-custody"),
      ])
      false
    }
  }
}

///|
/// Reuse the same operator-configured Site scope and authentication as the
/// observations channel. A candidate delivery supplies no endpoint or origin.
/// A nonstandard URL has no inferred fallback and keeps the original pending.
fn holder_effect_resume_current_url(observation_url : String) -> String? {
  holder_effect_control_read_url(observation_url, "effect-resume-current")
}

///|
fn holder_effect_reviewer_current_url(observation_url : String) -> String? {
  holder_effect_control_read_url(
    observation_url, "effect-resume-reviewer-current",
  )
}

///|
fn holder_effect_control_read_url(
  observation_url : String,
  operation : String,
) -> String? {
  let suffix = "/outbound/observations"
  if !observation_url.has_prefix("https://") ||
    !observation_url.has_suffix(suffix) {
    return None
  }
  Some(
    observation_url.unsafe_substring(
      start=0,
      end=observation_url.length() - suffix.length(),
    ) +
    "/outbound/" +
    operation,
  )
}

///|
/// A bounded fresh challenge for this holder invocation. Sequence exhaustion
/// fails closed; a new query never becomes a new Run or execution identity.
fn holder_effect_resume_query_id(
  dispatch_cid : String,
  now_ms : Int64,
  sequence : Int64,
) -> String? {
  if now_ms < 0L || sequence < 1L || sequence > 9007199254740991L {
    return None
  }
  Some(dispatch_cid + ":" + now_ms.to_string() + ":" + sequence.to_string())
}

///|
/// Route the retained Result through the original Review's saved-response and
/// final Receipt Owners. The ordinary output path stays unchanged; an Effect
/// computation with no installed Review never acquires a Result identity here.
fn holder_result_output(
  task : HolderTaskCustody,
  configuration : (@remote.DispatchRequest) -> @effect_review.NativeResidentEffectCloudResumeInstallation?,
  authorize_evidence_read : () -> Bool,
) -> @resident_host.ResidentExecuted? {
  if task.released || task.release_requested {
    return None
  }
  match task.effect_review {
    None => task.executed
    Some(review) => {
      guard configuration(task.request) is Some(installed) else { return None }
      match
        review.completed_result_output(
          authorize_evidence_read,
          installed.limits,
        ) {
        Ok((executed, _)) => Some(executed)
        Err(_) => {
          report("effect-output-pending", [
            ("request_cid", @remote.dispatch_request_identity(task.request)),
            ("reason", "original-custody"),
          ])
          None
        }
      }
    }
  }
}
