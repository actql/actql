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
