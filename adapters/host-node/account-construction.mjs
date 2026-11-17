// Private facet of the existing installed Host initialization original. All
// numeric mutations go to its same-Ledger byte-only Read; no JS budget owner.
import {open} from 'node:fs/promises';
import {openSync, fstatSync, readSync, closeSync} from 'node:fs';
import {checked} from '../host-common/runtime-result.mjs';
import {sourceJsonWireGeometry} from './installed-source-construction-geometry.mjs';
import {withOriginalFile} from './source-profile-json.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const valid = value => typeof value === 'bigint' && value >= 0n && value <= 9223372036854775807n;
const facets = new WeakSet();
export const isAccountConstruction = value => facets.has(value);

export function createAccountConstruction({moon, prepareRead, current}) {
  let closing = false;
  const controls = moon.clientProgramAccountReadControlBytes();
  if (!valid(controls) || controls === 0n || typeof prepareRead !== 'function' ||
      typeof current !== 'function') fail('AccountConstructionUnavailable');
  // The first actual byte-only child funds the facet/registry's fixed controls
  // before their construction. This constant baseline is never consumed by
  // an observation: each frame has its own original Read/control cohort.
  let firstRead = checked(prepareRead()), closeFlight;
  const frames = new Set(), retirements = [];
  function settleFrame(state) {
    if (state.closed) return true;
    if (checked(moon.clientProgramCloseAccountRead(state.read, true)) !== true) return false;
    state.closed = true;
    state.read = state.issue = undefined;
    frames.delete(state);
    return true;
  }
  function closeOriginalGate(state) {
    const owned = state.gate;
    if (owned === undefined) return true;
    // Only the actual owned Scope's two observations can end this hold. No
    // caller flag, replacement method or sibling's cleanup is an ACK.
    if (typeof owned.close !== 'function' || typeof owned.pending !== 'function') return false;
    try {
      const closed = Reflect.apply(owned.close, owned.original, []);
      const pending = Reflect.apply(owned.pending, owned.original, []);
      if (closed !== true || pending !== false) return false;
      state.gate = undefined;
      return true;
    } catch (cause) {state.issue ??= cause; throw cause;}
  }
  async function closeAll() {
    for (const callback of retirements) {if (await callback() === false) return false;}
    retirements.length = 0;
    for (const state of frames) {
      if (state.active || state.cleaning || state.unknownClose) return false;
      state.cleaning = true;
      try {
        state.closeRequested = true;
        if (!closeOriginalGate(state)) return false;
        if (state.cleanup !== undefined) {
          const {handle, retry, status} = state.cleanup;
          if (typeof retry !== 'function' || typeof status !== 'function') return false;
          try {await Reflect.apply(retry, handle, []);} catch {}
          const observation = Reflect.apply(status, handle, []);
          if (Object.getOwnPropertyDescriptor(observation ?? {}, 'pending')?.value !== false) return false;
          state.cleanup = undefined;
        }
        if (!settleFrame(state)) return false;
      } finally {state.cleaning = false;}
    }
    // The original fixed facet/registry controls survive every pending frame
    // and callback. Retire this constant cohort last, after actual child cleanup.
    if (firstRead !== undefined) {
      if (checked(moon.clientProgramCloseAccountRead(firstRead, true)) !== true) return false;
      firstRead = undefined;
    }
    return true;
  }
  function begin() {
    if (closing) fail('AccountConstructionClosed');
    current();
    // Retain the actual Core child before any later constructor or observation.
    const state = {read: checked(prepareRead()), retained: controls, execution: controls, active: true,
      closed: false, retainedOutput: false, failed: false, unknownClose: false, cleanup: undefined,
      issue: undefined, gate: undefined, cleaning: false, closeRequested: false};
    frames.add(state);
    function prepare(retained, execution) {
      if (!state.active || state.issue !== undefined || closing) fail('AccountConstructionUnavailable');
      if (!valid(retained) || !valid(execution) || !valid(state.retained + retained) ||
          !valid(state.retained + execution)) fail('AccountConstructionOverflow');
      const r = state.retained + retained;
      const e = state.execution > state.retained + execution ? state.execution : state.retained + execution;
      try {checked(moon.clientProgramPrepareAccountReadConstruction(state.read, r, e));}
      catch (cause) {state.issue = cause; state.failed = true; throw cause;}
      state.retained = r; state.execution = e;
    }
    function failure(cause) {
      state.failed = true;
      state.issue ??= cause;
      const handle = Object.getOwnPropertyDescriptor(Object(cause), 'cleanupHandle')?.value;
      if (handle !== undefined) state.cleanup ??= {handle, status: handle.status, retry: handle.retry};
    }
    function finish(retain = false) {
      state.active = false;
      if (state.retainedOutput && !state.failed && !state.unknownClose && state.cleanup === undefined) {
        // The awaited constructor returned and its actual gate/DATA is already
        // retained. Its parse/canonical/admission stack has ended; keep every
        // admitted retained byte and the SAME Read until real gate cleanup.
        try {checked(moon.clientProgramCompleteAccountReadConstruction(state.read));}
        catch (cause) {failure(cause); throw cause;}
        state.execution = state.retained;
      }
      if (!retain && !state.retainedOutput && !state.failed && !state.unknownClose && state.cleanup === undefined) {
        if (!settleFrame(state)) fail('AccountReadCleanupPending');
      }
    }
    let lastWire;
    const frame = Object.freeze({
      prepare,
      core(retained, execution) {
        try {prepare(retained, execution); return true;}
        catch (cause) {failure(cause); return false;}
      },
      assert() {if (state.issue !== undefined) throw state.issue;},
      failure,
      finish,
      hold() {state.retainedOutput = true;},
      retainGate(original) {
        if (state.gate !== undefined || state.closed) fail('ForeignAccountGateCleanup');
        // Capture the constructed original BEFORE a closing fence can refuse
        // publication. A late constructor remains owned by this SAME frame.
        state.gate = {original, close: undefined, pending: undefined};
        state.retainedOutput = true;
        const close = Object.getOwnPropertyDescriptor(original, 'close');
        const pending = Object.getOwnPropertyDescriptor(original, 'cleanupPending');
        if (!Object.hasOwn(close ?? {}, 'value') || typeof close.value !== 'function' ||
            !Object.hasOwn(pending ?? {}, 'value') || typeof pending.value !== 'function') {
          fail('InvalidAccountGateCleanup');
        }
        state.gate.close = close.value;
        state.gate.pending = pending.value;
        if (closing) fail('AccountConstructionClosed');
      },
      closeGate() {
        if (state.closed) return true;
        state.closeRequested = true;
        if (state.active || state.cleaning) return false;
        state.cleaning = true;
        try {
          if (!closeOriginalGate(state) || state.failed || state.unknownClose || state.cleanup !== undefined) return false;
          return settleFrame(state);
        } finally {state.cleaning = false;}
      },
      gateCleanupPending() {
        if (state.closed) return false;
        if (state.closeRequested || state.cleaning || state.failed || state.unknownClose || state.cleanup !== undefined) return true;
        const owned = state.gate;
        return owned === undefined || Reflect.apply(owned.pending, owned.original, []) !== false;
      },
      inputBytes(size) {
        if (!Number.isSafeInteger(size) || size < 0 || size === Number.MAX_SAFE_INTEGER) fail('AccountInputExtentUnavailable');
        const bytes = BigInt(size);
        prepare(33n + bytes, 128n + 2n * bytes + 1n);
      },
      decodedBytes(size) {const bytes = BigInt(size); prepare(16n + 2n * bytes, 128n + 4n * bytes);},
      nativeJson(wire) {
        if (lastWire === wire) return;
        // One original lexical scan. It does not normalize, JSON.parse or
        // allocate input-dependent key lists before admitting the forest.
        const shape = sourceJsonWireGeometry(wire, true);
        prepare(256n * shape.nodes + 72n * shape.units,
          1024n * shape.nodes + 1296n * shape.weighted + 512n);
        lastWire = wire;
      },
      record(units, nodes, depth = 8n) {
        // Closed caller observes borrowed strings/lists without copying them.
        prepare(256n * nodes + 72n * units,
          1024n * nodes + 1296n * units * depth + 512n);
      },
      admit(runtime, wire) {
        if (runtime !== moon) fail('ForeignAccountConstructionRuntime');
        frame.nativeJson(wire);
        const value = moon.executionAuthorizationAdmitPrepared(wire, frame.core);
        frame.assert();
        if (value === undefined) fail('AccountConstructionUnavailable');
        return value;
      },
      closeUnknown(cause) {state.unknownClose = true; failure(cause);},
    });
    try {prepare(0n, 0n);}
    catch (cause) {failure(cause); state.active = false; throw cause;}
    return frame;
  }
  function observe(operation) {
    const frame = begin();
    try {const value = operation(frame); frame.finish(false); return value;}
    catch (cause) {frame.failure(cause); frame.finish(false); throw cause;}
  }
  const facet = Object.freeze({moon, begin, observe,
    pending() {return firstRead !== undefined || frames.size !== 0;},
    onRetire(callback) {if (closing || typeof callback !== 'function') fail('AccountConstructionClosed'); retirements.push(callback);},
    close() {
      if (closeFlight !== undefined) return closeFlight;
      closing = true;
      // Enqueue after publishing the SAME flight, including the first sync
      // Core close/current boundary. Recursive/concurrent close cannot race it.
      const flight = Promise.resolve().then(closeAll);
      closeFlight = flight;
      const settled = () => {if (closeFlight === flight) closeFlight = undefined;};
      flight.then(settled, settled);
      return flight;
    },
  });
  facets.add(facet);
  return facet;
}

// Original physical file owner and its exact close/retry carrier remain shared
// with other installed metadata. The opened FD supplies size BEFORE Buffer.
export async function readAccountOriginal(path, frame) {
  try {
    return await withOriginalFile(path, value => open(value, 'r'), async original => {
      const observed = await original.stat();
      frame.inputBytes(observed.size);
      const bytes = Buffer.alloc(observed.size + 1);
      let used = 0;
      while (used < bytes.length) {
        const {bytesRead} = await original.read(bytes, used, bytes.length - used, used);
        if (bytesRead === 0) break;
        used += bytesRead;
      }
      if (used > observed.size) fail('AccountConfigurationChangedDuringRead');
      frame.decodedBytes(used);
      const wire = new TextDecoder('utf-8', {fatal: true}).decode(bytes.subarray(0, used));
      const after = await original.stat();
      if (after.size !== observed.size || after.mtimeMs !== observed.mtimeMs || after.ctimeMs !== observed.ctimeMs) {
        fail('AccountConfigurationChangedDuringRead');
      }
      return wire;
    });
  } catch (cause) {frame.failure(cause); throw cause;}
}

export function readAccountCurrent(path, frame) {
  let fd, primary, closed = false;
  try {
    fd = openSync(path, 'r');
    const observed = fstatSync(fd);
    frame.inputBytes(observed.size);
    const buffer = Buffer.alloc(observed.size + 1);
    let used = 0;
    while (used < buffer.length) {
      const read = readSync(fd, buffer, used, buffer.length - used, used);
      if (read === 0) break;
      used += read;
    }
    if (used > observed.size) fail('AccountConfigurationChangedDuringRead');
    frame.decodedBytes(used);
    const wire = new TextDecoder('utf-8', {fatal: true}).decode(buffer.subarray(0, used));
    const after = fstatSync(fd);
    if (after.size !== observed.size || after.mtimeMs !== observed.mtimeMs || after.ctimeMs !== observed.ctimeMs) {
      fail('AccountConfigurationChangedDuringRead');
    }
    return wire;
  } catch (cause) {primary = cause; frame.failure(cause); throw cause;}
  finally {
    if (fd !== undefined && !closed) {
      closed = true;
      try {closeSync(fd);}
      catch (cause) {
        // A numeric close is attempted once. Never retry an integer that may
        // already have been reused; keep original Host/Read cleanup pending.
        frame.closeUnknown(primary ?? cause);
        throw cause;
      }
    }
  }
}
