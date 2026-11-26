///|
// Project only closed constructors from this original failure. Never format
// Account, Source, SQL, body, key, path or other String payloads. Each recursive
// branch has four levels; both the primary and the return issue keep a slot.
fn local_publisher_binding_issue_code(
  issue : @local_host.NativeLocalPublisherBindingIssue,
  depth : Int,
) -> String {
  if depth >= 4 {
    return "Bounded"
  }
  match issue {
    Adoption(issue) =>
      "Adoption(" + local_publisher_adoption_issue_code(issue, depth + 1) + ")"
    Journal(issue) =>
      "Journal(" + local_publisher_journal_issue_code(issue, depth + 1) + ")"
    InvalidOriginal => "InvalidOriginal"
    SelectionMismatch => "SelectionMismatch"
    AuthorizationDenied => "AuthorizationDenied"
    OriginalOperation(primary, tail) => {
      let primary = match primary {
        None => "None"
        Some(issue) =>
          "Some(" + local_publisher_binding_issue_code(issue, depth + 1) + ")"
      }
      "OriginalOperation(" +
      primary +
      "," +
      local_publisher_operation_issue_code(tail, depth + 1) +
      ")"
    }
  }
}

///|
fn local_publisher_operation_issue_code(
  issue : @local_host.NativeLocalStoreOperationIssue,
  depth : Int,
) -> String {
  if depth >= 4 {
    return "Bounded"
  }
  match issue {
    StoreOperationUnavailable => "StoreOperationUnavailable"
    StoreOperationForeignOriginal => "StoreOperationForeignOriginal"
    StoreOperationCapture(issue) =>
      "StoreOperationCapture(" +
      local_publisher_adoption_issue_code(issue, depth + 1) +
      ")"
    StoreOperationResources(issue) =>
      "StoreOperationResources(" +
      local_publisher_resources_issue_code(issue, depth + 1) +
      ")"
    StoreOperationExecution(_) => "StoreOperationExecution"
    StoreOperationSqlite(issue) =>
      "StoreOperationSqlite(" +
      local_publisher_sqlite_issue_code(issue, depth + 1) +
      ")"
  }
}

///|
fn local_publisher_adoption_issue_code(
  issue : @local_host.NativeLocalAdoptionIssue,
  depth : Int,
) -> String {
  if depth >= 4 {
    return "Bounded"
  }
  match issue {
    InvalidInput => "InvalidInput"
    ConfigurationLimit => "ConfigurationLimit"
    Configuration(_) => "Configuration"
    ForeignAccount => "ForeignAccount"
    UninstalledBootstrapProfile => "UninstalledBootstrapProfile"
    CustodyLost => "CustodyLost"
    SourceChanged => "SourceChanged"
    AmbiguousInitialization => "AmbiguousInitialization"
    Closed => "Closed"
    Encoding => "Encoding"
    Crypto(_) => "Crypto"
    Filesystem(_) => "Filesystem"
    ReadAcquisitionFailure(_) => "ReadAcquisitionFailure"
    ReadPending(_, _) => "ReadPending"
    WritePending(_, _) => "WritePending"
    Physical(issue) =>
      "Physical(" + local_publisher_sqlite_issue_code(issue, depth + 1) + ")"
    Epoch(_) => "Epoch"
    Journal(issue) =>
      "Journal(" + local_publisher_journal_issue_code(issue, depth + 1) + ")"
    Fenced => "Fenced"
    TransactionUnknown => "TransactionUnknown"
    JournalStepFailed(step, _) =>
      if step.requires_reconciliation() {
        "TransactionUnknown"
      } else {
        "Physical"
      }
    DatabasePending(_, issue) =>
      "DatabasePending(" +
      local_publisher_adoption_issue_code(issue, depth + 1) +
      ")"
    Inspection(_) => "Inspection"
    InstallationReadTransactionFailure(primary, tail) =>
      "InstallationReadTransactionFailure(" +
      local_publisher_adoption_issue_code(primary, depth + 1) +
      "," +
      local_publisher_journal_issue_code(tail, depth + 1) +
      ")"
    OriginalResources(issue) =>
      "OriginalResources(" +
      local_publisher_resources_issue_code(issue, depth + 1) +
      ")"
    OriginalResourceScopePending => "OriginalResourceScopePending"
    OriginalResourceLeave(primary, tail) => {
      let primary = match primary {
        None => "None"
        Some(issue) =>
          "Some(" + local_publisher_adoption_issue_code(issue, depth + 1) + ")"
      }
      "OriginalResourceLeave(" +
      primary +
      "," +
      local_publisher_resources_issue_code(tail, depth + 1) +
      ")"
    }
    InspectionCleanup(_) => "InspectionCleanup"
    InspectionPending(primary, tail, _) => {
      let primary = match primary {
        None => "None"
        Some(issue) =>
          "Some(" + local_publisher_adoption_issue_code(issue, depth + 1) + ")"
      }
      "InspectionPending(" +
      primary +
      "," +
      local_publisher_adoption_issue_code(tail, depth + 1) +
      ")"
    }
  }
}

///|
fn local_publisher_journal_issue_code(
  issue : @local_host.NativeClientRunJournalIssue,
  depth : Int,
) -> String {
  if depth >= 4 {
    return "Bounded"
  }
  match issue {
    CustodyLost => "CustodyLost"
    CapacityExceeded => "CapacityExceeded"
    AuthorizationDenied => "AuthorizationDenied"
    ChangedIntent => "ChangedIntent"
    ForeignRun => "ForeignRun"
    Fenced => "Fenced"
    JournalStepFailed(step, _) =>
      if step.requires_reconciliation() {
        "TransactionUnknown"
      } else {
        "Physical"
      }
    Encoding => "Encoding"
    Physical(issue) =>
      "Physical(" + local_publisher_sqlite_issue_code(issue, depth + 1) + ")"
    Start(_) => "Start"
    Epoch(_) => "Epoch"
    InvalidSubmission => "InvalidSubmission"
    SubmissionReferenceUsed => "SubmissionReferenceUsed"
    NamedSubmission(_) => "NamedSubmission"
    SubmissionEpochRejected(_) => "SubmissionEpochRejected"
    UnsupportedPreparation => "UnsupportedPreparation"
    MissingEffectMaterialOriginal => "MissingEffectMaterialOriginal"
    ChangedEffectMaterialOriginal => "ChangedEffectMaterialOriginal"
    PublicationPolicy(_) => "PublicationPolicy"
    Checkpoint(_) => "Checkpoint"
    CancellationIdentity(_) => "CancellationIdentity"
    CancellationOperation(_) => "CancellationOperation"
    PublicationObservation(_) => "PublicationObservation"
    RunIdIndexIncomplete => "RunIdIndexIncomplete"
  }
}

///|
fn local_publisher_sqlite_issue_code(
  issue : @local_sqlite.NativeSqliteIssue,
  depth : Int,
) -> String {
  if depth >= 4 {
    return "Bounded"
  }
  match issue {
    UnsupportedTarget => "UnsupportedTarget"
    InvalidName => "InvalidName"
    InvalidLimit => "InvalidLimit"
    LibraryLoad(_) => "LibraryLoad"
    DatabaseOpen(_) => "DatabaseOpen"
    DatabaseClosed => "DatabaseClosed"
    NotFound => "NotFound"
    Collision => "Collision"
    Busy => "Busy"
    BodyTooLarge => "BodyTooLarge"
    CapacityExceeded => "CapacityExceeded"
    Physical(_) => "Physical"
    OperationRoutingBefore(code) =>
      "OperationRoutingBefore(" + code.to_string() + ")"
    OperationRoutingAfter(primary, code) => {
      let primary = match primary {
        None => "None"
        Some(issue) =>
          "Some(" + local_publisher_sqlite_issue_code(issue, depth + 1) + ")"
      }
      "OperationRoutingAfter(" + primary + "," + code.to_string() + ")"
    }
  }
}

///|
fn local_publisher_resources_issue_code(
  issue : @initial_arena.InstalledArenaLocalHostResourcesIssue,
  depth : Int,
) -> String {
  if depth >= 4 {
    return "Bounded"
  }
  match issue {
    Domain(issue) => "Domain(" + local_publisher_domain_issue_code(issue) + ")"
    Sqlite(issue) =>
      match issue {
        Domain(issue) =>
          "Sqlite.Domain(" + local_publisher_domain_issue_code(issue) + ")"
        Library(issue) =>
          "Sqlite.Library(" +
          local_publisher_sqlite_issue_code(issue, depth + 1) +
          ")"
      }
    Read(issue) =>
      match issue {
        Domain(issue) =>
          "Read.Domain(" + local_publisher_domain_issue_code(issue) + ")"
        Child(_) => "Read.Child"
        Buffer(_) => "Read.Buffer"
        Read(issue) =>
          "Read.Read(" +
          (match issue {
            InvalidBootstrap => "InvalidBootstrap"
            IncompleteInventory => "IncompleteInventory"
            ForeignOrigin => "ForeignOrigin"
            ChangedOriginalState => "ChangedOriginalState"
            SpentClaim => "SpentClaim"
            CleanupPending => "CleanupPending"
            Resource(issue) =>
              "Resource(" + local_publisher_ledger_issue_code(issue) + ")"
          }) +
          ")"
      }
  }
}

///|
fn local_publisher_domain_issue_code(
  issue : @initial_bootstrap.NativeBackedExecutionIssue,
) -> String {
  match issue {
    Bootstrap(issue) =>
      "Bootstrap(" +
      (match issue {
        Unavailable => "Unavailable"
        ForeignOriginal => "ForeignOriginal"
        AlreadyConsumed => "AlreadyConsumed"
        Closing => "Closing"
        ReadersPending => "ReadersPending"
        Physical(code) => "Physical(" + code.to_string() + ")"
        Resource(issue) =>
          "Resource(" + local_publisher_ledger_issue_code(issue) + ")"
      }) +
      ")"
    Accounting(issue) =>
      "Accounting(" +
      (match issue {
        ForeignOriginal => "ForeignOriginal"
        InvalidExtent => "InvalidExtent"
        ExtentConflict => "ExtentConflict"
        DuplicateChild => "DuplicateChild"
        RegionClosing => "RegionClosing"
        Retired => "Retired"
        CleanupPending => "CleanupPending"
        ChangedFinalUsage => "ChangedFinalUsage"
        ReadUseAlreadyIssued => "ReadUseAlreadyIssued"
        LiveAccessAlreadyIssued => "LiveAccessAlreadyIssued"
        LiveChildAlreadyAdmitted => "LiveChildAlreadyAdmitted"
        Resource(issue) =>
          "Resource(" + local_publisher_ledger_issue_code(issue) + ")"
      }) +
      ")"
  }
}

///|
fn local_publisher_ledger_issue_code(
  issue : @initial_resources.LedgerIssue,
) -> String {
  match issue {
    InvalidLimits => "InvalidLimits"
    PlanningLimit => "PlanningLimit"
    AttemptLimit => "AttemptLimit"
    HoldingLimit => "HoldingLimit"
    TransferLimit => "TransferLimit"
    RetentionLimit => "RetentionLimit"
    ExecutionLimit => "ExecutionLimit"
    ForeignOwner => "ForeignOwner"
    ClosedReservation => "ClosedReservation"
    ClosedHolding => "ClosedHolding"
    InvalidCharge => "InvalidCharge"
    IdentityOverflow => "IdentityOverflow"
    TokenLimit => "TokenLimit"
    CostLimit => "CostLimit"
    DurationLimit => "DurationLimit"
    ResourceParked => "ResourceParked"
    ChildFundingUnavailable => "ChildFundingUnavailable"
  }
}

///|
fn local_report_publisher_binding_issue(
  issue : @local_host.NativeLocalPublisherBindingIssue,
) -> Unit {
  let bytes = @utf8.encode(
    "ACTQL_NATIVE_PUBLISHER_ISSUE " +
    local_publisher_binding_issue_code(issue, 0),
  )
  report_failure_ffi(bytes, bytes.length())
}
