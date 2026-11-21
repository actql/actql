import {cidPattern, exactKeys, fail, quantity, readBounded} from './publication-store-io.mjs';

type HoldingBounds = Readonly<{maxObjects: number; maxObjectBytes: number}>;
type HoldingReadDemand = NonNullable<Parameters<typeof readBounded>[5]> & {
  data(fields: number, nodes: number, textUnits: number): unknown;
  finish(): unknown;
};
type CodedCause = Readonly<{code?: unknown}> | null | undefined;

// RegExp.test retains the original coercion. A parsed CID field is still
// unknown until the existing selected identity or physical lookup checks it.
type PhysicalHoldingObject = Readonly<{cid: unknown; byte_count: number}>;
type PhysicalHoldingRecord = Readonly<{
  version: 'actql-local-physical-holding/0.1';
  namespace: string;
  holding_cid: unknown;
  manifest_cid: unknown;
  objects: readonly PhysicalHoldingObject[];
}>;
type SelectedPhysicalHoldingRecord = PhysicalHoldingRecord & Readonly<{holding_cid: string}>;

export const closedMetadataObjectExtent = (value: Readonly<Record<string, unknown>>) => {
  let nodes = 1, textUnits = 0;
  for (const key of Object.keys(value)) {
    nodes++; textUnits += key.length;
    if (typeof value[key] === 'string') textUnits += value[key].length;
  }
  return {nodes, textUnits};
};

export function createPhysicalHoldingRecordReader(
  configuration: HoldingBounds, physicalHoldingNamespaces: readonly string[],
) {
  const parsePhysicalHolding = (bytes: Buffer): PhysicalHoldingRecord => {
    let value: unknown;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) {
      fail('InvalidPublicationPhysicalHoldingStore', error);
    }
    if (!exactKeys(value, [
      'version', 'namespace', 'holding_cid', 'manifest_cid', 'objects',
    ]) ||
        value.version !== 'actql-local-physical-holding/0.1' ||
        !physicalHoldingNamespaces.includes(value.namespace as string) ||
        !cidPattern.test(value.holding_cid as string) ||
        !cidPattern.test(value.manifest_cid as string) ||
        !Array.isArray(value.objects) ||
        value.objects.length > configuration.maxObjects ||
        value.objects.some((object: unknown) => !exactKeys(object, [
          'cid', 'byte_count',
        ]) || !cidPattern.test(object.cid as string) ||
          !quantity(object.byte_count) ||
          object.byte_count > configuration.maxObjectBytes)) {
      fail('InvalidPublicationPhysicalHoldingStore');
    }
    const sizes = new Map<unknown, number>();
    for (const object of value.objects as PhysicalHoldingObject[]) {
      const existing = sizes.get(object.cid);
      if (existing !== undefined && existing !== object.byte_count) {
        fail('InvalidPublicationPhysicalHoldingStore');
      }
      sizes.set(object.cid, object.byte_count);
    }
    return Object.freeze({
      ...value,
      objects: Object.freeze((value.objects as PhysicalHoldingObject[]).map(object =>
        Object.freeze({...object}))),
    }) as PhysicalHoldingRecord;
  };

  const readPhysicalHoldingAt = async (path: string, holdingCid: string, readDemand?: HoldingReadDemand) => {
    let bytes: Awaited<ReturnType<typeof readBounded>>;
    try { bytes = await readBounded(path, configuration.maxObjectBytes, undefined, undefined, false, readDemand); }
    catch (error) {
      if ((error as CodedCause)?.code === 'ENOENT') return undefined;
      throw error;
    }
    const record = parsePhysicalHolding(bytes);
    if (record.holding_cid !== holdingCid) {
      fail('InvalidPublicationPhysicalHoldingStore');
    }
    if (readDemand !== undefined) {
      const extent = closedMetadataObjectExtent(record);
      for (const object of record.objects) {
        const child = closedMetadataObjectExtent(object);
        extent.nodes += child.nodes; extent.textUnits += child.textUnits;
      }
      readDemand.data(10, extent.nodes, extent.textUnits);
      readDemand.finish();
    }
    return record as SelectedPhysicalHoldingRecord;
  };

  const admitPhysicalHolding = (value: unknown) => {
    if (!exactKeys(value, [
      'version', 'namespace', 'holding_cid', 'manifest_cid', 'objects',
    ]) || !Array.isArray(value.objects) ||
        value.objects.some((object: unknown) => !exactKeys(object, [
          'cid', 'byte_count',
        ]))) {
      fail('InvalidPublicationPhysicalHoldingStore');
    }
    const record = {
      version: value.version,
      namespace: value.namespace,
      holding_cid: value.holding_cid,
      manifest_cid: value.manifest_cid,
      objects: (value.objects as ReadonlyArray<Readonly<Record<'cid' | 'byte_count', unknown>>>).map(object => ({
        cid: object?.cid,
        byte_count: object?.byte_count,
      })),
    };
    const bytes = Buffer.from(JSON.stringify(record), 'utf8');
    if (bytes.byteLength > configuration.maxObjectBytes) {
      fail('PublicationObjectLimit');
    }
    return Object.freeze({
      record: parsePhysicalHolding(bytes),
      bytes,
    });
  };

  return {parsePhysicalHolding, readPhysicalHoldingAt, admitPhysicalHolding};
}

export function createPhysicalHoldingObjectVerifier<Physical extends Readonly<{bytes: number}>>(
  verifyObject: (cid: unknown) => Promise<Physical>,
) {
  return async (record: PhysicalHoldingRecord) => {
    const verified = new Map<unknown, Physical>();
    for (const object of record.objects) {
      if (verified.has(object.cid)) continue;
      const physical = await verifyObject(object.cid);
      if (physical.bytes !== object.byte_count) {
        fail('InvalidPublicationPhysicalHoldingStore');
      }
      verified.set(object.cid, physical);
    }
    return verified;
  };
}
