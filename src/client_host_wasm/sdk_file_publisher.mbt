///|
fn install_file_preflight_publisher(
  value : Instance,
  child : StoredPublisher,
  file : StoredFilePublicationPreflight,
  current_configuration : Int,
  current : StoredRunConfiguration,
) -> Int {
  guard file.prepared is Some(preflight) &&
    value.physical_starts.get(file.start) is Some(start) &&
    value.runs.get(start.run) is Some(run) &&
    value.run_configurations.get(run.configuration) is Some(original) &&
    original.sdk is Some(sdk) else {
    return -2
  }
  let checked = file_publication_preflight_current(value, file, current.account)
  if checked != 0 {
    return checked
  }
  let borrow = match child.borrow {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, []) is Ok(_) else {
    return -31
  }
  child.configuration = current_configuration
  child.unknown = false
  let installed = @local_run.install_local_captured_task_preflight_publisher_port(
    preflight,
    original.account,
    () => value.run_configurations.get(child.configuration).unwrap().account,
    () => publisher_current(value, child),
    fact => publisher_authorize(child, fact),
  )
  match installed {
    Err(issue) => publisher_check_status(child, Err(issue))
    Ok(port) => {
      if child.closing || file.work.closing || child.unknown {
        return if child.unknown { -36 } else { -5 }
      }
      child.store = sdk.store_authority_cid
      child.port = Some(port)
      0
    }
  }
}

///|
fn file_request_publisher_still_held(
  value : Instance,
  handle : Int,
  child : StoredPublisher,
  parent : StoredPublicationPreflight,
  file : StoredFilePublicationPreflight,
  port : @publication.PublicationPublisherPort,
) -> Bool {
  !value.closing &&
  !value.runtime_closing &&
  !child.closing &&
  !parent.closing &&
  !file.work.closing &&
  !file.work.failed &&
  value.publishers.get(handle) is Some(actual) &&
  physical_equal(actual, child) &&
  child.port is Some(actual_port) &&
  physical_equal(actual_port, port) &&
  value.publication_preflights.get(child.parent) is Some(active) &&
  physical_equal(active, parent) &&
  active.origin is FilePublicationPreflight(actual_file) &&
  physical_equal(actual_file, file)
}

///|
fn authorize_file_preflight_request(
  value : Instance,
  handle : Int,
  child : StoredPublisher,
  parent : StoredPublicationPreflight,
  file : StoredFilePublicationPreflight,
  port : @publication.PublicationPublisherPort,
  current_configuration : Int,
  current : StoredRunConfiguration,
) -> Int {
  if file.request_failure is Some(code) {
    return code
  }
  let first = !file.request_started
  if !first && file.request_publisher != Some(handle) {
    return -33
  }
  guard parent.produced &&
    file.prepared is Some(preflight) &&
    file_request_publisher_still_held(value, handle, child, parent, file, port) else {
    return -35
  }
  let result = with_file_publication_preflight_read(
    value,
    file,
    (_, _, _, _, original, snapshot, locator, recheck) => {
      fn check() -> Result[Unit, Int] {
        if !file_request_publisher_still_held(
            value, handle, child, parent, file, port,
          ) {
          return Err(-35)
        }
        if first {
          if !@local_run.local_captured_task_publication_preflight_compute_unstarted(
              preflight,
            ) {
            return Err(-33)
          }
        } else if !file_has_finished_capture(value, child.parent, file) {
          return Err(-7)
        }
        @local_run.check_local_captured_task_publication_preflight_current(
          preflight,
          snapshot,
          locator,
          current.account,
          original.context_cid,
          recheck,
        ).map_err(file_preflight_issue)
      }
      match check() {
        Err(code) => return Err(code)
        Ok(_) => ()
      }
      if first {
        if file.request_started {
          return Err(-33)
        }
        file.request_started = true
      }
      child.configuration = current_configuration
      child.unknown = false
      let (request, attempt) = @local_run.local_captured_task_publication_preflight_contracts(
        preflight,
      )
      let authorized = port.check(
        request,
        attempt,
        child.store,
        @publication.Request,
        None,
      )
      let code = publisher_check_status(child, authorized)
      if code != 0 {
        return Err(code)
      }
      check()
    },
    selected_file_projection=!first,
  )
  match result {
    Err(code) => {
      if first && file.request_started && file.request_failure is None {
        file.request_failure = Some(code)
      }
      code
    }
    Ok(_) => {
      if !file_request_publisher_still_held(
          value, handle, child, parent, file, port,
        ) {
        if first {
          file.request_failure = Some(-35)
        }
        return -35
      }
      if first {
        if !@local_run.local_captured_task_publication_preflight_compute_unstarted(
            preflight,
          ) {
          file.request_failure = Some(-33)
          return -33
        }
        // Only first successful authorization latches Task eligibility.
        file.request_publisher = Some(handle)
      } else if !file_has_finished_capture(value, child.parent, file) {
        return -7
      }
      0
    }
  }
}

///|
fn file_has_finished_capture(
  value : Instance,
  scope : Int,
  file : StoredFilePublicationPreflight,
) -> Bool {
  value.publications
  .values()
  .any(record => {
    record.preflight == scope &&
    record.produced &&
    !record.closing &&
    !record.failed &&
    record.file is Some(capture) &&
    physical_equal(capture.original, file) &&
    record.captured is Some(_)
  })
}

///|
fn file_publication_request_current(
  value : Instance,
  work : StoredSDKFileCaptureWork,
) -> Int {
  for preflight_handle, parent in value.publication_preflights {
    if parent.origin is FilePublicationPreflight(file) &&
      physical_equal(file.work, work) {
      if parent.closing || work.closing {
        return -5
      }
      if file.request_failure is Some(code) {
        return code
      }
      if !parent.produced || file.prepared is None || !file.request_started {
        return -7
      }
      guard file.request_publisher is Some(handle) else { return -33 }
      guard value.publishers.get(handle) is Some(child) && !child.closing else {
        return -5
      }
      guard child.parent == preflight_handle &&
        child.port is Some(port) &&
        file_request_publisher_still_held(
          value, handle, child, parent, file, port,
        ) else {
        return -35
      }
      child.unknown = false
      if !publisher_current(value, child) {
        return if child.unknown { -36 } else { -32 }
      }
      return if file_request_publisher_still_held(
          value, handle, child, parent, file, port,
        ) {
        0
      } else {
        -32
      }
    }
  }
  -7
}

///|
fn sdk_file_publisher_capture_matches(
  value : Instance,
  record : StoredPublication,
  publisher : Int,
  child : StoredPublisher,
  parent : StoredPublicationPreflight,
  file : StoredFilePublicationPreflight,
  port : @publication.PublicationPublisherPort,
) -> Bool {
  record.preflight == child.parent &&
  record.produced &&
  !record.closing &&
  record.commit_finished &&
  !record.commit_failed &&
  record.file is Some(capture) &&
  physical_equal(capture.original, file) &&
  file.request_publisher == Some(publisher) &&
  file_request_publisher_still_held(value, publisher, child, parent, file, port)
}

///|
/// Called by the existing physical before_commit reader. The original File
/// claim is reobserved in that adopted frame; this issues no Store write.
fn authorize_sdk_file_commit(
  value : Instance,
  record : StoredPublication,
  publisher : Int,
  child : StoredPublisher,
  parent : StoredPublicationPreflight,
  file : StoredFilePublicationPreflight,
  port : @publication.PublicationPublisherPort,
  current_configuration : Int,
  current : StoredRunConfiguration,
) -> Int {
  guard file.prepared is Some(preflight) &&
    sdk_file_publisher_capture_matches(
      value, record, publisher, child, parent, file, port,
    ) &&
    record.commit is Some(commit) &&
    record.commit_view is Some(view) &&
    record.commit_index is Some(index) &&
    commit.view_contract(view, 7) is Ok(retained_index) &&
    physical_equal(retained_index, index) else {
    return -35
  }
  let result = with_file_publication_preflight_read(value, file, (
    _,
    _,
    _,
    _,
    original,
    snapshot,
    locator,
    read,
  ) => {
    fn check() -> Result[Unit, Int] {
      if !sdk_file_publisher_capture_matches(
          value, record, publisher, child, parent, file, port,
        ) ||
        !(record.commit_view is Some(active_view) &&
        physical_equal(active_view, view)) ||
        !(record.commit_index is Some(active_index) &&
        physical_equal(active_index, index)) {
        return Err(-35)
      }
      @local_run.check_local_captured_task_publication_preflight_current(
        preflight,
        snapshot,
        locator,
        current.account,
        original.context_cid,
        read,
      ).map_err(file_preflight_issue)
    }
    match check() {
      Err(code) => return Err(code)
      Ok(_) => ()
    }
    child.configuration = current_configuration
    child.unknown = false
    let (request, attempt) = @local_run.local_captured_task_publication_preflight_contracts(
      preflight,
    )
    let code = publisher_check_status(
      child,
      port.check(
        request,
        attempt,
        child.store,
        @publication.Commit,
        Some(index),
      ),
    )
    if code != 0 {
      return Err(code)
    }
    check()
  })
  match result {
    Err(code) => code
    Ok(_) =>
      if sdk_file_publisher_capture_matches(
          value, record, publisher, child, parent, file, port,
        ) {
        0
      } else {
        -35
      }
  }
}

///|
/// This private call either consumes the actual index validated by
/// finish_observed_commit in this same call, or its exact retained observation
/// after that finish. It never receives the proposed Commit index.
fn authorize_sdk_file_observed_index(
  value : Instance,
  record : StoredPublication,
  publisher : Int,
  child : StoredPublisher,
  parent : StoredPublicationPreflight,
  file : StoredFilePublicationPreflight,
  port : @publication.PublicationPublisherPort,
  current_configuration : Int,
  observed : @publication.PublicationContract,
  file_state? : (Int, @host.ClientSavedRunStateUpdate)? = None,
) -> Int {
  guard record.observation is Some(ObservedStored(_, _, _)) &&
    record.observation_publisher == Some(publisher) &&
    !record.observation_closing &&
    !record.lookup_closing &&
    sdk_file_publisher_capture_matches(
      value, record, publisher, child, parent, file, port,
    ) &&
    file.prepared is Some(preflight) else {
    return -35
  }
  if record.observation_checked &&
    !(record.observation_index is Some(original) &&
    physical_equal(original, observed)) {
    return -35
  }
  guard value.run_configurations.get(current_configuration)
    is Some(configuration) else {
    return -35
  }
  if file_state is Some((handle, update)) {
    // ReturnCommitted after the RunState write must check the exact
    // same-holding successor. The original index and publisher stay selected.
    guard value.publications.get(handle) is Some(active) &&
      physical_equal(active, record) &&
      record.file is Some(capture) &&
      physical_equal(capture.original, file) &&
      value.physical_starts.get(record.source) is Some({ run, .. }) else {
      return -35
    }
    match
      sdk_file_live_state_read_current(
        value,
        handle,
        record,
        capture,
        run,
        configuration,
        confirm_update=Some(update),
      ) {
      Err(code) => return code
      Ok(_) => ()
    }
  } else {
    let checked = file_publication_preflight_current(
      value,
      file,
      configuration.account,
    )
    if checked != 0 {
      return checked
    }
  }
  child.configuration = current_configuration
  child.unknown = false
  let (request, attempt) = @local_run.local_captured_task_publication_preflight_contracts(
    preflight,
  )
  let code = publisher_check_status(
    child,
    port.check(
      request,
      attempt,
      child.store,
      @publication.ReturnCommitted,
      Some(observed),
    ),
  )
  if code != 0 {
    return code
  }
  if !sdk_file_publisher_capture_matches(
      value, record, publisher, child, parent, file, port,
    ) ||
    record.observation_closing ||
    record.lookup_closing ||
    record.observation_publisher != Some(publisher) {
    return -35
  }
  0
}
