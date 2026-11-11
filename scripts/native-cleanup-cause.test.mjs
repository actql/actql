import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';

// Execute the actual discriminant projection with synthetic PRIVATE strings in
// every payload slot. This is a privacy/presentation probe, not a Host issuance
// or Native lifecycle test; actual imported enum compatibility is compiler-checked
// by the canonical Native package gate.
test('cleanup category never serializes payloads and keeps public error code', {timeout: 90_000}, t => {
  const source = readFileSync(new URL('../src/cmd/native_client/local_command_cleanup_cause.mbt', import.meta.url), 'utf8');
  const helperBoundary = source.indexOf('\n///|\n// Closed original Model issue labels only,');
  assert(helperBoundary > 0);
  const functionSource = source.slice(source.indexOf('fn command_preparation_cleanup_cause('), helperBoundary);
  const answerSource = source.slice(source.indexOf('fn local_project_mock_answer_cleanup_cause('));
  const outer = [], declarations = [], assertions = [];
  // These nested families have explicit reviewed shapes. Do not broaden the
  // old literal-only matcher to accept arbitrary expressions or omit a family.
  const projectStart = functionSource.indexOf('    CommandProjectMock(cause) =>');
  const projectEnd = functionSource.indexOf('\n    CommandFilesystem(cause) =>', projectStart);
  assert(projectStart > 0 && projectEnd > projectStart);
  const projectMock = functionSource.slice(projectStart, projectEnd);
  assert.equal(projectMock, `    CommandProjectMock(cause) =>
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
      }`);
  const proposalStart = functionSource.indexOf('    CommandBusinessEffectProposals(cause) =>');
  const proposalEnd = functionSource.indexOf('\n    CommandBusinessSourceIdentity(cause) =>', proposalStart);
  assert(proposalStart > 0 && proposalEnd > proposalStart);
  const effectProposals = functionSource.slice(proposalStart, proposalEnd);
  assert.equal(effectProposals, `    CommandBusinessEffectProposals(cause) =>
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
      }`);
  const identityStart = functionSource.indexOf('    CommandBusinessSourceIdentity(cause) =>');
  const identityEnd = functionSource.indexOf('\n    CommandBusinessModelGraph(cause) =>', identityStart);
  assert(identityStart > 0 && identityEnd > identityStart);
  const sourceIdentity = functionSource.slice(identityStart, identityEnd);
  assert.equal(sourceIdentity, `    CommandBusinessSourceIdentity(cause) =>
      match cause {
        Capture(issue) =>
          match issue {
            Unavailable => "SourceIdentityUnavailable"
            _ => "SourceIdentityCapture"
          }
        Logical(issue) =>
          match issue {
            ForeignIdentity => "SourceIdentityForeignIdentity"
            ForeignPrepared | ForeignRequirement =>
              "SourceIdentityForeignSource"
            _ => "SourceIdentityLogical"
          }
        Observation(issue) =>
          match issue {
            SourceEvidence(_) => "SourceIdentityEvidence"
            _ => "SourceIdentityObservation"
          }
        Read(issue) =>
          match issue {
            ForeignRun => "ReadForeignRun"
            InvalidBootstrap => "ReadInvalidBootstrap"
            Resource(_) => "ReadResource"
          }
      }`);
  const graphStart = functionSource.indexOf('    CommandBusinessModelGraph(cause) =>');
  const graphEnd = functionSource.indexOf('\n    CommandBusinessModel(cause) =>', graphStart);
  assert(graphStart > 0 && graphEnd > graphStart);
  const modelGraph = functionSource.slice(graphStart, graphEnd);
  assert.equal(modelGraph, `    CommandBusinessModelGraph(cause) =>
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
      }`);
  const savedStart = functionSource.indexOf('    CommandSavedFileResource(cause) =>');
  const savedEnd = functionSource.indexOf('\n    CommandSavedEffectOutput(cause) =>', savedStart);
  assert(savedStart > 0 && savedEnd > savedStart);
  const savedFiles = functionSource.slice(savedStart, savedEnd);
  assert.equal(savedFiles, `    CommandSavedFileResource(cause) =>
      "SavedFileResource" + local_submission_ledger_tag(cause).to_string()
    CommandSavedFileEntry(cause) =>
      match cause {
        Unavailable => "SavedFileEntryUnavailable"
        Domain(Bootstrap(_)) => "SavedFileEntryDomainBootstrap"
        Domain(Accounting(_)) => "SavedFileEntryDomainAccounting"
        Resource(ledger) =>
          "SavedFileEntryResource" +
          local_submission_ledger_tag(ledger).to_string()
      }`);
  const diagnosticSource = readFileSync(new URL(
    '../src/cmd/native_client/local_submission_failure_diagnostic.mbt', import.meta.url), 'utf8');
  const ledgerStart = diagnosticSource.indexOf('fn local_submission_ledger_tag(');
  const ledgerEnd = diagnosticSource.indexOf('\n///|\nfn local_submission_sql_tag(', ledgerStart);
  assert(ledgerStart >= 0 && ledgerEnd > ledgerStart);
  const ledgerSource = diagnosticSource.slice(ledgerStart, ledgerEnd).trim();
  // Only this closed nullary projection may add a numeric label. Reject any
  // payload access, fallback, expression or additional output from the helper.
  const ledgerNames = ['InvalidLimits', 'PlanningLimit', 'AttemptLimit', 'HoldingLimit',
    'TransferLimit', 'RetentionLimit', 'ExecutionLimit', 'ForeignOwner', 'ClosedReservation',
    'ClosedHolding', 'InvalidCharge', 'IdentityOverflow', 'TokenLimit', 'CostLimit',
    'DurationLimit', 'ResourceParked', 'ChildFundingUnavailable'];
  function checkLedgerProjection(text) {
    const rows = [...text.matchAll(/    ([A-Z]\w*) => ([1-9]\d*)L/gu)];
    assert.deepEqual(rows.map(([, name, tag]) => [name, Number(tag)]),
      ledgerNames.map((name, index) => [name, index + 1]));
    const residual = rows.reduce((body, [row]) => body.replace(row, ''), text);
    assert.match(residual, /^fn local_submission_ledger_tag\(issue : @initial_resources\.LedgerIssue\) -> Int64 \{\s*match issue \{\s*\}\s*\}$/u);
  }
  checkLedgerProjection(ledgerSource);
  assert.throws(() => checkLedgerProjection(ledgerSource.replace('=> 1L', '=> issue.to_string()')));
  assert.throws(() => checkLedgerProjection(ledgerSource.replace('=> 1L', '=> 1L + 1L')));
  assert.throws(() => checkLedgerProjection(ledgerSource.replace('    InvalidLimits => 1L',
    '    _ => 1L')));
  const outputStart = functionSource.indexOf('    CommandSavedEffectOutput(cause) =>');
  const outputEnd = functionSource.indexOf('\n    CommandSavedEffectPublication(cause) =>', outputStart);
  assert(outputStart > 0 && outputEnd > outputStart);
  const savedOutput = functionSource.slice(outputStart, outputEnd);
  assert.equal(savedOutput, `    CommandSavedEffectOutput(cause) =>
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
      }`);
  const resumeStart = functionSource.indexOf('    CommandSavedFileResume(cause) =>');
  const resumeEnd = functionSource.indexOf('\n    CommandBusinessSource(cause) =>', resumeStart);
  assert(resumeStart > 0 && resumeEnd > resumeStart);
  const savedResume = functionSource.slice(resumeStart, resumeEnd);
  assert.equal(savedResume, `    CommandSavedFileResume(cause) =>
      match cause {
        HostAttestationUnavailable => "SavedFileOriginalUnavailable"
        HostAttestationJournal(_) => "SavedFileJournal"
        _ => "SavedFileOriginalAuthority"
      }`);
  let covered = functionSource.replace(projectMock, '').replace(effectProposals, '')
    .replace(sourceIdentity, '').replace(modelGraph, '').replace(savedFiles, '')
    .replace(savedOutput, '').replace(savedResume, '');
  const nested = [...covered.matchAll(/    (Command\w+)\(cause\) =>\s+match cause \{([\s\S]*?)\n      \}/g)];
  assert.ok(nested.length >= 20);
  for (const [block, variant, body] of nested) {
    const type = `Probe${variant}`;
    // Enumerate every closed alternative, including typed multi-payload
    // refusals sharing a literal tag. No payload expression is admitted.
    const rows = [...body.matchAll(/((?:[A-Z]\w*(?:\([_,\s]*\))?)(?:\s*\|\s*[A-Z]\w*(?:\([_,\s]*\))?)*)\s*=>\s*"([A-Za-z0-9]+)"/gu)];
    const cases = rows.flatMap(([, patterns, tag]) => patterns.split('|').map(pattern => {
      const [, name, fields] = /^([A-Z]\w*)(\([_,\s]*\))?$/u.exec(pattern.trim());
      return [pattern, name, fields, tag];
    }));
    assert.ok(cases.length > 0);
    const residual = rows.reduce((value, [row]) => value.replace(row, ''), body);
    assert.equal(residual.trim(), '', 'Only closed enum patterns and literal tags are permitted');
    declarations.push(`pub(all) enum ${type} {\n` + cases.map(([, name, fields]) =>
      '  ' + name + (fields ? '(' + Array((fields.match(/_/g) ?? []).length).fill('String').join(', ') + ')' : '')).join('\n') + '\n}');
    outer.push(`  ${variant}(${type})`);
    for (const [, name, fields, tag] of cases) {
      const payload = fields ? '(' + Array((fields.match(/_/g) ?? []).length).fill('"PRIVATE-PAYLOAD-NOT-A-CAPABILITY"').join(', ') + ')' : '';
      assertions.push(`  assert_eq(command_preparation_cleanup_cause(${variant}(${name}${payload})), "${tag}")`);
    }
    covered = covered.replace(block, '');
  }
  const direct = [...covered.matchAll(/    (Command\w+)(\(_\))? => "([A-Za-z0-9]+)"/g)];
  for (const [block, variant, payload, tag] of direct) {
    outer.push('  ' + variant + (payload ? '(String)' : ''));
    assertions.push(`  assert_eq(command_preparation_cleanup_cause(${variant}${payload ? '("PRIVATE-APPLICATION-MESSAGE")' : ''}), "${tag}")`);
    covered = covered.replace(block, '');
  }
  assert.match(covered, /^fn command_preparation_cleanup_cause\(\s*issue : LocalCommandPreparationIssue,?\s*\) -> String \{\s*match issue \{\s*\}\s*\}\s*$/);
  // Enumerate the current Owner's closed issue variants, not just one fallback.
  // Payload types are deliberately synthetic Strings: no capability is issued.
  const privateValue = '"PRIVATE-PAYLOAD-NOT-A-CAPABILITY"';
  function enumCases(path, name, kind = 'enum') {
    assert(kind === 'enum' || kind === 'suberror');
    const text = readFileSync(new URL('../' + path, import.meta.url), 'utf8');
    const header = new RegExp('\\b' + kind + ' ' + name + '(?:\\[E\\])? \\{').exec(text);
    const start = header?.index ?? -1;
    assert(start >= 0, name);
    const body = text.slice(start).split('\n}')[0].split('\n').slice(1).join('\n');
    // Enum payloads may wrap onto multiple lines, but remain closed type lists.
    // Reject every unmatched token; this is not a fallback Source parser.
    const rows = [...body.matchAll(/(?:^|\n)  ([A-Z]\w*)(?:\(([^()]*)\))?(?=\n|$)/gu)];
    let residual = body;
    const cases = rows.map(([row, variant, payload]) => {
      residual = residual.replace(row, '');
      const fields = payload === undefined ? [] : payload.split(',').map(value => value.trim());
      // The two actual Host error payloads have one closed original RunIssue
      // argument. These are type names only; no arbitrary expression parser.
      assert(fields.every(value => /^(?:@\w+\.)?[A-Z]\w*(?:\[(?:@\w+\.)?[A-Z]\w*\])?\??$/u.test(value)), name);
      return {name: variant, arity: fields.length};
    });
    assert.equal(residual.trim(), '', 'Unsupported issue declaration: ' + name);
    assert(cases.length > 0, name);
    return cases;
  }
  function declare(type, cases, typed = {}) {
    declarations.push(`pub(all) enum ${type} {\n` + cases.map(({name, arity}) => {
      const fields = typed[name] ?? Array(arity).fill('String');
      assert.equal(fields.length, arity);
      return '  ' + name + (arity ? '(' + fields.join(', ') + ')' : '');
    }).join('\n') + '\n}');
  }
  const value = ({name, arity}) => name + (arity ? '(' + Array(arity).fill(privateValue).join(', ') + ')' : '');
  const project = (expression, tag) => assertions.push(
    `  assert_eq(command_preparation_cleanup_cause(CommandProjectMock(${expression})), "${tag}")`);
  const publications = enumCases('src/client_source_publication/publication.mbt', 'PublicationIssue');
  const rowSources = enumCases('src/client_row_source_host/host.mbt', 'RowHostIssue');
  const rowDeclarations = enumCases('src/client_row_source_host/declaration.mbt', 'RowDeclarationIssue');
  const tasks = enumCases('src/check_environment/model_tasks.mbt', 'ModelTaskIssueKind');
  const dependencies = enumCases('src/check_environment/model_dependencies.mbt', 'ModelDependencyIssue');
  const providers = enumCases('src/model_execution/provider_admission.mbt', 'ModelProviderAdmissionIssue');
  const answers = enumCases('src/model_execution/mock_answer_originals.mbt', 'ModelMockAnswerIssue');
  const installations = enumCases('src/model_execution/mock_installation.mbt', 'ModelMockInstallationIssue');
  const projects = enumCases('src/cmd/native_client/local_project_mock.mbt', 'LocalProjectMockModelIssue');
  const mappings = enumCases('src/client_row_source_host/mapping.mbt', 'RowMappingIssue');
  const runtimes = enumCases('src/platform_native/client_host/local_packaged_runtime.mbt', 'NativeLocalPackagedRuntimeIssue');
  const writeHosts = enumCases('src/platform_native/client_host/local_adoption.mbt', 'NativeLocalAdoptionIssue');
  const writeInstallations = enumCases('src/run_publication_host/client_effect_target_selections.mbt', 'ClientEffectUpdateTargetIssue');
  declare('ProbeMockMapping', mappings);
  declare('ProbeMockRuntime', runtimes);
  declare('ProbeMockWriteHost', writeHosts);
  declare('ProbeMockWriteInstallation', writeInstallations);
  declare('ProbeMockPublication', publications);
  declare('ProbeMockRowDeclaration', rowDeclarations);
  declare('ProbeMockRowSource', rowSources, {Declaration: ['ProbeMockRowDeclaration']});
  declare('ProbeMockTaskKind', tasks);
  const taskSource = readFileSync(new URL('../src/check_environment/model_tasks.mbt', import.meta.url), 'utf8');
  assert.match(taskSource, /pub\(all\) struct ModelTaskIssue \{\s*kind : ModelTaskIssueKind\s*source : @decode.Cursor\?\s*\}/u);
  declarations.push('pub(all) struct ProbeMockTask {\n  kind : ProbeMockTaskKind\n  source : String?\n}');
  declare('ProbeMockDependencies', dependencies, {Body: ['String', 'ProbeMockTask']});
  declare('ProbeMockProvider', providers);
  declare('ProbeMockInstallation', installations, {Answers: ['@model.ModelMockAnswerIssue']});
  declare('ProbeCommandProjectMock', projects, {
    Publication: ['ProbeMockPublication'], Source: ['ProbeMockRowSource'], Task: ['ProbeMockTask'],
    Mapping: ['ProbeMockMapping'], Runtime: ['ProbeMockRuntime'], WriteHost: ['ProbeMockWriteHost'],
    WriteInstallation: ['ProbeMockWriteInstallation'],
    Answers: ['@model.ModelMockAnswerIssue'], Installation: ['ProbeMockInstallation'],
    Dependencies: ['ProbeMockDependencies'], Provider: ['ProbeMockProvider'],
  });
  outer.push('  CommandProjectMock(ProbeCommandProjectMock)');
  const proposalIssues = enumCases('src/cmd/native_client/local_effect_mock_proposals.mbt',
    'LocalNativeMockEffectProposalIssue');
  const proposalFamilies = {
    Managed: {
      path: 'src/client_local_host/installed_managed_run.mbt', name: 'ClientInstalledManagedRunIssue',
      tags: {InsufficientCapacity: 'EffectProposalsInsufficientCapacity', Ledger: 'EffectProposalsLedger'},
      fallback: 'EffectProposalsManaged',
    },
    Capture: {
      path: 'src/physical_strategy_host/captured_dag.mbt', name: 'RunIssue',
      tags: {ForeignCapture: 'EffectProposalsForeignCapture', Physical: 'EffectProposalsPhysical'},
      fallback: 'EffectProposalsCapture',
    },
    Proposal: {
      path: 'src/physical_strategy_host/effect_plan_verify.mbt', name: 'CapturedEffectProposalIssue',
      tags: {ForeignBinding: 'EffectProposalsForeignBinding', RowCountMismatch: 'EffectProposalsRowCountMismatch'},
      fallback: 'EffectProposalsProjection',
    },
    ManagedExport: {
      path: 'src/client_local_host/effect_result_export.mbt', name: 'LocalValuesEffectResultExportIssue',
      tags: {ForeignInput: 'EffectProposalsForeignOutput', Export: 'EffectProposalsExportBody',
        Bridge: 'EffectProposalsExportBridge'},
      fallback: 'EffectProposalsExport',
    },
    ManagedPublicExport: {
      path: 'src/client_local_host/publication.mbt', name: 'LocalValuesResultExportIssue',
      tags: {Transformation: 'EffectPublicExportTransformation', Bridge: 'EffectPublicExportBridge'},
      fallback: 'EffectPublicExport',
    },
    Completed: {
      path: 'src/execution_relation/completed_output_export.mbt', name: 'CompletedExportIssue',
      tags: {ForeignMaterial: 'EffectProposalsForeignMaterial', Closed: 'EffectProposalsClosed'},
      fallback: 'EffectProposalsCompleted',
    },
    Keyed: {
      path: 'src/run_publication_host/client_keyed_acquisition.mbt', name: 'ClientKeyedRequestIssue',
      tags: {Identity: 'EffectProposalsKeyedContract', Wire: 'EffectProposalsKeyedWire'},
      fallback: 'EffectProposalsKeyedIdentity',
    },
    Source: {
      path: 'src/run_publication_host/client_effect_acquired_evidence.mbt', name: 'ClientEffectAcquiredEvidenceIssue',
      tags: {Invocation: 'EffectProposalsSourceInvocation', Relation: 'EffectProposalsSourceRelation',
        Dependency: 'EffectProposalsSourceDependency'},
    },
    Materials: {
      path: 'src/run_publication_host/client_effect_run_materials.mbt', name: 'ClientEffectRunMaterialsIssue',
      tags: {RunMismatch: 'EffectProposalsMaterialsRunMismatch'}, fallback: 'EffectProposalsMaterials',
    },
    Definition: {
      path: 'src/run_publication_host/client_effect_local_result_definition.mbt', name: 'ClientEffectLocalResultDefinitionIssue',
      tags: {MissingResult: 'EffectProposalsDefinitionMissingResult'}, fallback: 'EffectProposalsDefinition',
    },
    Artifact: {
      path: 'src/run_publication_host/client_effect_local_result_artifact.mbt', name: 'ClientEffectLocalResultArtifactIssue',
      tags: {ForeignOwner: 'EffectProposalsArtifactForeignOwner', ForeignExport: 'EffectProposalsArtifactForeignExport',
        ForeignRun: 'EffectProposalsArtifactForeignRun'}, fallback: 'EffectProposalsArtifact',
    },
    Dependency: {
      path: 'src/run_publication_host/client_effect_dependency_capture.mbt', name: 'ClientEffectDependencyCaptureIssue',
      tags: {ForeignInput: 'EffectProposalsDependencyForeignInput', Dependency: 'EffectProposalsDependencyClosure'},
      fallback: 'EffectProposalsDependency',
    },
    Manifest: {
      path: 'src/run_publication_host/client_effect_local_manifest.mbt', name: 'ClientEffectLocalManifestIssue',
      tags: {IncompleteResults: 'EffectProposalsIncompleteResults', IncompleteTableInputs: 'EffectProposalsIncompleteTableInputs'},
      fallback: 'EffectProposalsManifest',
    },
    PreviewSource: {
      path: 'src/run_publication_host/client_effect_source_artifact.mbt', name: 'ClientEffectSourceArtifactIssue',
      tags: {ForeignRun: 'EffectPreviewSourceRun'}, fallback: 'EffectPreviewSource',
    },
    PreviewIdentity: {
      path: 'src/run_publication_host/client_effect_local_identity.mbt', name: 'ClientEffectLocalIdentityIssue',
      tags: {ForeignInput: 'EffectPreviewIdentityInput'}, fallback: 'EffectPreviewIdentity',
    },
    PreviewBody: {
      path: 'src/run_publication/effect_preview_identity.mbt', name: 'EffectPreviewIdentityIssue',
      tags: {PreviewShape: 'EffectPreviewBodyShape'}, fallback: 'EffectPreviewBody',
    },
    PreviewBinding: {
      path: 'src/run_publication_host/client_effect_captured_preview.mbt', name: 'ClientCapturedEffectPreviewIssue',
      tags: {ForeignInput: 'EffectPreviewBindingInput'}, fallback: 'EffectPreviewBinding',
    },
    PreviewDispatch: {
      path: 'src/effect_application/identity.mbt', name: 'EffectIdentityIssue',
      tags: {InvalidLimits: 'EffectPreviewDispatchLimits'}, fallback: 'EffectPreviewDispatch',
    },
    PreviewKeys: {
      path: 'src/effect_application/preview_identity.mbt', name: 'EffectPreviewApplyIdentityIssue',
      tags: {KeyInventoryMismatch: 'EffectPreviewKeyInventory'}, fallback: 'EffectPreviewKeys',
    },
    PreviewPlan: {
      path: 'src/physical_strategy_host/effect_plan_verify.mbt', name: 'CapturedEffectPlanVerifyIssue',
      tags: {InvalidMember: 'EffectPreviewPlanMember'}, fallback: 'EffectPreviewPlan',
    },
    CapturedSource: {
      path: 'src/run_publication/captured_run_issuance.mbt', name: 'CapturedRunIssuanceIssue',
      tags: {CaptureIssuanceReferenceMismatch: 'EffectCapturedSourceReference'}, fallback: 'EffectCapturedSource',
    },
    LocalSource: {
      path: 'src/run_publication/captured_local_effect_source.mbt', name: 'CapturedLocalEffectSourceIssue',
      tags: {InvalidLocalReference: 'EffectLocalSourceReference'}, fallback: 'EffectLocalSource',
    },
    Inventory: {
      path: 'src/run_publication/captured_effect_dependency_graph.mbt', name: 'CapturedEffectDependencyIssue',
      tags: {MissingDependency: 'EffectInventoryMissingDependency'}, fallback: 'EffectInventory',
    },
    PublicExport: {
      path: 'src/run_publication_host/output_export.mbt', name: 'PublicationOutputExportIssue',
      tags: {InvalidState: 'EffectPublicExportState'}, fallback: 'EffectPublicExport',
    },
    PublicManifest: {
      path: 'src/run_publication/result_manifest_issuance.mbt', name: 'ResultManifestIssuanceIssue',
      tags: {ManifestIssuanceEncoding: 'EffectPublicManifestEncoding'}, fallback: 'EffectPublicManifest',
    },
    PublicReceipt: {
      path: 'src/run_publication/run_receipt_issuance.mbt', name: 'RunReceiptIssuanceIssue',
      tags: {ReceiptIssuanceEncoding: 'EffectPublicReceiptEncoding'}, fallback: 'EffectPublicReceipt',
    },
    PublicBindings: {
      path: 'src/run_publication_host/client_effect_receipt_bindings.mbt', name: 'ClientEffectReceiptBindingsIssue',
      tags: {ForeignMaterials: 'EffectPublicBindingsOwner'}, fallback: 'EffectPublicBindings',
    },
    PublicNormalization: {
      path: 'src/run_publication_host/client_effect_normalization.mbt', name: 'ClientEffectNormalizationIssue',
      tags: {MissingOriginalJournal: 'EffectPublicNormalizationOriginal'}, fallback: 'EffectPublicNormalization',
    },
    PublicCapture: {
      path: 'src/run_publication_host/client_effect_captured_run.mbt', name: 'ClientEffectCapturedRunIssue',
      tags: {ForeignInput: 'EffectPublicCaptureInput'}, fallback: 'EffectPublicCapture',
    },
    HostExecution: {
      path: 'src/client_local_host/execute.mbt', name: 'LocalValuesExecutionIssue',
      tags: {InvalidLimits: 'EffectHostLimits', Fenced: 'EffectHostFenced',
        UnsupportedGraph: 'EffectHostGraph', MissingLocalModule: 'EffectHostModule',
        Driver: 'EffectHostDriver', Estimate: 'EffectHostEstimate',
        FinalizationLimit: 'EffectHostFinalization', MissingOutput: 'EffectHostOutput'},
    },
    ImportObservation: {
      path: 'src/run_publication_host/client_effect_result_import.mbt', name: 'ClientEffectResultImportIssue',
      tags: {ForeignInput: 'EffectImportForeignInput'}, fallback: 'EffectImportObservation',
    },
    Imports: {
      path: 'src/run_publication_host/client_effect_imported_evidence.mbt', name: 'ClientEffectImportedEvidenceIssue',
      tags: {MissingScope: 'EffectImportedScopeMissing'}, fallback: 'EffectImportedEvidence',
    },
    PolicyDependency: {
      path: 'src/program_check/local_dependency_body.mbt', name: 'LocalDependencyBodyIssue',
      tags: {MissingUnit: 'EffectProposalsPolicyMissingUnit', MissingDependency: 'EffectProposalsPolicyMissingDependency',
        Encoding: 'EffectProposalsPolicyEncoding', ForeignBody: 'EffectProposalsPolicyForeignBody',
        BudgetExceeded: 'EffectProposalsPolicyBudget'},
    },
  };
  assert.deepEqual(proposalIssues, Object.keys(proposalFamilies).map(name => ({name, arity: 1})));
  // The managed facades retain the original export failures. Exercise those
  // nested Owners too, including every PRIVATE payload behind each fallback.
  const effectExportBindings = enumCases('src/physical_strategy_host/effect_dependency_ports.mbt',
    'CapturedEffectLocalResultExportIssue');
  declare('ProbeEffectExportBinding', effectExportBindings);
  const publicExports = enumCases(proposalFamilies.PublicExport.path, proposalFamilies.PublicExport.name);
  const proposalTypes = {};
  for (const [family, owner] of Object.entries(proposalFamilies)) {
    const cases = enumCases(owner.path, owner.name);
    assert(Object.keys(owner.tags).every(name => cases.some(item => item.name === name)));
    if (owner.fallback === undefined) assert.deepEqual(Object.keys(owner.tags), cases.map(item => item.name));
    const type = 'ProbeEffectProposals' + family;
    const typed = family === 'ManagedExport' ? {Binding: ['ProbeEffectExportBinding']}
      : family === 'ManagedPublicExport' ? {Export: ['ProbeEffectProposalsPublicExport']} : {};
    declare(type, cases, typed);
    proposalTypes[family] = [type];
    for (const item of cases) {
      if (family === 'ManagedExport' && item.name === 'Binding') {
        for (const binding of effectExportBindings) assertions.push(
          `  assert_eq(command_preparation_cleanup_cause(CommandBusinessEffectProposals(ManagedExport(Binding(${value(binding)})))), "${binding.name === 'ForeignOutput' ? 'EffectProposalsForeignOutput' : 'EffectProposalsExport'}")`);
      } else if (family === 'ManagedPublicExport' && item.name === 'Export') {
        for (const exported of publicExports) assertions.push(
          `  assert_eq(command_preparation_cleanup_cause(CommandBusinessEffectProposals(ManagedPublicExport(Export(${value(exported)})))), "${exported.name === 'InvalidState' ? 'EffectPublicExportState' : 'EffectPublicExport'}")`);
      } else assertions.push(
        `  assert_eq(command_preparation_cleanup_cause(CommandBusinessEffectProposals(${family}(${value(item)}))), "${owner.tags[item.name] ?? owner.fallback}")`);
    }
  }
  declare('ProbeCommandBusinessEffectProposals', proposalIssues, proposalTypes);
  outer.push('  CommandBusinessEffectProposals(ProbeCommandBusinessEffectProposals)');
  const identityIssues = enumCases('src/cmd/native_client/local_effect_mock_source_identity.mbt',
    'LocalNativeMockSourceIdentityIssue');
  assert.deepEqual(identityIssues, ['Read', 'Capture', 'Logical', 'Observation']
    .map(name => ({name, arity: 1})));
  const identityFamilies = {
    Read: {
      path: 'src/run_publication_host/client_model_read_preparation.mbt', name: 'ClientModelReadPreparationIssue',
      tags: {ForeignRun: 'ReadForeignRun', InvalidBootstrap: 'ReadInvalidBootstrap', Resource: 'ReadResource'},
    },
    Capture: {
      path: 'src/execution_query/captured_source.mbt', name: 'CapturedSourceIssue',
      tags: {Unavailable: 'SourceIdentityUnavailable', Binding: 'SourceIdentityCapture',
        Completion: 'SourceIdentityCapture', Storage: 'SourceIdentityCapture',
        Export: 'SourceIdentityCapture', DependencyBodyLimit: 'SourceIdentityCapture'},
    },
    Logical: {
      path: 'src/run_publication_host/client_source_input_logical.mbt', name: 'ClientCapturedSourceLogicalIssue',
      tags: {ForeignPrepared: 'SourceIdentityForeignSource', ForeignIdentity: 'SourceIdentityForeignIdentity',
        ForeignRequirement: 'SourceIdentityForeignSource', Encoding: 'SourceIdentityLogical',
        Evidence: 'SourceIdentityLogical', Admission: 'SourceIdentityLogical'},
    },
    Observation: {
      path: 'src/client_row_source_host/host.mbt', name: 'RowHostIssue',
      tags: {InvalidSpecification: 'SourceIdentityObservation', Declaration: 'SourceIdentityObservation',
        ForeignDeclaration: 'SourceIdentityObservation', Source: 'SourceIdentityObservation',
        InvalidContracts: 'SourceIdentityObservation', Registration: 'SourceIdentityObservation',
        Candidate: 'SourceIdentityObservation', Selection: 'SourceIdentityObservation',
        Evidence: 'SourceIdentityObservation', Attempt: 'SourceIdentityObservation',
        Consumer: 'SourceIdentityObservation', SourceEvidence: 'SourceIdentityEvidence',
        Physical: 'SourceIdentityObservation', Residual: 'SourceIdentityObservation',
        ResidualWork: 'SourceIdentityObservation', InputValidationWork: 'SourceIdentityObservation',
        InputKeys: 'SourceIdentityObservation', InputScores: 'SourceIdentityObservation',
        InvalidState: 'SourceIdentityObservation'},
    },
  };
  assert.deepEqual(Object.keys(identityFamilies), identityIssues.map(item => item.name));
  const identityTypes = {};
  for (const [family, owner] of Object.entries(identityFamilies)) {
    const cases = enumCases(owner.path, owner.name);
    assert.deepEqual(Object.keys(owner.tags), cases.map(item => item.name));
    const type = 'ProbeSourceIdentity' + family;
    declare(type, cases);
    identityTypes[family] = [type];
    for (const item of cases) assertions.push(
      `  assert_eq(command_preparation_cleanup_cause(CommandBusinessSourceIdentity(${family}(${value(item)}))), "${owner.tags[item.name]}")`);
  }
  declare('ProbeCommandBusinessSourceIdentity', identityIssues, identityTypes);
  outer.push('  CommandBusinessSourceIdentity(ProbeCommandBusinessSourceIdentity)');
  // Match only this reviewed nested family, then execute every actual Owner
  // variant with PRIVATE synthetic payloads, including each fallback branch.
  const graphRequests = enumCases('src/client_local_host/preparation_request_program_body.mbt',
    'ClientRequestProgramPlanIssue', 'suberror');
  assert.deepEqual(graphRequests, ['CapacityExceeded', 'Preparation', 'Installed', 'Construction',
    'ValuesCompilation', 'TaskCompilation', 'QueryTime', 'SerializationGraph', 'ModelGraph',
    'ModelBinding', 'ModelQuery', 'ModelSource', 'ContentQuery', 'ContentSource']
    .map(name => ({name, arity: 1})));
  const graphPreparations = enumCases('src/client_local_host/preparation_request_parent.mbt',
    'ClientRequestPreparationIssue');
  const graphIssues = enumCases('src/run_publication_host/client_infer_plan_graph.mbt',
    'ClientInferPlanGraphIssue');
  const graphInputs = enumCases('src/run_publication_host/client_task_fragment.mbt',
    'ClientTaskFragmentIssue');
  const preparationTags = {Policy: 'ModelGraphPreparationPolicy',
    ForeignOriginal: 'ModelGraphPreparationForeignOriginal', Capacity: 'ModelGraphPreparationCapacity'};
  const graphTags = {UnsupportedProgram: 'ModelGraphUnsupportedProgram',
    ForeignExecution: 'ModelGraphForeignExecution', Encoding: 'ModelGraphEncoding'};
  const inputTags = {UnrepresentableContract: 'ModelGraphInputContract',
    UnsupportedCarrier: 'ModelGraphInputCarrier', Pipeline: 'ModelGraphInputPipeline'};
  for (const [cases, tags] of [[graphPreparations, preparationTags], [graphIssues, graphTags],
    [graphInputs, inputTags]]) assert(Object.keys(tags).every(name => cases.some(item => item.name === name)));
  assert(graphIssues.some(item => item.name === 'Input' && item.arity === 1));
  declare('ProbeModelGraphPreparation', graphPreparations);
  declare('ProbeModelGraphInput', graphInputs);
  declare('ProbeModelGraphIssue', graphIssues, {Input: ['ProbeModelGraphInput']});
  declare('ProbeCommandBusinessModelGraph', graphRequests, {
    Preparation: ['ProbeModelGraphPreparation'], ModelGraph: ['ProbeModelGraphIssue'],
  });
  outer.push('  CommandBusinessModelGraph(ProbeCommandBusinessModelGraph)');
  const graphProject = (expression, tag) => assertions.push(
    `  assert_eq(command_preparation_cleanup_cause(CommandBusinessModelGraph(${expression})), "${tag}")`);
  for (const item of graphRequests) {
    if (item.name === 'Preparation') {
      for (const preparation of graphPreparations) graphProject('Preparation(' + value(preparation) + ')',
        preparationTags[preparation.name] ?? 'ModelGraphPreparation');
    } else if (item.name === 'ModelGraph') {
      for (const graph of graphIssues) {
        if (graph.name === 'Input') {
          for (const input of graphInputs) graphProject('ModelGraph(Input(' + value(input) + '))',
            inputTags[input.name] ?? 'ModelGraphInput');
        } else graphProject('ModelGraph(' + value(graph) + ')',
          graphTags[graph.name] ?? 'ModelGraphConstruction');
      }
    } else graphProject(value(item), 'ModelGraphRequest');
  }
  const ledgerIssues = enumCases('src/physical_resources/ledger.mbt', 'LedgerIssue');
  assert.deepEqual(ledgerIssues, ledgerNames.map(name => ({name, arity: 0})));
  const savedDomains = enumCases('src/platform_native/host_bootstrap/backed_region_native.mbt',
    'NativeBackedExecutionIssue');
  assert.deepEqual(savedDomains, ['Bootstrap', 'Accounting'].map(name => ({name, arity: 1})));
  const savedEntries = enumCases('src/platform_native/installed_arena_control/nonmodel_work_entry_native.mbt',
    'InstalledArenaNonModelWorkEntryIssue');
  assert.deepEqual(savedEntries, [{name: 'Unavailable', arity: 0}, {name: 'Resource', arity: 1},
    {name: 'Domain', arity: 1}]);
  declare('ProbeSavedFileDomain', savedDomains);
  declare('ProbeSavedFileEntry', savedEntries, {
    Resource: ['@initial_resources.LedgerIssue'], Domain: ['ProbeSavedFileDomain'],
  });
  outer.push('  CommandSavedFileResource(@initial_resources.LedgerIssue)',
    '  CommandSavedFileEntry(ProbeSavedFileEntry)');
  assertions.push('  assert_eq(command_preparation_cleanup_cause(CommandSavedFileEntry(Unavailable)), "SavedFileEntryUnavailable")');
  for (const item of savedDomains) assertions.push(
    `  assert_eq(command_preparation_cleanup_cause(CommandSavedFileEntry(Domain(${value(item)}))), "SavedFileEntryDomain${item.name}")`);
  for (const [index, item] of ledgerIssues.entries()) {
    const issue = '@initial_resources.LedgerIssue::' + item.name, tag = index + 1;
    assertions.push(`  assert_eq(local_submission_ledger_tag(${issue}), ${tag}L)`,
      `  assert_eq(command_preparation_cleanup_cause(CommandSavedFileResource(${issue})), "SavedFileResource${tag}")`,
      `  assert_eq(command_preparation_cleanup_cause(CommandSavedFileEntry(Resource(${issue}))), "SavedFileEntryResource${tag}")`);
  }
  const savedLiteralFamilies = {
    CommandSavedEffectOutput: {
      path: 'src/platform_native/run_publication/publication.mbt', name: 'NativePublicationOutputIssue',
      tags: {Snapshot: 'SavedPublicationSnapshot', SnapshotCleanup: 'SavedPublicationSnapshotCleanup',
        OutputCleanup: 'SavedPublicationOutputCleanup', StoreCleanup: 'SavedPublicationOutputCleanup',
        BindingCleanup: 'SavedPublicationOutputCleanup', Store: 'SavedPublicationOutputStore',
        Binding: 'SavedPublicationOutputBinding'}, fallback: 'SavedPublicationOutput',
    },
    CommandSavedFileResume: {
      path: 'src/platform_native/client_host/local_initial_host_attestation_preparation.mbt',
      name: 'NativeLocalInitialHostAttestationIssue',
      tags: {HostAttestationUnavailable: 'SavedFileOriginalUnavailable', HostAttestationJournal: 'SavedFileJournal'},
      fallback: 'SavedFileOriginalAuthority',
    },
  };
  for (const [command, owner] of Object.entries(savedLiteralFamilies)) {
    const cases = enumCases(owner.path, owner.name), type = 'Probe' + command;
    assert(Object.keys(owner.tags).every(name => cases.some(item => item.name === name)));
    declare(type, cases);
    outer.push(`  ${command}(${type})`);
    for (const item of cases) assertions.push(
      `  assert_eq(command_preparation_cleanup_cause(${command}(${value(item)})), "${owner.tags[item.name] ?? owner.fallback}")`);
  }
  const completionFamilies = {
    Member: {
      path: 'src/effect_application/member_receipt_evidence.mbt', name: 'EffectMemberReceiptEvidenceIssue',
      tags: {ActivePhysicalOwner: 'SavedEffectMemberPhysicalOwner', MissingTerminalReceipt: 'SavedEffectMemberMissingReceipt',
        ForeignLedgerHead: 'SavedEffectMemberForeignLedger'}, fallback: 'SavedEffectMemberReceipt',
    },
    Set: {
      path: 'src/run_publication/effect_set_apply_receipt.mbt', name: 'EffectSetApplyReceiptIssuanceIssue',
      tags: {MemberReceipt: 'SavedEffectSetMemberReceipt', InvalidInventory: 'SavedEffectSetInventory'},
      fallback: 'SavedEffectSetReceipt',
    },
    Final: {
      path: 'src/run_publication/effectful_final_receipt.mbt', name: 'EffectfulFinalReceiptIssuanceIssue',
      tags: {InvalidComputation: 'SavedEffectFinalComputation', References: 'SavedEffectFinalReferences'},
      fallback: 'SavedEffectFinalReceipt',
    },
    Admission: {
      path: 'src/run_publication/effectful_final_receipt.mbt', name: 'EffectfulPublicationCommitIssue',
      tags: {ResultEvidence: 'SavedEffectFinalResultEvidence', FinalChain: 'SavedEffectFinalChain'},
      fallback: 'SavedEffectFinalAdmission',
    },
  };
  const completionIssues = enumCases('src/cmd/native_client/local_effect_saved_publication.mbt',
    'LocalSavedEffectCompletionIssue');
  assert.deepEqual(completionIssues, Object.keys(completionFamilies).map(name => ({name, arity: 1})));
  const completionTypes = {};
  for (const [family, owner] of Object.entries(completionFamilies)) {
    const cases = enumCases(owner.path, owner.name), type = 'ProbeSavedEffect' + family;
    assert(Object.keys(owner.tags).every(name => cases.some(item => item.name === name)));
    declare(type, cases);
    completionTypes[family] = [type];
    for (const item of cases) assertions.push(
      `  assert_eq(command_preparation_cleanup_cause(CommandSavedEffectCompletion(${family}(${value(item)}))), "${owner.tags[item.name] ?? owner.fallback}")`);
  }
  declare('ProbeSavedEffectCompletion', completionIssues, completionTypes);
  outer.push('  CommandSavedEffectCompletion(ProbeSavedEffectCompletion)');
  const commands = enumCases('src/cmd/native_client/local_command_preparation.mbt', 'LocalCommandPreparationIssue');
  assert.deepEqual(new Set(outer.map(line => /Command\w+/u.exec(line)[0])), new Set(commands.map(entry => entry.name)));
  for (const [name, tag] of [['ForeignOriginal', 'ProjectMockForeignOriginal'],
    ['AlreadyPreparing', 'ProjectMockAlreadyPreparing'], ['Environment', 'ProjectMockEnvironment']]) project(name, tag);
  for (const item of publications) project('Publication(' + value(item) + ')',
    item.name === 'Limit' ? 'ProjectMockPublicationLimit' : item.name === 'Alias' ? 'ProjectMockPublicationAlias' : 'ProjectMockPublication');
  for (const item of rowSources) {
    if (item.name === 'Declaration') {
      for (const declaration of rowDeclarations) project('Source(Declaration(' + value(declaration) + '))',
        declaration.name === 'OutputLimit' ? 'ProjectMockSourceDeclarationLimit' : 'ProjectMockSourceDeclaration');
    } else project('Source(' + value(item) + ')', item.name === 'InvalidSpecification'
      ? 'ProjectMockSourceInvalidSpecification' : item.name === 'InvalidContracts' ? 'ProjectMockSourceInvalidContracts' : 'ProjectMockSourceDeclaration');
  }
  for (const item of mappings) project('Mapping(' + value(item) + ')',
    item.name === 'OutputLimit' ? 'ProjectMockWriteMappingLimit' : 'ProjectMockWriteMapping');
  for (const item of runtimes) project('Runtime(' + value(item) + ')',
    {CleanupPending: 'ProjectMockWriteRuntimeCleanupPending', Changed: 'ProjectMockWriteRuntimeChanged'}[item.name]
      ?? 'ProjectMockWriteRuntime');
  for (const item of writeHosts) project('WriteHost(' + value(item) + ')',
    {CustodyLost: 'ProjectMockWriteHostCustodyLost', TransactionUnknown: 'ProjectMockWriteHostTransactionUnknown'}[item.name]
      ?? 'ProjectMockWriteHost');
  for (const item of writeInstallations) project('WriteInstallation(' + value(item) + ')',
    {Limit: 'ProjectMockWriteInstallationLimit', InvalidMaterials: 'ProjectMockWriteInstallationMaterials'}[item.name]
      ?? 'ProjectMockWriteInstallation');
  for (const item of tasks) project('Task({kind: ' + value(item) + ', source: Some(' + privateValue + ')})',
    item.name === 'InvalidLimits' ? 'ProjectMockTaskInvalidLimits'
      : ['BodyLimit', 'TaskLimit', 'WorkLimit'].includes(item.name) ? 'ProjectMockTaskLimit' : 'ProjectMockTaskInvalid');
  const dependencyTags = {Missing: 'ProjectMockDependencyMissing', Body: 'ProjectMockDependencyInvalid',
    UnsupportedPolicy: 'ProjectMockDependencyUnsupportedPolicy', MediaRole: 'ProjectMockDependencyMediaRole'};
  assert.deepEqual(new Set(Object.keys(dependencyTags)), new Set(dependencies.map(entry => entry.name)));
  for (const item of dependencies) {
    if (item.name === 'Body') {
      for (const task of tasks) project('Dependencies(Body(' + privateValue + ', {kind: ' + value(task) +
        ', source: Some(' + privateValue + ')}))', task.name === 'InvalidLimits' ? 'ProjectMockDependencyInvalidLimits'
        : ['BodyLimit', 'TaskLimit', 'WorkLimit'].includes(task.name) ? 'ProjectMockDependencyLimit' : dependencyTags.Body);
    } else project('Dependencies(' + value(item) + ')', dependencyTags[item.name]);
  }
  const providerTags = {ForeignDependencies: 'ProjectMockProviderForeignDependencies',
    ForeignProvider: 'ProjectMockProviderForeignOriginal', UnsupportedPrompt: 'ProjectMockProviderUnsupportedPrompt'};
  assert.deepEqual(new Set(Object.keys(providerTags)), new Set(providers.map(entry => entry.name)));
  assert(providers.every(entry => entry.arity === 0));
  for (const item of providers) project('Provider(' + value(item) + ')', providerTags[item.name]);
  const answerTags = {InvalidLimits: 'ProjectMockAnswerInvalidLimits', BodyLimit: 'ProjectMockAnswerLimit',
    WorkLimit: 'ProjectMockAnswerLimit', EntryLimit: 'ProjectMockAnswerLimit', InvalidBody: 'ProjectMockAnswerInvalidBody',
    TaskIdentity: 'ProjectMockAnswerTaskIdentity', OutputValue: 'ProjectMockAnswerOutputValue',
    ForeignOriginal: 'ProjectMockAnswerForeignOriginal', Retired: 'ProjectMockAnswerRetired'};
  assert.deepEqual(new Set(Object.keys(answerTags)), new Set(answers.map(entry => entry.name)));
  assert(answers.every(entry => entry.arity === 0));
  // The actual answer helper accepts only nullary discriminants/union patterns
  // and literal labels. Its original body is executed below, never reimplemented.
  let closedAnswers = answerSource;
  for (const [row] of answerSource.matchAll(/    [A-Z]\w*(?: \| [A-Z]\w*)* => "[A-Za-z0-9]+"/gu)) {
    closedAnswers = closedAnswers.replace(row, '');
  }
  assert.match(closedAnswers, /^fn local_project_mock_answer_cleanup_cause\(\s*issue : @model.ModelMockAnswerIssue,?\s*\) -> String \{\s*match issue \{\s*\}\s*\}\s*$/u);
  for (const item of answers) {
    const answer = '@model.ModelMockAnswerIssue::' + item.name, tag = answerTags[item.name];
    assertions.push(`  assert_eq(local_project_mock_answer_cleanup_cause(${answer}), "${tag}")`);
    project('Answers(' + answer + ')', tag);
    project('Installation(Answers(' + answer + '))', tag);
  }
  for (const item of installations) if (item.name !== 'Answers') project('Installation(' + value(item) + ')',
    {ForeignOriginal: 'ProjectMockInstallationForeignOriginal', Retired: 'ProjectMockInstallationRetired',
      Busy: 'ProjectMockInstallationBusy', MissingAnswer: 'ProjectMockInstallationMissingAnswer'}[item.name]);
  const main = readFileSync(new URL('../src/cmd/native_client/main.mbt', import.meta.url), 'utf8');
  assert.match(main, /fn fail_cleanup_command\(message : String\)[\s\S]*?"ACTQL_E_CLEANUP_PENDING",\s*message,/);
  assert.match(main, /command_preparation_cleanup_kind\(issue\) \+\s*observed \+\s*" cause=" \+\s*command_preparation_cleanup_cause\(issue\)/);
  const crypto = readFileSync(new URL('../src/cmd/native_client/local_initial_crypto_domain.mbt', import.meta.url), 'utf8');
  assert.match(crypto, /Filesystem\(issue\) =>\s*"Filesystem\(" \+\s*command_preparation_cleanup_cause\(CommandFilesystemCleanup\(issue\)\) \+\s*"\)"/);
  const presentation = readFileSync(new URL('../src/cmd/native_client/local_command_diagnostic.mbt', import.meta.url), 'utf8');
  assert.match(presentation, /\("code", Json::string\(code\)\), \("message", Json::string\(text\)\)/);
  const root = mkdtempSync(join(tmpdir(), 'actql-cleanup-cause-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  mkdirSync(join(root, 'src'));
  writeFileSync(join(root, 'moon.mod'), 'name = "actql/cleanup-cause-probe"\nsource = "src"\n');
  mkdirSync(join(root, 'src/model'));
  writeFileSync(join(root, 'src/model/moon.pkg'), 'supported_targets = "js"\n');
  writeFileSync(join(root, 'src/model/answers.mbt'), 'pub(all) enum ModelMockAnswerIssue {\n' +
    answers.map(({name}) => '  ' + name).join('\n') + '\n}\n');
  mkdirSync(join(root, 'src/resources'));
  writeFileSync(join(root, 'src/resources/moon.pkg'), 'supported_targets = "js"\n');
  writeFileSync(join(root, 'src/resources/ledger.mbt'), 'pub(all) enum LedgerIssue {\n' +
    ledgerIssues.map(({name}) => '  ' + name).join('\n') + '\n}\n');
  writeFileSync(join(root, 'src/moon.pkg'), 'import { "actql/cleanup-cause-probe/model" @model, "actql/cleanup-cause-probe/resources" @initial_resources, }\nsupported_targets = "js"\n');
  writeFileSync(join(root, 'src/probe.mbt'), declarations.join('\n') + '\npub(all) enum LocalCommandPreparationIssue {\n' + outer.join('\n') + '\n}\n');
  writeFileSync(join(root, 'src/probe_wbtest.mbt'), functionSource + '\n' + ledgerSource + '\n' + answerSource + '\n' + 'test "all closed causes exclude private payloads" {\n' + assertions.join('\n') + '\n}\n');
  const actual = spawnSync('moon', ['test', '--target', 'js', '--deny-warn'], {cwd: root, encoding: 'utf8', timeout: 75_000, maxBuffer: 4 * 1024 * 1024});
  assert.equal(actual.error, undefined, actual.error?.message);
  assert.equal(actual.status, 0, actual.stdout + actual.stderr);
  assert.match(actual.stdout + actual.stderr, /Total tests: 1, passed: 1, failed: 0/);
});
