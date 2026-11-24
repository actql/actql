import {installedEffectDependencyOriginal} from './installed-effect-dependency-original.mjs';
import {checked} from './runtime-result.mjs';

type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type Artifact = Readonly<{identity: string}>;
type DependencyBody = Readonly<{kind: string; wire: string; cid?: string}>;
type Contract = Readonly<{name: string; identityField: string; identity: string; wire: string}>;
type CollectionKey = 'definitions' | 'artifacts' | 'derivations' | 'orderings' | 'retentions' | 'durableBindings';
type PublicationChain = Readonly<{
  capturedRun: unknown; computationReceipt: unknown; runDefinition: unknown; invocation: unknown; manifest: unknown;
}> & Readonly<Record<CollectionKey, readonly unknown[]>>;
type ReceiptWires = Readonly<{setWire: string; memberWires: readonly string[]; finalWire?: string}>;
type ConstructionArgs =
  | readonly [PublicationChain, unknown, ReceiptWires, Limits]
  | readonly [PublicationChain, unknown, ReceiptWires & Readonly<{finalWire: string}>, unknown, unknown, unknown, Limits];

// Generated Common represents these Results and nominal contract handles opaquely.
type CommonEffectPublicationBindings = Readonly<{
  clientProgramAdmitEffectDependencyBody(kind: string, cid: string | undefined, wire: string,
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramBeginInstalledEffectCapturePublication(original: unknown, issue: boolean,
    contracts: unknown, receiptWires: unknown, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramEffectDependencyBodyCid(body: unknown): string;
  clientProgramInstalledEffectCapturePublicationInputLimit(original: unknown): unknown;
  clientProgramInstalledEffectDependencyInventoryPrepare(owner: unknown, prepared: unknown,
    request: unknown, plan: unknown, kinds: unknown, identities: unknown, wires: unknown,
    artifacts: unknown, maxBytes: number, maxNodes: number, maxDepth: number,
    originalArtifacts: unknown): unknown;
  clientProgramIssueEffectDependencyInventory(bodies: unknown, artifacts: unknown, maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  clientProgramIssuePreparedEffectfulFinalRunReceipt(runDefinition: unknown, invocation: unknown,
    definitions: unknown, artifacts: unknown, manifest: unknown, computationReceipt: unknown,
    capturedRun: unknown, prepared: unknown, preview: unknown, setReceiptWire: string,
    memberReceiptWires: unknown, maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  strategyIssueEffectSetApplyReceiptFromMembers(preview: unknown, memberReceiptWires: unknown,
    replayed: unknown, maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  strategyIssueEffectfulFinalRunReceipt(runDefinition: unknown, invocation: unknown,
    definitions: unknown, artifacts: unknown, manifest: unknown, computationReceipt: unknown,
    capturedRun: unknown, preview: unknown, setReceiptWire: string, memberReceiptWires: unknown,
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
}>;

type EffectPublicationPorts = Readonly<{
  localEffectArtifactTokens: WeakMap<object, unknown>;
  computationPreviewTokens: WeakMap<object, unknown>;
  recoveredEffectCaptures: WeakMap<object, unknown>;
  issuanceLimits: (limits: Limits, label: string) => Limits;
  captureContractLimits: (limits: Limits, label: string) => Limits;
  token: (value: unknown) => unknown;
  inspect: (value: unknown, limits: Limits) => Contract;
}>;

export function createEffectPublicationControls(moon: CommonEffectPublicationBindings, {
  localEffectArtifactTokens, computationPreviewTokens, recoveredEffectCaptures,
  issuanceLimits, captureContractLimits, token, inspect,
}: EffectPublicationPorts) {
  return {
    prepareLocalEffectDependencyInventory(artifacts: readonly Artifact[], bodies: readonly DependencyBody[],
      limits: Limits, construction?: unknown, originalArtifacts: readonly unknown[] = []) {
      issuanceLimits(limits, 'Effect dependency inventory');
      if (!Array.isArray(artifacts) || construction === undefined && artifacts.length > 4096 ||
          !Array.isArray(bodies) || construction === undefined && bodies.length > 4096) {
        throw new TypeError('Invalid Effect dependency inventory');
      }
      if (construction !== undefined) {
        const original=installedEffectDependencyOriginal(construction,moon);
        const kinds=[], identities=[], wires=[], roots=[], originals=[];
        for (const artifact of artifacts) {
          const owned=localEffectArtifactTokens.get(artifact as object);
          if(owned===undefined)throw new TypeError('Foreign Effect dependency root');
          roots.push(owned);
        }
        if (!Array.isArray(originalArtifacts)) throw new TypeError('Invalid Effect dependency originals');
        for (const artifact of originalArtifacts) {
          const owned=localEffectArtifactTokens.get(artifact as object);
          if(owned===undefined)throw new TypeError('Foreign Effect dependency original');
          originals.push(owned);
        }
        for(const body of bodies){
          if(body===null||typeof body!=='object')throw new TypeError('Invalid Effect dependency body');
          const kind=Object.getOwnPropertyDescriptor(body,'kind'),
            wire=Object.getOwnPropertyDescriptor(body,'wire'),cid=Object.getOwnPropertyDescriptor(body,'cid');
          if(!kind||!wire||!Object.hasOwn(kind,'value')||!Object.hasOwn(wire,'value')||
              cid!==undefined&&!Object.hasOwn(cid,'value')||typeof kind.value!=='string'||
              typeof wire.value!=='string'||cid!==undefined&&typeof cid.value!=='string')
            throw new TypeError('Invalid Effect dependency body');
          kinds.push(kind.value);identities.push(cid?.value);wires.push(wire.value);
        }
        const value=checked(moon.clientProgramInstalledEffectDependencyInventoryPrepare(
          original.parent,original.prepared,original.request,original.plan,kinds,identities,wires,roots,
          limits.maxWireBytes,limits.maxNodes,limits.maxDepth,originals));
        original.current();
        return value;
      }
      const roots = new Map();
      for (const artifact of artifacts) {
        const owned = localEffectArtifactTokens.get(artifact as object);
        if (owned === undefined) {
          throw new TypeError('Foreign Effect dependency root');
        }
        roots.set(artifact.identity, owned);
      }
      let remaining = Math.min(limits.maxWireBytes, 16 * 1024 * 1024);
      const entries = new Map<string, Readonly<{wire: string; admitted: unknown}>>();
      const encoder = new TextEncoder();
      for (const body of bodies) {
        const {kind, wire, cid} = body ?? {};
        if (typeof kind !== 'string' || typeof wire !== 'string' ||
            (cid !== undefined && typeof cid !== 'string')) {
          throw new TypeError('Invalid Effect dependency body');
        }
        // Check the aggregate input before parsing or retaining another
        // admitted body. Encoding/envelope limits are checked again by MoonBit.
        if (wire.length > remaining) {
          throw new RangeError('EffectDependencyBodyByteLimit');
        }
        const bytes = encoder.encode(wire).byteLength;
        if (bytes > remaining) {
          throw new RangeError('EffectDependencyBodyByteLimit');
        }
        remaining -= bytes;
        const admitted = checked(moon.clientProgramAdmitEffectDependencyBody(
          kind, cid, wire, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
        const identity = moon.clientProgramEffectDependencyBodyCid(admitted);
        const key = `${kind}\0${identity}`;
        const previous = entries.get(key);
        if (previous !== undefined && previous.wire !== wire) {
          throw new TypeError('Conflicting Effect dependency body');
        }
        if (previous === undefined) entries.set(key, {wire, admitted});
      }
      return checked(moon.clientProgramIssueEffectDependencyInventory(
        [...entries.values()].map(value => value.admitted), [...roots.values()],
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    beginEffectfulPublicationConstruction(owner: unknown, issue: boolean, args: ConstructionArgs,
      additionalContracts?: readonly unknown[]) {
      if (typeof issue !== 'boolean' || !Array.isArray(args) ||
          args.length !== (issue ? 4 : 7)) {
        throw new TypeError('Invalid Effectful publication construction');
      }
      const chain = args[0], receipts = args[2];
      const limits = captureContractLimits(args[args.length - 1] as Limits, 'Effectful publication construction');
      // This bound belongs to the original completed Read's prepaid metadata.
      // Inspect lengths before allocating flattened token or receipt arrays.
      const inputLimit = checked(moon.clientProgramInstalledEffectCapturePublicationInputLimit(owner)) as number;
      if (!Number.isSafeInteger(inputLimit) || inputLimit < 5 ||
          chain === null || typeof chain !== 'object' ||
          receipts === null || typeof receipts !== 'object' ||
          typeof receipts.setWire !== 'string' || !Array.isArray(receipts.memberWires) ||
          issue && !Array.isArray(additionalContracts) ||
          !issue && typeof receipts.finalWire !== 'string') {
        throw new TypeError('Invalid Effectful publication construction');
      }
      let contractCount = 5;
      for (const name of ['definitions', 'artifacts', 'derivations', 'orderings', 'retentions', 'durableBindings']) {
        const values = chain[name as CollectionKey];
        if (!Array.isArray(values) || values.length > inputLimit - contractCount) {
          throw new RangeError('EffectfulPublicationMetadataLimit');
        }
        contractCount += values.length;
      }
      const extraCount = issue ? additionalContracts!.length : 3;
      if (extraCount > inputLimit - contractCount ||
          receipts.memberWires.length > inputLimit - contractCount - extraCount - (issue ? 1 : 2)) {
        throw new RangeError('EffectfulPublicationMetadataLimit');
      }
      const contracts = [token(chain.capturedRun), token(chain.computationReceipt),
        token(chain.runDefinition), token(chain.invocation), token(chain.manifest)];
      for (const name of ['definitions', 'artifacts', 'derivations', 'orderings', 'retentions', 'durableBindings']) {
        for (const contract of chain[name as CollectionKey]) contracts.push(token(contract));
      }
      if (issue) {
        for (const contract of additionalContracts!) contracts.push(token(contract));
      } else {
        for (let index = 3; index < 6; index++) contracts.push(token(args[index]));
      }
      const wires = [receipts.setWire];
      for (const wire of receipts.memberWires) {
        if (typeof wire !== 'string') throw new TypeError('Invalid Effectful publication Receipt');
        wires.push(wire);
      }
      if (!issue) wires.push(receipts.finalWire!);
      return checked(moon.clientProgramBeginInstalledEffectCapturePublication(owner, issue,
        contracts, wires, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    issueEffectfulFinalRunReceipt(chain: PublicationChain, preview: unknown, receipts: ReceiptWires,
      limits: Limits) {
      limits = captureContractLimits(limits, 'final Effectful Run Receipt');
      if (chain === null || typeof chain !== 'object' ||
          !Array.isArray(chain.definitions) ||
          !Array.isArray(chain.artifacts) ||
          receipts === null || typeof receipts !== 'object' ||
          typeof receipts.setWire !== 'string' ||
          !Array.isArray(receipts.memberWires) ||
          receipts.memberWires.some(wire => typeof wire !== 'string')) {
        throw new TypeError('Invalid final Effectful Run Receipt');
      }
      const ownedPreview = computationPreviewTokens.get(preview as object);
      if (ownedPreview === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      const prepared = recoveredEffectCaptures.get(chain.capturedRun as object);
      return inspect(checked(prepared === undefined ? moon.strategyIssueEffectfulFinalRunReceipt(
        token(chain.runDefinition), token(chain.invocation),
        chain.definitions.map(token), chain.artifacts.map(token),
        token(chain.manifest), token(chain.computationReceipt),
        token(chain.capturedRun), ownedPreview, receipts.setWire,
        receipts.memberWires, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth,
      ) : moon.clientProgramIssuePreparedEffectfulFinalRunReceipt(
        token(chain.runDefinition), token(chain.invocation),
        chain.definitions.map(token), chain.artifacts.map(token),
        token(chain.manifest), token(chain.computationReceipt),
        token(chain.capturedRun), prepared, ownedPreview, receipts.setWire,
        receipts.memberWires, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth,
      )), limits);
    },
    issueEffectSetApplyReceiptFromMembers(preview: unknown, members: readonly Readonly<{wire: string}>[],
      replayed: readonly boolean[], limits: Limits) {
      limits = captureContractLimits(limits, 'Effect Set Apply Receipt');
      if (!Array.isArray(members) ||
          members.some(member => typeof member?.wire !== 'string') ||
          !Array.isArray(replayed) ||
          replayed.some(value => typeof value !== 'boolean')) {
        throw new TypeError('Invalid Effect Set Apply Receipt request');
      }
      const ownedPreview = computationPreviewTokens.get(preview as object);
      if (ownedPreview === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return inspect(checked(
        moon.strategyIssueEffectSetApplyReceiptFromMembers(
          ownedPreview, members.map(member => member.wire), replayed,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
        ),
      ), limits);
    },
  };
}
