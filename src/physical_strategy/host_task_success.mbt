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
/// Common ownership state for the successful completion of one Host task.
/// Environment adapters execute physical actions and report their results;
/// they do not retain a parallel set of progression flags.
struct HostTaskSuccessProgress {
  connector_owned_output : Bool
  managed_binding_claimed : Bool
  mut site_completion_checked : Bool
  mut site_completion_ready : Bool
  mut common_completion_checked : Bool
  mut common_completed : Bool
  mut output_retained : Bool
  mut site_operation_settled : Bool
  mut managed_binding_checked : Bool
  mut managed_binding_valid : Bool
}

///|
pub fn begin_host_task_success_progress(
  connector_owned_output : Bool,
  managed_binding_claimed : Bool,
) -> HostTaskSuccessProgress {
  {
    connector_owned_output,
    managed_binding_claimed,
    site_completion_checked: false,
    site_completion_ready: false,
    common_completion_checked: false,
    common_completed: false,
    output_retained: false,
    site_operation_settled: false,
    managed_binding_checked: false,
    managed_binding_valid: false,
  }
}

///|
pub fn record_host_task_site_completion(
  progress : HostTaskSuccessProgress,
  ready : Bool,
) -> Bool {
  if progress.site_completion_checked {
    false
  } else {
    progress.site_completion_checked = true
    progress.site_completion_ready = ready
    true
  }
}

///|
pub fn record_host_task_common_completion(
  progress : HostTaskSuccessProgress,
  completed : Bool,
) -> Bool {
  if !progress.site_completion_checked ||
    !progress.site_completion_ready ||
    progress.common_completion_checked {
    false
  } else {
    progress.common_completion_checked = true
    progress.common_completed = completed
    true
  }
}

///|
pub fn record_host_task_output_retained(
  progress : HostTaskSuccessProgress,
) -> Bool {
  if !progress.common_completion_checked ||
    !progress.common_completed ||
    progress.output_retained {
    false
  } else {
    progress.output_retained = true
    true
  }
}

///|
pub fn record_host_task_site_operation_settled(
  progress : HostTaskSuccessProgress,
) -> Bool {
  if !progress.output_retained || progress.site_operation_settled {
    false
  } else {
    progress.site_operation_settled = true
    true
  }
}

///|
pub fn record_host_task_managed_binding(
  progress : HostTaskSuccessProgress,
  valid : Bool,
) -> Bool {
  if !progress.managed_binding_claimed ||
    !progress.site_operation_settled ||
    progress.managed_binding_checked {
    false
  } else {
    progress.managed_binding_checked = true
    progress.managed_binding_valid = valid
    true
  }
}

///|
pub fn prepare_host_task_success_progress_step(
  progress : HostTaskSuccessProgress,
) -> HostTaskSuccessAction {
  prepare_host_task_success_step(
    progress.site_completion_checked,
    progress.site_completion_ready,
    progress.common_completion_checked,
    progress.common_completed,
    progress.connector_owned_output,
    progress.output_retained,
    progress.site_operation_settled,
    progress.managed_binding_claimed,
    progress.managed_binding_checked,
    progress.managed_binding_valid,
  )
}

///|
pub fn host_task_success_site_operation_settled(
  progress : HostTaskSuccessProgress,
) -> Bool {
  progress.site_operation_settled
}

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
