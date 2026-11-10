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
    CommandSavedResolution(cause) =>
      match cause {
        SavedResolutionUnavailable => "SavedResolutionUnavailable"
        SavedResolutionOriginal(_) => "SavedResolutionOriginal"
        SavedResolutionReviewer(_) => "SavedResolutionReviewer"
        SavedResolutionKey(_) => "SavedResolutionKey"
        SavedResolutionProof(_) => "SavedResolutionProof"
        SavedResolutionSigning(_) => "SavedResolutionSigning"
        SavedResolutionAccount(_) => "SavedResolutionAccount"
        SavedResolutionHost(_) => "SavedResolutionHost"
        SavedResolutionEncoding => "SavedResolutionEncoding"
      }
    CommandBusinessChildren => "CommandBusinessChildren"
    CommandSavedFileResource(cause) =>
      "SavedFileResource" + local_submission_ledger_tag(cause).to_string()
    CommandSavedFileEntry(cause) =>
      match cause {
        Unavailable => "SavedFileEntryUnavailable"
        Domain(Bootstrap(_)) => "SavedFileEntryDomainBootstrap"
        Domain(Accounting(_)) => "SavedFileEntryDomainAccounting"
        Resource(ledger) =>
          "SavedFileEntryResource" +
          local_submission_ledger_tag(ledger).to_string()
      }
    CommandSavedEffectOutput(cause) =>
      match cause {
        Snapshot(_) => "SavedPublicationSnapshot"
        SnapshotCleanup(_, _) => "SavedPublicationSnapshotCleanup"
        OutputCleanup(_, _) | StoreCleanup(_, _) | BindingCleanup(_, _) =>
          "SavedPublicationOutputCleanup"
        Store(_) => "SavedPublicationOutputStore"
        Binding(_) => "SavedPublicationOutputBinding"
        _ => "SavedPublicationOutput"
      }
    CommandSavedEffectCompletion(cause) =>
      match cause {
        Member(issue) =>
          match issue {
            ActivePhysicalOwner(_) => "SavedEffectMemberPhysicalOwner"
            MissingTerminalReceipt(_) => "SavedEffectMemberMissingReceipt"
            ForeignLedgerHead(_) => "SavedEffectMemberForeignLedger"
            _ => "SavedEffectMemberReceipt"
          }
        Set(issue) =>
          match issue {
            MemberReceipt(_, _) => "SavedEffectSetMemberReceipt"
            InvalidInventory => "SavedEffectSetInventory"
            _ => "SavedEffectSetReceipt"
          }
        Final(issue) =>
          match issue {
            InvalidComputation => "SavedEffectFinalComputation"
            References(_) => "SavedEffectFinalReferences"
            _ => "SavedEffectFinalReceipt"
          }
        Admission(issue) =>
          match issue {
            ResultEvidence(_) => "SavedEffectFinalResultEvidence"
            FinalChain(_) => "SavedEffectFinalChain"
            _ => "SavedEffectFinalAdmission"
          }
      }
    CommandSavedEffectPublication(cause) =>
      match cause {
        Original(_) => "SavedPublicationOriginal"
        Journal(_) => "SavedPublicationJournal"
        Service(_) => "SavedPublicationService"
        Construction => "SavedPublicationConstruction"
        Publisher(_) => "SavedPublicationPublisher"
      }
    CommandSavedFileResume(cause) =>
      match cause {
        HostAttestationUnavailable => "SavedFileOriginalUnavailable"
        HostAttestationJournal(_) => "SavedFileJournal"
        _ => "SavedFileOriginalAuthority"
      }
    CommandBusinessSource(cause) =>
      match cause {
        InvalidInput => "SourceInvalidInput"
        Unavailable => "SourceUnavailable"
        ForeignOriginal => "SourceForeignOriginal"
        Capacity => "SourceCapacity"
        FileLimit => "SourceFileLimit"
        Filesystem(_) => "SourceFilesystem"
        Execution(_) => "SourceExecution"
        Resource(_) => "SourceResource"
        Row(_) => "SourceRow"
        Document(_) => "SourceDocument"
        Mapping(_) => "SourceMapping"
        ManagedRead(_) => "SourceManagedRead"
        Content(_) => "SourceContent"
        Store(_) => "SourceStore"
        Lookup(_) => "SourceLookup"
      }
    CommandBusinessEffectProposals(cause) =>
      match cause {
        ImportObservation(original) =>
          match original {
            ForeignInput => "EffectImportForeignInput"
            _ => "EffectImportObservation"
          }
        Imports(original) =>
          match original {
            MissingScope => "EffectImportedScopeMissing"
            _ => "EffectImportedEvidence"
          }
        HostExecution(original) =>
          match original {
            InvalidLimits => "EffectHostLimits"
            Fenced => "EffectHostFenced"
            UnsupportedGraph => "EffectHostGraph"
            MissingLocalModule => "EffectHostModule"
            Driver(_) => "EffectHostDriver"
            Estimate(_) => "EffectHostEstimate"
            FinalizationLimit => "EffectHostFinalization"
            MissingOutput => "EffectHostOutput"
          }
        PublicExport(original) =>
          match original {
            InvalidState => "EffectPublicExportState"
            _ => "EffectPublicExport"
          }
        PublicManifest(original) =>
          match original {
            ManifestIssuanceEncoding => "EffectPublicManifestEncoding"
            _ => "EffectPublicManifest"
          }
        PublicReceipt(original) =>
          match original {
            ReceiptIssuanceEncoding => "EffectPublicReceiptEncoding"
            _ => "EffectPublicReceipt"
          }
        PublicBindings(original) =>
          match original {
            ForeignMaterials => "EffectPublicBindingsOwner"
            _ => "EffectPublicBindings"
          }
        PublicNormalization(original) =>
          match original {
            MissingOriginalJournal => "EffectPublicNormalizationOriginal"
            _ => "EffectPublicNormalization"
          }
        PublicCapture(original) =>
          match original {
            ForeignInput => "EffectPublicCaptureInput"
            _ => "EffectPublicCapture"
          }
        CapturedSource(original) =>
          match original {
            CaptureIssuanceReferenceMismatch(_) =>
              "EffectCapturedSourceReference"
            _ => "EffectCapturedSource"
          }
        LocalSource(original) =>
          match original {
            InvalidLocalReference(_) => "EffectLocalSourceReference"
            _ => "EffectLocalSource"
          }
        PolicyDependency(original) =>
          match original {
            MissingUnit => "EffectProposalsPolicyMissingUnit"
            MissingDependency => "EffectProposalsPolicyMissingDependency"
            Encoding(_) => "EffectProposalsPolicyEncoding"
            ForeignBody => "EffectProposalsPolicyForeignBody"
            BudgetExceeded => "EffectProposalsPolicyBudget"
          }
        Inventory(original) =>
          match original {
            MissingDependency => "EffectInventoryMissingDependency"
            _ => "EffectInventory"
          }
        PreviewSource(original) =>
          match original {
            ForeignRun => "EffectPreviewSourceRun"
            _ => "EffectPreviewSource"
          }
        PreviewIdentity(original) =>
          match original {
            ForeignInput => "EffectPreviewIdentityInput"
            _ => "EffectPreviewIdentity"
          }
        PreviewBody(original) =>
          match original {
            PreviewShape(_) => "EffectPreviewBodyShape"
            _ => "EffectPreviewBody"
          }
        PreviewBinding(original) =>
          match original {
            ForeignInput => "EffectPreviewBindingInput"
            _ => "EffectPreviewBinding"
          }
        PreviewDispatch(original) =>
          match original {
            InvalidLimits => "EffectPreviewDispatchLimits"
            _ => "EffectPreviewDispatch"
          }
        PreviewKeys(original) =>
          match original {
            KeyInventoryMismatch => "EffectPreviewKeyInventory"
            _ => "EffectPreviewKeys"
          }
        PreviewPlan(original) =>
          match original {
            InvalidMember => "EffectPreviewPlanMember"
            _ => "EffectPreviewPlan"
          }
        Manifest(original) =>
          match original {
            IncompleteResults => "EffectProposalsIncompleteResults"
            IncompleteTableInputs => "EffectProposalsIncompleteTableInputs"
            _ => "EffectProposalsManifest"
          }
        Dependency(original) =>
          match original {
            ForeignInput => "EffectProposalsDependencyForeignInput"
            Dependency(_) => "EffectProposalsDependencyClosure"
            _ => "EffectProposalsDependency"
          }
        Materials(original) =>
          match original {
            RunMismatch => "EffectProposalsMaterialsRunMismatch"
            _ => "EffectProposalsMaterials"
          }
        Definition(original) =>
          match original {
            MissingResult => "EffectProposalsDefinitionMissingResult"
            _ => "EffectProposalsDefinition"
          }
        Artifact(original) =>
          match original {
            ForeignOwner => "EffectProposalsArtifactForeignOwner"
            ForeignExport => "EffectProposalsArtifactForeignExport"
            ForeignRun => "EffectProposalsArtifactForeignRun"
            _ => "EffectProposalsArtifact"
          }
        Source(original) =>
          match original {
            Invocation(_) => "EffectProposalsSourceInvocation"
            Relation(_) => "EffectProposalsSourceRelation"
            Dependency(_) => "EffectProposalsSourceDependency"
          }
        Keyed(original) =>
          match original {
            Identity(_) => "EffectProposalsKeyedContract"
            Wire(_) => "EffectProposalsKeyedWire"
            _ => "EffectProposalsKeyedIdentity"
          }
        Managed(original) =>
          match original {
            InsufficientCapacity => "EffectProposalsInsufficientCapacity"
            Ledger(_) => "EffectProposalsLedger"
            _ => "EffectProposalsManaged"
          }
        Capture(original) =>
          match original {
            ForeignCapture => "EffectProposalsForeignCapture"
            Physical(_) => "EffectProposalsPhysical"
            _ => "EffectProposalsCapture"
          }
        Proposal(original) =>
          match original {
            ForeignBinding => "EffectProposalsForeignBinding"
            RowCountMismatch => "EffectProposalsRowCountMismatch"
            _ => "EffectProposalsProjection"
          }
        ManagedExport(original) =>
          match original {
            ForeignInput | Binding(ForeignOutput) =>
              "EffectProposalsForeignOutput"
            Export(_) => "EffectProposalsExportBody"
            Bridge(_) => "EffectProposalsExportBridge"
            _ => "EffectProposalsExport"
          }
        ManagedPublicExport(original) =>
          match original {
            Export(InvalidState) => "EffectPublicExportState"
            Transformation(_) => "EffectPublicExportTransformation"
            Bridge(_) => "EffectPublicExportBridge"
            _ => "EffectPublicExport"
          }
        Completed(original) =>
          match original {
            ForeignMaterial => "EffectProposalsForeignMaterial"
            Closed => "EffectProposalsClosed"
            _ => "EffectProposalsCompleted"
          }
      }
    CommandBusinessSourceIdentity(cause) =>
      match cause {
        Read(issue) =>
          match issue {
            ForeignRun => "ReadForeignRun"
            InvalidBootstrap => "ReadInvalidBootstrap"
            Resource(_) => "ReadResource"
          }
      }
    CommandBusinessModelGraph(cause) =>
      match cause {
        Preparation(Policy) => "ModelGraphPreparationPolicy"
        Preparation(ForeignOriginal) => "ModelGraphPreparationForeignOriginal"
        Preparation(Capacity(_)) => "ModelGraphPreparationCapacity"
        Preparation(_) => "ModelGraphPreparation"
        ModelGraph(UnsupportedProgram) => "ModelGraphUnsupportedProgram"
        ModelGraph(ForeignExecution) => "ModelGraphForeignExecution"
        ModelGraph(Input(UnrepresentableContract)) => "ModelGraphInputContract"
        ModelGraph(Input(UnsupportedCarrier)) => "ModelGraphInputCarrier"
        ModelGraph(Input(Pipeline(_))) => "ModelGraphInputPipeline"
        ModelGraph(Input(_)) => "ModelGraphInput"
        ModelGraph(Encoding) => "ModelGraphEncoding"
        ModelGraph(_) => "ModelGraphConstruction"
        _ => "ModelGraphRequest"
      }
    CommandBusinessModel(cause) =>
      match cause {
        ForeignOriginal => "ModelForeignOriginal"
        NotOpened => "ModelNotOpened"
        CleanupPending => "ModelCleanupPending"
        Account(_) => "ModelAccount"
        Original(_) => "ModelOriginal"
        Model(_) => "ModelExecution"
        Binding(_) => "ModelBinding"
        Dispatch(_) => "ModelDispatch"
        Egress(_) => "ModelEgress"
        Evidence(_) => "ModelEvidence"
        Capture(_) => "ModelCapture"
        Store(_) => "ModelStore"
        Start(_) => "ModelStart"
        Review(_) => "EffectReview"
        Encoding => "ModelEncoding"
      }
    CommandBusinessEffectAcceptance(cause) =>
      match cause {
        Journal(_) => "EffectAcceptanceJournal"
        MissingRunAdmission => "EffectAcceptanceMissingRunAdmission"
        UnresolvedHistory => "EffectAcceptanceUnresolvedHistory"
        ForeignPreparation => "EffectAcceptanceForeignPreparation"
        ChangedIntent => "EffectAcceptanceChangedIntent"
        ForeignRun => "EffectAcceptanceForeignRun"
        Materials(_) => "EffectAcceptanceMaterials"
      }
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
        PublicationPreparation(_) => "PublicationPreparation"
        PublicationCommit(_) => "PublicationCommit"
        EffectfulPublication(_) => "EffectfulPublication"
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
        PublicationPreparation(_) => "PublicationPreparation"
        PublicationCommit(_) => "PublicationCommit"
        EffectfulPublication(_) => "EffectfulPublication"
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
        Publication(issue) =>
          match issue {
            Limit => "ProjectMockPublicationLimit"
            Alias(_) => "ProjectMockPublicationAlias"
            _ => "ProjectMockPublication"
          }
        Mapping(cause) =>
          match cause {
            OutputLimit => "ProjectMockWriteMappingLimit"
            _ => "ProjectMockWriteMapping"
          }
        Runtime(cause) =>
          match cause {
            CleanupPending => "ProjectMockWriteRuntimeCleanupPending"
            Changed => "ProjectMockWriteRuntimeChanged"
            _ => "ProjectMockWriteRuntime"
          }
        WriteHost(cause) =>
          match cause {
            CustodyLost => "ProjectMockWriteHostCustodyLost"
            TransactionUnknown => "ProjectMockWriteHostTransactionUnknown"
            _ => "ProjectMockWriteHost"
          }
        WriteInstallation(cause) =>
          match cause {
            Limit => "ProjectMockWriteInstallationLimit"
            InvalidMaterials => "ProjectMockWriteInstallationMaterials"
            _ => "ProjectMockWriteInstallation"
          }
        Source(issue) =>
          match issue {
            InvalidSpecification => "ProjectMockSourceInvalidSpecification"
            InvalidContracts => "ProjectMockSourceInvalidContracts"
            Declaration(OutputLimit) => "ProjectMockSourceDeclarationLimit"
            _ => "ProjectMockSourceDeclaration"
          }
        Task(original) =>
          match original.kind {
            InvalidLimits => "ProjectMockTaskInvalidLimits"
            BodyLimit | TaskLimit | WorkLimit => "ProjectMockTaskLimit"
            _ => "ProjectMockTaskInvalid"
          }
        Answers(original) => local_project_mock_answer_cleanup_cause(original)
        Dependencies(original) =>
          match original {
            Missing(_) => "ProjectMockDependencyMissing"
            Body(_, issue) =>
              match issue.kind {
                InvalidLimits => "ProjectMockDependencyInvalidLimits"
                BodyLimit | TaskLimit | WorkLimit =>
                  "ProjectMockDependencyLimit"
                _ => "ProjectMockDependencyInvalid"
              }
            UnsupportedPolicy(_) => "ProjectMockDependencyUnsupportedPolicy"
            MediaRole(_, _) => "ProjectMockDependencyMediaRole"
          }
        Provider(original) =>
          match original {
            ForeignDependencies => "ProjectMockProviderForeignDependencies"
            ForeignProvider => "ProjectMockProviderForeignOriginal"
            UnsupportedPrompt => "ProjectMockProviderUnsupportedPrompt"
          }
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
