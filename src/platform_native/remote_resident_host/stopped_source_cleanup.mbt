///|
pub(all) enum ResidentStoppedSourceCleanupIssue {
  NotCurrent
  ConsumerReleasePending
  Host(ResidentHostIssue)
  Binding(@host.ClientRetainedTaskInputIssue)
  Receiver(ResidentStoppedRetainedCleanupIssue)
  File(@retained_file.NativeRetainedTaskFileIssue)
  CustodyPending
}

///|
/// Reclaim only the original producer file in the checked sole-consumer
/// profile. The actual executor slot must fence both holder descendants.
/// Consumer formal release, exact receiver cleanup and original file custody
/// are separate prerequisites. No Source/Compute/Output, reservation or
/// execution transition is created. The checked cleanup relationship is returned
/// only after physical confirmation, so callers can discharge the exact consumer
/// component holding through its existing bundle Owner. The release intent is saved before
/// file removal; failed retries retain Releasing and the original custody.
pub fn reclaim_stopped_resident_source_output(
  journal : @journal.Journal,
  admission : ResidentRunAdmission,
  site : @site.ExecutionSite,
  delegation : @resident.ResidentSiteDelegation,
  producer_attempt : String,
  consumer_attempt : String,
  receiver : @transfer_journal.Journal,
  receiver_root : @filesystem.Root,
  producer_root : String,
  limits : @output.NativeRemoteStandardTransferBindingLimits,
  exclusive_current : () -> Bool,
  recorded? : @publication.RecordedRunPublication? = None,
) -> Result[
  @host.ClientRetainedSourceCleanup,
  ResidentStoppedSourceCleanupIssue,
] {
  if !exclusive_current() {
    return Err(NotCurrent)
  }
  let saved_dispatch = attempt => {
    let envelope = match journal.dispatch_envelope(attempt) {
      Ok(Some(value)) => value
      Ok(None) => return Err(ResidentHostIssue::EnvelopeMissing)
      Err(issue) => return Err(ResidentHostIssue::Journal(issue))
    }
    let dispatch = match @remote.admit_remote_poll_dispatch_json(envelope) {
      Ok(value) => value
      Err(issue) => return Err(ResidentHostIssue::Protocol(issue))
    }
    if @remote.dispatch_request_attempt_identity(
        @remote.remote_poll_dispatch_request(dispatch),
      ) !=
      Ok(attempt) {
      return Err(ResidentHostIssue::Protocol(@remote.DispatchIdentityMismatch))
    }
    Ok(dispatch)
  }
  let producer = match saved_dispatch(producer_attempt) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  let consumer = match saved_dispatch(consumer_attempt) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  let request = @remote.remote_poll_dispatch_request(producer)
  let consumer_request = @remote.remote_poll_dispatch_request(consumer)
  guard @remote.remote_poll_dispatch_run_materials(producer) is Some(wire) else {
    return Err(Host(EnvelopeMissing))
  }
  guard admission.source is Some((source_ref, source_contract)) else {
    return Err(Host(Refused(@resident.ForeignSource)))
  }
  // The recorded path is selected explicitly; a failed ordinary admission
  // never falls back to another Plan or grants execution permission.
  let cleanup_graph = match recorded {
    Some(original) => {
      let (run_cid, _) = @remote.dispatch_request_task_scope(request)
      match
        @host.admit_recorded_client_source_cleanup_graph(
          wire,
          run_cid,
          original,
          admission.expressions,
          admission.operations,
          admission.limits,
          source_ref,
          source_contract,
        ) {
        Ok(value) => Some(value)
        Err(issue) => return Err(Binding(issue))
      }
    }
    None => None
  }
  let materials = match cleanup_graph {
    Some(_) => None
    None => {
      let value = match rebuild_materials(admission, request, wire) {
        Ok(value) => value
        Err(issue) => return Err(Host(Refused(issue)))
      }
      if !(resident_source_dispatch_role(value, request)
        is Ok(InternalSourceProducer)) {
        return Err(Host(Refused(@resident.UnsupportedTask)))
      }
      guard @host.prepared_client_source_evidence_facts(value.prepared, 0, 0)
        is Some(facts) else {
        return Err(Host(Refused(@resident.ForeignSource)))
      }
      let selected = @planning.query_source_evidence_fact_values(facts)
      if selected[0] != source_ref || selected[1] != source_contract {
        return Err(Host(Refused(@resident.ForeignSource)))
      }
      Some(value)
    }
  }
  let p = match journal.observation(request) {
    Ok(value) => value
    Err(issue) => return Err(Host(Journal(issue)))
  }
  let c = match journal.observation(consumer_request) {
    Ok(value) => value
    Err(issue) => return Err(Host(Journal(issue)))
  }
  if !@remote.remote_runtime_record_released(
      @journal.recovered_site_dispatch_record(c),
    ) {
    return Err(ConsumerReleasePending)
  }
  guard @journal.recovered_site_dispatch_evidence(p) is Some(pe) &&
    @journal.recovered_site_dispatch_subject(p) is Some(ps) &&
    @journal.recovered_site_dispatch_measurement(p) is Some(pm) &&
    @journal.recovered_site_dispatch_file_custody(p) is Some(file_custody) &&
    @journal.recovered_site_dispatch_evidence(c) is Some(ce) &&
    @journal.recovered_site_dispatch_subject(c) is Some(cs) &&
    @journal.recovered_site_dispatch_measurement(c) is Some(cm) else {
    return Err(CustodyPending)
  }
  let permitted = match (cleanup_graph, materials) {
    (Some(original), None) =>
      @host.prepare_client_retained_source_cleanup_from_recorded(
        original,
        @remote.remote_poll_dispatch_input_binding(consumer),
        @journal.recovered_site_dispatch_record(p),
        pe,
        ps,
        pm,
        @journal.recovered_site_dispatch_record(c),
        ce,
        cs,
        cm,
        limits.max_binding_bytes,
        limits.max_chunks,
        limits.max_manifest_bytes,
        limits.max_referenced_bytes,
      )
    (None, Some(current)) =>
      @host.prepare_client_retained_source_cleanup(
        current,
        @remote.remote_poll_dispatch_input_binding(consumer),
        @journal.recovered_site_dispatch_record(p),
        pe,
        ps,
        pm,
        @journal.recovered_site_dispatch_record(c),
        ce,
        cs,
        cm,
        limits.max_binding_bytes,
        limits.max_chunks,
        limits.max_manifest_bytes,
        limits.max_referenced_bytes,
      )
    _ => return Err(CustodyPending)
  }
  let permit = match permitted {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  let subject = @remote.remote_managed_output_subject_projection(ps)
  if !@journal.native_output_file_custody_matches_request(file_custody, request) ||
    @journal.native_output_file_custody_material_generation(file_custody) !=
    subject[1] ||
    @cleanup_manifest.manifest_cid(
      @journal.native_output_file_custody_manifest(file_custody),
    ) !=
    subject[7] {
    return Err(CustodyPending)
  }
  // This returns only the exact original borrow. Any other durable reader
  // fences receiver reclaim; neither a returned borrow nor Released alone
  // substitutes for confirmation of the receiver's physical Owner.
  match
    reclaim_stopped_resident_retained_input(
      journal, site, delegation, producer_attempt, consumer_attempt, receiver, receiver_root,
      limits, exclusive_current,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Receiver(issue))
  }
  if !exclusive_current() {
    return Err(NotCurrent)
  }
  // Re-read both durable observations after physical receiver reclamation.
  let p = match journal.observation(request) {
    Ok(value) => value
    Err(issue) => return Err(Host(Journal(issue)))
  }
  let c = match journal.observation(consumer_request) {
    Ok(value) => value
    Err(issue) => return Err(Host(Journal(issue)))
  }
  if !@remote.remote_runtime_record_released(
      @journal.recovered_site_dispatch_record(c),
    ) {
    return Err(ConsumerReleasePending)
  }
  guard @journal.recovered_site_dispatch_evidence(p) is Some(pe) &&
    @journal.recovered_site_dispatch_subject(p) is Some(ps) &&
    @journal.recovered_site_dispatch_measurement(p) is Some(pm) &&
    @journal.recovered_site_dispatch_evidence(c) is Some(ce) &&
    @journal.recovered_site_dispatch_subject(c) is Some(cs) &&
    @journal.recovered_site_dispatch_measurement(c) is Some(cm) else {
    return Err(CustodyPending)
  }
  match
    @host.verify_client_retained_source_cleanup_observation(
      permit,
      @journal.recovered_site_dispatch_record(p),
      pe,
      ps,
      pm,
      @journal.recovered_site_dispatch_record(c),
      ce,
      cs,
      cm,
      limits.max_binding_bytes,
      limits.max_chunks,
      limits.max_manifest_bytes,
      limits.max_referenced_bytes,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Binding(issue))
  }
  // Withhold future producer handoffs before deleting bytes. This is the
  // existing release intention, never a cleanup-complete or Released claim.
  // A failed persistence sends nothing to the physical file Owner.
  let producer_record = @journal.recovered_site_dispatch_record(p)
  match @remote.dispatch_record_state(producer_record).2 {
    CleanupReleasing | CleanupReleased => ()
    CleanupActive | CleanupUnknown => {
      let transition = match
        @remote.prepare_begin_remote_release(producer_record) {
        Ok(value) => value
        Err(issue) => return Err(Host(Protocol(issue)))
      }
      match journal.commit_transition(transition) {
        Ok(_) => ()
        Err(issue) => return Err(Host(Journal(issue)))
      }
    }
    CleanupForceLost | CleanupRecoveredAfterLoss => return Err(CustodyPending)
  }
  let file = match
    @retained_file.restore_native_retained_task_file_cleanup(
      producer_root,
      @journal.native_output_file_custody_occurrence(file_custody),
      @journal.native_output_file_custody_generation(file_custody),
      @journal.native_output_file_custody_content_cid(file_custody),
      limits.max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(File(issue))
  }
  if !exclusive_current() {
    return Err(NotCurrent)
  }
  match file.release() {
    Ok(_) =>
      if file.release_confirmed() {
        Ok(permit)
      } else {
        Err(CustodyPending)
      }
    Err(issue) => Err(File(issue))
  }
}
