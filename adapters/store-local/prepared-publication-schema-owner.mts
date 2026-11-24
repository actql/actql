import {createHash, randomUUID} from 'node:crypto';
import type {Stats} from 'node:fs';
import {lstat, readdir, rename, unlink} from 'node:fs/promises';
import {resolve} from 'node:path';
import {retainFirstAndLatestCleanupError} from '../host-common/managed-failure.mjs';
import {cidPattern, exactKeys, fail, PublicationStoreError, quantity, readBounded, writeExclusive}
  from './publication-store-io.mjs';

type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type SchemaGeneration = Readonly<{device: string; inode: string}>;
type PreparedSchemaRecord = Readonly<{
  version: 'actql-local-prepared-schema/0.1';
  semantic_cid: string;
  physical_cid: string;
  byte_count: number;
  removable: boolean;
  run_definition_cid: unknown;
}> & (SchemaGeneration | Readonly<{device: null; inode: null}>);
type SchemaHolder = {
  path: string | undefined;
  active: boolean;
  releasing: Promise<boolean> | undefined;
  errors: unknown[];
  runDefinitionCid: unknown;
};
type SchemaGroup<Removal> = {
  record: PreparedSchemaRecord;
  removable: boolean;
  holders: Set<SchemaHolder>;
  unconfirmedPhysical: (SchemaGeneration & Readonly<{removal: Removal; bytes: number}>) | undefined;
  pendingAliasSync: boolean;
  generation: SchemaGeneration | undefined;
  generationRetired: boolean;
};
type PhysicalGenerationRow = SchemaGeneration & Readonly<{byte_count: number}>;
type ReclaimableCustody = {
  record: SchemaGeneration & Readonly<{material_generation_cid: unknown}>;
  accounted: boolean;
};
type StoredSchema = Readonly<{
  semanticCid: string;
  physical: Readonly<{cid: string; bytes: number; created: boolean}>;
  created: boolean;
}>;
type PreparedSchemaStatus = Readonly<{pending: boolean; errors?: readonly unknown[]}>;
type PreparationCleanup = Readonly<{
  status(): PreparedSchemaStatus | undefined;
  retry(): Promise<unknown>;
}>;
type PreparationCause = (NonNullable<CodedCause> & Readonly<{cleanupHandle?: PreparationCleanup}>) | null | undefined;
type PreparedSchemaFailure = PublicationStoreError & {
  cleanupPending: true;
  cleanupHandle: PreparationCleanup;
  primaryFailure: unknown;
};
type SchemaPorts<Removal> = Readonly<{
  active(): unknown;
  cidHex(value: unknown): string;
  contractPath(cid: string): string;
  objectPath(cid: string): string;
  preparedSchemaPath(token: string): string;
  syncDirectory(path: string): unknown;
  withSemanticCommit<Result>(operation: () => Promise<Result>): Promise<Result>;
  currentDeliveryIndex(): Readonly<{physicalObject(cid: string): PhysicalGenerationRow | undefined}> | undefined;
  confirmPhysicalRemovals(objects: Map<string, Removal>): Promise<unknown>;
  rememberPhysicalRemoval(cid: string, bytes: number, state?: Stats): Promise<Removal>;
  metadataContractHasLiveReference(cid: string, excludedRun: undefined): Promise<boolean>;
  materialHasLiveReference(cid: string): Promise<boolean>;
  putSemantic(wire: string, semanticCid: string): Promise<StoredSchema>;
  readSemanticOriginal(cid: string, includeNative: false, retainGeneration: true): Promise<
    Readonly<{bytes: Buffer; physicalCid: string; generation?: SchemaGeneration}>>;
  exactUtf8WireMatches(bytes: Buffer, wire: string): boolean;
}>;

export function createPreparedSchemaOwner<Removal>(
  configuration: Readonly<{maxObjectBytes: number}>,
  preparedSchemasDirectory: string, contractsDirectory: string, objectsDirectory: string,
  custodyNamePattern: RegExp, preparedSchemas: Map<string, SchemaGroup<Removal>>,
  preparedObjects: ReadonlyMap<string, Readonly<{holders: ReadonlySet<unknown>}>>,
  reclaimableCustodies: ReadonlyMap<unknown, ReclaimableCustody>,
  activePhysicalRecordWriters: ReadonlySet<unknown>,
  {active, cidHex, contractPath, objectPath, preparedSchemaPath, syncDirectory,
    withSemanticCommit, currentDeliveryIndex, confirmPhysicalRemovals, rememberPhysicalRemoval,
    metadataContractHasLiveReference, materialHasLiveReference, putSemantic, readSemanticOriginal,
    exactUtf8WireMatches}: SchemaPorts<Removal>,
) {
  const parsePreparedSchema = (bytes: Buffer): PreparedSchemaRecord => {
    let value: unknown;
    try { value = JSON.parse(bytes.toString('utf8')); }
    catch (error) { fail('InvalidPublicationPreparedSchema', error); }
    if (!exactKeys(value, [
      'version', 'semantic_cid', 'physical_cid', 'byte_count', 'removable',
      'run_definition_cid', 'device', 'inode',
    ]) || value.version !== 'actql-local-prepared-schema/0.1' ||
        !cidPattern.test(value.semantic_cid as string) ||
        !cidPattern.test(value.physical_cid as string) ||
        value.semantic_cid !== value.physical_cid ||
        !cidPattern.test(value.run_definition_cid as string) ||
        !quantity(value.byte_count) ||
        typeof value.removable !== 'boolean' ||
        ![value.device, value.inode].every(part => part === null ||
          (typeof part === 'string' && /^(0|[1-9][0-9]*)$/u.test(part))) ||
        (value.device === null) !== (value.inode === null)) {
      fail('InvalidPublicationPreparedSchema');
    }
    return Object.freeze(value) as PreparedSchemaRecord;
  };

  const releasePreparedSchema = (group: SchemaGroup<Removal>, holder: SchemaHolder) => {
    if (!holder.active) return Promise.resolve(false);
    if (holder.releasing !== undefined) return holder.releasing;
    const flight = withSemanticCommit(async () => {
      if (!holder.active) return false;
      if (group.unconfirmedPhysical !== undefined) {
        await confirmPhysicalRemovals(new Map([[group.record.physical_cid,group.unconfirmedPhysical.removal]]));
        for (const custody of reclaimableCustodies.values()) {
          if (custody.record.material_generation_cid ===
                group.record.physical_cid &&
              custody.record.device === group.unconfirmedPhysical.device &&
              custody.record.inode === group.unconfirmedPhysical.inode) {
            custody.accounted = false;
          }
        }
        group.unconfirmedPhysical = undefined;
        group.generationRetired = true;
      }
      if (group.pendingAliasSync) {
        await syncDirectory(contractsDirectory);
        group.pendingAliasSync = false;
      }
      if (group.holders.size === 1 && group.removable &&
          !await metadataContractHasLiveReference(
            group.record.semantic_cid, undefined,
          )) {
        const semanticPath = contractPath(group.record.semantic_cid);
        const physicalPath = objectPath(group.record.physical_cid);
        let physical;
        try { physical = await lstat(physicalPath); }
        catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
        let semantic;
        try { semantic = await lstat(semanticPath); }
        catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
        if (semantic !== undefined) {
          if (physical === undefined || !semantic.isFile() ||
              !physical.isFile() ||
              semantic.size !== group.record.byte_count ||
              physical.size !== group.record.byte_count ||
              semantic.dev !== physical.dev ||
              semantic.ino !== physical.ino) {
            fail('PublicationContractCorrupt');
          }
          if (group.generation !== undefined &&
              (group.generation.device !== String(physical.dev) ||
                group.generation.inode !== String(physical.ino))) {
            group.generationRetired = true;
          }
          if (!group.generationRetired) {
            group.generation = {
              device: String(physical.dev), inode: String(physical.ino),
            };
            await unlink(semanticPath);
            group.pendingAliasSync = true;
            await syncDirectory(contractsDirectory);
            group.pendingAliasSync = false;
          }
        }
        if (!group.generationRetired && physical === undefined &&
            group.generation !== undefined) {
          // A crash can leave the original quota row after unlink, before
          // its directory ACK. Only this prepared generation can settle it;
          // absence never refunds a successor with the same content CID.
          const original = currentDeliveryIndex()!.physicalObject(group.record.physical_cid);
          if (original !== undefined &&
              original.byte_count === group.record.byte_count &&
              original.device === group.generation.device &&
              original.inode === group.generation.inode) {
            const removal = await rememberPhysicalRemoval(group.record.physical_cid, group.record.byte_count);
            group.unconfirmedPhysical = {bytes: group.record.byte_count, ...group.generation, removal};
            await confirmPhysicalRemovals(new Map([[group.record.physical_cid, removal]]));
            group.unconfirmedPhysical = undefined;
          }
          group.generationRetired = true;
        }
        if (!group.generationRetired && physical !== undefined &&
            group.generation !== undefined &&
            String(physical.dev) === group.generation.device &&
            String(physical.ino) === group.generation.inode &&
            physical.nlink <= 2 &&
            !(preparedObjects.get(group.record.physical_cid)?.holders.size! > 0) &&
            !await materialHasLiveReference(group.record.physical_cid)) {
          const remaining = await lstat(physicalPath);
          if (remaining.nlink === 1) {
            const removal = await rememberPhysicalRemoval(group.record.physical_cid,group.record.byte_count,remaining);
            group.unconfirmedPhysical = {
              removal,
              bytes: group.record.byte_count,
              device: String(remaining.dev),
              inode: String(remaining.ino),
            };
            await confirmPhysicalRemovals(new Map([[group.record.physical_cid, removal]]));
            for (const custody of reclaimableCustodies.values()) {
              if (custody.record.material_generation_cid ===
                    group.record.physical_cid &&
                  custody.record.device === group.unconfirmedPhysical.device &&
                  custody.record.inode === group.unconfirmedPhysical.inode) {
                custody.accounted = false;
              }
            }
            group.unconfirmedPhysical = undefined;
          }
        }
      }
      if (holder.path !== undefined) {
        try { await unlink(holder.path!); }
        catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
        await syncDirectory(preparedSchemasDirectory);
      }
      group.holders.delete(holder);
      holder.active = false;
      if (group.holders.size === 0) {
        preparedSchemas.delete(group.record.semantic_cid);
      }
      return true;
    });
    holder.releasing = flight.catch(error => {
      retainFirstAndLatestCleanupError(holder.errors, error);
      throw error;
    }).finally(() => { holder.releasing = undefined; });
    return holder.releasing;
  };

  const preparedSchemaHandle = (group: SchemaGroup<Removal>, holder: SchemaHolder) => Object.freeze({
    status: () => Object.freeze({
      pending: holder.active,
      errors: Object.freeze([...holder.errors]),
    }),
    release: () => releasePreparedSchema(group, holder),
    async retry() {
      if (holder.active) await releasePreparedSchema(group, holder);
      return Object.freeze({
        pending: holder.active,
        errors: Object.freeze([...holder.errors]),
      });
    },
  });

  const adoptPreparedSchemas = async (cids: Iterable<string>, runDefinitionCid: string) => {
    for (const cid of new Set(cids)) {
      const group = preparedSchemas.get(cid);
      if (group === undefined) continue;
      const adopted = [...group.holders].filter(holder =>
        holder.runDefinitionCid === runDefinitionCid);
      const durable = adopted.filter(holder => holder.path !== undefined);
      for (const holder of durable) {
        try { await unlink(holder.path!); }
        catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
      }
      if (durable.length !== 0) await syncDirectory(preparedSchemasDirectory);
      for (const holder of adopted) {
        holder.active = false;
        group.holders.delete(holder);
      }
      if (group.holders.size === 0) preparedSchemas.delete(cid);
    }
  };

  const putPreparedResultSchema = (wire: unknown, semanticCid: string, runDefinitionCid: string) =>
    withSemanticCommit(async () => {
      active();
      if (typeof wire !== 'string' ||
          Buffer.byteLength(wire, 'utf8') > configuration.maxObjectBytes) {
        fail('InvalidPublicationSemanticWire');
      }
      cidHex(semanticCid);
      cidHex(runDefinitionCid);
      const bytes = Buffer.from(wire, 'utf8');
      const physicalCid = `sha256:${createHash('sha256')
        .update(bytes).digest('hex')}`;
      if (semanticCid !== physicalCid) {
        fail('PublicationObjectIdentityMismatch');
      }
      let group = preparedSchemas.get(semanticCid);
      if (group === undefined) {
        let existing;
        try { existing = await lstat(contractPath(semanticCid)); }
        catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
        group = {
          record: Object.freeze({
            version: 'actql-local-prepared-schema/0.1',
            semantic_cid: semanticCid,
            physical_cid: physicalCid,
            byte_count: bytes.byteLength,
            removable: existing === undefined,
            run_definition_cid: runDefinitionCid,
            device: null,
            inode: null,
          }),
          removable: existing === undefined,
          holders: new Set(),
          unconfirmedPhysical: undefined,
          pendingAliasSync: false,
          generation: undefined,
          generationRetired: false,
        };
        preparedSchemas.set(semanticCid, group);
      }
      const token = randomUUID();
      const holder: SchemaHolder = {
        // A visible link from an unsettled writer is not a durable original.
        // Keep the existing write/ACK protocol until those duties complete.
        path: group.removable || activePhysicalRecordWriters.size !== 0
          ? preparedSchemaPath(token) : undefined,
        active: true,
        releasing: undefined, errors: [], runDefinitionCid,
      };
      const record = Object.freeze({
        ...group.record, run_definition_cid: runDefinitionCid,
      });
      group.holders.add(holder);
      const prepared = preparedSchemaHandle(group, holder);
      try {
        let stored, generation;
        if (holder.path !== undefined) {
          // Newly created bytes need the existing crash-reclamation marker.
          await writeExclusive(holder.path,
            Buffer.from(JSON.stringify(record), 'utf8'));
          await syncDirectory(preparedSchemasDirectory);
          stored = await putSemantic(wire, semanticCid);
        } else {
          // An already owned immutable schema creates no new durable state.
          // Acquire this operation's real original; retain its live holder,
          // without rewriting crash markers for an allocation we cannot delete.
          const original = await readSemanticOriginal(semanticCid, false, true);
          if (original.physicalCid !== physicalCid ||
              !exactUtf8WireMatches(original.bytes, wire)) {
            fail('PublicationObjectIdentityMismatch');
          }
          stored = Object.freeze({semanticCid, physical: Object.freeze({
            cid: physicalCid, bytes: original.bytes.byteLength, created: false,
          }), created: false});
          generation = original.generation;
        }
        if (generation === undefined) {
          // A writer still needs its actual final aliases observed. An
          // existing body's reader already checked these same inode/extent
          // facts while acquiring its bytes in this preparation.
          const physical = await lstat(objectPath(physicalCid));
          const semantic = await lstat(contractPath(semanticCid));
          if (!physical.isFile() || !semantic.isFile() ||
              physical.dev !== semantic.dev ||
              physical.ino !== semantic.ino ||
              physical.size !== bytes.byteLength) {
            fail('PublicationPreparedSchemaGenerationMismatch');
          }
          generation = Object.freeze({
            device: String(physical.dev), inode: String(physical.ino),
          });
        }
        if (group.generation !== undefined &&
            (group.generation.device !== generation.device ||
              group.generation.inode !== generation.inode)) {
          fail('PublicationPreparedSchemaGenerationMismatch');
        }
        if (holder.path !== undefined) {
          const staged = resolve(preparedSchemasDirectory,
            `.staging-${randomUUID()}.json`);
          await writeExclusive(staged, Buffer.from(JSON.stringify({
            ...record, ...generation,
          }), 'utf8'));
          await rename(staged, holder.path);
          await syncDirectory(preparedSchemasDirectory);
        }
        group.generation = generation;
        return Object.freeze({...stored, prepared});
      } catch (error) {
        // A new allocation keeps its durable marker. Every path retains the
        // same acquired reader/holder cleanup without resending any data.
        const cause = error as PreparationCause;
        const failure = new PublicationStoreError(
          typeof cause?.code === 'string'
            ? cause.code : 'PublicationPreparedSchemaFailed', error,
        ) as PreparedSchemaFailure;
        failure.cleanupPending = true;
        failure.cleanupHandle = Object.freeze({
          status: () => Object.freeze({
            pending: prepared.status().pending ||
              cause?.cleanupHandle?.status()?.pending === true,
            errors: Object.freeze([
              ...prepared.status().errors,
              ...(cause?.cleanupHandle?.status()?.errors ?? []),
            ]),
          }),
          async retry() {
            if (prepared.status().pending) await prepared.retry();
            if (cause?.cleanupHandle?.status()?.pending === true) {
              await cause.cleanupHandle.retry();
            }
            return this.status();
          },
        });
        failure.primaryFailure = error;
        throw failure;
      }
    });

  const recoverPreparedSchemas = async () => {
    const names = await readdir(preparedSchemasDirectory);
    // No pending original means there is no schema recovery transition to
    // confirm. Selected reads and later mutations keep their own real ACKs.
    if (names.length === 0) return Object.freeze([]);
    await syncDirectory(contractsDirectory);
    await syncDirectory(objectsDirectory);
    const recovered: {group: SchemaGroup<Removal>; holder: SchemaHolder}[] = [];
    for (const name of names) {
      if (!custodyNamePattern.test(name)) {
        fail('InvalidPublicationPreparedSchema');
      }
      const path = resolve(preparedSchemasDirectory, name);
      const record = parsePreparedSchema(await readBounded(
        path, configuration.maxObjectBytes,
      ));
      let group = preparedSchemas.get(record.semantic_cid);
      if (group === undefined) {
        group = {
          record, removable: record.removable,
          holders: new Set(), unconfirmedPhysical: undefined,
          pendingAliasSync: false,
          generation: record.device === null ? undefined : {
            device: record.device, inode: record.inode,
          },
          generationRetired: false,
        };
        preparedSchemas.set(record.semantic_cid, group);
      } else if (group.record.physical_cid !== record.physical_cid ||
          group.record.byte_count !== record.byte_count ||
          group.removable !== record.removable ||
          (group.generation !== undefined && record.device !== null &&
            (group.generation.device !== record.device ||
              group.generation.inode !== record.inode))) {
        fail('InvalidPublicationPreparedSchema');
      }
      if (record.device !== null) {
        group.generation = {
          device: record.device, inode: record.inode,
        };
      }
      const holder: SchemaHolder = {
        path, active: true, releasing: undefined, errors: [],
        runDefinitionCid: record.run_definition_cid,
      };
      group.holders.add(holder);
      recovered.push({group, holder});
    }
    for (const {group, holder} of recovered) {
      await releasePreparedSchema(group, holder);
    }
    return Object.freeze(recovered.map(({group}) =>
      group.record.semantic_cid));
  };

  return {adoptPreparedSchemas, putPreparedResultSchema, recoverPreparedSchemas};
}
