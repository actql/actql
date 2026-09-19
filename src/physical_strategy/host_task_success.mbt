///|
/// Common progression after one implementation returns. The environment
/// observes readiness and retains opaque physical output; MoonBit owns the
/// order in which those facts may become a completed Host task.
pub(all) enum HostTaskSuccessAction {
  HostTaskCheckSiteCompletion
  HostTaskRejectSiteCompletion
  HostTaskCheckCommonCompletion
  HostTaskRejectCommonCompletion
  HostTaskRetainConnectorOutput
  HostTaskRetainCoreOutput
  HostTaskSettleSiteOperation
  HostTaskValidateManagedBinding
  HostTaskRejectManagedBinding
  HostTaskSuccessFinished
  HostTaskSuccessInvalid
} derive(Eq, Debug)

///|
pub fn prepare_host_task_success_step(
  site_completion_checked : Bool,
  site_completion_ready : Bool,
  common_completion_checked : Bool,
  common_completed : Bool,
  connector_owned_output : Bool,
  output_retained : Bool,
  site_operation_settled : Bool,
  managed_binding_claimed : Bool,
  managed_binding_checked : Bool,
  managed_binding_valid : Bool,
) -> HostTaskSuccessAction {
  if (site_completion_ready && !site_completion_checked) ||
    (common_completed && !common_completion_checked) ||
    (output_retained && !common_completed) ||
    (site_operation_settled && !output_retained) ||
    (managed_binding_valid && !managed_binding_checked) {
    return HostTaskSuccessInvalid
  }
  if !site_completion_checked {
    return HostTaskCheckSiteCompletion
  }
  if !site_completion_ready {
    return HostTaskRejectSiteCompletion
  }
  if !common_completion_checked {
    return HostTaskCheckCommonCompletion
  }
  if !common_completed {
    return HostTaskRejectCommonCompletion
  }
  if !output_retained {
    return if connector_owned_output {
      HostTaskRetainConnectorOutput
    } else {
      HostTaskRetainCoreOutput
    }
  }
  if !site_operation_settled {
    return HostTaskSettleSiteOperation
  }
  if managed_binding_claimed {
    if !managed_binding_checked {
      return HostTaskValidateManagedBinding
    }
    if !managed_binding_valid {
      return HostTaskRejectManagedBinding
    }
  }
  HostTaskSuccessFinished
}

///|
pub fn host_task_success_action_code(action : HostTaskSuccessAction) -> Int {
  match action {
    HostTaskCheckSiteCompletion => 0
    HostTaskRejectSiteCompletion => 1
    HostTaskCheckCommonCompletion => 2
    HostTaskRejectCommonCompletion => 3
    HostTaskRetainConnectorOutput => 4
    HostTaskRetainCoreOutput => 5
    HostTaskSettleSiteOperation => 6
    HostTaskValidateManagedBinding => 7
    HostTaskRejectManagedBinding => 8
    HostTaskSuccessFinished => 9
    HostTaskSuccessInvalid => 10
  }
}
