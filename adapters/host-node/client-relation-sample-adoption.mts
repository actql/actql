// The Request Journal owns this optional durable table. Its presence alone
// grants neither a live Sample writer nor authority to disclose stored data.
import {createHash} from 'node:crypto';
import {validWireSampleRelationShape} from '../../packages/client-wire/index.mjs';

import type {WireRunRef} from '../../packages/client-wire/index.js';
import type {WireSampleCapture, WireSampleSource} from '../../packages/client-wire/interactive-control.generated.js';
import type {JournalSqlConnection} from './client-request-journal-sql.mjs';
import type {createJournalAttempts} from './client-request-journal-attempts.mjs';

type Statement = ReturnType<JournalSqlConnection['prepare']>;
type SampleLimits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type SampleProofs = Readonly<{
  sample_source_generation: Pick<WireSampleSource, 'run_ref' | 'compiled_plan_cid' | 'logical_map_cid' |
    'step_id' | 'carrier_contract_cid'> & {
      self_cid: string; output_port_id: string; carrier: 'relation'; committed_generation: string;
      producer_occurrence: {start_revision: string; attempt_sequence: string};
    };
  sample_original_capture: Pick<WireSampleCapture, 'strategy'> & {
    self_cid: string; source_generation_cid: string; control_admission_cid: string; resolved_profile_cid: string;
    max_bytes: string; max_items: number; max_artifacts: number; ttl_seconds: number; required: boolean;
  };
  sample_emission_provenance: Pick<WireSampleCapture, 'sampled_items' | 'total' | 'completeness' | 'truncation'> & {
    self_cid: string; relation_prefix_cid: string; ordering_evidence_cid: string | null;
    source_generation_cid: string; original_capture_cid: string;
  };
  sample_reference: {self_cid: string; run_ref: WireRunRef; output_port_id: string;
    original_capture_cid: string; emission_provenance_cid: string};
  sample_adoption_receipt: {self_cid: string; run_ref: WireRunRef; sample_ref_cid: string; expires_at_epoch_ms: string};
}>;
type ProofName = keyof SampleProofs;
type SampleEvidenceControl = Readonly<{
  admitRunEvidence(name: ProofName, wire: string, limits: SampleLimits): {name: string; wire: string; identity: string};
  sealRunEvidence(name: ProofName, wire: string, limits: SampleLimits): {name: string; wire: string; identity: string};
}>;
type SampleOwnerStart = NonNullable<ReturnType<Statement['get']>>;
type SampleProofInput = Readonly<{generation: unknown; capture: unknown; emission: unknown; reference: unknown}>;
type SampleCustody = Readonly<{current(): unknown; reserve(bytes: number): unknown}>;
type SampleLoan = Readonly<{generation: string; capture: string; emission: string; reference: string; relation: string;
  current(): unknown; fundedBytes: number}>;
type SampleAdoptionOriginal = Readonly<{
  revision: number; controlAdmissionCid: string; resolvedProfileCid: string;
  matchesAdoption(source: SampleProofs['sample_source_generation'], capture: SampleProofs['sample_original_capture']): unknown;
  visitAdoption(ticket: object, use: (loan: SampleLoan) => unknown): unknown;
}>;
type SampleReadSelection = Readonly<{compiledPlanCid: string; logicalMapCid: string; stepId: string;
  outputPortId: string; carrierContractCid: string; maxBytes: number; sampleRefCid?: string}>;
type SampleProducerOccurrence = Readonly<{startRevision: number; generation: string; attemptSequence: string}>;
type SampleLookupArgs = [definition: string, sample: string, namespace: string, authority: string];
type SampleStorage = Readonly<{
  ensureOpen(): unknown;
  transact: ReturnType<typeof createJournalAttempts>['transact'];
  now(): number;
  maxRecords: number;
  maxWireBytes: number;
  createSupported: boolean;
}>;

export const relationSampleStartTable = `CREATE TABLE client_relation_sample_starts (
  run_definition_cid TEXT PRIMARY KEY REFERENCES client_requests(run_definition_cid) ON DELETE CASCADE,
  namespace_id TEXT NOT NULL,
  authority_scope_cid TEXT NOT NULL,
  submitted_intent_cid TEXT NOT NULL,
  control_admission_cid TEXT NOT NULL,
  resolved_profile_cid TEXT NOT NULL,
  start_revision INTEGER NOT NULL CHECK (start_revision BETWEEN 1 AND 2147483647)
) STRICT`;
export function inspectRelationSampleStartStorage(database: JournalSqlConnection) {
  const row = database.prepare("SELECT substr(sql, 1, ?) AS sql FROM sqlite_master WHERE type = 'table' AND name = 'client_relation_sample_starts'")
    .get(relationSampleStartTable.length + 1);
  if (row !== undefined && row.sql !== relationSampleStartTable) fail('UnknownClientRequestJournalFormat');
  return row !== undefined;
}

export const relationSampleAdoptionTable = `CREATE TABLE client_relation_sample_adoptions (
  run_definition_cid TEXT NOT NULL REFERENCES client_relation_sample_starts(run_definition_cid) ON DELETE CASCADE,
  sample_ref_cid TEXT NOT NULL,
  source_generation_cid TEXT NOT NULL,
  output_port_id TEXT NOT NULL,
  original_capture_cid TEXT NOT NULL,
  emission_provenance_cid TEXT NOT NULL,
  expires_at INTEGER NOT NULL CHECK (expires_at > 0),
  journal_receipt_ordinal INTEGER NOT NULL CHECK (journal_receipt_ordinal > 0),
  run_receipt_ordinal INTEGER NOT NULL CHECK (run_receipt_ordinal > 0),
  source_generation_wire TEXT,
  capture_wire TEXT,
  emission_wire TEXT,
  reference_wire TEXT,
  receipt_wire TEXT NOT NULL,
  relation_wire TEXT,
  CHECK ((relation_wire IS NULL) = (source_generation_wire IS NULL) AND
    (relation_wire IS NULL) = (capture_wire IS NULL) AND
    (relation_wire IS NULL) = (emission_wire IS NULL) AND
    (relation_wire IS NULL) = (reference_wire IS NULL)),
  PRIMARY KEY (run_definition_cid, sample_ref_cid),
  UNIQUE (run_definition_cid, source_generation_cid),
  UNIQUE (run_definition_cid, output_port_id, sample_ref_cid),
  UNIQUE (journal_receipt_ordinal),
  UNIQUE (run_definition_cid, run_receipt_ordinal)
) STRICT`;

const fail: (code: string, cause?: unknown) => never = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const cid = (value: unknown): value is string => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const sameRef = (left: WireRunRef | undefined, right: WireRunRef) => left?.namespaceId === right.namespaceId &&
  left.authorityScopeCid === right.authorityScopeCid && left.runDefinitionCid === right.runDefinitionCid;
const sampleFailure = (error: unknown) => {
  const code = (error as {code?: unknown} | undefined)?.code;
  return typeof code === 'string' && code.startsWith('ClientRelationSample');
};

const schemaSql = "SELECT substr(sql, 1, ?) AS sql FROM sqlite_master WHERE type = 'table' AND name = 'client_relation_sample_adoptions'";

export function inspectRelationSampleAdoptionStorage(database: JournalSqlConnection) {
  return checkSchema(database.prepare(schemaSql));
}

function checkSchema(statement: Statement) {
  const row = statement.get(relationSampleAdoptionTable.length + 1);
  if (row !== undefined && row.sql !== relationSampleAdoptionTable) fail('UnknownClientRequestJournalFormat');
  return row !== undefined;
}

function requireAuthority(current: () => unknown) {
  if (typeof current !== 'function') fail('ClientRelationSampleDenied');
  const result = current();
  if (result !== true) {
    if (typeof (result as {then?: unknown} | undefined)?.then === 'function') {
      void Promise.resolve(result).catch(() => {});
    }
    fail('ClientRelationSampleDenied');
  }
}

function reserveOriginal(reserve: (bytes: number) => unknown, bytes: number) {
  if (typeof reserve !== 'function' || !Number.isSafeInteger(bytes) || bytes < 1) {
    fail('ClientRelationSampleCapacity');
  }
  const result = reserve(bytes);
  if (result !== undefined) {
    if (typeof (result as {then?: unknown} | undefined)?.then === 'function') {
      void Promise.resolve(result).catch(() => {});
    }
    fail('ClientRelationSampleCapacity');
  }
}

function wireBytes(wire: unknown, maximum: number) {
  // Refuse an unbounded UTF-16 input before scanning for its UTF-8 extent.
  if (typeof wire !== 'string' || wire.length === 0 || wire.length > maximum) fail('ClientRelationSampleCapacity');
  const bytes = Buffer.byteLength(wire, 'utf8');
  if (bytes > maximum) fail('ClientRelationSampleCapacity');
  return bytes;
}

function admitEvidence<Name extends ProofName>(control: SampleEvidenceControl, name: Name,
  wire: unknown, limits: SampleLimits): SampleProofs[Name] {
  if (typeof wire !== 'string') fail('ClientRelationSampleInvalidOriginal');
  try {
    const original = control.admitRunEvidence(name, wire, limits);
    if (original.name !== name || original.wire !== wire || !cid(original.identity)) {
      fail('ClientRelationSampleInvalidOriginal');
    }
    return JSON.parse(original.wire) as SampleProofs[Name];
  } catch (cause) {fail('ClientRelationSampleInvalidOriginal', cause);}
}

function checkSampleEvidence(control: SampleEvidenceControl, ref: WireRunRef,
  start: SampleOwnerStart, limits: SampleLimits, input: SampleProofInput) {
  const source = admitEvidence(control, 'sample_source_generation', input.generation, limits);
  const capture = admitEvidence(control, 'sample_original_capture', input.capture, limits);
  const emission = admitEvidence(control, 'sample_emission_provenance', input.emission, limits);
  const reference = admitEvidence(control, 'sample_reference', input.reference, limits);
  if (!sameRef(source.run_ref, ref) || !sameRef(reference.run_ref, ref) ||
      source.compiled_plan_cid !== start.plan_cid ||
      source.producer_occurrence.start_revision !== String(start.start_revision) ||
      capture.control_admission_cid !== start.control_admission_cid ||
      capture.resolved_profile_cid !== start.resolved_profile_cid ||
      capture.source_generation_cid !== source.self_cid || emission.source_generation_cid !== source.self_cid ||
      emission.original_capture_cid !== capture.self_cid || reference.original_capture_cid !== capture.self_cid ||
      reference.emission_provenance_cid !== emission.self_cid || reference.output_port_id !== source.output_port_id) {
    fail('ClientRelationSampleOriginalChanged');
  }
  return {source, capture, emission, reference};
}

function checkSamplePrefix(capture: SampleProofs['sample_original_capture'],
  emission: SampleProofs['sample_emission_provenance'], relation: string, relationBytes: number) {
  if (BigInt(relationBytes) > BigInt(capture.max_bytes) ||
      BigInt(emission.sampled_items) > BigInt(capture.max_items)) fail('ClientRelationSampleCapacity');
  const prefixCid = 'sha256:' + createHash('sha256').update(relation, 'utf8').digest('hex');
  if (prefixCid !== emission.relation_prefix_cid) fail('ClientRelationSampleOriginalChanged');
}

function retainedReceipt(control: SampleEvidenceControl, ref: WireRunRef, sampleRefCid: string,
  limits: SampleLimits, row: Readonly<Record<string, unknown>>) {
  if (typeof row.expires_at !== 'number' || !Number.isSafeInteger(row.expires_at) || row.expires_at < 1 || typeof row.receipt_wire !== 'string') {
    fail('ClientRelationSampleInvalidOriginal');
  }
  const receipt = admitEvidence(control, 'sample_adoption_receipt', row.receipt_wire, limits);
  if (!sameRef(receipt.run_ref, ref) || receipt.sample_ref_cid !== sampleRefCid ||
      receipt.expires_at_epoch_ms !== String(row.expires_at)) fail('ClientRelationSampleOriginalChanged');
  // Only scalar identity and expiry escape. The funded receipt wire and its
  // decoded tree are local to this call.
  return Object.freeze({kind: 'adopted', sampleRefCid, receiptCid: receipt.self_cid,
    expiresAt: row.expires_at});
}

export function clientRelationSampleAdoptionStorage(database: JournalSqlConnection, {
  ensureOpen, transact, now, maxRecords, maxWireBytes, createSupported,
}: SampleStorage) {
  let schema: Statement | undefined, lookupStart: Statement | undefined, lookupReceipt: Statement | undefined;
  let compareOriginal: Statement | undefined, findGeneration: Statement | undefined;
  let readReceiptOrdinals: Statement | undefined, insert: Statement | undefined, retirePayload: Statement | undefined;
  let probePayload: Statement | undefined, readPayload: Statement | undefined;
  let readExpiredReceipt: Statement | undefined, referenceCandidates: Statement | undefined;
  const stored = () => checkSchema(schema ??= database.prepare(schemaSql));
  const limitsFor = (ref: WireRunRef): SampleLimits => ({maxWireBytes: 1024 + 6 * ref.namespaceId.length,
    maxNodes: 32, maxDepth: 4});
  const receipt = (ref: WireRunRef, sampleRefCid: string, limits: SampleLimits) => {
    lookupReceipt ??= database.prepare(`SELECT a.expires_at, a.relation_wire IS NOT NULL AS has_payload,
      substr(a.source_generation_cid, 1, 72) AS source_generation_cid,
      CASE WHEN length(CAST(a.receipt_wire AS BLOB)) <= ? THEN a.receipt_wire END AS receipt_wire
      FROM client_relation_sample_adoptions a JOIN client_relation_sample_starts s USING (run_definition_cid)
      WHERE a.run_definition_cid = ? AND a.sample_ref_cid = ? AND s.namespace_id = ? AND s.authority_scope_cid = ?`);
    return lookupReceipt.get(limits.maxWireBytes, ref.runDefinitionCid, sampleRefCid,
      ref.namespaceId, ref.authorityScopeCid);
  };
  // Receipts keep their original ordinal after payload retirement. The
  // Journal and the selected profile both retain their cumulative limit.
  // Each MAX seeks the end of its corresponding receipt index.
  const lastReceiptOrdinals = (runDefinitionCid: string) => {
    readReceiptOrdinals ??= database.prepare(`SELECT
      COALESCE((SELECT MAX(journal_receipt_ordinal) FROM client_relation_sample_adoptions), 0) AS journal_ordinal,
      COALESCE((SELECT MAX(run_receipt_ordinal) FROM client_relation_sample_adoptions
        WHERE run_definition_cid = ?), 0) AS run_ordinal`);
    const ordinals = readReceiptOrdinals.get(runDefinitionCid);
    const journalOrdinal = ordinals?.journal_ordinal, runOrdinal = ordinals?.run_ordinal;
    if (typeof journalOrdinal !== 'number' || !Number.isSafeInteger(journalOrdinal) ||
        typeof runOrdinal !== 'number' || !Number.isSafeInteger(runOrdinal) ||
        runOrdinal < 0 || journalOrdinal < runOrdinal) fail('ClientRelationSampleInvalidOriginal');
    return {journal_ordinal: journalOrdinal, run_ordinal: runOrdinal};
  };
  const originalStart = (ref: WireRunRef) => {
    lookupStart ??= database.prepare(`SELECT s.start_revision,
      substr(s.control_admission_cid, 1, 72) AS control_admission_cid,
      substr(s.resolved_profile_cid, 1, 72) AS resolved_profile_cid,
      substr(r.lookup_expires_at, 1, 25) AS lookup_expires_at, r.cancellation_requested,
      r.physical_close_confirmed, r.observed_terminal_outcome IS NULL AS terminal_clear,
      substr(json_extract(r.run_definition_wire, '$.compiled_plan_cid'), 1, 72) AS plan_cid,
      substr(json_extract(r.run_definition_wire, '$.valid_until'), 1, 25) AS valid_until
      FROM client_relation_sample_starts s JOIN client_requests r USING (run_definition_cid)
      WHERE s.run_definition_cid = ? AND s.namespace_id = ? AND s.authority_scope_cid = ? AND
        s.namespace_id = r.namespace_id AND s.authority_scope_cid = r.authority_scope_cid AND
        r.physical_start_reserved = 1`);
    return lookupStart.get(ref.runDefinitionCid, ref.namespaceId, ref.authorityScopeCid);
  };
  // A scoped visit from this exact checked profile has funded the synchronous
  // decode and bind. The Journal's private SQLite transaction owns the copy.
  const adopt = (ref: WireRunRef, original: SampleAdoptionOriginal, control: SampleEvidenceControl, {
    generation, capture, emission, reference, relation, current, fundedBytes,
  }: SampleLoan) => {
    ensureOpen();
    requireAuthority(current);
    const limits = limitsFor(ref);
    const relationBytes = wireBytes(relation, maxWireBytes);
    const bytes = wireBytes(generation, limits.maxWireBytes) + wireBytes(capture, limits.maxWireBytes) +
      wireBytes(emission, limits.maxWireBytes) + wireBytes(reference, limits.maxWireBytes) + relationBytes;
    if (bytes + limits.maxWireBytes !== fundedBytes) fail('ClientRelationSampleCapacity');
    requireAuthority(current);
    return transact('relation_sample_adoption', 'ClientRelationSampleAdoptionUnknown', sampleFailure, () => {
      const start = originalStart(ref);
      if (start === undefined || start.start_revision !== original.revision ||
          start.control_admission_cid !== original.controlAdmissionCid ||
          start.resolved_profile_cid !== original.resolvedProfileCid) {
        fail('ClientRelationSampleOriginalChanged');
      }
      const evidence = checkSampleEvidence(control, ref, start, limits, {
        generation, capture, emission, reference,
      });
      const {source, capture: retainedCapture, emission: retainedEmission, reference: retainedReference} = evidence;
      if (original.matchesAdoption(source, retainedCapture) !== true) fail('ClientRelationSampleOriginalChanged');
      checkSamplePrefix(retainedCapture, retainedEmission, relation, relationBytes);
      const sample = {capture: retainedCapture, sourceGenerationCid: source.self_cid,
        sampleRefCid: retainedReference.self_cid};
      if (!stored()) {
        if (!createSupported) fail('ClientRelationSampleStorageUnavailable');
        database.exec(relationSampleAdoptionTable);
      }
      const prior = receipt(ref, sample.sampleRefCid, limits);
      if (prior !== undefined) {
        if (prior.source_generation_cid !== sample.sourceGenerationCid) {
          fail('ClientRelationSampleOriginalChanged');
        }
        if (prior.has_payload === 1) {
          // Compare SQLite's retained content directly without materializing
          // it. After retirement the independently reverified reference
          // binds the exact evidence chain and original Relation digest.
          compareOriginal ??= database.prepare(`SELECT 1 AS exact FROM client_relation_sample_adoptions
            WHERE run_definition_cid = ? AND sample_ref_cid = ? AND
              source_generation_wire = ? AND capture_wire = ? AND emission_wire = ? AND
              reference_wire = ? AND relation_wire = ?`);
          if (compareOriginal.get(ref.runDefinitionCid, sample.sampleRefCid,
            generation, capture, emission, reference, relation)?.exact !== 1) {
            fail('ClientRelationSampleOriginalChanged');
          }
        }
        const result = retainedReceipt(control, ref, sample.sampleRefCid, limits, prior);
        requireAuthority(current);
        return result;
      }
      if (start.cancellation_requested !== 0 || start.physical_close_confirmed !== 0 ||
          start.terminal_clear !== 1) fail('ClientRelationSampleOriginalChanged');
      findGeneration ??= database.prepare(`SELECT 1 FROM client_relation_sample_adoptions
        WHERE run_definition_cid = ? AND source_generation_cid = ?`);
      if (findGeneration.get(ref.runDefinitionCid, sample.sourceGenerationCid) !== undefined) {
        fail('ClientRelationSampleOriginalChanged');
      }
      const ordinals = lastReceiptOrdinals(ref.runDefinitionCid);
      if (ordinals.run_ordinal >= sample.capture.max_artifacts || ordinals.journal_ordinal >= maxRecords) {
        fail('ClientRelationSampleCapacity');
      }
      if (typeof start.lookup_expires_at !== 'string' || typeof start.valid_until !== 'string') {
        fail('ClientRelationSampleExpired');
      }
      const adoptedAt = now();
      const expiresAt = Math.min(adoptedAt + sample.capture.ttl_seconds * 1000,
        Date.parse(start.lookup_expires_at), Date.parse(start.valid_until));
      if (!Number.isSafeInteger(expiresAt) || expiresAt <= adoptedAt) fail('ClientRelationSampleExpired');
      const issued = control.sealRunEvidence('sample_adoption_receipt', JSON.stringify({
        version: 'actql-sample-adoption-receipt/0.1', run_ref: ref,
        sample_ref_cid: sample.sampleRefCid, adoption: 'retained_relation_prefix',
        expires_at_epoch_ms: String(expiresAt),
      }), limits);
      const result = retainedReceipt(control, ref, sample.sampleRefCid, limits,
        {expires_at: expiresAt, receipt_wire: issued.wire});
      requireAuthority(current);
      insert ??= database.prepare(`INSERT INTO client_relation_sample_adoptions
        (run_definition_cid, sample_ref_cid, source_generation_cid, expires_at,
          journal_receipt_ordinal, run_receipt_ordinal, output_port_id, original_capture_cid, emission_provenance_cid,
          source_generation_wire, capture_wire, emission_wire, reference_wire, receipt_wire, relation_wire)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
      if (insert.run(ref.runDefinitionCid, sample.sampleRefCid, sample.sourceGenerationCid,
        expiresAt, ordinals.journal_ordinal + 1, ordinals.run_ordinal + 1,
        retainedReference.output_port_id, retainedReference.original_capture_cid,
        retainedReference.emission_provenance_cid, generation, capture, emission,
        reference, issued.wire, relation).changes !== 1) {
        fail('ClientRelationSampleOriginalChanged');
      }
      // Roll back on loss before the transaction's actual COMMIT. Never
      // report an acknowledgement from the body or from a thrown COMMIT.
      requireAuthority(current);
      return result;
    });
  };
  // Keep the canonical reference's scalar preimage in the adoption row.
  // A cold Step reader can verify a port association after payload expiry,
  // without reading the retired proof or Relation wires. An index limits
  // the probe to the first two candidates; ambiguity selects neither.
  const resolveReference = (ref: WireRunRef, outputPortId: string, control: SampleEvidenceControl,
    limits: SampleLimits) => {
    if (!stored()) return Object.freeze({kind: 'unobserved'});
    referenceCandidates ??= database.prepare(`SELECT
      substr(a.sample_ref_cid, 1, 72) AS sample_ref_cid,
      substr(a.original_capture_cid, 1, 72) AS original_capture_cid,
      substr(a.emission_provenance_cid, 1, 72) AS emission_provenance_cid
      FROM client_relation_sample_adoptions a JOIN client_relation_sample_starts s USING (run_definition_cid)
      WHERE a.run_definition_cid = ? AND a.output_port_id = ? AND s.namespace_id = ? AND s.authority_scope_cid = ?
      ORDER BY a.sample_ref_cid LIMIT 2`);
    const rows = referenceCandidates.all(ref.runDefinitionCid, outputPortId, ref.namespaceId, ref.authorityScopeCid);
    for (const row of rows) {
      if (!cid(row.sample_ref_cid) || !cid(row.original_capture_cid) || !cid(row.emission_provenance_cid)) {
        fail('ClientRelationSampleInvalidOriginal');
      }
      const reference = control.sealRunEvidence('sample_reference', JSON.stringify({
        version: 'actql-sample-reference/0.1',
        run_ref: {namespaceId: ref.namespaceId, authorityScopeCid: ref.authorityScopeCid,
          runDefinitionCid: ref.runDefinitionCid},
        output_port_id: outputPortId,
        original_capture_cid: row.original_capture_cid,
        emission_provenance_cid: row.emission_provenance_cid,
      }), limits);
      if (reference.name !== 'sample_reference' || reference.identity !== row.sample_ref_cid) {
        fail('ClientRelationSampleOriginalChanged');
      }
    }
    if (rows.length === 0) return Object.freeze({kind: 'unobserved'});
    if (rows.length !== 1) return Object.freeze({kind: 'ambiguous'});
    const [row] = rows;
    if (!cid(row.sample_ref_cid)) fail('ClientRelationSampleInvalidOriginal');
    return Object.freeze({kind: 'selected', sampleRefCid: row.sample_ref_cid});
  };
  // The persisted receipt key selects only one Run's Sample. The caller
  // supplies the original Plan/map/port and holds the READ reservation through
  // consumption. Owner-local absence cannot reconcile an uncertain writer.
  const sampleColumns = ['source_generation_wire', 'capture_wire', 'emission_wire',
    'reference_wire', 'relation_wire'];
  const payloadColumns = [...sampleColumns, 'receipt_wire'];
  const scope = `FROM client_relation_sample_adoptions a JOIN client_relation_sample_starts s USING (run_definition_cid)
    WHERE a.run_definition_cid = ? AND a.sample_ref_cid = ? AND s.namespace_id = ? AND s.authority_scope_cid = ?`;
  const lengthSql = (column: string) => `length(CAST(a.${column} AS BLOB))`;
  const probe = (args: SampleLookupArgs, cutoff: number) => {
    // Skip even SQLite's payload-length expressions for expired rows.
    probePayload ??= database.prepare(`WITH observation(cutoff) AS (VALUES (?))
      SELECT a.expires_at, ${lengthSql('receipt_wire')} AS receipt_wire,
      ${sampleColumns.map(column =>
        `CASE WHEN a.expires_at > (SELECT cutoff FROM observation) THEN ${lengthSql(column)} END AS ${column}`
      ).join(', ')} ${scope}`);
    return probePayload.get(cutoff, ...args);
  };
  const readRetained = (ref: WireRunRef, selected: SampleReadSelection, control: SampleEvidenceControl,
    {current, reserve}: SampleCustody, expectedProducer?: SampleProducerOccurrence) => {
    ensureOpen();
    requireAuthority(current);
    const {compiledPlanCid, logicalMapCid, stepId, outputPortId, carrierContractCid, maxBytes} = selected;
    const byPort = selected.sampleRefCid === undefined;
    let sampleRefCid = selected.sampleRefCid;
    if ((!byPort && !cid(sampleRefCid)) ||
        ![compiledPlanCid, logicalMapCid, stepId, outputPortId, carrierContractCid].every(cid) ||
        !Number.isSafeInteger(maxBytes) || maxBytes < 1 || maxBytes > maxWireBytes) {
      fail('ClientRelationSampleInvalidOriginal');
    }
    const limits = limitsFor(ref);
    if (byPort) {
      // Two bounded candidate tuples and the two canonical proof lifetimes
      // precede observation. The caller owns their additive Read tariff.
      reserveOriginal(reserve, 2 * (3 * 72 + limits.maxWireBytes));
      requireAuthority(current);
      const resolved = resolveReference(ref, outputPortId, control, limits);
      requireAuthority(current);
      if (resolved.kind !== 'selected') return resolved;
      sampleRefCid = resolved.sampleRefCid;
    }
    if (sampleRefCid === undefined) fail('ClientRelationSampleInvalidOriginal');
    const args: SampleLookupArgs = [ref.runDefinitionCid, sampleRefCid, ref.namespaceId, ref.authorityScopeCid];
    const observedAt = now();
    const extent = stored() ? probe(args, observedAt) : undefined;
    requireAuthority(current);
    if (extent === undefined) return Object.freeze({kind: 'unobserved'});
    const {expires_at: expiry, receipt_wire: receiptBytes} = extent;
    if (typeof expiry !== 'number' || !Number.isSafeInteger(expiry) || expiry <= 0 ||
        typeof receiptBytes !== 'number' || !Number.isSafeInteger(receiptBytes) || receiptBytes < 1 ||
        receiptBytes > limits.maxWireBytes) fail('ClientRelationSampleInvalidOriginal');

    // An expired or retired row needs only its authenticated receipt. In all
    // other cases the native call bounds every field before copying it.
    const expired = expiry <= observedAt;
    if (!expired && extent.relation_wire === null) fail('ClientRelationSampleInvalidOriginal');
    const columns = expired ? ['receipt_wire'] : payloadColumns;
    const amounts = columns.map(column => {
      const size = extent[column];
      if (typeof size !== 'number' || !Number.isSafeInteger(size) || size < 1 ||
          size > (column === 'relation_wire' ? maxBytes : limits.maxWireBytes)) fail('ClientRelationSampleCapacity');
      return size;
    });
    // This extent is input to the caller's full materialization, codec and
    // egress tariff. It is not permission or a successful physical read.
    reserveOriginal(reserve, amounts.reduce((total, size) => total + size, 0));
    requireAuthority(current);
    const observation = transact('relation_sample_read', 'ClientRelationSampleReadUnknown', sampleFailure, () => {
      const start = originalStart(ref);
      if (start === undefined || start.plan_cid !== compiledPlanCid || typeof start.start_revision !== 'number' ||
          !Number.isSafeInteger(start.start_revision) || start.start_revision <= 0) fail('ClientRelationSampleOriginalChanged');
      if (expectedProducer !== undefined && start.start_revision !== expectedProducer.startRevision) {
        fail('ClientRelationSampleOriginalChanged');
      }
      if (byPort) {
        const selected = resolveReference(ref, outputPortId, control, limits);
        if (selected.kind !== 'selected' || selected.sampleRefCid !== sampleRefCid) fail('ClientRelationSampleOriginalChanged');
      }
      const checkedAt = Math.max(observedAt, now());
      const expiredAtRead = expiry <= checkedAt;
      const latest = probe(args, checkedAt);
      if (latest === undefined || latest.expires_at !== expiry || latest.receipt_wire !== receiptBytes ||
          !expiredAtRead && payloadColumns.some(column => latest[column] !== extent[column])) {
        fail('ClientRelationSampleOriginalChanged');
      }
      let row;
      if (!expiredAtRead) {
        readPayload ??= database.prepare(`SELECT a.expires_at,
          substr(a.source_generation_cid, 1, 72) AS source_generation_cid,
          ${payloadColumns.map(column => `a.${column}`).join(', ')} ${scope}
          AND a.expires_at = ? AND ${payloadColumns.map(column => `${lengthSql(column)} = ?`).join(' AND ')}`);
        row = readPayload.get(...args, expiry, ...amounts);
      } else {
        readExpiredReceipt ??= database.prepare(`SELECT a.expires_at, a.receipt_wire ${scope}
          AND a.expires_at = ? AND ${lengthSql('receipt_wire')} = ?`);
        row = readExpiredReceipt.get(...args, expiry, receiptBytes);
      }
      if (row === undefined) fail('ClientRelationSampleOriginalChanged');
      const receiptOriginal = retainedReceipt(control, ref, sampleRefCid, limits, row);
      requireAuthority(current);
      // Receipt expiry is scoped to the Run and SampleRef. Only the
      // separately verified reference establishes a port association.
      if (expiredAtRead || receiptOriginal.expiresAt <= now()) {
        // The receipt has no producer generation. It cannot prove that
        // this expired association belongs to the currently selected Next.
        return expectedProducer === undefined ? Object.freeze({kind: 'expired', sampleRefCid})
          : Object.freeze({kind: 'unobserved'});
      }
      const {source, capture, emission, reference} = checkSampleEvidence(control, ref, start, limits, {
        generation: row.source_generation_wire, capture: row.capture_wire, emission: row.emission_wire,
        reference: row.reference_wire,
      });
      if (reference.self_cid !== sampleRefCid || source.self_cid !== row.source_generation_cid ||
          source.logical_map_cid !== logicalMapCid || source.step_id !== stepId ||
          source.output_port_id !== outputPortId || source.carrier_contract_cid !== carrierContractCid) {
        fail('ClientRelationSampleOriginalChanged');
      }
      if (expectedProducer !== undefined && (source.committed_generation !== expectedProducer.generation ||
          source.producer_occurrence.attempt_sequence !== expectedProducer.attemptSequence)) {
        return Object.freeze({kind: 'unobserved'});
      }
      const rawRelation = row.relation_wire, relationBytes = extent.relation_wire;
      if (typeof rawRelation !== 'string' || typeof relationBytes !== 'number') {
        fail('ClientRelationSampleInvalidOriginal');
      }
      checkSamplePrefix(capture, emission, rawRelation, relationBytes);
      let relation: unknown;
      try {relation = JSON.parse(rawRelation);}
      catch (error) {fail('ClientRelationSampleInvalidOriginal', error);}
      if (!validWireSampleRelationShape(relation) || String(relation.rows.length) !== emission.sampled_items ||
          relation.ordering_evidence_cid !== emission.ordering_evidence_cid) {
        fail('ClientRelationSampleInvalidOriginal');
      }
      return Object.freeze({kind: 'available', source, capture, emission, reference, receipt: receiptOriginal, relation});
    }, {readOnly: true});
    requireAuthority(current);
    if (observation.kind === 'available' && observation.receipt.expiresAt <= now()) {
      // This read already verified the live original, including its generation.
      return Object.freeze({kind: 'expired', sampleRefCid});
    }
    return observation;
  };
  return Object.freeze({
    writer(ref: WireRunRef, original: SampleAdoptionOriginal, control: SampleEvidenceControl) {
      return (ticket: object) => {
        ensureOpen();
        return original.visitAdoption(ticket, loan => adopt(ref, original, control, loan));
      };
    },
    lookup(ref: WireRunRef, sampleRefCid: string, control: SampleEvidenceControl, {current, reserve}: SampleCustody) {
      ensureOpen();
      requireAuthority(current);
      if (!cid(sampleRefCid)) fail('ClientRelationSampleInvalidOriginal');
      const limits = limitsFor(ref);
      reserveOriginal(reserve, limits.maxWireBytes);
      requireAuthority(current);
      const result = transact('relation_sample_adoption_lookup', 'ClientRelationSampleLookupUnknown', sampleFailure, () => {
        const row = stored() ? receipt(ref, sampleRefCid, limits) : undefined;
        const observation = row === undefined ? Object.freeze({kind: 'unobserved'}) :
          retainedReceipt(control, ref, sampleRefCid, limits, row);
        requireAuthority(current);
        return observation;
      }, {readOnly: true});
      requireAuthority(current);
      return result;
    },
    readRetained,
    retire(ref: WireRunRef, sampleRefCid: string, control: SampleEvidenceControl, {current, reserve}: SampleCustody) {
      ensureOpen();
      requireAuthority(current);
      if (!cid(sampleRefCid)) fail('ClientRelationSampleInvalidOriginal');
      const limits = limitsFor(ref);
      reserveOriginal(reserve, limits.maxWireBytes);
      requireAuthority(current);
      return transact('relation_sample_retirement', 'ClientRelationSampleRetirementUnknown', sampleFailure, () => {
        if (!stored()) return false;
        const prior = receipt(ref, sampleRefCid, limits);
        if (prior === undefined) return false;
        const original = retainedReceipt(control, ref, sampleRefCid, limits, prior);
        if (prior.has_payload === 0 || original.expiresAt > now()) return false;
        requireAuthority(current);
        retirePayload ??= database.prepare(`UPDATE client_relation_sample_adoptions SET
          source_generation_wire = NULL, capture_wire = NULL,
          emission_wire = NULL, reference_wire = NULL, relation_wire = NULL
          WHERE run_definition_cid = ? AND sample_ref_cid = ? AND expires_at = ? AND relation_wire IS NOT NULL`);
        if (retirePayload.run(ref.runDefinitionCid, sampleRefCid, original.expiresAt).changes !== 1) {
          fail('ClientRelationSampleOriginalChanged');
        }
        requireAuthority(current);
        return true;
      });
    },
  });
}
