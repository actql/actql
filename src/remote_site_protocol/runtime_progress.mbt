///|
/// Physical adapters execute these actions but do not choose state progress.
/// A transition must be durably committed at the position implied by the
/// action before the adapter asks for another step.
pub(all) enum RemoteRuntimeAction {
  RuntimeAwaitStop
  RuntimePersistTransition
  RuntimeSettleThenPersist
  RuntimeReclaimResources
  RuntimeFinished
} derive(Eq, Debug)

///|
/// Common admission result for a physical remote runtime. Environment
/// adapters report installed resources and current Site observations; they do
/// not choose whether a request may start or reuse an active occurrence.
pub(all) enum RemoteRuntimeAdmission {
  RuntimeAdmissionReady
  RuntimeAdmissionReuseActive
  RuntimeAdmissionClosed
  RuntimeAdmissionRecordMismatch
  RuntimeAdmissionRegistrationUnavailable
  RuntimeAdmissionBudgetUnavailable
  RuntimeAdmissionSiteUnavailable
  RuntimeAdmissionCapacityUnsupported
  RuntimeAdmissionAlreadyStarted
} derive(Eq, Debug)

///|
/// Common success progression. Environment adapters perform the selected
/// physical action and report its exact ownership fact before asking for the
/// next step.
pub(all) enum RemoteRuntimeSuccessAction {
  RuntimeAcquireBundle
  RuntimePersistProvisioning
  RuntimeAcquireOperation
  RuntimePersistRunning
  RuntimeExecutePhysical
  RuntimeAcquireHolding
  RuntimeSettleOperation
  RuntimePersistSettled
  RuntimePersistRetained
  RuntimePersistEvidence
  RuntimeSuccessFinished
} derive(Eq, Debug)

///|
/// Portable ownership state for one physical remote execution occurrence.
/// Adapter handles remain environment-owned, but the common runtime owns the
/// facts that decide settlement, stop confirmation, and resource release.
struct RemoteRuntimeCustody {
  mut operation_acquired : Bool
  mut operation_settled : Bool
  mut output_acquired : Bool
  mut output_released : Bool
  mut holding_acquired : Bool
  mut holding_released : Bool
  mut bundle_acquired : Bool
  mut bundle_released : Bool
  mut stop_required : Bool
  mut stop_confirmed : Bool
  mut cancelled : Bool
  mut completed_restoration : (String, Int)?
}

///|
pub fn create_remote_runtime_custody() -> RemoteRuntimeCustody {
  {
    operation_acquired: false,
    operation_settled: false,
    output_acquired: false,
    output_released: false,
    holding_acquired: false,
    holding_released: false,
    bundle_acquired: false,
    bundle_released: false,
    stop_required: false,
    stop_confirmed: true,
    cancelled: false,
    completed_restoration: None,
  }
}

///|
/// Restore only the settled-operation fact of an exact completed occurrence.
/// The caller must separately verify current Site/authority and exclusive
/// physical custody. No output, holding, bundle, reservation or start permit
/// is created here; actual resource handles must be reacquired by their owners.
pub fn restore_remote_runtime_completed_custody(
  record : DispatchRecord,
  evidence : RemoteExecutionEvidence,
  subject : RemoteManagedOutputSubject,
  measurement : RemoteManagedOutputMeasurement,
) -> Result[RemoteRuntimeCustody, DispatchIssue] {
  if record.execution != NativeSettled ||
    record.cleanup != CleanupActive ||
    !record.material_available ||
    record.quarantined_capacity {
    return Err(InvalidTransition)
  }
  if !remote_managed_output_subject_matches_evidence(
      subject,
      evidence,
      record.request,
    ) ||
    !remote_managed_output_subject_matches_measurement(subject, measurement) {
    return Err(DispatchIdentityMismatch)
  }
  guard record.evidence is EvidenceDurable(material, holding, saved_evidence) else {
    return Err(InvalidTransition)
  }
  if material != subject.material_generation ||
    holding != subject.holding_evidence_cid ||
    saved_evidence != evidence.evidence_cid {
    return Err(DispatchIdentityMismatch)
  }
  let custody = create_remote_runtime_custody()
  // NativeSettled plus the exact durable completion proves the original
  // operation settled. This does not acquire a new physical operation.
  custody.operation_acquired = true
  custody.operation_settled = true
  custody.completed_restoration = Some(
    (record.request.dispatch_request_cid, record.revision),
  )
  Ok(custody)
}

///|
/// Confirm resource ownership was reconstructed, not that execution happened
/// again or cleanup finished. Every actual handle must already be attached by
/// its existing owner, and the original durable revision must remain current.
pub fn confirm_remote_runtime_completed_restoration(
  record : DispatchRecord,
  custody : RemoteRuntimeCustody,
) -> Bool {
  guard custody.completed_restoration is Some((request_cid, revision)) else {
    return false
  }
  if request_cid != record.request.dispatch_request_cid ||
    revision != record.revision ||
    record.execution != NativeSettled ||
    record.cleanup != CleanupActive ||
    !record.material_available ||
    record.quarantined_capacity ||
    !(record.evidence is EvidenceDurable(_, _, _)) ||
    !custody.operation_settled ||
    !custody.bundle_acquired ||
    custody.bundle_released ||
    !custody.output_acquired ||
    custody.output_released ||
    !custody.holding_acquired ||
    custody.holding_released {
    return false
  }
  custody.completed_restoration = None
  true
}

///|
pub fn remote_runtime_custody_acquire_operation(
  custody : RemoteRuntimeCustody,
) -> Bool {
  if custody.operation_acquired {
    false
  } else {
    custody.operation_acquired = true
    true
  }
}

///|
pub fn remote_runtime_custody_settle_operation(
  custody : RemoteRuntimeCustody,
) -> Bool {
  if !custody.operation_acquired || custody.operation_settled {
    false
  } else {
    custody.operation_settled = true
    true
  }
}

///|
pub fn remote_runtime_custody_operation_settled(
  custody : RemoteRuntimeCustody,
) -> Bool {
  custody.operation_settled
}

///|
pub fn remote_runtime_custody_operation_acquired(
  custody : RemoteRuntimeCustody,
) -> Bool {
  custody.operation_acquired
}

///|
pub fn remote_runtime_custody_acquire_output(
  custody : RemoteRuntimeCustody,
) -> Bool {
  if custody.output_acquired {
    false
  } else {
    custody.output_acquired = true
    true
  }
}

///|
pub fn remote_runtime_custody_release_output(
  custody : RemoteRuntimeCustody,
) -> Bool {
  if !custody.output_acquired || custody.output_released {
    false
  } else {
    custody.output_released = true
    true
  }
}

///|
pub fn remote_runtime_custody_output_released(
  custody : RemoteRuntimeCustody,
) -> Bool {
  custody.output_released
}

///|
pub fn remote_runtime_custody_output_acquired(
  custody : RemoteRuntimeCustody,
) -> Bool {
  custody.output_acquired
}

///|
pub fn remote_runtime_custody_acquire_holding(
  custody : RemoteRuntimeCustody,
) -> Bool {
  if custody.holding_acquired {
    false
  } else {
    custody.holding_acquired = true
    true
  }
}

///|
pub fn remote_runtime_custody_release_holding(
  custody : RemoteRuntimeCustody,
) -> Bool {
  if !custody.holding_acquired || custody.holding_released {
    false
  } else {
    custody.holding_released = true
    true
  }
}

///|
pub fn remote_runtime_custody_holding_released(
  custody : RemoteRuntimeCustody,
) -> Bool {
  custody.holding_released
}

///|
pub fn remote_runtime_custody_holding_acquired(
  custody : RemoteRuntimeCustody,
) -> Bool {
  custody.holding_acquired
}

///|
pub fn remote_runtime_custody_acquire_bundle(
  custody : RemoteRuntimeCustody,
) -> Bool {
  if custody.bundle_acquired {
    false
  } else {
    custody.bundle_acquired = true
    true
  }
}

///|
pub fn remote_runtime_custody_release_bundle(
  custody : RemoteRuntimeCustody,
) -> Bool {
  if !custody.bundle_acquired || custody.bundle_released {
    false
  } else {
    custody.bundle_released = true
    true
  }
}

///|
pub fn remote_runtime_custody_bundle_released(
  custody : RemoteRuntimeCustody,
) -> Bool {
  custody.bundle_released
}

///|
pub fn remote_runtime_custody_bundle_acquired(
  custody : RemoteRuntimeCustody,
) -> Bool {
  custody.bundle_acquired
}

///|
/// Replace the current physical failure observation. This does not confirm
/// stop merely because the adapter-facing operation returned.
pub fn remote_runtime_custody_record_failure(
  custody : RemoteRuntimeCustody,
  cancelled : Bool,
  stop_required : Bool,
  stop_confirmed : Bool,
) -> Bool {
  if stop_required && stop_confirmed {
    false
  } else {
    custody.cancelled = cancelled
    custody.stop_required = stop_required
    custody.stop_confirmed = !stop_required || stop_confirmed
    true
  }
}

///|
pub fn remote_runtime_custody_confirm_stop(
  custody : RemoteRuntimeCustody,
) -> Bool {
  if !custody.stop_required || custody.stop_confirmed {
    false
  } else {
    custody.stop_confirmed = true
    true
  }
}

///|
pub fn remote_runtime_custody_stop_pending(
  custody : RemoteRuntimeCustody,
) -> Bool {
  custody.stop_required && !custody.stop_confirmed
}

///|
pub fn remote_runtime_custody_resources_reclaimed(
  custody : RemoteRuntimeCustody,
) -> Bool {
  custody.completed_restoration is None &&
  (!custody.output_acquired || custody.output_released) &&
  (!custody.holding_acquired || custody.holding_released) &&
  (!custody.bundle_acquired || custody.bundle_released)
}

///|
/// Select the only valid next success action. Physical output contents are
/// not inspected here; their registered projection is admitted by the
/// existing retained-output and evidence transitions.
pub fn prepare_remote_runtime_success(
  record : DispatchRecord,
  custody : RemoteRuntimeCustody,
) -> Result[RemoteRuntimeSuccessAction, DispatchIssue] {
  if custody.completed_restoration is Some(_) {
    return Err(MaterialUnavailable)
  }
  if record.cleanup != CleanupActive ||
    record.quarantined_capacity ||
    custody.stop_required ||
    custody.cancelled ||
    custody.output_released ||
    custody.holding_released ||
    custody.bundle_released {
    return Err(InvalidTransition)
  }
  match record.execution {
    Accepted => {
      if record.evidence != NoEvidence || record.material_available {
        return Err(InvalidTransition)
      }
      if !custody.bundle_acquired {
        Ok(RuntimeAcquireBundle)
      } else {
        Ok(RuntimePersistProvisioning)
      }
    }
    Provisioning => {
      if !custody.bundle_acquired ||
        record.evidence != NoEvidence ||
        record.material_available {
        return Err(InvalidTransition)
      }
      if !custody.operation_acquired {
        Ok(RuntimeAcquireOperation)
      } else {
        Ok(RuntimePersistRunning)
      }
    }
    Running => {
      if !custody.bundle_acquired ||
        !custody.operation_acquired ||
        record.evidence != NoEvidence ||
        record.material_available {
        return Err(InvalidTransition)
      }
      if !custody.output_acquired {
        Ok(RuntimeExecutePhysical)
      } else if !custody.holding_acquired {
        Ok(RuntimeAcquireHolding)
      } else if !custody.operation_settled {
        Ok(RuntimeSettleOperation)
      } else {
        Ok(RuntimePersistSettled)
      }
    }
    NativeSettled => {
      if !custody.bundle_acquired ||
        !custody.operation_acquired ||
        !custody.operation_settled ||
        !custody.output_acquired ||
        !custody.holding_acquired {
        return Err(InvalidTransition)
      }
      match record.evidence {
        NoEvidence =>
          if record.material_available {
            Err(InvalidTransition)
          } else {
            Ok(RuntimePersistRetained)
          }
        OutputRetained(_, _) =>
          if record.material_available {
            Ok(RuntimePersistEvidence)
          } else {
            Err(InvalidTransition)
          }
        EvidenceDurable(_, _, _) =>
          if record.material_available {
            Ok(RuntimeSuccessFinished)
          } else {
            Err(InvalidTransition)
          }
        EvidenceRejected => Err(InvalidTransition)
      }
    }
    ExecutionFailed | ExecutionCancelled | ExecutionUnknown =>
      Err(InvalidTransition)
  }
}

///|
pub fn remote_runtime_success_action_code(
  action : RemoteRuntimeSuccessAction,
) -> Int {
  match action {
    RuntimeAcquireBundle => 0
    RuntimePersistProvisioning => 1
    RuntimeAcquireOperation => 2
    RuntimePersistRunning => 3
    RuntimeExecutePhysical => 4
    RuntimeAcquireHolding => 5
    RuntimeSettleOperation => 6
    RuntimePersistSettled => 7
    RuntimePersistRetained => 8
    RuntimePersistEvidence => 9
    RuntimeSuccessFinished => 10
  }
}

///|
/// Classify runtime admission in a stable order. An already active exact
/// dispatch is reusable even if the Site stops accepting new work; it is not a
/// new execution. Site and capacity facts still gate every new occurrence.
pub fn classify_remote_runtime_admission(
  runtime_closed : Bool,
  record_matches : Bool,
  registration_available : Bool,
  budget_available : Bool,
  active_dispatch : Bool,
  site_available : Bool,
  capacity_supported : Bool,
  record_startable : Bool,
) -> RemoteRuntimeAdmission {
  if runtime_closed {
    RuntimeAdmissionClosed
  } else if !record_matches {
    RuntimeAdmissionRecordMismatch
  } else if !registration_available {
    RuntimeAdmissionRegistrationUnavailable
  } else if !budget_available {
    RuntimeAdmissionBudgetUnavailable
  } else if active_dispatch {
    RuntimeAdmissionReuseActive
  } else if !site_available {
    RuntimeAdmissionSiteUnavailable
  } else if !capacity_supported {
    RuntimeAdmissionCapacityUnsupported
  } else if !record_startable {
    RuntimeAdmissionAlreadyStarted
  } else {
    RuntimeAdmissionReady
  }
}

///|
/// Stable adapter projection. These codes are local control results, not wire
/// state or durable protocol identity.
pub fn remote_runtime_admission_code(admission : RemoteRuntimeAdmission) -> Int {
  match admission {
    RuntimeAdmissionReady => 0
    RuntimeAdmissionReuseActive => 1
    RuntimeAdmissionClosed => 2
    RuntimeAdmissionRecordMismatch => 3
    RuntimeAdmissionRegistrationUnavailable => 4
    RuntimeAdmissionBudgetUnavailable => 5
    RuntimeAdmissionSiteUnavailable => 6
    RuntimeAdmissionCapacityUnsupported => 7
    RuntimeAdmissionAlreadyStarted => 8
  }
}

///|
/// One portable progression decision for a remote execution occurrence.
/// Physical resource observations are inputs; the resulting transition and
/// ordering are owned by the common protocol.
struct RemoteRuntimeStep {
  action : RemoteRuntimeAction
  transition : DispatchTransition?
}

///|
fn runtime_step(
  action : RemoteRuntimeAction,
  transition : DispatchTransition?,
) -> RemoteRuntimeStep {
  { action, transition, }
}

///|
pub fn remote_runtime_record_startable(record : DispatchRecord) -> Bool {
  record.execution == Accepted &&
  record.evidence == NoEvidence &&
  record.cleanup == CleanupActive &&
  !record.material_available &&
  !record.quarantined_capacity
}

///|
/// Decide the first durable state change after an execution failure. A
/// rejected Promise is not proof that physical access stopped; callers must
/// pass stop_confirmed only from the physical cleanup authority.
pub fn prepare_remote_runtime_failure(
  record : DispatchRecord,
  cancelled : Bool,
  stop_confirmed : Bool,
) -> Result[RemoteRuntimeStep, DispatchIssue] {
  match record.execution {
    Accepted =>
      if cancelled {
        match prepare_confirm_execution_cancelled(record) {
          Ok(value) => Ok(runtime_step(RuntimePersistTransition, Some(value)))
          Err(issue) => Err(issue)
        }
      } else {
        match prepare_begin_remote_release(record) {
          Ok(value) => Ok(runtime_step(RuntimePersistTransition, Some(value)))
          Err(issue) => Err(issue)
        }
      }
    Provisioning | Running =>
      if stop_confirmed {
        let transition = if cancelled {
          prepare_confirm_execution_cancelled(record)
        } else {
          prepare_confirm_execution_failed(record)
        }
        match transition {
          Ok(value) => Ok(runtime_step(RuntimeSettleThenPersist, Some(value)))
          Err(issue) => Err(issue)
        }
      } else {
        match prepare_mark_execution_unknown(record) {
          Ok(value) => Ok(runtime_step(RuntimePersistTransition, Some(value)))
          Err(issue) => Err(issue)
        }
      }
    NativeSettled =>
      match record.evidence {
        NoEvidence | OutputRetained(_, _) =>
          match prepare_reject_execution_evidence(record) {
            Ok(value) => Ok(runtime_step(RuntimePersistTransition, Some(value)))
            Err(issue) => Err(issue)
          }
        EvidenceDurable(_, _, _) | EvidenceRejected => Err(InvalidTransition)
      }
    ExecutionFailed | ExecutionCancelled | ExecutionUnknown =>
      Err(InvalidTransition)
  }
}

///|
/// Ownership-aware failure planning is the product entry for runtimes. The
/// Boolean form remains a small transition primitive for independent vectors.
pub fn prepare_owned_remote_runtime_failure(
  record : DispatchRecord,
  custody : RemoteRuntimeCustody,
) -> Result[RemoteRuntimeStep, DispatchIssue] {
  prepare_remote_runtime_failure(
    record,
    custody.cancelled,
    !remote_runtime_custody_stop_pending(custody),
  )
}

///|
/// Decide one cleanup step from current durable state and current physical
/// observations. The function intentionally emits at most one transition so
/// every state change is durable before the next decision.
pub fn prepare_remote_runtime_cleanup(
  record : DispatchRecord,
  cancelled : Bool,
  stop_confirmed : Bool,
  resources_reclaimed : Bool,
) -> Result[RemoteRuntimeStep, DispatchIssue] {
  match record.cleanup {
    CleanupReleased | CleanupRecoveredAfterLoss =>
      Ok(runtime_step(RuntimeFinished, None))
    CleanupForceLost => Ok(runtime_step(RuntimeAwaitStop, None))
    CleanupReleasing =>
      if resources_reclaimed {
        match prepare_confirm_remote_release(record) {
          Ok(value) => Ok(runtime_step(RuntimePersistTransition, Some(value)))
          Err(issue) => Err(issue)
        }
      } else {
        Ok(runtime_step(RuntimeReclaimResources, None))
      }
    CleanupActive | CleanupUnknown =>
      match record.execution {
        Accepted | Provisioning | Running =>
          if stop_confirmed {
            prepare_remote_runtime_failure(record, cancelled, true)
          } else if record.execution == Accepted && cancelled {
            prepare_remote_runtime_failure(record, true, false)
          } else {
            match prepare_mark_execution_unknown(record) {
              Ok(value) =>
                Ok(runtime_step(RuntimePersistTransition, Some(value)))
              Err(issue) => Err(issue)
            }
          }
        ExecutionUnknown =>
          if !stop_confirmed {
            Ok(runtime_step(RuntimeAwaitStop, None))
          } else {
            let transition = if cancelled {
              prepare_reconcile_cancelled_execution(record)
            } else {
              prepare_reconcile_failed_execution(record)
            }
            match transition {
              Ok(value) =>
                Ok(runtime_step(RuntimeSettleThenPersist, Some(value)))
              Err(issue) => Err(issue)
            }
          }
        NativeSettled | ExecutionFailed | ExecutionCancelled =>
          if !stop_confirmed {
            Ok(runtime_step(RuntimeAwaitStop, None))
          } else {
            match prepare_begin_remote_release(record) {
              Ok(value) =>
                Ok(runtime_step(RuntimePersistTransition, Some(value)))
              Err(issue) => Err(issue)
            }
          }
      }
  }
}

///|
/// Plan cleanup from the common ownership record rather than adapter-local
/// flags. Physical cleanup is still performed by the environment adapter.
pub fn prepare_owned_remote_runtime_cleanup(
  record : DispatchRecord,
  custody : RemoteRuntimeCustody,
) -> Result[RemoteRuntimeStep, DispatchIssue] {
  // Historical holding/output obligations are still real while their handles
  // are being reconstructed. Absence of an attached handle is not cleanup.
  if custody.completed_restoration is Some(_) {
    return Err(MaterialUnavailable)
  }
  prepare_remote_runtime_cleanup(
    record,
    custody.cancelled,
    !remote_runtime_custody_stop_pending(custody),
    remote_runtime_custody_resources_reclaimed(custody),
  )
}

///|
/// A failed physical reclaim makes current cleanup uncertain without claiming
/// that execution or evidence facts changed.
pub fn prepare_remote_runtime_reclaim_unknown(
  record : DispatchRecord,
) -> Result[RemoteRuntimeStep, DispatchIssue] {
  match record.cleanup {
    CleanupReleasing =>
      match prepare_mark_execution_unknown(record) {
        Ok(value) => Ok(runtime_step(RuntimePersistTransition, Some(value)))
        Err(issue) => Err(issue)
      }
    _ => Err(InvalidTransition)
  }
}

///|
/// Stable adapter projection. Codes select physical actions and are not wire
/// identity or durable state.
pub fn remote_runtime_step_action_code(step : RemoteRuntimeStep) -> Int {
  match step.action {
    RuntimeAwaitStop => 0
    RuntimePersistTransition => 1
    RuntimeSettleThenPersist => 2
    RuntimeReclaimResources => 3
    RuntimeFinished => 4
  }
}

///|
pub fn remote_runtime_step_transition(
  step : RemoteRuntimeStep,
) -> Result[DispatchTransition, DispatchIssue] {
  match step.transition {
    Some(value) => Ok(value)
    None => Err(InvalidTransition)
  }
}
