///|
// One closed policy with ten CID fields including the seal, five timestamps,
// and the fixed purpose/version. Both the sealing writer and registered
// policy reader are funded against this finite shape.
let portable_model_capture_policy_bytes = 2048

///|
let portable_model_retention_dependency_bytes = 8192

///|
// The worker never owns these nominations. The original Wasm Model Task
// retains the binding until physical Raw and Call cleanup can return it.
fn portable_model_capture_capacity(backed : Bool) -> (Int64, Int64)? {
  let bytes = portable_model_capture_policy_bytes
  let dependencies = portable_model_retention_dependency_bytes
  guard @publication.run_evidence_admission_construction_inventory(bytes, 36, 2)
    is Some(policy) &&
    @encode.text_writer_construction_inventory(bytes, 36, 2) is Some(writer) &&
    @decode.preserving_json_admission_construction_inventory(
      dependencies, 36, 8,
    )
    is Some(dependency_array) &&
    @execution.preparation_representation_cost({
      // Four dependency references, the three canonical bodies from
      // installed retention, the bound policy and registration closures.
      record_headers: policy.retained.record_headers + 64L,
      reference_slots: policy.retained.reference_slots + 128L,
      scalar_words: policy.retained.scalar_words + 64L,
      owned_utf16_units: policy.retained_utf16_units +
      2L * dependencies.to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      // One held outer dependency view and three sequential inner role
      // admissions. Co-count the emitter, two evidence parser passes,
      // registered policy identity check, current and authorization carriers.
      record_headers: 4L * dependency_array.record_headers +
      3L * policy.record_headers +
      writer.record_headers +
      64L,
      reference_slots: 4L * dependency_array.reference_slots +
      3L * policy.reference_slots +
      writer.reference_slots +
      128L,
      scalar_words: 4L * dependency_array.scalar_words +
      3L * policy.scalar_words +
      writer.scalar_words +
      64L,
      owned_utf16_units: 4L * dependency_array.owned_utf16_units +
      3L * policy.owned_utf16_units +
      writer.owned_utf16_units +
      dependencies.to_int64(),
      owned_wire_bytes: 3L * policy.owned_wire_bytes +
      2L * dependencies.to_int64(),
    })
    is Some(workspace) &&
    @execution.checked_preparation_add_product(retained, workspace, 1L)
    is Some(peak) else {
    return None
  }
  if !backed {
    return Some((retained, peak))
  }
  // The acquired Run issues and admits one effective policy from its
  // checked compilation while the finite Raw constructor is still live.
  let policy_bytes = 4096
  let policy_nodes = 128
  let policy_depth = 8
  guard @publication.run_evidence_admission_construction_inventory(
      policy_bytes, policy_nodes, policy_depth,
    )
    is Some(policy_body) &&
    @encode.text_writer_construction_inventory(
      policy_bytes, policy_nodes, policy_depth,
    )
    is Some(policy_writer) &&
    @execution.preparation_representation_cost({
      record_headers: policy_body.retained.record_headers + 4L,
      reference_slots: policy_body.retained.reference_slots + 8L,
      scalar_words: policy_body.retained.scalar_words + 4L,
      owned_utf16_units: policy_body.retained_utf16_units +
      policy_bytes.to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(policy_retained) &&
    @execution.preparation_representation_cost({
      record_headers: 2L * policy_body.record_headers +
      policy_writer.record_headers +
      32L,
      reference_slots: 2L * policy_body.reference_slots +
      policy_writer.reference_slots +
      64L,
      scalar_words: 2L * policy_body.scalar_words +
      policy_writer.scalar_words +
      64L,
      owned_utf16_units: 2L * policy_body.owned_utf16_units +
      policy_writer.owned_utf16_units,
      owned_wire_bytes: 2L * policy_body.owned_wire_bytes +
      policy_bytes.to_int64(),
    })
    is Some(policy_scratch) &&
    @execution.checked_preparation_add_product(retained, policy_retained, 1L)
    is Some(held) &&
    @execution.checked_preparation_add_product(peak, policy_retained, 1L)
    is Some(base) &&
    @execution.checked_preparation_add_product(base, policy_scratch, 1L)
    is Some(live) else {
    return None
  }
  Some((held, live))
}

///|
fn register_portable_model_capture(
  value : Instance,
  task : StoredManagedTask,
  run : StoredPortableModelRun,
  selected_task : StoredPortableModelMember,
  configuration : StoredRunConfiguration,
  admission : @host.ClientInferDispatchAdmission,
  scope : @publication.BoundModelInvocationScope,
  at : String,
) -> Result[@host.ClientModelRawCaptureRegistration, Int] {
  guard selected_task.capture_capacity is None &&
    configuration.sdk is Some(sdk) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) &&
    value.computes.get(task.compute) is Some(compute) &&
    stored_compute_original_run(value, compute)
    is Some({ finite_policy: Some(finite), .. }) &&
    portable_model_capture_capacity(run.sources is Some(_))
    is Some((retained, peak)) else {
    return Err(-32)
  }
  let capacity = match @resources.reserve_capacity(value.root, retained, peak) {
    Ok(value) => value
    Err(_) => return Err(-4)
  }
  // Keep the same reservation reachable if the write/current frame refuses
  // or an interrupted builder leaves its original owner pending.
  selected_task.capture_capacity = Some(capacity)
  let registration = build_portable_model_capture(
    value, task, run, selected_task, configuration, sdk, current, finite, admission,
    scope, at,
  )
  match registration {
    Err(code) => {
      retire_portable_model_capture(value.root, selected_task) |> ignore
      Err(code)
    }
    Ok(registration) =>
      if @resources.shrink_capacity_reservation(
          value.root,
          capacity,
          retained,
          retained,
        )
        is Ok(_) {
        Ok(registration)
      } else {
        Err(-9)
      }
  }
}

///|
fn build_portable_model_capture(
  value : Instance,
  task : StoredManagedTask,
  run : StoredPortableModelRun,
  selected_task : StoredPortableModelMember,
  configuration : StoredRunConfiguration,
  sdk : StoredSDKRunConfiguration,
  current : StoredHostCurrent,
  finite : @host.ClientLocalRunPolicyOriginal,
  admission : @host.ClientInferDispatchAdmission,
  scope : @publication.BoundModelInvocationScope,
  at : String,
) -> Result[@host.ClientModelRawCaptureRegistration, Int] {
  let dependencies = match
    sdk_selected_original(
      value, current, "retention.json", portable_model_retention_dependency_bytes,
    ) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  let policy = match
    @host.issue_sdk_run_model_raw_capture_policy(
      finite,
      sdk.profile,
      dependencies,
      run.request,
      admission,
      scope,
      run.response_profile,
      run.profile,
      sdk.adoption_cid,
      sdk.store_authority_cid,
      at,
      whole_sources=run.sources.map(evidence => evidence.selection),
    ) {
    Ok(value) => value
    Err(_) => return Err(-37)
  }
  @host.register_client_model_raw_capture(
    admission,
    scope,
    policy,
    run.response_profile,
    run.profile,
    None,
    configuration.account,
    at,
    sdk.store_authority_cid,
    () => managed_task_run_current(value, task) == 0,
    () => {
      guard selected_task.dispatch_clock.val is Some(observed) &&
        !task.closing &&
        managed_task_run_current(value, task) == 0 else {
        return Err(@host.UnavailableSelection)
      }
      Ok((configuration.account, observed))
    },
  ).map_err(issue => {
    match issue {
      @host.Expired => -36
      _ => -37
    }
  })
}

///|
fn retire_portable_model_capture(
  root : @resources.Ledger,
  selected_task : StoredPortableModelMember,
) -> Bool {
  match selected_task.capture_capacity {
    None => true
    Some(capacity) =>
      match @resources.settle_capacity(root, capacity) {
        Ok(_) => {
          selected_task.capture_capacity = None
          selected_task.capture = None
          true
        }
        Err(_) => false
      }
  }
}
