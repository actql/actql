import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {parse} from 'acorn';
import {createInstalledHostServices as actualCreateServices} from './installed-host-services.mjs';

// Actual initializer and identity bodies with explicit initial/service/read
// ports. This proves caller order and originals, not a nominal Core reservation
// or Account/Source/Store/physical read acknowledgement.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const program = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declaration = name => program.body.map(node => node.declaration ?? node)
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === name);
const identityBody = declaration('embeddedInstallationIdentity');
// The public connect entry forwards to the same shared Local/Remote owner.
// Extract that actual owner, rather than searching beyond the wrapper's end.
const connectEntry = declaration('connectEmbeddedLocal');
const handoff = connectEntry.body.body[0];
assert.equal(connectEntry.body.body.length, 1);
assert.equal(handoff.type, 'ReturnStatement');
assert.equal(handoff.argument.type, 'CallExpression');
assert.equal(handoff.argument.callee.name, 'openPreparedInstalledHost');
assert.deepEqual(handoff.argument.arguments.map(node => [node.type, node.name]),
  [['Identifier', 'options'], ['Identifier', 'initialEntry']]);
const connectBody = declaration(handoff.argument.callee.name);
const start = source.indexOf('  const root = installation?.directory', connectBody.start);
const end = source.indexOf('  const client = await profiles.connect', start);
assert(start > connectBody.start && end > start && end < connectBody.end);
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const compile = (scope, body) => new AsyncFunction(...Object.keys(scope), body)
  .bind(undefined, ...Object.values(scope));

function fixture(paths) {
  const configurationReader = Object.freeze({readJson() {assert.fail('Explicit identity reader port only');}});
  const services = Object.freeze({name: 'same-initial-services'});
  const moon = {}, originalInstallation = {}, record = {}, originals = {}, control = {};
  const installation = {directory: '/explicit/source-initial-parent',
    ...(paths.length === 0 ? {} : {sourceProfilePaths: paths})};
  const project = undefined, projectProfile = {}, projectSourcePreparation = undefined;
  const calls = [];
  let sourceServices;
  const preparation = {
    sourceInitializationServices(actualMoon, root, principal) {
      assert.equal(this, preparation); assert.equal(actualMoon, moon);
      assert.equal(root, installation.directory); assert.equal(principal, 'original-principal');
      assert.equal(originalInstallation.root, root);
      sourceServices = services; calls.push('same-initial-service'); return services;
    },
  };
  const common = {validateSourceNamespace() {}, assertInstalledConnectorTable() {},
    installedSourcePaths: value => value.sourceProfilePaths ?? [], installedEffectPaths: () => [],
    installedSourceIdentity: async (path, options) => {
      assert.equal(sourceServices, services, 'first Source identity requires the same initial service');
      assert.equal(options.configurationReader, configurationReader, 'exact original managed configuration reader');
      calls.push('identity:' + path); return {path};
    },
    installedEffectIdentity() {assert.fail('No Effect selected');},
    canonicalJson: JSON.stringify, bytesCid: text => 'explicit-identity:' + text,
    installedProjectOriginalsForRuntime() {assert.fail('No Project selected');},
    installedCalendarIdentityCid() {assert.fail('No Calendar selected');},
    publicKeyCid() {assert.fail('No key selected');}, readFile() {assert.fail('No account file selected');},
  };
  const identity = compile(common, source.slice(identityBody.start, identityBody.end) +
    '; return embeddedInstallationIdentity(...arguments[arguments.length - 1]);');
  // The function above is captured from the actual complete declaration. Keep
  // its lexical ports, then call it with the actual initializer tuple below.
  const makeIdentity = new Function(...Object.keys(common),
    source.slice(identityBody.start, identityBody.end) + ';return embeddedInstallationIdentity;');
  const embeddedInstallationIdentity = makeIdentity(...Object.values(common));
  const run = compile({installation, project, projectProfile, projectSourcePreparation,
    originalInstallation, record, moon, control, originals, preparation, resolve, process: {env: {}},
    localStateRoot() {assert.fail('Explicit root selected');},
    installedSourcePaths: common.installedSourcePaths,
    userInfo: () => ({username: 'original-principal'}),
    installedSourceConfigurationReader(actual) {assert.equal(actual, services);return configurationReader;},
    embeddedInstallationIdentity,
    assertInitialControlInstallationCurrent(actualControl, actualOriginals) {
      assert.equal(actualControl, control); assert.equal(actualOriginals, originals); calls.push('initial-current');
    }}, source.slice(start, end) + '\nreturn {identity,record,originalInstallation};');
  return {run, calls, services, configurationReader};
}

test('first Source identity consumes the same initial service and configuration reader before any file read', async () => {
  const f = fixture(['/explicit/one-source.json', '/explicit/two-source.json']);
  const result = await f.run();
  assert.deepEqual(f.calls.slice(0, 3), ['same-initial-service',
    'identity:/explicit/one-source.json', 'identity:/explicit/two-source.json']);
  assert.equal(result.record.installation, result.originalInstallation);
});

test('Source-free identity keeps its absent configuration service path', async () => {
  const f = fixture([]);
  await f.run();
  assert.deepEqual(f.calls, ['initial-current']);
});

function serviceFixture({failConstruction = false} = {}) {
  const selected = connectBody.body.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations.some(value => value.id.name === 'preparation'));
  const object = selected.declarations.find(value => value.id.name === 'preparation').init.arguments[0];
  const names = ['sourceInitializationServices', 'hostInitializationPreparation'];
  const methods = names.map(name => object.properties.find(value => value.key.name === name));
  assert(methods.every(Boolean));
  const check = connectBody.body.body.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'assertSourceInitializationSelection');
  assert(check);
  const scope = {createInstalledHostServices: actualCreateServices,
    clientOperationError: code => Object.assign(new Error(code), {code})};
  const factory = new Function(...Object.keys(scope), `
    const moon={},originals={},control={},project={};
    let sourceInitializationSelection,sourceInitializationServices,hostInitialization,sourceManaged;
    let projectOriginal={}, currentProjectOriginal=projectOriginal, sourceCurrent, parentCurrent;
    let parentOpens=0,serviceOpens=0,hostCalls=0;
    const originalInstallation={root:'/explicit/source-initial-parent'};
    const record={runtime:moon},parent={};
    function installedProjectOriginalsForRuntime(actualProject,actualMoon) {
      if(actualProject!==project||actualMoon!==moon)throw Error('ForeignProjectTuple');
      return currentProjectOriginal;
    }
    function assertInitialControlHostPreparation(value) {if(value!==originals)throw Error('ForeignInitialOriginal');}
    function assertInitialControlInstallationCurrent(actualControl,value) {
      if(actualControl!==control||value!==originals)throw Error('ForeignInitialControl');
    }
    function openHostInitializationPreparation(state,actualMoon,input,current,children) {
      if(actualMoon!==moon||input!==originalInstallation||children()!==false)throw Error('ForeignParentTuple');
      parentCurrent=current;current();parentOpens++;state.parent=parent;return parent;
    }
    ${source.slice(check.start, check.end)}
    const createOriginal=createInstalledHostServices;
    createInstalledHostServices=function(options) {
      serviceOpens++;sourceCurrent=options.assertCurrent;
      if(options.initialPreparation!==parent)throw Error('ForeignInitialParent');
      if(${JSON.stringify(failConstruction)})throw originalFailure;
      return createOriginal(options);
    };
    const originalFailure=new Error('same-service-constructor-failure');
    const preparation=Object.freeze({${methods.map(node => source.slice(node.start, node.end)).join(',')}});
    const hostCurrent=()=>{hostCalls++;};
    return {moon,parent,originalInstallation,record,preparation,hostCurrent,originalFailure,
      sourceCurrent:()=>sourceCurrent(),parentCurrent:()=>parentCurrent(),
      changeProject:()=>{currentProjectOriginal={};},
      state:()=>({parentOpens,serviceOpens,hostCalls,selection:sourceInitializationSelection,
        services:sourceInitializationServices,hostInitialization})};
  `);
  return factory(...Object.values(scope));
}

test('identity and Host loader reuse one actual service and parent with the original Project and current fences', () => {
  const f = serviceFixture();
  const first = f.preparation.sourceInitializationServices(f.moon, f.originalInstallation.root, 'principal');
  const actualHostStart = source.indexOf('  const installationServices = preparation === undefined');
  const actualHostEnd = source.indexOf('  const control = runtimeCore(moon).publicationControl;', actualHostStart);
  assert(actualHostStart > 0 && actualHostEnd > actualHostStart);
  const take = new Function('preparation', 'moon', 'root', 'principalId', 'assertProjectRuntime',
    'createInstalledHostServices', source.slice(actualHostStart, actualHostEnd) + ';return installationServices;');
  const second = take(f.preparation, f.moon, f.originalInstallation.root, 'principal', f.hostCurrent,
    () => assert.fail('No second Host service constructor'));
  assert.equal(second, first); assert.equal(f.state().parentOpens, 1); assert.equal(f.state().serviceOpens, 1);
  const hostChecks = f.state().hostCalls;
  f.sourceCurrent(); f.parentCurrent();
  assert.equal(f.state().hostCalls, hostChecks + 2);
  for (const args of [[{}, f.originalInstallation.root, 'principal'],
    [f.moon, '/foreign-root', 'principal'], [f.moon, f.originalInstallation.root, 'foreign-principal'],
    [f.moon, f.originalInstallation.root, 'principal', () => {}]]) {
    assert.throws(() => f.preparation.sourceInitializationServices(...args),
      {code: 'ForeignInstalledSourceInitialization'});
  }
  f.changeProject();
  for (const current of [f.sourceCurrent, f.parentCurrent]) assert.throws(current,
    {code: 'ForeignInstalledSourceInitialization'});
  assert.equal(f.state().parentOpens, 1); assert.equal(f.state().serviceOpens, 1);
});

test('failed first service construction retains its same initial parent and refuses replacement construction', () => {
  const f = serviceFixture({failConstruction: true});
  assert.throws(() => f.preparation.sourceInitializationServices(f.moon,
    f.originalInstallation.root, 'principal'), error => error === f.originalFailure);
  const retained = f.state().selection;
  assert.equal(f.state().hostInitialization.parent, f.parent);
  assert.equal(f.record.sourceInitializationSelection, retained);
  assert.throws(() => f.preparation.sourceInitializationServices(f.moon,
    f.originalInstallation.root, 'principal'), {code: 'ForeignInstalledSourceInitialization'});
  assert.equal(f.state().selection, retained);
  assert.equal(f.state().parentOpens, 1); assert.equal(f.state().serviceOpens, 1);
});
