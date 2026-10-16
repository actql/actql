// Connector DATA only. Common checks the complete original role/Catalog pair;
// neither this wire nor its CID is a Ref, installation or physical I/O grant.
import {checked} from '../../../host-common/runtime-result.mjs';
const fail = code => { throw Object.assign(new Error(code), {code}); };
const integer = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
function argumentsFor(connectorId, {maxBytes, maxNodes, maxDepth}) {
  if (typeof connectorId !== 'string') fail('GcsInvalidUploadDeclarationBinding');
  if (![maxBytes, maxNodes, maxDepth].every(integer)) fail('GcsInvalidUploadDeclarationLimits');
  return [connectorId, maxBytes, maxNodes, maxDepth];
}
function declarationResult(moon, result) {
  try { return checked(result); }
  catch (failure) {
    if (failure?.code !== 'MoonBitHostFailure') throw failure;
    const code = moon.gcsUploadDeclarationFailureCode(failure.cause);
    throw Object.assign(new Error(code, {cause: failure.cause}), {code});
  }
}
export function gcsUploadCommandDeclaration(moon, connectorId, limits) {
  return declarationResult(moon, moon.gcsUploadCommandJson(...argumentsFor(connectorId, limits)));
}
export function gcsUploadCatalogDeclaration(moon, declaredWire, connectorId, limits) {
  const args = argumentsFor(connectorId, limits);
  if (typeof declaredWire !== 'string') fail('GcsInvalidUploadDeclaration');
  return declarationResult(moon, moon.gcsUploadCatalogJson(declaredWire, ...args));
}
