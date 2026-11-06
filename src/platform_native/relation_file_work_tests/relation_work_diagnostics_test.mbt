///|
// Failure-only observations after the original callback and routing return
// ACKs. These labels are not physical cleanup outcomes or replacement issues.
fn relation_work_row_issue(issue : @rows.RowHostIssue) -> String {
  match issue {
    InvalidSpecification => "InvalidSpecification"
    Declaration(_) => "Declaration (original retained)"
    ForeignDeclaration => "ForeignDeclaration"
    Source(reason) => "Source: " + @debug.to_string(reason)
    InvalidContracts => "InvalidContracts"
    Registration => "Registration"
    Candidate => "Candidate"
    Selection => "Selection"
    Evidence(_) => "Evidence (original retained)"
    Attempt(_) => "Attempt (original retained)"
    Consumer(_) => "Consumer (original retained)"
    SourceEvidence(_) => "SourceEvidence (original retained)"
    Physical(reason) => "Physical: " + @debug.to_string(reason)
    Residual(_) => "Residual (original retained)"
    ResidualWork(_) => "ResidualWork (original retained)"
    InputValidationWork(reason) =>
      "InputValidationWork: " + @debug.to_string(reason)
    InputKeys(_) => "InputKeys (original retained)"
    InputScores(_) => "InputScores (original retained)"
    InvalidState => "InvalidState"
  }
}

///|
fn relation_work_source_issue(
  issue : @row_file.NativeRelationFileIssue,
) -> String {
  match issue {
    InvalidInput => "InvalidInput"
    Unavailable => "Unavailable"
    ForeignOriginal => "ForeignOriginal"
    Capacity => "Capacity"
    FileLimit => "FileLimit"
    Filesystem(reason) =>
      "Filesystem: " + relation_initial_open_filesystem_issue(reason)
    Execution(Domain(reason)) => "Execution.Domain: " + @debug.to_string(reason)
    Execution(Child(reason)) => "Execution.Child: " + @debug.to_string(reason)
    Resource(reason) => "Resource: " + @debug.to_string(reason)
    Row(reason) => "Row: " + relation_work_row_issue(reason)
    Document(reason) => "Document: " + @debug.to_string(reason)
    Mapping(reason) => "Mapping: " + @debug.to_string(reason)
  }
}

///|
fn relation_work_values_issue(
  issue : @client.NativeClientValuesWorkIssue,
) -> String {
  match issue {
    AuthorizationDenied => "AuthorizationDenied"
    UnsupportedProfile => "UnsupportedProfile"
    Configuration => "Configuration"
    Journal(_) => "Journal (original retained)"
    Start(_) => "Start (original retained)"
    Normalization(_) => "unexpected export-only Normalization"
    Execution(_) => "Execution (original retained)"
    Export(_) => "Export (original retained)"
    OriginalOperation(primary, reason) => {
      let primary = match primary {
        None => "None"
        Some(value) => relation_work_values_issue(value)
      }
      let route = match reason {
        StoreOperationUnavailable => "StoreOperationUnavailable"
        StoreOperationForeignOriginal => "StoreOperationForeignOriginal"
        StoreOperationCapture(_) => "StoreOperationCapture (original retained)"
        StoreOperationResources(_) =>
          "StoreOperationResources (original retained)"
        StoreOperationExecution(Domain(value)) =>
          "StoreOperationExecution.Domain: " + @debug.to_string(value)
        StoreOperationExecution(Child(value)) =>
          "StoreOperationExecution.Child: " + @debug.to_string(value)
        StoreOperationSqlite(value) =>
          "StoreOperationSqlite: " + relation_original_sqlite_issue(value)
      }
      "OriginalOperation(primary=" + primary + ", route=" + route + ")"
    }
  }
}

///|
// Report exact direct variants and bounded Source/Resource payloads. Labels
// explicitly say when a deeper original is retained but not rendered here;
// this is not a general-purpose serialization of every Common/Journal issue.
fn relation_work_issue(issue : @client.NativeClientSourceWorkIssue) -> String {
  match issue {
    Configuration => "Configuration"
    OriginalOperation(reason) =>
      "OriginalOperation: " + relation_work_values_issue(reason)
    RelationFile(reason) =>
      "RelationFile: " + relation_work_source_issue(reason)
    LocalExecution(reason) =>
      "LocalExecution: " +
      (match reason {
        InvalidLimits => "InvalidLimits"
        Fenced => "Fenced"
        UnsupportedGraph => "UnsupportedGraph"
        MissingLocalModule => "MissingLocalModule"
        Driver(_) => "Driver (original retained)"
        Estimate(_) => "Estimate (original retained)"
        FinalizationLimit => "FinalizationLimit"
        MissingOutput => "MissingOutput"
      })
    LocalExport(_) => "LocalExport (original retained)"
    CaptureIdentity(_) => "CaptureIdentity (original retained)"
    AuthorizationDenied => "AuthorizationDenied"
    Normalization(_) => "unexpected export-only Normalization"
    NeedsOriginalReconciliation => "NeedsOriginalReconciliation"
    OriginalRunNotCurrent => "OriginalRunNotCurrent"
    Journal(_) => "Journal (original retained)"
    Work(_) => "unexpected Resident Work"
    Observation(_) => "unexpected publication Observation"
    Invocation(_) => "unexpected publication Invocation"
    Open(_, _) => "unexpected Resident Open"
  }
}

///|
// Static terminal diagnostics only. Field access and exhaustive tag matches
// borrow existing objects; they create no String, collection, Option, Result,
// callback or cleanup authority. Payloads remain with their original custody.
// These labels intentionally identify families, not every nested payload.
fn relation_return_adoption_label(
  issue : @client.NativeLocalAdoptionIssue,
) -> String {
  match issue {
    InvalidInput => "Adoption.InvalidInput; original custody retained"
    ConfigurationLimit =>
      "Adoption.ConfigurationLimit; original custody retained"
    Configuration(_) => "Adoption.Configuration; original custody retained"
    ForeignAccount => "Adoption.ForeignAccount; original custody retained"
    UninstalledBootstrapProfile => "Adoption.UninstalledBootstrapProfile"
    CustodyLost => "Adoption.CustodyLost; original custody retained"
    SourceChanged => "Adoption.SourceChanged; original custody retained"
    AmbiguousInitialization => "Adoption.AmbiguousInitialization"
    Closed => "Adoption.Closed; original custody retained"
    Encoding => "Adoption.Encoding; original custody retained"
    Crypto(_) => "Adoption.Crypto; original custody retained"
    Filesystem(_) => "Adoption.Filesystem; original custody retained"
    ReadAcquisitionFailure(_) => "Adoption.ReadAcquisitionFailure"
    ReadPending(_, _) => "Adoption.ReadPending; original custody retained"
    WritePending(_, _) => "Adoption.WritePending; original custody retained"
    Physical(_) => "Adoption.Physical; original custody retained"
    Epoch(_) => "Adoption.Epoch; original custody retained"
    Journal(_) => "Adoption.Journal; original custody retained"
    Fenced => "Adoption.Fenced; original custody retained"
    TransactionUnknown => "Adoption.TransactionUnknown"
    DatabasePending(_, _) =>
      "Adoption.DatabasePending; original custody retained"
    Inspection(_) => "Adoption.Inspection; original custody retained"
    InstallationReadTransactionFailure(_, _) =>
      "Adoption.InstallationReadTransactionFailure"
    OriginalResources(Read(_)) => "Adoption.OriginalResources.Read"
    OriginalResources(Sqlite(_)) => "Adoption.OriginalResources.Sqlite"
    OriginalResources(Domain(_)) => "Adoption.OriginalResources.Domain"
    OriginalResourceScopePending => "Adoption.OriginalResourceScopePending"
    OriginalResourceLeave(_, Read(_)) => "Adoption.OriginalResourceLeave.Read"
    OriginalResourceLeave(_, Sqlite(_)) =>
      "Adoption.OriginalResourceLeave.Sqlite"
    OriginalResourceLeave(_, Domain(_)) =>
      "Adoption.OriginalResourceLeave.Domain"
    InspectionCleanup(_) => "Adoption.InspectionCleanup"
    InspectionPending(_, _, _) => "Adoption.InspectionPending"
  }
}

///|
fn relation_return_work_label(
  issue : @client.NativeClientSourceWorkIssue,
) -> String {
  match issue {
    Configuration => "Work.Configuration; original custody retained"
    OriginalOperation(AuthorizationDenied) =>
      "Work.OriginalOperation.AuthorizationDenied"
    OriginalOperation(UnsupportedProfile) =>
      "Work.OriginalOperation.UnsupportedProfile"
    OriginalOperation(Configuration) => "Work.OriginalOperation.Configuration"
    OriginalOperation(Journal(_)) => "Work.OriginalOperation.Journal"
    OriginalOperation(Start(_)) => "Work.OriginalOperation.Start"
    OriginalOperation(Normalization(_)) =>
      "Work.OriginalOperation.Normalization"
    OriginalOperation(Execution(_)) => "Work.OriginalOperation.Execution"
    OriginalOperation(Export(_)) => "Work.OriginalOperation.Export"
    OriginalOperation(OriginalOperation(_, StoreOperationUnavailable)) =>
      "Work.OriginalOperation.Route.Unavailable"
    OriginalOperation(OriginalOperation(_, StoreOperationForeignOriginal)) =>
      "Work.OriginalOperation.Route.ForeignOriginal"
    OriginalOperation(OriginalOperation(_, StoreOperationCapture(_))) =>
      "Work.OriginalOperation.Route.Capture"
    OriginalOperation(OriginalOperation(_, StoreOperationResources(_))) =>
      "Work.OriginalOperation.Route.Resources"
    OriginalOperation(OriginalOperation(_, StoreOperationExecution(_))) =>
      "Work.OriginalOperation.Route.Execution"
    OriginalOperation(OriginalOperation(_, StoreOperationSqlite(_))) =>
      "Work.OriginalOperation.Route.Sqlite"
    RelationFile(InvalidInput) => "Work.RelationFile.InvalidInput"
    RelationFile(Unavailable) => "Work.RelationFile.Unavailable"
    RelationFile(ForeignOriginal) => "Work.RelationFile.ForeignOriginal"
    RelationFile(Capacity) => "Work.RelationFile.Capacity"
    RelationFile(FileLimit) => "Work.RelationFile.FileLimit"
    RelationFile(Filesystem(_)) => "Work.RelationFile.Filesystem"
    RelationFile(Execution(_)) => "Work.RelationFile.Execution"
    RelationFile(Resource(_)) => "Work.RelationFile.Resource"
    RelationFile(Row(_)) => "Work.RelationFile.Row"
    RelationFile(Document(_)) => "Work.RelationFile.Document"
    RelationFile(Mapping(_)) => "Work.RelationFile.Mapping"
    LocalExecution(_) => "Work.LocalExecution; original custody retained"
    LocalExport(_) => "Work.LocalExport; original custody retained"
    CaptureIdentity(_) => "Work.CaptureIdentity; original custody retained"
    AuthorizationDenied => "Work.AuthorizationDenied; original custody retained"
    Normalization(_) => "Work.Normalization; original custody retained"
    NeedsOriginalReconciliation => "Work.NeedsOriginalReconciliation"
    OriginalRunNotCurrent => "Work.OriginalRunNotCurrent"
    Journal(_) => "Work.Journal; original custody retained"
    Work(_) => "Work.ResidentWork; original custody retained"
    Observation(_) => "Work.Observation; original custody retained"
    Invocation(_) => "Work.Invocation; original custody retained"
    Open(_, _) => "Work.ResidentOpen; original custody retained"
  }
}

///|
fn relation_return_failure_label(
  entry : Result[Unit, @client.NativeLocalAdoptionIssue],
  failure : @client.NativeClientRelationFileWorkFailure?,
) -> String {
  match failure {
    Some(original) => relation_return_work_label(original.issue())
    None =>
      match entry {
        Err(original) => relation_return_adoption_label(original)
        Ok(_) => "unexpected successful original return diagnostic"
      }
  }
}
