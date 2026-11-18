// Public DATA-only author validation through this package's SAME shipped
// Common. No Host/session/store/secret/transport is constructed or imported.
import {createRequire} from 'node:module';
import {exchangeLimits} from './adapters/host-common/http-exchange.mjs';
import {runtimeField, runtimeIsOk, runtimeIsError, runtimeIsBoxedSome}
  from './adapters/host-common/compiler-binding.generated.mjs';

const require = createRequire(import.meta.url);
const unavailable = () => Object.assign(new Error(
  'RestAuthoringValidatorUnavailable: install a matching @actql/local-node package before connector build'),
{code: 'RestAuthoringValidatorUnavailable'});
const invalid = code => Object.assign(new TypeError(`InvalidRestReadDeclaration:${code}`),
  {code: 'InvalidRestReadDeclaration'});
let library;
function validator() {
  if (library !== undefined) return library;
  let moon;
  try {moon = require('@actql/local-node/runtime');}
  catch (cause) {
    if (cause?.code === 'MODULE_NOT_FOUND' || cause?.code === 'ERR_PACKAGE_PATH_NOT_EXPORTED') throw unavailable();
    throw cause;
  }
  const methods = Object.fromEntries(['clientProgramRowSourceGetReadAuthorLimits',
    'clientProgramRowSourceAdmitGetRead', 'clientProgramRowSourceGetReadWire',
    'clientProgramRowSourceGetReadIssueCode'].map(name => {
    const field = Object.getOwnPropertyDescriptor(moon, name);
    if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') throw unavailable();
    return [name, field.value.bind(moon)];
  }));
  const selected = methods.clientProgramRowSourceGetReadAuthorLimits(exchangeLimits.maxQueryPairs,
    exchangeLimits.maxQueryBytes, exchangeLimits.maxHeaderNameBytes, exchangeLimits.maxHeaderValueBytes);
  if (!runtimeIsBoxedSome(selected)) throw unavailable();
  const limits = runtimeField(selected, 0);
  if (!Array.isArray(limits) || limits.length !== 8 || !limits.every(Number.isSafeInteger) || limits[0] <= 0) throw unavailable();
  library = Object.freeze({...methods, limits: Object.freeze(limits)});
  return library;
}

// The String is already bounded nonsecret author DATA. The Core validator
// retains its own checked original; callers receive only that original wire,
// never an opaque handle, permission, Request/Run or cleanup acknowledgement.
export function validateRestReadDeclaration(readWire, cursorParameter) {
  if (typeof readWire !== 'string' || !readWire.isWellFormed() ||
      cursorParameter !== undefined && typeof cursorParameter !== 'string') throw invalid('InvalidRead');
  const core = validator();
  if (readWire.length > core.limits[0] || Buffer.byteLength(readWire, 'utf8') > core.limits[0]) throw invalid('InvalidLimits');
  const value = result => {
    if (runtimeIsOk(result)) return runtimeField(result, 0);
    if (runtimeIsError(result)) throw invalid(core.clientProgramRowSourceGetReadIssueCode(runtimeField(result, 0)));
    throw unavailable();
  };
  const read = value(core.clientProgramRowSourceAdmitGetRead(Buffer.from(readWire, 'utf8'),
    cursorParameter !== undefined, cursorParameter ?? '', core.limits));
  return value(core.clientProgramRowSourceGetReadWire(read));
}
