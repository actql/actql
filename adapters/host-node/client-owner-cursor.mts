// A stateless Host binding for existing Owner history prefixes. The token is
// neither authority nor a new history store. Callers reauthorize before read.
import {KeyObject, createPrivateKey, createPublicKey, sign, verify} from 'node:crypto';
import {validRunRef, snapshotClientRequest} from '../../packages/client-wire/index.mjs';
import type {WireRunRef, WireOwnerRef} from '@actql/client-wire';

interface Position {generation: string; revision: number; entryCid: string}
interface CursorConfiguration {
  privateKey: KeyObject | Parameters<typeof createPrivateKey>[0];
  publicKey: KeyObject | Parameters<typeof createPublicKey>[0];
  now?: () => unknown; maxAgeMs?: number;
}


const domain = 'actql-owner-observation-cursor/0.1';
const owners = new Set(['run', 'effect', 'publication', 'delivery', 'site']);
const cid = (value: unknown): value is string => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const exact = (value: unknown, keys: readonly string[]): value is Record<string, unknown> => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join(',') === [...keys].sort().join(',');
const validOwner = (value: unknown): value is WireOwnerRef => exact(value, ['kind','scopeCid','streamCid']) &&
  owners.has(value.kind as string) && cid(value.scopeCid) && cid(value.streamCid);
const validPosition = (value: unknown): value is Position => exact(value, ['generation','revision','entryCid']) &&
  cid(value.generation) && cid(value.entryCid) && Number.isSafeInteger(value.revision) && (value.revision as number) > 0;
const sameRef = (a: WireRunRef,b: WireRunRef) => a.namespaceId === b.namespaceId &&
  a.authorityScopeCid === b.authorityScopeCid && a.runDefinitionCid === b.runDefinitionCid;
const sameOwner = (a: WireOwnerRef,b: WireOwnerRef) => a.kind === b.kind && a.scopeCid === b.scopeCid && a.streamCid === b.streamCid;
const mismatch = () => Object.freeze({kind:'cursor_mismatch'});

export function createClientOwnerCursorCodec({privateKey, publicKey, now=Date.now, maxAgeMs=300000}: CursorConfiguration) {
  if(typeof now !== 'function' || !Number.isSafeInteger(maxAgeMs) || maxAgeMs < 1) {
    throw new TypeError('InvalidClientOwnerCursorLifetime');
  }
  const clock=()=>{
    const value=now();
    if(!Number.isSafeInteger(value) || (value as number) < 0)throw new TypeError('InvalidClientOwnerCursorClock');
    return value as number;
  };
  const secret = privateKey instanceof KeyObject ? privateKey : createPrivateKey(privateKey);
  const selected = publicKey instanceof KeyObject ? publicKey : createPublicKey(publicKey);
  if (secret.type !== 'private' || selected.type !== 'public' ||
      secret.asymmetricKeyType !== 'ed25519' || selected.asymmetricKeyType !== 'ed25519' ||
      !createPublicKey(secret).export({type:'spki', format:'der'})
        .equals(selected.export({type:'spki', format:'der'}))) {
    throw new TypeError('InvalidClientOwnerCursorKeys');
  }
  return Object.freeze({
    issue({ref, owner, position}: {ref: unknown; owner: unknown; position: unknown}) {
      if (!validRunRef(ref) || !ref.namespaceId.isWellFormed() ||
          !validOwner(owner) || !validPosition(position)) throw new TypeError('InvalidClientOwnerCursorScope');
      const expiresAt=clock()+maxAgeMs;
      if(!Number.isSafeInteger(expiresAt))throw new TypeError('InvalidClientOwnerCursorLifetime');
      const claim = {version:domain, expiresAt, ref:snapshotClientRequest(ref),
        owner:snapshotClientRequest(owner), position:snapshotClientRequest(position)};
      // These fixed fields contain admitted identities and a bounded counter.
      // JSON preserves the exact namespace bytes; configuration NFC does not
      // participate in the signature preimage or matching.
      const bytes = Buffer.from(JSON.stringify(claim), 'utf8');
      const signature = sign(null, bytes, secret);
      return `${bytes.toString('base64url')}.${signature.toString('base64url')}`;
    },
    read(cursor: unknown, {ref, owner}: {ref: unknown; owner: unknown}) {
      if (!validRunRef(ref) || !validOwner(owner)) throw new TypeError('InvalidClientOwnerCursorScope');
      if (typeof cursor !== 'string' || cursor.length > 8192 ||
          !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/u.test(cursor)) return mismatch();
      try {
        const [body, signature] = cursor.split('.');
        const bytes = Buffer.from(body, 'base64url'), seal = Buffer.from(signature, 'base64url');
        if (bytes.toString('base64url') !== body || seal.toString('base64url') !== signature ||
            seal.length !== 64 || !verify(null, bytes, selected, seal)) return mismatch();
        const claim: unknown = JSON.parse(new TextDecoder('utf-8', {fatal:true}).decode(bytes));
        if (!exact(claim, ['version','expiresAt','ref','owner','position']) || claim.version !== domain ||
            !Number.isSafeInteger(claim.expiresAt) || (claim.expiresAt as number) < 0 ||
            !validRunRef(claim.ref) || !validOwner(claim.owner) || !validPosition(claim.position) ||
            !sameRef(claim.ref, ref) || !sameOwner(claim.owner, owner)) return mismatch();
        if(clock() >= (claim.expiresAt as number))return Object.freeze({kind:'cursor_expired'});
        return Object.freeze({kind:'matched', position:Object.freeze({...claim.position})});
      } catch {return mismatch();}
    },
  });
}
