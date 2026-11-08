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
  // This one nested family has an explicit reviewed shape. Do not broaden the
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
  let covered = functionSource.replace(projectMock, '');
  const nested = [...covered.matchAll(/    (Command\w+)\(cause\) =>\s+match cause \{([\s\S]*?)\n      \}/g)];
  assert.ok(nested.length >= 20);
  for (const [block, variant, body] of nested) {
    const type = `Probe${variant}`;
    const cases = [...body.matchAll(/([A-Z]\w*)(\((?:_|,|\s)*\))?\s*=>\s*"([A-Za-z0-9]+)"/g)];
    assert.ok(cases.length > 0);
    const residual = cases.reduce((value, [row]) => value.replace(row, ''), body);
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
  function enumCases(path, name) {
    const text = readFileSync(new URL('../' + path, import.meta.url), 'utf8');
    const start = text.indexOf('enum ' + name + ' {');
    assert(start >= 0, name);
    const body = text.slice(start).split('\n}')[0].split('\n').slice(1).join('\n');
    // Enum payloads may wrap onto multiple lines, but remain closed type lists.
    // Reject every unmatched token; this is not a fallback Source parser.
    const rows = [...body.matchAll(/(?:^|\n)  ([A-Z]\w*)(?:\(([^()]*)\))?(?=\n|$)/gu)];
    let residual = body;
    const cases = rows.map(([row, variant, payload]) => {
      residual = residual.replace(row, '');
      const fields = payload === undefined ? [] : payload.split(',').map(value => value.trim());
      assert(fields.every(value => /^(?:@\w+\.)?[A-Z]\w*\??$/u.test(value)), name);
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
  writeFileSync(join(root, 'src/moon.pkg'), 'import { "actql/cleanup-cause-probe/model" @model, }\nsupported_targets = "js"\n');
  writeFileSync(join(root, 'src/probe.mbt'), declarations.join('\n') + '\npub(all) enum LocalCommandPreparationIssue {\n' + outer.join('\n') + '\n}\n');
  writeFileSync(join(root, 'src/probe_wbtest.mbt'), functionSource + '\n' + answerSource + '\n' + 'test "all closed causes exclude private payloads" {\n' + assertions.join('\n') + '\n}\n');
  const actual = spawnSync('moon', ['test', '--target', 'js', '--deny-warn'], {cwd: root, encoding: 'utf8', timeout: 75_000, maxBuffer: 4 * 1024 * 1024});
  assert.equal(actual.error, undefined, actual.error?.message);
  assert.equal(actual.status, 0, actual.stdout + actual.stderr);
  assert.match(actual.stdout + actual.stderr, /Total tests: 1, passed: 1, failed: 0/);
});
