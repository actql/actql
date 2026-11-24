// Capture the actual startup facility at the Request Journal's module initialization.
import {DatabaseSync, StatementSync} from 'node:sqlite';
import {realpathSync} from 'node:fs';
import * as facilityFs from 'node:fs';
import * as facilityFsPromises from 'node:fs/promises';
import * as facilityCrypto from 'node:crypto';
import {types as utilTypes} from 'node:util';
import facilityFields from './host-journal-facility-fields.cjs';
import {fail} from './client-request-journal-sql.mjs';

export function captureOriginalClientRequestJournalFacility() {
  const facilityDescriptor = Object.getOwnPropertyDescriptor;
  const facilityRealpath = realpathSync;
  const facilityNativeRealpath: typeof realpathSync.native | undefined = facilityDescriptor(facilityRealpath, 'native')?.value;
  const nativePathOptions = Object.freeze({__proto__: null, encoding: 'utf8'});
  const facilityHasOwn = Object.hasOwn, facilityIsProxy = utilTypes.isProxy;
  const facilityDatabase = DatabaseSync, facilityStatement = StatementSync;
  const facilityIteratorProperty = facilityDescriptor(globalThis, 'Iterator');
  // No getter/Proxy is evaluated while capturing this actual namespace. Missing
  // or unsupported originals remain absent and the selected fence refuses them.
  const facilityIteratorConstructor = facilityIteratorProperty !== undefined &&
    facilityHasOwn(facilityIteratorProperty, 'value') &&
    typeof facilityIteratorProperty.value === 'function' &&
    !facilityIsProxy(facilityIteratorProperty.value) ? facilityIteratorProperty.value as object : undefined;
  const facilityOperations = Object.freeze(([
    [facilityDatabase.prototype, 'open'], [facilityDatabase.prototype, 'close'],
    [facilityDatabase.prototype, 'prepare'], [facilityDatabase.prototype, 'exec'],
    [facilityStatement.prototype, 'get'], [facilityStatement.prototype, 'run'],
    [facilityStatement.prototype, 'iterate'],
  ] as const).map(([receiver, name]) => Object.freeze({receiver, name,
    property: facilityDescriptor(receiver, name)})));
  const facilityPlatformOperations = Object.freeze(([
    ['fs',facilityFs],['crypto',facilityCrypto],['constants',facilityFs.constants],
    ['promises',facilityFsPromises],
    ['iteratorGlobal',globalThis],['iteratorConstructor',facilityIteratorConstructor],
    ['directory',facilityFs.Dir.prototype],['hash',facilityCrypto.Hash.prototype],
    ['hmac',facilityCrypto.Hmac.prototype],['realpath',facilityRealpath],
  ] as const).flatMap(([group,receiver]) => facilityFields[group].map(name => Object.freeze({
    group,receiver,name,property:receiver === undefined ? undefined : facilityDescriptor(receiver,name),
  }))));

  function originalJournalFacilityField(value: unknown, name: string): unknown {
    if (value === null || typeof value !== 'object' || facilityIsProxy(value)) {
      fail('ClientRequestJournalFacilityUnavailable');
    }
    const property = facilityDescriptor(value,name);
    if (property === undefined || !facilityHasOwn(property,'value')) {
      fail('ClientRequestJournalFacilityUnavailable');
    }
    return property.value;
  }

  // Fixed namespace forwarder for the selected startup's actual node:sqlite
  // originals. This observes correspondence/currentness, not capacity, a new
  // installation or authority. No caller callback or equal label is a native
  // constructor, and restoration after a detected change cannot revive it.
  let facilityChanged = false;
  function assertOriginalClientRequestJournalFacilityCurrent(database: unknown, statement: unknown, nativeBindings?: unknown): void {
    if (database !== facilityDatabase || statement !== facilityStatement) {
      fail('ClientRequestJournalFacilityUnavailable');
    }
    for (const {receiver, name, property} of facilityOperations) {
      const current = facilityDescriptor(receiver, name);
      if (property === undefined || current === undefined ||
          typeof property.value !== 'function' || current.value !== property.value ||
          current.get !== property.get || current.set !== property.set ||
          current.writable !== property.writable || current.configurable !== property.configurable ||
          current.enumerable !== property.enumerable) facilityChanged = true;
    }
    if (nativeBindings !== undefined) {
      // This is correspondence DATA from the actual early prefix, not a new
      // facility issuer. A foreign table cannot poison another original's
      // currentness; a detected change in the real operations is irreversible.
      for (const {group,name,property} of facilityPlatformOperations) {
        const selected = originalJournalFacilityField(nativeBindings,group);
        if (property === undefined || !facilityHasOwn(property, 'value') ||
            originalJournalFacilityField(selected,name) !== property.value) {
          fail('ClientRequestJournalFacilityUnavailable');
        }
      }
      for (const {receiver,name,property} of facilityPlatformOperations) {
        const current = receiver === undefined ? undefined : facilityDescriptor(receiver,name);
        if (current === undefined || current.value !== property!.value ||
            current.get !== property!.get || current.set !== property!.set ||
            current.writable !== property!.writable || current.configurable !== property!.configurable ||
            current.enumerable !== property!.enumerable) facilityChanged = true;
      }
    }
    if (facilityChanged) fail('ClientRequestJournalFacilityUnavailable');
  }

  return {facilityNativeRealpath, facilityRealpath, nativePathOptions, assertOriginalClientRequestJournalFacilityCurrent};
}
