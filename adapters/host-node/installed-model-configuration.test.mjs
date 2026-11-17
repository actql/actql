import test from 'node:test';
import assert from 'node:assert/strict';
import {installConfiguredModelProviders} from './installed-model-configuration.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';

function fixture() {
  let installs = 0, sends = 0, current = true;
  // Only the Core installation primitive is doubled in these control tests.
  // They establish no actual Common Task, resource, Store or public Run result.
  const moon = {clientProgramInstallModelProvider() {installs++; return {};}};
  const entry = {providerId: 'models/configuration', validatePrompt: () => true,
    invoke() {sends++; assert.fail('No Model invocation');}};
  const check = () => {if (!current) throw Object.assign(new Error('OriginalLost'), {code: 'OriginalLost'});};
  const options = {moon, assertCurrent: check, assertHostRuntime: check, assertNewHostRuntime: check};
  return {moon, entry, options, counts: () => ({installs, sends}), loseCurrent: () => {current = false;}};
}

test('configuration preserves the legacy single synchronous registration callback', async () => {
  const f = fixture(); let callbacks = 0, context;
  const installed = await installConfiguredModelProviders({...f.options, register(runtime, actual) {
    assert.strictEqual(runtime, f.moon); callbacks++; context = actual;
    assert.equal(Object.isFrozen(actual), true);
    return [f.entry];
  }});
  assert.equal(installed.providers.has(f.entry.providerId), true);
  assert.equal(installed.projectTasks, undefined);
  assert.deepEqual(f.counts(), {installs: 1, sends: 0});
  assert.equal(callbacks, 1);
  assert.throws(() => context.readText('not-opened', {maxBytes: 1}),
    {code: 'InstalledModelConfigurationClosed'});
});

test('configuration awaits one asynchronous registration without invoking a model', async () => {
  const f = fixture(); let callbacks = 0;
  const result = await installConfiguredModelProviders({...f.options, async register(runtime) {
    callbacks++; await Promise.resolve(); assert.strictEqual(runtime, f.moon);
    return [f.entry];
  }});
  assert.equal(result.providers.size, 1);
  assert.equal(callbacks, 1);
  assert.deepEqual(f.counts(), {installs: 1, sends: 0});
});

test('configuration rechecks the original current predicate after callback await', async () => {
  const f = fixture();
  await assert.rejects(installConfiguredModelProviders({...f.options, async register() {
    await Promise.resolve(); f.loseCurrent(); return [f.entry];
  }}), {code: 'OriginalLost'});
  assert.deepEqual(f.counts(), {installs: 0, sends: 0});
});

test('configuration cannot swallow an invalid bounded secret read and install a fallback', async () => {
  const f = fixture(); let first;
  await assert.rejects(installConfiguredModelProviders({...f.options, async register(_, context) {
    try {await context.readText('not-opened', {maxBytes: 0});}
    catch (cause) {first = cause;}
    return [f.entry];
  }}), cause => cause === first && cause.code === 'InvalidInstalledModelConfigurationRead');
  assert.deepEqual(f.counts(), {installs: 0, sends: 0});
});

test('configuration refuses a read without the original managed construction owner', async () => {
  const f = fixture();
  await assert.rejects(installConfiguredModelProviders({...f.options, async register(_, context) {
    await context.readText('not-opened', {maxBytes: 64}); return [f.entry];
  }}), {code: 'InstalledModelTaskConstructionUnavailable'});
  assert.deepEqual(f.counts(), {installs: 0, sends: 0});
});

test('configuration requires the original constructor before canonical binding preparation', async () => {
  const f = fixture();
  await assert.rejects(installConfiguredModelProviders({...f.options, async register(_, context) {
    await context.prepareBindingOriginals('{}', '{}', '{}'); return [f.entry];
  }}), {code: 'InstalledModelTaskConstructionUnavailable'});
  assert.deepEqual(f.counts(), {installs: 0, sends: 0});
});

test('configuration refuses missing construction before inspecting bindings or admitting a Task', async () => {
  for (const accessor of [false, true]) {
    const f = fixture(); let gets = 0;
    const binding = {providerId: f.entry.providerId,
      bindingOriginals: providerBindingOriginals(f.entry.providerId)};
    const other = accessor ? Object.defineProperty({}, 'providerId', {
      enumerable: true, get() {gets++; return f.entry.providerId;},
    }) : {...binding};
    await assert.rejects(installConfiguredModelProviders({...f.options, project: {},
      taskLimits: {maxMembers: 4}, async register(_, context) {
        await context.prepareTasks([binding, other]); return [f.entry];
    }}), {code: 'InstalledModelTaskConstructionUnavailable'});
    assert.equal(gets, 0);
    assert.deepEqual(f.counts(), {installs: 0, sends: 0});
  }
});

test('configuration preserves the original callback error and closes its context', async () => {
  const f = fixture(), primary = new Error('Selected callback failure'); let context;
  await assert.rejects(installConfiguredModelProviders({...f.options, register(_, actual) {
    context = actual; throw primary;
  }}), cause => cause === primary);
  assert.throws(() => context.prepareTasks([]), cause => cause === primary);
  assert.deepEqual(f.counts(), {installs: 0, sends: 0});
});

test('configuration preserves thrown undefined as the original failure', async () => {
  const f = fixture(); let context, failed = false;
  try {
    await installConfiguredModelProviders({...f.options, register(_, actual) {
      context = actual; throw undefined;
    }});
  } catch (cause) {failed = true; assert.strictEqual(cause, undefined);}
  assert.equal(failed, true);
  failed = false;
  try {await context.prepareTasks([]);}
  catch (cause) {failed = true; assert.strictEqual(cause, undefined);}
  assert.equal(failed, true);
  assert.deepEqual(f.counts(), {installs: 0, sends: 0});
});

test('configuration seals the context before consuming a retained provider entry getter', async () => {
  const f = fixture(); let gets = 0;
  await assert.rejects(installConfiguredModelProviders({...f.options, register(_, context) {
    return [{...f.entry, get providerId() {
      gets++;
      context.readText('must-not-open-after-callback', {maxBytes: 64});
      assert.fail('No asynchronous read may start after the callback drain');
    }}];
  }}), {code: 'InstalledModelConfigurationClosed'});
  assert.equal(gets, 1);
  assert.deepEqual(f.counts(), {installs: 0, sends: 0});
});

test('configuration closed context never calls current predicates or replaces its original failure', async () => {
  for (const mode of ['installed', 'error', 'undefined']) {
    const f = fixture(); let context, calls = 0, closed = false;
    const primary = mode === 'error' ? new Error('OriginalConfigurationFailure') : undefined;
    const current = () => {
      calls++;
      if (closed) {
        // Reentry must be impossible after closure, including a predicate
        // that would otherwise recurse through this same retained context.
        context.readText('must-not-open', {maxBytes: 64});
        throw new Error('LaterCurrentFailure');
      }
    };
    let failed = false;
    try {
      await installConfiguredModelProviders({...f.options,
        assertCurrent: current, assertHostRuntime: current, assertNewHostRuntime: current,
        register(_, actual) {
          context = actual;
          if (mode !== 'installed') throw primary;
          return [f.entry];
        }});
    } catch (cause) {failed = true; assert.strictEqual(cause, primary);}
    assert.equal(failed, mode !== 'installed');
    const before = calls;
    closed = true; failed = false;
    try {context.readText('must-not-open', {maxBytes: 64});}
    catch (cause) {
      failed = true;
      if (mode === 'installed') assert.equal(cause.code, 'InstalledModelConfigurationClosed');
      else assert.strictEqual(cause, primary);
    }
    assert.equal(failed, true);
    assert.equal(calls, before, 'no current callback after context closure');
  }
});
