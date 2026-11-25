// Connector DATA only. Common checks the complete original role/Catalog pair;
// neither this wire nor its CID is a Ref, installation or physical I/O grant.
import {checked} from '../../../host-common/runtime-result.mjs';
type UploadLimits = Readonly<{maxBytes: unknown; maxNodes: unknown; maxDepth: unknown}>;
type UploadArguments = [connectorId: string, maxBytes: number, maxNodes: number, maxDepth: number];
type UploadCore = {
  gcsUploadCommandJson(...args: UploadArguments): unknown;
  gcsUploadCatalogJson(declaredWire: string, ...args: UploadArguments): unknown;
  gcsUploadDeclarationFailureCode(cause: unknown): string;
};

const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
const integer = (value: unknown): value is number =>
  Number.isSafeInteger(value) && (value as number) > 0 && (value as number) <= 2147483647;
function argumentsFor(connectorId: unknown, {maxBytes, maxNodes, maxDepth}: UploadLimits): UploadArguments {
  if (typeof connectorId !== 'string') fail('GcsInvalidUploadDeclarationBinding');
  if (![maxBytes, maxNodes, maxDepth].every(integer)) fail('GcsInvalidUploadDeclarationLimits');
  return [connectorId, maxBytes, maxNodes, maxDepth] as UploadArguments;
}
function declarationResult(moon: UploadCore, result: unknown): string {
  // Both selected Core constructors return Result[String, ObjectUploadDeclarationIssue].
  try { return checked(result) as string; }
  catch (failure) {
    if ((failure as {code?: unknown} | null | undefined)?.code !== 'MoonBitHostFailure') throw failure;
    const code = moon.gcsUploadDeclarationFailureCode((failure as Error).cause);
    throw Object.assign(new Error(code, {cause: (failure as Error).cause}), {code});
  }
}
export function gcsUploadCommandDeclaration(moon: UploadCore, connectorId: unknown, limits: UploadLimits) {
  return declarationResult(moon, moon.gcsUploadCommandJson(...argumentsFor(connectorId, limits)));
}
export function gcsUploadCatalogDeclaration(moon: UploadCore, declaredWire: unknown,
  connectorId: unknown, limits: UploadLimits) {
  const args = argumentsFor(connectorId, limits);
  if (typeof declaredWire !== 'string') fail('GcsInvalidUploadDeclaration');
  return declarationResult(moon, moon.gcsUploadCatalogJson(declaredWire, ...args));
}
