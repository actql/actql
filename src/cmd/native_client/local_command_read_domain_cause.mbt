///|
// Closed constructor tags for the actual original Read backing refusal.
// The typed primary survives unchanged. No physical integer, resource amount,
// path, Source, credential or opaque original is formatted or inspected.
fn command_read_domain_cause(
  issue : @initial_bootstrap.NativeBackedExecutionIssue,
) -> String {
  match issue {
    Bootstrap(cause) =>
      match cause {
        Unavailable => "DomainBootstrapUnavailable"
        ForeignOriginal => "DomainBootstrapForeignOriginal"
        AlreadyConsumed => "DomainBootstrapAlreadyConsumed"
        Closing => "DomainBootstrapClosing"
        ReadersPending => "DomainBootstrapReadersPending"
        Physical(_) => "DomainBootstrapPhysical"
        Resource(ledger) => command_read_domain_resource_cause(ledger, true)
      }
    Accounting(cause) =>
      match cause {
        ForeignOriginal => "DomainAccountingForeignOriginal"
        InvalidExtent => "DomainAccountingInvalidExtent"
        ExtentConflict => "DomainAccountingExtentConflict"
        DuplicateChild => "DomainAccountingDuplicateChild"
        RegionClosing => "DomainAccountingRegionClosing"
        Retired => "DomainAccountingRetired"
        CleanupPending => "DomainAccountingCleanupPending"
        ChangedFinalUsage => "DomainAccountingChangedFinalUsage"
        ReadUseAlreadyIssued => "DomainAccountingReadUseAlreadyIssued"
        LiveAccessAlreadyIssued => "DomainAccountingLiveAccessAlreadyIssued"
        LiveChildAlreadyAdmitted => "DomainAccountingLiveChildAlreadyAdmitted"
        Resource(ledger) => command_read_domain_resource_cause(ledger, false)
      }
  }
}

///|
// Both prefixes and every payload-free Ledger constructor are static Strings.
// This Bool chooses diagnostic DATA only; it never selects a resource action.
fn command_read_domain_resource_cause(
  issue : @initial_resources.LedgerIssue,
  bootstrap : Bool,
) -> String {
  match issue {
    InvalidLimits =>
      if bootstrap {
        "DomainBootstrapResourceInvalidLimits"
      } else {
        "DomainAccountingResourceInvalidLimits"
      }
    PlanningLimit =>
      if bootstrap {
        "DomainBootstrapResourcePlanningLimit"
      } else {
        "DomainAccountingResourcePlanningLimit"
      }
    AttemptLimit =>
      if bootstrap {
        "DomainBootstrapResourceAttemptLimit"
      } else {
        "DomainAccountingResourceAttemptLimit"
      }
    HoldingLimit =>
      if bootstrap {
        "DomainBootstrapResourceHoldingLimit"
      } else {
        "DomainAccountingResourceHoldingLimit"
      }
    TransferLimit =>
      if bootstrap {
        "DomainBootstrapResourceTransferLimit"
      } else {
        "DomainAccountingResourceTransferLimit"
      }
    RetentionLimit =>
      if bootstrap {
        "DomainBootstrapResourceRetentionLimit"
      } else {
        "DomainAccountingResourceRetentionLimit"
      }
    ExecutionLimit =>
      if bootstrap {
        "DomainBootstrapResourceExecutionLimit"
      } else {
        "DomainAccountingResourceExecutionLimit"
      }
    ForeignOwner =>
      if bootstrap {
        "DomainBootstrapResourceForeignOwner"
      } else {
        "DomainAccountingResourceForeignOwner"
      }
    ClosedReservation =>
      if bootstrap {
        "DomainBootstrapResourceClosedReservation"
      } else {
        "DomainAccountingResourceClosedReservation"
      }
    ClosedHolding =>
      if bootstrap {
        "DomainBootstrapResourceClosedHolding"
      } else {
        "DomainAccountingResourceClosedHolding"
      }
    InvalidCharge =>
      if bootstrap {
        "DomainBootstrapResourceInvalidCharge"
      } else {
        "DomainAccountingResourceInvalidCharge"
      }
    IdentityOverflow =>
      if bootstrap {
        "DomainBootstrapResourceIdentityOverflow"
      } else {
        "DomainAccountingResourceIdentityOverflow"
      }
    TokenLimit =>
      if bootstrap {
        "DomainBootstrapResourceTokenLimit"
      } else {
        "DomainAccountingResourceTokenLimit"
      }
    CostLimit =>
      if bootstrap {
        "DomainBootstrapResourceCostLimit"
      } else {
        "DomainAccountingResourceCostLimit"
      }
    DurationLimit =>
      if bootstrap {
        "DomainBootstrapResourceDurationLimit"
      } else {
        "DomainAccountingResourceDurationLimit"
      }
    ResourceParked =>
      if bootstrap {
        "DomainBootstrapResourceResourceParked"
      } else {
        "DomainAccountingResourceResourceParked"
      }
    ChildFundingUnavailable =>
      if bootstrap {
        "DomainBootstrapResourceChildFundingUnavailable"
      } else {
        "DomainAccountingResourceChildFundingUnavailable"
      }
  }
}
