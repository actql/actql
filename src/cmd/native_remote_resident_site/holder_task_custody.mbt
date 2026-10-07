///|
/// Physical custody retained by this holder for one exact checked dispatch.
/// The common Owners still admit its task, edge, transfer and start claim.
/// A linear producer has one outgoing handoff; its successor keeps a separate
/// input borrow, Runtime, output reports and payload cleanup responsibility.
priv struct HolderTaskCustody {
  request : @remote.DispatchRequest
  producer_identity : String?
  consumer : @resident_host.ResidentRetainedConsumer?
  process_hold : Ref[@bundle.NativeActiveRuntimeBinding?]
  mut executed : @resident_host.ResidentExecuted?
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
) -> HolderTaskCustody {
  {
    request,
    producer_identity,
    consumer,
    process_hold: Ref(None),
    executed,
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
fn release_holder_task(
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
  task.released = true
  if !control_ended {
    ignore(
      @client.acknowledge_status(
        environment.journal,
        resources.control,
        resources.observation_url,
        task.request,
      ),
    )
  }
  true
}
