///|
// Closed constructor DATA only. The static literals borrow no payload, name,
// expression or exception text. Projection never executes, checks current or
// reads a later Ledger; a composite refusal is not a work/memory diagnosis.
pub fn local_managed_failure_cause(issue : LocalDispatchIssue) -> String? {
  match issue {
    Configuration(original) | Execution(@strategy.Compute(original)) =>
      local_managed_compute_failure_cause(original)
    Execution(original) =>
      Some(
        match original {
          @strategy.UnsupportedGraph => "execution.unsupported_graph"
          @strategy.ForeignCapture => "execution.foreign_capture"
          @strategy.NotReady => "execution.not_ready"
          @strategy.Stopped => "execution.stopped"
          @strategy.ForeignCandidate => "execution.foreign_candidate"
          @strategy.PreviewWorkLimit => "execution.preview_work_limit"
          @strategy.MissingOutput => "execution.missing_output"
          @strategy.Capture(_) => "execution.capture"
          @strategy.Binding(_) => "execution.binding"
          @strategy.Read(_) => "execution.read"
          @strategy.Compute(compute) =>
            return local_managed_compute_failure_cause(compute)
          @strategy.Implementation(_) => "execution.implementation"
          @strategy.Physical(resource) =>
            local_managed_resource_failure_cause(resource)
          @strategy.ActivationNotAuthorized =>
            "execution.activation_not_authorized"
        },
      )
    Preparation(_) => Some("local.preparation")
    Dispatch(_) => Some("local.dispatch")
    Search(_) => Some("local.search")
    ManagedValues(_) => Some("local.managed_values")
    ManagedCopy(_) => Some("local.managed_copy")
    ManagedRetention(_) => Some("local.managed_retention")
    ManagedCompletion(_) => Some("local.managed_completion")
    IdentityExport(_) => Some("local.identity_export")
    CarrierSnapshot(_) => Some("local.carrier_snapshot")
    ControlWorkLimit(_) => Some("local.control_work_limit")
    ExecutionCapacityRefusal(resource, _, _, _) =>
      Some(local_managed_resource_failure_cause(resource))
  }
}

///|
fn local_managed_compute_failure_cause(
  issue : @connector.FixedComputeIssue,
) -> String? {
  Some(
    match issue {
      @connector.UnsupportedInputShape => "compute.unsupported_input_shape"
      @connector.InputUnavailable => "compute.input_unavailable"
      @connector.ForeignPreparation => "compute.foreign_preparation"
      @connector.ForeignRequest(_) => "compute.foreign_request"
      @connector.ForeignCapability(_) => "compute.foreign_capability"
      @connector.CapabilityClosed => "compute.capability_closed"
      @connector.ComputeUnsupported => "compute.unsupported"
      @connector.NotSelected => "compute.not_selected"
      @connector.InvalidLimits => "compute.invalid_limits"
      @connector.CapacityContract => "compute.capacity_contract"
      @connector.CommonInputRows => "compute.common_input_rows"
      @connector.CommonFragmentUnsupported =>
        "compute.common_fragment_unsupported"
      @connector.LogicalIdentityUnsupported =>
        "compute.logical_identity_unsupported"
      @connector.PlanningLimit => "compute.planning_limit"
      @connector.NegativeQuantity => "compute.negative_quantity"
      @connector.Cost(_) => "compute.cost"
      @connector.Guard(_) => "compute.guard"
      @connector.ControlWorkLimit => "compute.control_work_limit"
      @connector.Execution(original) =>
        return local_managed_sequence_failure_cause(original)
    },
  )
}

///|
fn local_managed_sequence_failure_cause(
  issue : @execution.SequenceRunIssue,
) -> String? {
  Some(
    match issue {
      @execution.InvalidLimits => "sequence.invalid_limits"
      @execution.InputOwnership => "sequence.input_ownership"
      @execution.InputSet => "sequence.input_set"
      @execution.InputExecutionEvidencePending(_) =>
        "sequence.input_execution_evidence_pending"
      @execution.InputRepresentationRequired(_) =>
        "sequence.input_representation_required"
      @execution.InputLimit => "sequence.input_limit"
      @execution.InputKey(_, _) => "sequence.input_key"
      @execution.InputScore(_, _) => "sequence.input_score"
      @execution.Wiring(_) => "sequence.wiring"
      @execution.Capture(_, original) =>
        local_managed_capture_failure_cause(original)
      @execution.Rows(step, original) => {
        if step < 0 {
          return None
        }
        let cause = @execution.row_failure_diagnostic_cause(original)
        // Return the existing Some unchanged; do not cohold a second carrier.
        return match cause {
          Some(_) => cause
          None => Some("sequence.rows")
        }
      }
      @execution.Store(_) => "sequence.store"
      @execution.OrderedContext(_, _) => "sequence.ordered_context"
      @execution.FragmentContext(_, _) => "sequence.fragment_context"
      @execution.MissingFragmentContext(_) =>
        "sequence.missing_fragment_context"
      @execution.MixedExecutionConfiguration =>
        "sequence.mixed_execution_configuration"
      @execution.UnsupportedRowComparison(_, _) =>
        "sequence.unsupported_row_comparison"
    },
  )
}

///|
fn local_managed_capture_failure_cause(
  issue : @execution.CaptureIssue,
) -> String {
  match issue {
    @execution.InvalidCaptureLimits => "capture.invalid_limits"
    @execution.CaptureLimit => "capture.capture_limit"
    @execution.NotValuesNode => "capture.not_values_node"
    @execution.MissingParameter(_) => "capture.missing_parameter"
    @execution.InvalidCheckedRow => "capture.invalid_checked_row"
    @execution.NotRelationInput => "capture.not_relation_input"
    @execution.NotRelationOutput => "capture.not_relation_output"
    @execution.ScopedInputNotImplemented =>
      "capture.scoped_input_not_implemented"
    @execution.ConditionalInputRequiresPresence =>
      "capture.conditional_input_requires_presence"
    @execution.InputValue(_, _) => "capture.input_value"
    @execution.ClosedCapture => "capture.closed"
    @execution.ForeignCheckedValue(_, _) => "capture.foreign_checked_value"
    @execution.CaptureWorkLimit(_) => "capture.work_limit"
    @execution.CaptureWorkRefusal(_, _) => "capture.work_refusal"
  }
}

///|
fn local_managed_resource_failure_cause(
  issue : @resources.LedgerIssue,
) -> String {
  match issue {
    @resources.InvalidLimits => "resource.invalid_limits"
    @resources.PlanningLimit => "resource.planning_limit"
    @resources.AttemptLimit => "resource.attempt_limit"
    @resources.HoldingLimit => "resource.holding_limit"
    @resources.TransferLimit => "resource.transfer_limit"
    @resources.RetentionLimit => "resource.retention_limit"
    @resources.ExecutionLimit => "resource.execution_limit"
    @resources.ForeignOwner => "resource.foreign_owner"
    @resources.ClosedReservation => "resource.closed_reservation"
    @resources.ClosedHolding => "resource.closed_holding"
    @resources.InvalidCharge => "resource.invalid_charge"
    @resources.IdentityOverflow => "resource.identity_overflow"
    @resources.TokenLimit => "resource.token_limit"
    @resources.CostLimit => "resource.cost_limit"
    @resources.DurationLimit => "resource.duration_limit"
    @resources.ResourceParked => "resource.resource_parked"
    @resources.ChildFundingUnavailable => "resource.child_funding_unavailable"
  }
}

///|
/// Original sequence step, or -1 when this failure has no such row occurrence.
/// This ordinal DATA is not a current proof, retry or execution permission.
pub fn local_managed_failure_row_step(issue : LocalDispatchIssue) -> Int {
  match issue {
    Configuration(@connector.Execution(@execution.Rows(step, _)))
    | Execution(
      @strategy.Compute(@connector.Execution(@execution.Rows(step, _)))
    ) if step >= 0 => step
    _ => -1
  }
}

///|
/// Project the already-retained immutable limit only for this original
/// provider's closed work failure. No new counter or allowance is created.
fn local_managed_provider_failure(
  issue : @connector.FixedComputeIssue,
  initial_work_limit : Int,
) -> LocalDispatchIssue {
  match issue {
    @connector.ControlWorkLimit => ControlWorkLimit(initial_work_limit)
    _ => Configuration(issue)
  }
}

///|
/// Inert diagnosis of one closed original failure. Exhausted slice quantum is
/// not a failure; physical ExecutionLimit is memory and must stay unclassified.
pub fn local_managed_advance_control_work_limit(
  issue : LocalDispatchIssue,
) -> Int? {
  match issue {
    ControlWorkLimit(limit) if limit >= 0 => Some(limit)
    _ => None
  }
}

///|
/// The original value-capture work allowance and Capture step are distinct
/// from the provider control counter. No generic CaptureLimit is classified.
pub fn local_managed_advance_capture_work(
  issue : LocalDispatchIssue,
) -> Array[Int]? {
  match issue {
    Configuration(
      @connector.Execution(
        @execution.Capture(
          step,
          @execution.CaptureWorkRefusal(limit, remaining)
        )
      )
    ) if step >= 0 && limit >= 0 && remaining >= 0 && remaining <= limit =>
      Some([step, limit])
    Configuration(
      @connector.Execution(
        @execution.Capture(step, @execution.CaptureWorkLimit(limit))
      )
    ) if step >= 0 && limit >= 0 => Some([step, limit])
    _ => None
  }
}

///|
/// Project only the exact original physical quota constructor, never a
/// generic configuration, row, capture, current or cleanup refusal.
pub fn local_managed_failure_resource_dimension(
  issue : LocalDispatchIssue,
) -> String? {
  match issue {
    ExecutionCapacityRefusal(@resources.RetentionLimit, _, _, _) =>
      Some("retained_bytes")
    ExecutionCapacityRefusal(@resources.ExecutionLimit, _, _, _) =>
      Some("execution_bytes")
    Execution(@strategy.Physical(@resources.RetentionLimit)) =>
      Some("retained_bytes")
    Execution(@strategy.Physical(@resources.ExecutionLimit)) =>
      Some("execution_bytes")
    _ => None
  }
}

///|
/// Closed diagnostic quantities from this original failed reserve/probe.
/// The Bool distinguishes exact demand from a proved lower bound. All memory
/// quantities are logical bytes; work is the original UTF8 probe's work unit.
pub fn local_managed_failure_budget(
  issue : LocalDispatchIssue,
) -> (String, Bool, Int64, Int64, Int64)? {
  match issue {
    ExecutionCapacityRefusal(original, needed, available, policy) if needed >
      available &&
      available >= 0L &&
      policy >= available => {
      let dimension = match original {
        @resources.RetentionLimit => "retained_bytes"
        @resources.ExecutionLimit => "execution_bytes"
        _ => return None
      }
      Some((dimension, true, needed, available, policy))
    }
    Configuration(
      @connector.Execution(
        @execution.Capture(_, @execution.CaptureWorkRefusal(policy, available))
      )
    ) if policy >= 0 && available >= 0 && available <= policy =>
      Some(
        (
          "value_capture_work",
          false,
          available.to_int64() + 1L,
          available.to_int64(),
          policy.to_int64(),
        ),
      )
    _ => None
  }
}
