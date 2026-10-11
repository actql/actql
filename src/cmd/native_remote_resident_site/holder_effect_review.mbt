///|
/// Independently installed typed Provider configuration is never a projection
/// of a poll or candidate materials. Preparation joins completed holders and
/// their journal through existing Original, capture and normalization Owners.
fn prepare_holder_effect_review(
  task : HolderTaskCustody,
  tasks : Map[String, HolderTaskCustody],
  journal : @journal.Journal,
  policy : @effect_review.NativeResidentEffectReviewPolicy,
) -> Bool {
  if task.released || task.release_requested {
    return false
  }
  // A replay retains the same owner. It cannot refresh policy or replace
  // original inputs, and this projection grants no write authority.
  if task.effect_review is Some(_) {
    return true
  }
  if task.effect_review_cleanup is Some(pending) {
    if !pending.close() {
      return false
    }
    task.effect_review_cleanup = None
  }
  guard task.consumer is Some(consumer) &&
    task.producer_identity is Some(identity) &&
    tasks.get(identity) is Some(producer) &&
    !producer.released &&
    producer.effect_producer is Some(original) else {
    return false
  }
  let context = match
    consumer.prepare_effect_review_inputs(
      journal,
      original,
      journal,
      policy.stage,
      0,
      policy.retention,
      policy.export_limits,
      // The existing finite one-Source/two-task capture fixture uses this
      // connection budget. It is not a language-level Run-count restriction.
      4,
      policy.max_work,
      policy.preview_limits.max_wire_bytes,
      policy.preview_limits.max_nodes,
      policy.preview_limits.max_depth,
    ) {
    Ok(value) => value
    Err(failure) => {
      task.effect_review_cleanup = failure.pending
      return false
    }
  }
  match
    @effect_review.prepare_native_resident_effect_review_from_original_materials(
      consumer, journal, context, policy,
    ) {
    Ok(review) => {
      task.effect_review = Some(review)
      true
    }
    Err(failure) => {
      task.effect_review_cleanup = failure.pending
      false
    }
  }
}

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
  true
}

///|
/// Publish only the exact live task's prepared Review. A pending Store write,
/// typed ACK or artifact upload retains this Owner for explicit retry; it is
/// neither ordinary Output success nor approval or dispatch cleanup.
fn publish_holder_effect_review(
  task : HolderTaskCustody,
  configuration : @effect_review.NativeResidentEffectReviewPublication,
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
  match
    review.publish_review(
      resources.store,
      resources.control,
      configuration,
      authorize_evidence_read,
    ) {
    Ok(original) => {
      report("effect-review-reported", [
        ("request_cid", review.dispatch_identity()),
        (
          "report_cid",
          @remote.remote_effect_checkpoint_report_identity(original),
        ),
      ])
      true
    }
    Err(_) => {
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
  policy : (@remote.DispatchRequest) -> @effect_review.NativeResidentEffectReviewPolicy?,
  publication : (@remote.DispatchRequest) -> @effect_review.NativeResidentEffectReviewPublication?,
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
    guard policy(task.request) is Some(installed) else { return false }
    if !prepare_holder_effect_review(task, tasks, journal, installed) {
      report("effect-review-pending", [
        ("request_cid", @remote.dispatch_request_identity(task.request)),
        ("reason", "original-custody"),
      ])
      return false
    }
  }
  guard publication(task.request) is Some(installed) else { return false }
  publish_holder_effect_review(
    task, installed, resources, authorize_evidence_read,
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
