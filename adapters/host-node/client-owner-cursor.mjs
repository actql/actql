// A stateless Host binding for existing Owner history prefixes. The token is
// neither authority nor a new history store. Callers reauthorize before read.
import {KeyObject, createPrivateKey, createPublicKey, sign, verify} from 'node:crypto';
import {validRunRef, snapshotClientRequest} from '../../packages/client-wire/index.mjs';

const domain = 'actql-owner-observation-cursor/0.1';
const owners = new Set(['run', 'effect', 'publication', 'delivery', 'site']);
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const exact = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join(',') === [...keys].sort().join(',');
const validOwner = value => exact(value, ['kind','scopeCid','streamCid']) &&
  owners.has(value.kind) && cid(value.scopeCid) && cid(value.streamCid);
const validPosition = value => exact(value, ['generation','revision','entryCid']) &&
  cid(value.generation) && cid(value.entryCid) && Number.isSafeInteger(value.revision) && value.revision > 0;
const sameRef = (a,b) => a.namespaceId === b.namespaceId &&
  a.authorityScopeCid === b.authorityScopeCid && a.runDefinitionCid === b.runDefinitionCid;
const sameOwner = (a,b) => a.kind === b.kind && a.scopeCid === b.scopeCid && a.streamCid === b.streamCid;
const mismatch = () => Object.freeze({kind:'cursor_mismatch'});

export function createClientOwnerCursorCodec({privateKey, publicKey, now=Date.now, maxAgeMs=300000}) {
  if(typeof now !== 'function' || !Number.isSafeInteger(maxAgeMs) || maxAgeMs < 1) {
    throw new TypeError('InvalidClientOwnerCursorLifetime');
  }
  const clock=()=>{
    const value=now();
    if(!Number.isSafeInteger(value) || value < 0)throw new TypeError('InvalidClientOwnerCursorClock');
    return value;
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
    issue({ref, owner, position}) {
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
    read(cursor, {ref, owner}) {
      if (!validRunRef(ref) || !validOwner(owner)) throw new TypeError('InvalidClientOwnerCursorScope');
      if (typeof cursor !== 'string' || cursor.length > 8192 ||
          !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/u.test(cursor)) return mismatch();
      try {
        const [body, signature] = cursor.split('.');
        const bytes = Buffer.from(body, 'base64url'), seal = Buffer.from(signature, 'base64url');
        if (bytes.toString('base64url') !== body || seal.toString('base64url') !== signature ||
            seal.length !== 64 || !verify(null, bytes, selected, seal)) return mismatch();
        const claim = JSON.parse(new TextDecoder('utf-8', {fatal:true}).decode(bytes));
        if (!exact(claim, ['version','expiresAt','ref','owner','position']) || claim.version !== domain ||
            !Number.isSafeInteger(claim.expiresAt) || claim.expiresAt < 0 ||
            !validRunRef(claim.ref) || !validOwner(claim.owner) || !validPosition(claim.position) ||
            !sameRef(claim.ref, ref) || !sameOwner(claim.owner, owner)) return mismatch();
        if(clock() >= claim.expiresAt)return Object.freeze({kind:'cursor_expired'});
        return Object.freeze({kind:'matched', position:Object.freeze({...claim.position})});
      } catch {return mismatch();}
    },
  });
}
