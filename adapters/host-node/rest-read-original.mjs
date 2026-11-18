// One pure original GET declaration under the EXISTING Source initializer.
// The capsule hides Core parser/Bytes backing in captured functions; the JSON
// projection freezer never traverses or freezes foreign opaque objects.
import {types} from 'node:util';
import {runtimeField, runtimeIsOk, runtimeIsError, runtimeIsBoxedSome}
  from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {exchangeLimits} from '../host-common/http-exchange.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const portNames = ['clientProgramRowSourceAdmitGetRead', 'clientProgramRowSourceGetReadMetadata',
  'clientProgramRowSourceGetReadCapacity', 'clientProgramRowSourceGetPageCapacity',
  'clientProgramRowSourceGetReadPage', 'clientProgramRowSourceGetPageFrame',
  'clientProgramRowSourceGetReadIssueCode',
  'clientProgramInstalledSourceConstructionCapacity', 'clientProgramComposeInstalledSourceConstructionCapacity',
  'clientProgramRowSourceGetRequestCapacity'];

export function captureRestReadOriginals(moon) {
  if (!moon || typeof moon !== 'object' || types.isProxy(moon)) fail('RestReadOriginalRuntimeUnavailable');
  const ports = Object.freeze(Object.fromEntries(portNames.map(name => {
    const field = Object.getOwnPropertyDescriptor(moon, name);
    if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') fail('RestReadOriginalRuntimeUnavailable');
    return [name, field.value.bind(moon)];
  })));
  const value = result => {
    if (runtimeIsOk(result)) return runtimeField(result, 0);
    if (runtimeIsError(result)) {
      const issue = ports.clientProgramRowSourceGetReadIssueCode(runtimeField(result, 0));
      if (typeof issue !== 'string') fail('RestReadOriginalRuntimeUnavailable');
      throw Object.assign(new Error(issue, {cause: runtimeField(result, 0)}), {code: issue});
    }
    fail('RestReadOriginalRuntimeUnavailable');
  };
  const quantity = option => {
    if (!runtimeIsBoxedSome(option)) fail('RestReadOriginalCapacityUnavailable');
    return runtimeField(option, 0);
  };
  const limitsFor = (readWire, cursorParameter, profile) => {
    if (typeof readWire !== 'string' || !readWire.isWellFormed() ||
        cursorParameter !== undefined && typeof cursorParameter !== 'string') fail('InvalidRestReadOriginal');
    const bytes = Buffer.byteLength(readWire, 'utf8');
    if (bytes < 1 || bytes > profile.maxDeclarationBytes) fail('RestReadOriginalBoundsExceeded');
    return Object.freeze([bytes, Math.min(bytes, profile.maxDeclarationNodes), profile.maxDepth,
      profile.maxTargetBytes, exchangeLimits.maxQueryPairs, exchangeLimits.maxQueryBytes,
      exchangeLimits.maxHeaderNameBytes, exchangeLimits.maxHeaderValueBytes]);
  };
  return Object.freeze({
    quote(readWire, cursorParameter, profile) {
      // Quote DATA only: no UTF8 input, parser, per-read callback holder or
      // target is built before the SAME initializer reserves this quantity.
      return ports.clientProgramRowSourceGetReadCapacity(limitsFor(readWire, cursorParameter, profile));
    },
    project(readWire, cursorParameter, profile) {
      const limits = limitsFor(readWire, cursorParameter, profile);
      const read = value(ports.clientProgramRowSourceAdmitGetRead(Buffer.from(readWire, 'utf8'),
        cursorParameter !== undefined, cursorParameter ?? '', limits));
      const metadata = value(ports.clientProgramRowSourceGetReadMetadata(read));
      // This is actual Tuple5, NOT a FixedArray or a hand-built Option.
      const path = runtimeField(metadata, 0), present = runtimeField(metadata, 1);
      const pageSize = runtimeField(metadata, 2), pairs = runtimeField(metadata, 3), headers = runtimeField(metadata, 4);
      if (typeof path !== 'string' || typeof present !== 'boolean' ||
          ![pageSize, pairs, headers].every(Number.isSafeInteger)) fail('RestReadOriginalRuntimeUnavailable');
      const capacityOption = ports.clientProgramRowSourceGetPageCapacity(read);
      quantity(capacityOption);
      return Object.freeze({path, pageSize: present ? pageSize : undefined,
        pairs, headers,
        capacityOption() {return capacityOption;},
        page(remaining, hint, cursor) {
          const page = value(ports.clientProgramRowSourceGetReadPage(read, remaining, hint,
            cursor !== undefined, cursor ?? ''));
          const frame = value(ports.clientProgramRowSourceGetPageFrame(page));
          const method = runtimeField(frame, 0), path = runtimeField(frame, 1);
          const query = runtimeField(frame, 2), headers = runtimeField(frame, 3);
          if (method !== 'GET' || typeof path !== 'string' || !Array.isArray(query) || !Array.isArray(headers)) {
            fail('RestReadOriginalRuntimeUnavailable');
          }
          return Object.freeze({method, path, query, headers, responseHeaders: []});
        }});
    },
    composeConstruction(units, quotes) {
      const base = checked(ports.clientProgramInstalledSourceConstructionCapacity(...units));
      // Pass actual Some quantities from this SAME namespace. Neither the
      // Source projection freezer nor a caller-created Option touches them.
      return checked(ports.clientProgramComposeInstalledSourceConstructionCapacity(base, quotes));
    },
    requestCapacity(units, originals) {
      const transport = checked(ports.clientProgramInstalledSourceConstructionCapacity(...units));
      return quantity(ports.clientProgramRowSourceGetRequestCapacity(transport,
        originals.map(original => original.capacityOption())));
    },
  });
}

// Post-Core transport construction ONLY. Core already owns the page/tuple
// vectors and page-size decimal; do not retain the replaced JS copies twice.
// These remain the existing Host logical allowance units and query ceiling.
export function restReadTransportConstructionUnits(original) {
  if (!original || types.isProxy(original) || !Object.isFrozen(original)) fail('InvalidRestReadOriginal');
  const pairs = BigInt(original.pairs), headers = BigInt(original.headers);
  const path = BigInt(original.path.length), query = BigInt(exchangeLimits.maxQueryBytes);
  const retained = 6n + (1n + 4n * headers) + 1n + 4n;
  const workspace = retained + (1n + 4n * pairs) + (5n + 4n * headers) + 12n;
  return [retained, 2n * (path + 1n + query), 0n,
    workspace, 2n * (4n * query + 2n * (path + 1n + query)), 0n];
}

// Exact Host capsule/control inventory around the separately quoted Core
// parser. No JSON/text payload is copied here: its original readWire remains
// in the static Source definition, while input+Core Bytes use the native quote.
export function restReadOriginalControlUnits(count) {
  if (!Number.isSafeInteger(count) || count < 1) fail('InvalidRestReadOriginal');
  const n = BigInt(count);
  // Each original: limits vector9, input Buffer control1, returned capsule
  // record7, two closures (2+4 slots), native page quantity/Some5.
  const originals = n * (9n + 1n + 7n + 2n + 4n + 5n);
  // Original quote, request and target vectors, plus the two-field wrapper.
  const vectors = 3n * (1n + n) + 3n;
  const retained = originals + vectors;
  // Source's existing deep freezer walks the wrapper/request/target fields.
  // Keep its own-values vectors, pending-reference growth and both constructor
  // map-call argument vectors live; functions hide opaque parser backing.
  // Wrapper own-values3; target/request vector values2*(1+n); pending
  // references at most2*n+3 with old+grown arrays2*(1+2*(2*n+3)).
  // Capsule own-values7, metadata check vector4 and its closure1 per read.
  const freeze = 3n + 2n * (1n + n) + 2n * (1n + 2n * (2n * n + 3n)) + 12n * n;
  return [retained, 0n, 0n, retained + freeze, 0n, 0n];
}
