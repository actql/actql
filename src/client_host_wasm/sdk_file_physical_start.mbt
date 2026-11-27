///|
// The original managed File Run after the one ProgramBodyReady transfer.
// The old preparation remains its cleanup parent, never another Plan owner.
priv struct StoredSDKFileManaged {
  parent : @local_host.ClientRequestPreparation[@buffers.BufferSlot]
  transfer : @local_host.ClientRequestCaptureTransfer[@buffers.BufferSlot]
  mut closing : Bool
  source : StoredSDKWholeSourceTransfer
  mut capture_work : StoredSDKFileCaptureWork?
}

///|
fn sdk_file_physical_claim(
  value : Instance,
  custody : StoredPhysicalStart,
) -> (Int, StoredSDKFileStart)? {
  guard custody.sdk_step is Some(handle) &&
    value.materials.get(handle) is Some(material) &&
    !material.closing &&
    material.run == custody.run &&
    material.kind == 8 &&
    material.produced &&
    material.file_start is Some(claim) else {
    return None
  }
  Some((handle, claim))
}

///|
fn check_sdk_file_physical_start(
  value : Instance,
  handle : Int,
  custody : StoredPhysicalStart,
  step : Int,
  claim : StoredSDKFileStart,
) -> Int {
  guard custody.invoked &&
    claim.observed is Some(_) &&
    custody.file_managed is Some(managed) &&
    !managed.closing else {
    return -33
  }
  observe_sdk_file_start(
    value,
    step,
    claim,
    true,
    live=Some((handle, custody, managed)),
  )
}

///|
fn adopt_sdk_file_physical_start(
  value : Instance,
  handle : Int,
  custody : StoredPhysicalStart,
  step : Int,
  claim : StoredSDKFileStart,
) -> Int {
  if custody.invoked {
    return check_sdk_file_physical_start(value, handle, custody, step, claim)
  }
  guard claim.observed is Some(_) else { return -35 }
  let observed = observe_sdk_file_start(value, step, claim, true)
  if observed != 0 {
    return observed
  }
  guard value.physical_starts.get(handle) is Some(active) &&
    physical_equal(active, custody) &&
    !custody.invoked &&
    value.runs.get(custody.run) is Some(run) &&
    custody.current_configuration == run.configuration &&
    value.run_configurations.get(run.configuration) is Some(configuration) &&
    value.preparations.get(run.preparation) is Some(preparation) &&
    sdk_whole_file_rows_handle(value, custody.run, run.configuration)
    is Some(rows) &&
    value.materials.get(claim.publication_material)
    is Some({ file_publication: Some(publication), .. }) &&
    publication.rows_material == rows &&
    publication.claim_material == Some(step) &&
    sdk_whole_file_project_parent(value, preparation, configuration)
    is Some(parent) else {
    return -9
  }
  let original = match
    sdk_whole_file_journal_material_original(value, rows, run.configuration) {
    Ok(value) => value
    Err(code) => return code
  }
  let request = original.candidate.task_materials.plan.request
  let transfer = match @local_host.retain_request_capture_transfer(parent) {
    Ok(transfer) => transfer
    Err(_) => return -35
  }
  // Spend only this start invocation. The transfer itself calls no Source.
  // Install the ownership cell before Common can consume the ready parent.
  custody.file_managed = Some({
    parent,
    transfer,
    closing: false,
    source: { capture: None, csv_read: None, },
    capture_work: None,
  })
  custody.invoked = true
  match
    @local_host.begin_request_capture_managed_run(
      parent,
      request,
      transfer=Some(transfer),
    ) {
    Ok(_) => 0
    Err(InsufficientCapacity | MetadataCapacityUnavailable) => -4
    Err(CleanupPending) => -9
    Err(ForeignOriginal) => -35
    Err(_) => -23
  }
}

///|
fn retire_sdk_file_physical_start(
  value : Instance,
  custody : StoredPhysicalStart,
) -> Int {
  guard custody.file_managed is Some(managed) else { return 0 }
  if managed.capture_work is Some(_) || managed.source.csv_read is Some(_) {
    return -9
  }
  guard value.runs.get(custody.run) is Some(run) &&
    value.preparations.get(run.preparation) is Some(preparation) &&
    preparation.project_request is Some(held) &&
    held.parent is Some(parent) &&
    physical_equal(parent, managed.parent) else {
    return -9
  }
  managed.closing = true
  let owner = match
    @local_host.observe_request_capture_transfer(managed.transfer) {
    Err(_) => return -9
    Ok(Some(owner)) => owner
    Ok(None) => {
      // Adoption refused before moving the original prepared body. Its
      // existing preparation cleanup still owns the unconsumed parent.
      custody.file_managed = None
      return 0
    }
  }
  if @local_host.quiesce_installed_managed_run(owner) is Err(_) {
    return -9
  }
  match @local_host.retire_installed_managed_run(owner) {
    Err(Resource(Unavailable)) => {
      let result = report_mock_project_child_stop(held)
      if result != 0 {
        return result
      }
      let result = retire_mock_project_access(held, preparation.slot)
      if result != 0 {
        return result
      }
      if @local_host.retire_installed_managed_run(owner) is Err(_) {
        return -9
      }
    }
    Err(_) => return -9
    Ok(_) => ()
  }
  held.parent = None
  held.initial = None
  held.frame = None
  held.whole_file_source = None
  custody.file_managed = None
  0
}
