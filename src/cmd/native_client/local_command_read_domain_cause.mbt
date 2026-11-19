///|
// Closed constructor tags for the actual original Read backing refusal.
// The typed primary survives unchanged. Both complete labels are static so
// the actual renderer adds no extra String concatenation or copied payload.
// No physical integer, resource amount,
// path, Source, credential or opaque original is formatted or inspected.
fn command_read_domain_cause(
  issue : @initial_bootstrap.NativeBackedExecutionIssue,
  read_kind? : Bool = false,
) -> String {
  match issue {
    Bootstrap(cause) =>
      match cause {
        Unavailable =>
          if read_kind {
            "read:DomainBootstrapUnavailable"
          } else {
            "DomainBootstrapUnavailable"
          }
        ForeignOriginal =>
          if read_kind {
            "read:DomainBootstrapForeignOriginal"
          } else {
            "DomainBootstrapForeignOriginal"
          }
        AlreadyConsumed =>
          if read_kind {
            "read:DomainBootstrapAlreadyConsumed"
          } else {
            "DomainBootstrapAlreadyConsumed"
          }
        Closing =>
          if read_kind {
            "read:DomainBootstrapClosing"
          } else {
            "DomainBootstrapClosing"
          }
        ReadersPending =>
          if read_kind {
            "read:DomainBootstrapReadersPending"
          } else {
            "DomainBootstrapReadersPending"
          }
        Physical(_) =>
          if read_kind {
            "read:DomainBootstrapPhysical"
          } else {
            "DomainBootstrapPhysical"
          }
        Resource(ledger) =>
          command_read_domain_resource_cause(ledger, true, read_kind~)
      }
    Accounting(cause) =>
      match cause {
        ForeignOriginal =>
          if read_kind {
            "read:DomainAccountingForeignOriginal"
          } else {
            "DomainAccountingForeignOriginal"
          }
        InvalidExtent =>
          if read_kind {
            "read:DomainAccountingInvalidExtent"
          } else {
            "DomainAccountingInvalidExtent"
          }
        ExtentConflict =>
          if read_kind {
            "read:DomainAccountingExtentConflict"
          } else {
            "DomainAccountingExtentConflict"
          }
        DuplicateChild =>
          if read_kind {
            "read:DomainAccountingDuplicateChild"
          } else {
            "DomainAccountingDuplicateChild"
          }
        RegionClosing =>
          if read_kind {
            "read:DomainAccountingRegionClosing"
          } else {
            "DomainAccountingRegionClosing"
          }
        Retired =>
          if read_kind {
            "read:DomainAccountingRetired"
          } else {
            "DomainAccountingRetired"
          }
        CleanupPending =>
          if read_kind {
            "read:DomainAccountingCleanupPending"
          } else {
            "DomainAccountingCleanupPending"
          }
        ChangedFinalUsage =>
          if read_kind {
            "read:DomainAccountingChangedFinalUsage"
          } else {
            "DomainAccountingChangedFinalUsage"
          }
        ReadUseAlreadyIssued =>
          if read_kind {
            "read:DomainAccountingReadUseAlreadyIssued"
          } else {
            "DomainAccountingReadUseAlreadyIssued"
          }
        LiveAccessAlreadyIssued =>
          if read_kind {
            "read:DomainAccountingLiveAccessAlreadyIssued"
          } else {
            "DomainAccountingLiveAccessAlreadyIssued"
          }
        LiveChildAlreadyAdmitted =>
          if read_kind {
            "read:DomainAccountingLiveChildAlreadyAdmitted"
          } else {
            "DomainAccountingLiveChildAlreadyAdmitted"
          }
        Resource(ledger) =>
          command_read_domain_resource_cause(ledger, false, read_kind~)
      }
  }
}

///|
// Both prefixes and every payload-free Ledger constructor are static Strings.
// This Bool chooses diagnostic DATA only; it never selects a resource action.
fn command_read_domain_resource_cause(
  issue : @initial_resources.LedgerIssue,
  bootstrap : Bool,
  read_kind? : Bool = false,
) -> String {
  match issue {
    InvalidLimits =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourceInvalidLimits"
        } else {
          "DomainBootstrapResourceInvalidLimits"
        }
      } else if read_kind {
        "read:DomainAccountingResourceInvalidLimits"
      } else {
        "DomainAccountingResourceInvalidLimits"
      }
    PlanningLimit =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourcePlanningLimit"
        } else {
          "DomainBootstrapResourcePlanningLimit"
        }
      } else if read_kind {
        "read:DomainAccountingResourcePlanningLimit"
      } else {
        "DomainAccountingResourcePlanningLimit"
      }
    AttemptLimit =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourceAttemptLimit"
        } else {
          "DomainBootstrapResourceAttemptLimit"
        }
      } else if read_kind {
        "read:DomainAccountingResourceAttemptLimit"
      } else {
        "DomainAccountingResourceAttemptLimit"
      }
    HoldingLimit =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourceHoldingLimit"
        } else {
          "DomainBootstrapResourceHoldingLimit"
        }
      } else if read_kind {
        "read:DomainAccountingResourceHoldingLimit"
      } else {
        "DomainAccountingResourceHoldingLimit"
      }
    TransferLimit =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourceTransferLimit"
        } else {
          "DomainBootstrapResourceTransferLimit"
        }
      } else if read_kind {
        "read:DomainAccountingResourceTransferLimit"
      } else {
        "DomainAccountingResourceTransferLimit"
      }
    RetentionLimit =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourceRetentionLimit"
        } else {
          "DomainBootstrapResourceRetentionLimit"
        }
      } else if read_kind {
        "read:DomainAccountingResourceRetentionLimit"
      } else {
        "DomainAccountingResourceRetentionLimit"
      }
    ExecutionLimit =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourceExecutionLimit"
        } else {
          "DomainBootstrapResourceExecutionLimit"
        }
      } else if read_kind {
        "read:DomainAccountingResourceExecutionLimit"
      } else {
        "DomainAccountingResourceExecutionLimit"
      }
    ForeignOwner =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourceForeignOwner"
        } else {
          "DomainBootstrapResourceForeignOwner"
        }
      } else if read_kind {
        "read:DomainAccountingResourceForeignOwner"
      } else {
        "DomainAccountingResourceForeignOwner"
      }
    ClosedReservation =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourceClosedReservation"
        } else {
          "DomainBootstrapResourceClosedReservation"
        }
      } else if read_kind {
        "read:DomainAccountingResourceClosedReservation"
      } else {
        "DomainAccountingResourceClosedReservation"
      }
    ClosedHolding =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourceClosedHolding"
        } else {
          "DomainBootstrapResourceClosedHolding"
        }
      } else if read_kind {
        "read:DomainAccountingResourceClosedHolding"
      } else {
        "DomainAccountingResourceClosedHolding"
      }
    InvalidCharge =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourceInvalidCharge"
        } else {
          "DomainBootstrapResourceInvalidCharge"
        }
      } else if read_kind {
        "read:DomainAccountingResourceInvalidCharge"
      } else {
        "DomainAccountingResourceInvalidCharge"
      }
    IdentityOverflow =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourceIdentityOverflow"
        } else {
          "DomainBootstrapResourceIdentityOverflow"
        }
      } else if read_kind {
        "read:DomainAccountingResourceIdentityOverflow"
      } else {
        "DomainAccountingResourceIdentityOverflow"
      }
    TokenLimit =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourceTokenLimit"
        } else {
          "DomainBootstrapResourceTokenLimit"
        }
      } else if read_kind {
        "read:DomainAccountingResourceTokenLimit"
      } else {
        "DomainAccountingResourceTokenLimit"
      }
    CostLimit =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourceCostLimit"
        } else {
          "DomainBootstrapResourceCostLimit"
        }
      } else if read_kind {
        "read:DomainAccountingResourceCostLimit"
      } else {
        "DomainAccountingResourceCostLimit"
      }
    DurationLimit =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourceDurationLimit"
        } else {
          "DomainBootstrapResourceDurationLimit"
        }
      } else if read_kind {
        "read:DomainAccountingResourceDurationLimit"
      } else {
        "DomainAccountingResourceDurationLimit"
      }
    ResourceParked =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourceResourceParked"
        } else {
          "DomainBootstrapResourceResourceParked"
        }
      } else if read_kind {
        "read:DomainAccountingResourceResourceParked"
      } else {
        "DomainAccountingResourceResourceParked"
      }
    ChildFundingUnavailable =>
      if bootstrap {
        if read_kind {
          "read:DomainBootstrapResourceChildFundingUnavailable"
        } else {
          "DomainBootstrapResourceChildFundingUnavailable"
        }
      } else if read_kind {
        "read:DomainAccountingResourceChildFundingUnavailable"
      } else {
        "DomainAccountingResourceChildFundingUnavailable"
      }
  }
}
