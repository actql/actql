import {createHash} from 'node:crypto';

// The existing Host Store identity preimage, shared by first publication and
// normal Host startup. Preserve field order and JSON.stringify bytes exactly;
// this is not an Account identity or a new canonicalization domain.
export const localHostStoreAuthorityCid = (root, principalId) =>
  `sha256:${createHash('sha256').update(JSON.stringify({
    version: 'actql-local-store-owner/0.1', root, principalId})).digest('hex')}`;
