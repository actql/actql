///|
// Acquisition and cleanup address the same exact retained consumer component.
fn consumer_process_hold_identity(request : @remote.DispatchRequest) -> String {
  "consumer:" + @remote.dispatch_request_identity(request)
}

///|
/// The exclusive holder slot proves that no former process can keep using
/// these exact files or readers. Historical binding admission selects the
/// existing cleanup Owners; no payload use or fresh borrow is authorized here.
fn settle_stopped_holder_custody(
  matches : @argparse.Matches,
  owner : StoppedReleaseRecovery,
  request : @remote.DispatchRequest,
) -> Bool raise CommandStop {
  if owner.physical_cleanup_done {
    return true
  }
  let environment = owner.environment
  let scope = @remote.dispatch_request_execution_scope(request)
  let cleanup_current = () => {
    owner.slot.verify_current_hold() == Ok(()) &&
    environment.site_key == scope[0] &&
    environment.site_generation.to_string() == scope[1] &&
    environment.runtime_bundle_cid == scope[2]
  }
  if !cleanup_current() {
    return false
  }
  if owner.physical_cleanup is None {
    let transfers = match owner.transfer_journal {
      Some(value) => value
      None => {
        let opened = match
          @transfer_journal.open_journal(
            environment.sqlite_library,
            required(matches, "transfer-journal"),
            environment.max_record_bytes,
            65536,
            1048576,
            environment.max_bytes,
          ) {
          Ok(value) => value
          Err(_) => return false
        }
        owner.transfer_journal = Some(opened)
        opened
      }
    }
    let root_path = optional(matches, "retained-input-root")
    let root = match root_path {
      None => None
      Some(path) =>
        match @filesystem.open_root(path) {
          Ok(value) => Some(value)
          Err(_) => return false
        }
    }
    if owner.recorded_source is Some(original) {
      guard root_path is Some(path) &&
        root is Some(retained_root) &&
        owner.recorded_consumer is Some((consumer_attempt, expected_consumer)) else {
        return false
      }
      let envelope = match owner.journal.dispatch_envelope(consumer_attempt) {
        Ok(Some(value)) => value
        _ => return false
      }
      guard @remote.admit_remote_poll_dispatch_json(envelope) is Ok(consumer) &&
        @remote.dispatch_request_identity(
          @remote.remote_poll_dispatch_request(consumer),
        ) ==
        expected_consumer else {
        return false
      }
      let delegated = delegation(matches, budget(matches))
      if !saved_output_bundle_current(
          owner.bundles,
          delegated,
          required(matches, "target-triple"),
        ) {
        return false
      }
      guard @site.create_site(
          environment.site_key,
          environment.site_generation,
          environment.runtime_bundle_cid,
          environment.max_operations,
          environment.max_transfers,
          environment.max_bytes,
          environment.max_bytes,
        )
        is Some(site) else {
        return false
      }
      let producer_attempt = match
        @remote.dispatch_request_attempt_identity(request) {
        Ok(value) => value
        Err(_) => return false
      }
      // Source, receiver and borrow responsibility must be discharged before
      // the existing formal-release owner can return the producer capability.
      let confirmed = match
        @resident_host.reclaim_stopped_resident_source_output(
          owner.journal,
          run_admission(matches),
          site,
          delegated,
          producer_attempt,
          consumer_attempt,
          transfers,
          retained_root,
          path,
          {
            max_binding_bytes: 1048576,
            max_chunks: 65536,
            max_manifest_bytes: 1048576,
            max_referenced_bytes: environment.max_bytes,
          },
          cleanup_current,
          recorded=Some(original),
        ) {
        Ok(value) => value
        Err(_) => return false
      }
      let (_, checked_consumer) = @host.client_retained_source_cleanup_requests(
        confirmed,
      )
      // Older recovery used the holder claimant for this component. Use the
      // same identity as acquisition, from the Owner-confirmed relationship.
      match
        owner.bundles.release(consumer_process_hold_identity(checked_consumer)) {
        Ok(_) => ()
        Err(_) => return false
      }
    }
    let input = match
      @resident_host.prepare_resident_saved_input_cleanup(
        owner.journal,
        transfers,
        root,
        run_admission(matches),
        request,
        environment.max_bytes,
        cleanup_current,
        recorded_source=owner.recorded_source,
      ) {
      Ok(value) => value
      Err(_) => return false
    }
    let recovered = match owner.journal.observation(request) {
      Ok(value) => value
      Err(_) => return false
    }
    let release_input = input.unwrap_or(() => true)
    let cleanup = match
      @journal.recovered_site_dispatch_file_custody(recovered) {
      Some(_) => {
        guard root_path is Some(path) else { return false }
        match
          @output.prepare_native_remote_standard_saved_output_cleanup(
            recovered,
            path,
            required_int64(matches, "max-output-bytes"),
            release_input,
            cleanup_current,
          ) {
          Some(value) => value
          None => return false
        }
      }
      None => {
        // A completed retained task requires its original output custody.
        // Absence is not evidence that its file was physically reclaimed.
        let record = @journal.recovered_site_dispatch_record(recovered)
        if input is Some(_) &&
          @remote.dispatch_record_state_codes(record)[0] == 3 {
          return false
        }
        () => cleanup_current() && release_input()
      }
    }
    owner.retained_input = input is Some(_)
    owner.physical_cleanup = Some(cleanup)
  }
  if !owner.physical_cleanup.unwrap()() {
    return false
  }
  if owner.transfer_journal is Some(journal) && !journal.close() {
    return false
  }
  owner.physical_cleanup_done = true
  true
}
