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
          match prepare_begin_remote_release(record) {
            Ok(value) => Ok(runtime_step(RuntimePersistTransition, Some(value)))
            Err(issue) => Err(issue)
          }
      }
  }
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
