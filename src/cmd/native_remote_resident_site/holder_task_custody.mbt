///|
/// Physical custody retained by this holder for one exact checked dispatch.
/// The common Owners still admit its task, edge, transfer and start claim.
/// A linear producer has one outgoing handoff; its successor keeps a separate
/// input borrow, Runtime, output reports and payload cleanup responsibility.
priv struct HolderTaskCustody {
  request : @remote.DispatchRequest
  producer_identity : String?
  mut consumer : @resident_host.ResidentRetainedConsumer?
  process_hold : Ref[@bundle.NativeActiveRuntimeBinding?]
  mut executed : @resident_host.ResidentExecuted?
  mut effect_producer : @resident_host.ResidentEffectProducerExecuted?
  mut effect_review : @effect_review.NativeResidentEffectReview?
  mut effect_review_cleanup : @resident_host.ResidentEffectReviewInputContext?
  mut restoration : @resident_host.ResidentCompletedAttempt?
  mut restoration_cleanup : @runtime.NativeRemoteRuntime?
  mut restoration_failed : Bool
  mut handoff : (String, @resident_host.ResidentRetainedTransfer)?
  mut successor_identity : String?
  mut release_requested : Bool
  mut released : Bool
  payloads : Array[@payload.PublicationPayloadRequest]
  failed_cleanups : Array[@resident_host.ResidentOutputIssue]
  unsaved_reports : Array[@remote.RemoteOutputReportCustody]
}

///|
fn new_holder_task_custody(
  request : @remote.DispatchRequest,
  executed : @resident_host.ResidentExecuted?,
  consumer : @resident_host.ResidentRetainedConsumer?,
  producer_identity : String?,
  effect_producer? : @resident_host.ResidentEffectProducerExecuted? = None,
) -> HolderTaskCustody {
  {
    request,
    producer_identity,
    consumer,
    process_hold: Ref(None),
    executed,
    effect_producer,
    effect_review: None,
    effect_review_cleanup: None,
    restoration: None,
    restoration_cleanup: None,
    restoration_failed: false,
    handoff: None,
    successor_identity: None,
    release_requested: false,
    released: false,
    payloads: [],
    failed_cleanups: [],
    unsaved_reports: [],
  }
}

///|
/// This is the existing Runtime's live computation, not a restored capability
/// from equal file bytes. Capture retains its own pins; task cleanup stays with
/// the producer/consumer Runtime and cannot be discharged by this projection.
fn holder_effect_computation(
  task : HolderTaskCustody,
  journal : @journal.Journal,
) -> @resident_host.ResidentSourceCompute? {
  if task.released || task.release_requested {
    return None
  }
  match task.effect_producer {
    Some(producer) => producer.source_for_capture(journal)
    None =>
      match task.consumer {
        Some(consumer) => consumer.effect_computation(journal)
        None => None
      }
  }
}

///|
/// Attach only the already-admitted single successor. Exact replay preserves
/// the same entry; another attempt cannot replace its outstanding custody.
fn remember_holder_successor(
  tasks : Map[String, HolderTaskCustody],
  order : Array[String],
  producer : HolderTaskCustody,
  candidate : HolderTaskCustody,
) -> HolderTaskCustody? {
  let identity = @remote.dispatch_request_identity(candidate.request)
  let producer_identity = @remote.dispatch_request_identity(producer.request)
  if producer.released ||
    candidate.producer_identity != Some(producer_identity) ||
    identity == producer_identity ||
    (producer.successor_identity is Some(saved) && saved != identity) {
    return None
  }
  match tasks.get(identity) {
    Some(saved) => {
      if saved.producer_identity != Some(producer_identity) {
        return None
      }
      Some(saved)
    }
    None => {
      producer.successor_identity = Some(identity)
      tasks.set(identity, candidate)
      order.push(identity)
      Some(candidate)
    }
  }
}

///|
/// A local custody fence, not authority to release a Runtime or receiver.
/// Their existing Owners must subsequently confirm physical cleanup.
fn holder_successor_released(
  task : HolderTaskCustody,
  tasks : Map[String, HolderTaskCustody],
) -> Bool {
  match task.successor_identity {
    None => true
    Some(identity) =>
      match tasks.get(identity) {
        Some(successor) => successor.released
        None => false
      }
  }
}

///|
fn retain_holder_task_reports(
  task : HolderTaskCustody,
  journal : @journal.Journal,
) -> Bool {
  let remaining = task.unsaved_reports.filter(custody => {
    journal.retain_output_report(custody) is Err(_)
  })
  task.unsaved_reports.clear()
  task.unsaved_reports.append(remaining)
  task.unsaved_reports.is_empty()
}

///|
/// Called only after the consumer Owner has closed every acquired resource.
/// EOF can discharge a never-started local owner without inventing a terminal
/// Site record. A saved start claim still requires formal cleanup confirmation.
fn confirm_holder_consumer_cleanup(
  journal : @journal.Journal,
  request : @remote.DispatchRequest,
  control_ended : Bool,
) -> Bool {
  if control_ended {
    match journal.require(request) {
      Err(@journal.MissingDispatch) => return true
      Ok(record) if @remote.remote_runtime_record_startable(record) =>
        return journal.start_claimant(request) is Ok(None)
      _ => ()
    }
  }
  confirm_unstarted_consumer_cleanup(journal, request)
}

///|
fn close_holder_task(
  task : HolderTaskCustody,
  tasks : Map[String, HolderTaskCustody],
  environment : SiteEnvironment,
  execution : @resident_host.ResidentExecution,
  resources : HolderOutputResources,
  control_ended? : Bool = false,
) -> Bool {
  if task.released {
    return true
  }
  if !holder_successor_released(task, tasks) {
    return false
  }
  // A saved outgoing transfer can still be awaiting its consumer. An ordinary
  // producer release does not revoke that responsibility. Control termination
  // or a durable cancellation selects teardown through the existing Owners.
  if task.handoff is Some(_) &&
    task.successor_identity is None &&
    !control_ended &&
    !(environment.journal.cancellation_requested(task.request) is Ok(true)) {
    return false
  }
  if !retain_holder_task_reports(task, environment.journal) {
    return false
  }
  if task.producer_identity is None && !control_ended {
    // The original holder's report handoff still precedes physical teardown.
    // Each released descendant already persisted its own exact report custody.
    holder_checkpoint(resources)("report-handoff")
  }
  // A pending reconstructed owner must finish restoring its exact custody
  // before cleanup can discharge it. Keep that same owner across retries.
  if task.restoration is Some(owner) {
    match owner.advance() {
      @resident_host.ResidentCompletedReady(completed) => {
        task.executed = Some(completed)
        task.restoration = None
      }
      _ => return false
    }
  }
  if task.restoration_cleanup is Some(runtime) {
    if runtime.close() is Err(_) {
      return false
    }
    // Physical close alone does not settle historical dispatch cleanup.
    if !holder_completed_restoration_settled(task, environment.journal) {
      return false
    }
    task.restoration_cleanup = None
  }
  if !holder_completed_restoration_settled(task, environment.journal) {
    return false
  }
  // Review owns separate semantic pins and an export. Retiring it must
  // precede its original consumer, receiver and producer Runtime cleanup.
  if !close_holder_effect_review(task) {
    return false
  }
  if task.handoff is Some((_, handoff)) {
    while handoff.reclaim() is Err(_) {
      report("consumer-release-pending", [("reason", "receiver-cleanup")])
      @slot.native_wait_milliseconds(250)
    }
  }
  if task.executed is Some(completed) {
    settle_holder_cleanup(
      completed.runtime,
      completed.request,
      environment.journal,
      resources.store,
      task.failed_cleanups,
      task.payloads,
      resources.release_failures,
      holder_checkpoint(resources),
      close_store=false,
    )
    task.failed_cleanups.clear()
    task.payloads.clear()
  }
  if task.consumer is Some(owner) {
    while !owner.close() {
      report("consumer-release-pending", [("reason", "borrow-cleanup")])
      @slot.native_wait_milliseconds(250)
    }
  }
  close_untransferred_consumer_binding(execution, task.process_hold)
  // Return this consumer's receiver only after its exact input borrow closes.
  // The producer output remains owned until that producer's own release.
  if task.producer_identity is Some(identity) {
    guard tasks.get(identity) is Some(producer) else { return false }
    if producer.handoff is Some((_, handoff)) {
      while handoff.reclaim() is Err(_) {
        report("consumer-release-pending", [("reason", "receiver-cleanup")])
        @slot.native_wait_milliseconds(250)
      }
    }
  }
  if task.consumer is Some(_) &&
    task.executed is None &&
    !confirm_holder_consumer_cleanup(
      environment.journal,
      task.request,
      control_ended,
    ) {
    return false
  }
  // The consumer's own opaque close and the actual Resource/Review/receiver
  // cleanup above precede this stamp retirement. Do not wait for producer
  // Released: its CapturedDAG Ledger still funds the exact consumer charge.
  if task.consumer is Some(owner) && owner.has_initial_catalog_use_custody() {
    guard task.producer_identity is Some(producer_identity) &&
      tasks.get(producer_identity) is Some(producer) &&
      producer.effect_producer is Some(original) else {
      return false
    }
    if !owner.cleanup_initial_catalog_use(environment.journal, original) {
      return false
    }
  }
  // Clear only after every existing Owner confirmed cleanup. An uncertain
  // release keeps the same reference and responsibility for the next retry.
  task.effect_producer = None
  true
}

///|
/// Physical cleanup is completed once. Its durable observation is repeated
/// for an exact release replay; a lost HTTP response cannot erase that duty.
fn reconcile_holder_task_release(
  task : HolderTaskCustody,
  cleanup : () -> Bool,
  observe : (@remote.DispatchRequest) -> Unit,
  control_ended? : Bool = false,
) -> Bool {
  if !task.released {
    if !cleanup() {
      return false
    }
    task.released = true
  }
  if !control_ended {
    observe(task.request)
  }
  true
}

///|
fn release_holder_task(
  task : HolderTaskCustody,
  tasks : Map[String, HolderTaskCustody],
  environment : SiteEnvironment,
  execution : @resident_host.ResidentExecution,
  resources : HolderOutputResources,
  control_ended? : Bool = false,
) -> Bool {
  reconcile_holder_task_release(
    task,
    () => {
      close_holder_task(
        task,
        tasks,
        environment,
        execution,
        resources,
        control_ended~,
      )
    },
    request => {
      match
        @client.acknowledge_status(
          environment.journal,
          resources.control,
          resources.observation_url,
          request,
        ) {
        Ok(_) => ()
        Err(issue) =>
          report("holder-release-observation-pending", [
            ("request_cid", @remote.dispatch_request_identity(request)),
            ("reason", client_code(issue)),
          ])
      }
    },
    control_ended~,
  )
}

///|
/// Replaying a release also revisits already-cleaned descendants. They keep
/// the same request and report current journal facts without releasing again.
fn handle_holder_release_frame(
  tasks : Map[String, HolderTaskCustody],
  order : Array[String],
  target : String,
  release : (HolderTaskCustody) -> Unit,
) -> Bool {
  guard tasks.get(target) is Some(selected) else { return false }
  selected.release_requested = true
  for index = order.length() - 1; index >= 0; index = index - 1 {
    let task = tasks.get(order[index]).unwrap()
    if task.release_requested {
      release(task)
    }
  }
  true
}

///|
/// Failed restoration is not completed execution or cleanup. Only the existing
/// journal's formal release can settle it without a successfully restored owner.
fn holder_completed_restoration_settled(
  task : HolderTaskCustody,
  journal : @journal.Journal,
) -> Bool {
  if !task.restoration_failed || task.executed is Some(_) {
    return true
  }
  match journal.require(task.request) {
    Ok(record) => @remote.remote_runtime_record_released(record)
    Err(_) => false
  }
}
