///|
// Closed enum discriminants only. Never serialize a nested message, path,
// credential, scalar identity, receiver, or retained cleanup capability.
// Existing outer error families and public codes remain unchanged.
fn command_preparation_cleanup_cause(
  issue : LocalCommandPreparationIssue,
) -> String {
  match issue {
    CommandInvalidProfile => "CommandInvalidProfile"
    CommandNativeStorage(cause) =>
      match cause {
        NativeStorageInvalidInput => "NativeStorageInvalidInput"
        NativeStorageOverflow => "NativeStorageOverflow"
        NativeStoragePlatformUnadmitted => "NativeStoragePlatformUnadmitted"
        NativeStorageSqliteHeapMissing => "NativeStorageSqliteHeapMissing"
        NativeStorageControlMissing => "NativeStorageControlMissing"
        NativeStorageInsufficient => "NativeStorageInsufficient"
        NativeStorageSqliteDomainMissing => "NativeStorageSqliteDomainMissing"
      }
    CommandUnavailable => "CommandUnavailable"
    CommandRequestPreparation(cause) =>
      match cause {
        ForeignOriginal => "ForeignOriginal"
        WrongPhase => "WrongPhase"
        Policy => "Policy"
        Initial(_) => "Initial"
        Capacity(_) => "Capacity"
        ProgramJson(_) => "ProgramJson"
        ProgramCheck(_) => "ProgramCheck"
        Parameters(_) => "Parameters"
        Intent(_) => "Intent"
        SourceInput(_) => "SourceInput"
        Work(_) => "Work"
        ParameterDeclarations(_) => "ParameterDeclarations"
        ParameterSource(_) => "ParameterSource"
      }
    CommandHost(cause) =>
      match cause {
        Unavailable => "Unavailable"
        ForeignOriginal => "ForeignOriginal"
        AlreadyConsumed => "AlreadyConsumed"
        Closing => "Closing"
        ReadersPending => "ReadersPending"
        Physical(_) => "Physical"
        Resource(_) => "Resource"
      }
    CommandDomain(cause) =>
      match cause {
        Bootstrap(_) => "Bootstrap"
        Accounting(_) => "Accounting"
      }
    CommandRead(cause) =>
      match cause {
        Domain(_) => "Domain"
        Child(_) => "Child"
        Read(_) => "Read"
        Buffer(_) => "Buffer"
      }
    CommandRetainedExecution(cause) =>
      match cause {
        Domain(_) => "Domain"
        Child(_) => "Child"
        Initialization(_) => "Initialization"
      }
    CommandStoreOperation(cause) =>
      match cause {
        StoreOperationUnavailable => "StoreOperationUnavailable"
        StoreOperationForeignOriginal => "StoreOperationForeignOriginal"
        StoreOperationCapture(_) => "StoreOperationCapture"
        StoreOperationResources(_) => "StoreOperationResources"
        StoreOperationExecution(_) => "StoreOperationExecution"
        StoreOperationSqlite(_) => "StoreOperationSqlite"
      }
    CommandBusinessChildren => "CommandBusinessChildren"
    CommandBusinessPublication => "CommandBusinessPublication"
    CommandBusinessStore(cause) =>
      match cause {
        UnsupportedTarget => "UnsupportedTarget"
        CheckpointEvidence(_) => "CheckpointEvidence"
        PreviewAdmission(_) => "PreviewAdmission"
        PrivateEvidence(_) => "PrivateEvidence"
        PrivateCaptureRollback(_, _) => "PrivateCaptureRollback"
        Closed => "Closed"
        InvalidConfiguration => "InvalidConfiguration"
        LegacyStoreFormat(_) => "LegacyStoreFormat"
        UnknownStoreFormat(_) => "UnknownStoreFormat"
        StoreFormatIo(_) => "StoreFormatIo"
        Protocol(_) => "Protocol"
        Filesystem(_) => "Filesystem"
        Database(_) => "Database"
        StateCollision => "StateCollision"
        RecoveryRequired => "RecoveryRequired"
        ExistingPayload => "ExistingPayload"
        DigestMismatch => "DigestMismatch"
        Delivery(_) => "Delivery"
        RowFrame(_) => "RowFrame"
        SinkProgress(_) => "SinkProgress"
        DeliveryIssuance(_) => "DeliveryIssuance"
        DeliveryGrantUsage(_) => "DeliveryGrantUsage"
        PublicationCommit(_) => "PublicationCommit"
        PublicationCommitIssuance(_) => "PublicationCommitIssuance"
        PublicationCommitConflict => "PublicationCommitConflict"
        ClockRegression => "ClockRegression"
        DeliveryLimit => "DeliveryLimit"
        DeliveryIncomplete => "DeliveryIncomplete"
        CleanupPending => "CleanupPending"
        ReaderBusy => "ReaderBusy"
        ExistingDeliveryAttempt => "ExistingDeliveryAttempt"
        DeliveryAttemptUnresolved => "DeliveryAttemptUnresolved"
        OperationRouting(_, _) => "OperationRouting"
        OperationCleanup(_, _) => "OperationCleanup"
      }
    CommandRunObservationPending => "CommandRunObservationPending"
    CommandRunObservationStore(cause) =>
      match cause {
        UnsupportedTarget => "UnsupportedTarget"
        CheckpointEvidence(_) => "CheckpointEvidence"
        PreviewAdmission(_) => "PreviewAdmission"
        PrivateEvidence(_) => "PrivateEvidence"
        PrivateCaptureRollback(_, _) => "PrivateCaptureRollback"
        Closed => "Closed"
        InvalidConfiguration => "InvalidConfiguration"
        LegacyStoreFormat(_) => "LegacyStoreFormat"
        UnknownStoreFormat(_) => "UnknownStoreFormat"
        StoreFormatIo(_) => "StoreFormatIo"
        Protocol(_) => "Protocol"
        Filesystem(_) => "Filesystem"
        Database(_) => "Database"
        StateCollision => "StateCollision"
        RecoveryRequired => "RecoveryRequired"
        ExistingPayload => "ExistingPayload"
        DigestMismatch => "DigestMismatch"
        Delivery(_) => "Delivery"
        RowFrame(_) => "RowFrame"
        SinkProgress(_) => "SinkProgress"
        DeliveryIssuance(_) => "DeliveryIssuance"
        DeliveryGrantUsage(_) => "DeliveryGrantUsage"
        PublicationCommit(_) => "PublicationCommit"
        PublicationCommitIssuance(_) => "PublicationCommitIssuance"
        PublicationCommitConflict => "PublicationCommitConflict"
        ClockRegression => "ClockRegression"
        DeliveryLimit => "DeliveryLimit"
        DeliveryIncomplete => "DeliveryIncomplete"
        CleanupPending => "CleanupPending"
        ReaderBusy => "ReaderBusy"
        ExistingDeliveryAttempt => "ExistingDeliveryAttempt"
        DeliveryAttemptUnresolved => "DeliveryAttemptUnresolved"
        OperationRouting(_, _) => "OperationRouting"
        OperationCleanup(_, _) => "OperationCleanup"
      }
    CommandBusinessResult(cause) =>
      match cause {
        InvalidRequest => "InvalidRequest"
        InvalidProgress => "InvalidProgress"
        AccessDenied => "AccessDenied"
        ResultUnavailable => "ResultUnavailable"
        LookupUnavailable => "LookupUnavailable"
        Store(_) => "Store"
        Publication(_) => "Publication"
      }
    CommandBusinessFileOutput(cause) =>
      match cause {
        Selection(_) => "Selection"
        Adoption(_) => "Adoption"
        Journal(_) => "Journal"
        AuthorizationDenied => "AuthorizationDenied"
        Disabled => "Disabled"
        SelectionMismatch => "SelectionMismatch"
        InvalidObservationTime => "InvalidObservationTime"
        PolicyExpired => "PolicyExpired"
        PolicyNotSelected => "PolicyNotSelected"
        MaterialUnavailable => "MaterialUnavailable"
        FileOutputUnavailable => "FileOutputUnavailable"
        FileOutput(_) => "FileOutput"
        OriginalRead(_, _) => "OriginalRead"
        SubmittedResult(_) => "SubmittedResult"
      }
    CommandSqlite(cause) =>
      match cause {
        Domain(_) => "Domain"
        Library(_) => "Library"
      }
    CommandPair(cause) =>
      match cause {
        Read(_) => "Read"
        Sqlite(_) => "Sqlite"
        Domain(_) => "Domain"
      }
    CommandRuntime(cause) =>
      match cause {
        InvalidInput => "InvalidInput"
        InvalidManifest => "InvalidManifest"
        Changed => "Changed"
        Limit => "Limit"
        Physical(_) => "Physical"
        OriginalReadUnavailable => "OriginalReadUnavailable"
        OriginalRead(_) => "OriginalRead"
        CleanupPending => "CleanupPending"
        OriginalHostResources(_) => "OriginalHostResources"
      }
    CommandComponent(cause) =>
      match cause {
        Domain(_) => "Domain"
        Signature(_) => "Signature"
      }
    CommandReadCrypto(cause) =>
      match cause {
        Resources(_) => "Resources"
        Crypto(_) => "Crypto"
      }
    CommandSignature(cause) =>
      match cause {
        UnsupportedTarget => "UnsupportedTarget"
        InvalidInput => "InvalidInput"
        LibraryLoad(_) => "LibraryLoad"
        InvalidPublicKey(_) => "InvalidPublicKey"
        InvalidPrivateKey(_) => "InvalidPrivateKey"
        UnsupportedKey(_) => "UnsupportedKey"
        Verification(_) => "Verification"
        Signing(_) => "Signing"
        CleanupPending => "CleanupPending"
        CloseUnconfirmed(_) => "CloseUnconfirmed"
      }
    CommandJournal(cause) =>
      match cause {
        JournalNotOpened => "JournalNotOpened"
        JournalOpeningUnconfirmed => "JournalOpeningUnconfirmed"
        JournalCaptureClosed => "JournalCaptureClosed"
        JournalAdoption(_) => "JournalAdoption"
      }
    CommandAdoption(cause) =>
      match cause {
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
        Physical(_) => "Physical"
        Epoch(_) => "Epoch"
        Journal(_) => "Journal"
        Fenced => "Fenced"
        TransactionUnknown => "TransactionUnknown"
        DatabasePending(_, _) => "DatabasePending"
        Inspection(_) => "Inspection"
        InstallationReadTransactionFailure(_, _) =>
          "InstallationReadTransactionFailure"
        OriginalResources(_) => "OriginalResources"
        OriginalResourceScopePending => "OriginalResourceScopePending"
        OriginalResourceLeave(_, _) => "OriginalResourceLeave"
        InspectionCleanup(_) => "InspectionCleanup"
        InspectionPending(_, _, _) => "InspectionPending"
      }
    CommandCapture(cause) =>
      match cause {
        AdoptionNotOpened => "AdoptionNotOpened"
        AdoptionOpeningUnconfirmed => "AdoptionOpeningUnconfirmed"
        AdoptionCaptureClosed => "AdoptionCaptureClosed"
        AdoptionJournalAlreadyCaptured => "AdoptionJournalAlreadyCaptured"
        AdoptionOriginal(_) => "AdoptionOriginal"
        AdoptionJournal(_) => "AdoptionJournal"
      }
    CommandApplication(_) => "CommandApplication"
    CommandProjectMock(cause) =>
      match cause {
        ForeignOriginal => "ProjectMockForeignOriginal"
        AlreadyPreparing => "ProjectMockAlreadyPreparing"
        Environment => "ProjectMockEnvironment"
        Task(original) =>
          match original.kind {
            InvalidLimits => "ProjectMockTaskInvalidLimits"
            BodyLimit | TaskLimit | WorkLimit => "ProjectMockTaskLimit"
            _ => "ProjectMockTaskInvalid"
          }
        Answers(original) => local_project_mock_answer_cleanup_cause(original)
        Installation(original) =>
          match original {
            ForeignOriginal => "ProjectMockInstallationForeignOriginal"
            Retired => "ProjectMockInstallationRetired"
            Busy => "ProjectMockInstallationBusy"
            MissingAnswer => "ProjectMockInstallationMissingAnswer"
            Answers(cause) => local_project_mock_answer_cleanup_cause(cause)
          }
      }
    CommandFilesystem(cause) =>
      match cause {
        InvalidLimit => "InvalidLimit"
        Missing => "Missing"
        CapacityExceeded => "CapacityExceeded"
        Filesystem(_) => "Filesystem"
        Cleanup(_, _) => "Cleanup"
        InvalidUtf8 => "InvalidUtf8"
        PreparationUnavailable => "PreparationUnavailable"
      }
    CommandFilesystemCleanup(cause) =>
      match cause {
        UnsupportedTarget => "UnsupportedTarget"
        InvalidName => "InvalidName"
        InvalidLimit => "InvalidLimit"
        RootOpen(_) => "RootOpen"
        Lock(_) => "Lock"
        WriterCreate(_) => "WriterCreate"
        CapacityExceeded => "CapacityExceeded"
        WriterClosed => "WriterClosed"
        Write(_) => "Write"
        Conflict => "Conflict"
        GenerationMismatch => "GenerationMismatch"
        InvalidReadSize => "InvalidReadSize"
        IncompleteRead => "IncompleteRead"
        ReaderClosed => "ReaderClosed"
        Read(_) => "Read"
        Seal(_) => "Seal"
        Cleanup(_) => "Cleanup"
      }
  }
}

///|
// Closed original Model issue labels only, not Task/document strings or
// execution/refusal classification. The retained issue remains authoritative.
fn local_project_mock_answer_cleanup_cause(
  issue : @model.ModelMockAnswerIssue,
) -> String {
  match issue {
    InvalidLimits => "ProjectMockAnswerInvalidLimits"
    BodyLimit | WorkLimit | EntryLimit => "ProjectMockAnswerLimit"
    InvalidBody => "ProjectMockAnswerInvalidBody"
    TaskIdentity => "ProjectMockAnswerTaskIdentity"
    OutputValue => "ProjectMockAnswerOutputValue"
    ForeignOriginal => "ProjectMockAnswerForeignOriginal"
    Retired => "ProjectMockAnswerRetired"
  }
}
