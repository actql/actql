import {unlink, writeFile} from 'node:fs/promises';
import {join} from 'node:path';

export const loadedFrom = import.meta.url;

const cid = digit => `sha256:${digit.repeat(64)}`;

// This authored component performs local physical work. Its managed-output
// envelope is a synthetic fixture, not a canonical data-plane implementation.
export function loadMember(name, {outputDirectory, provider, secret, closed}) {
  let evaluate;
  let physicalManifestCid;
  switch (name) {
    case 'local-alpha':
      evaluate = value => [value + 1, value + 2];
      physicalManifestCid = cid('8');
      break;
    case 'local-beta':
      evaluate = value => [value * 2, value * 3];
      physicalManifestCid = cid('9');
      break;
    default:
      throw new Error('FixtureConnectorNotListed');
  }
  return async ({inputBindingBody}) => {
    const {value} = JSON.parse(inputBindingBody);
    // These injected callbacks only record local boundary crossings. They
    // neither contact a provider nor read actual credentials.
    await provider(name);
    await secret(name);
    const rows = evaluate(value);
    const body = `${JSON.stringify(rows)}\n`;
    const path = join(outputDirectory, `${name}.json`);
    await writeFile(path, body, {flag: 'wx', mode: 0o600});
    const valueBytes = rows.map(row => Buffer.byteLength(String(row)));
    return Object.freeze({
      materialGeneration: `${name}-material`,
      managedProfileCid: cid('3'),
      measurement: Object.freeze({
        rowCount: rows.length,
        admissionNodes: 0,
        admissionTextBytes: 0,
        admissionWork: 0,
        columnRows: Object.freeze([rows.length]),
        columnBytes: Object.freeze([valueBytes.reduce((a, b) => a + b, 0)]),
        columnNodes: Object.freeze([rows.length]),
        columnMaxValueBytes: Object.freeze([Math.max(...valueBytes)]),
        columnNullRows: Object.freeze([0]),
        columnAdmittedDepths: Object.freeze([10]),
      }),
      resultSchemaCid: cid('5'),
      logicalViewCid: cid('6'),
      representationCodecCid: cid('7'),
      physicalManifestCid,
      rowCount: rows.length,
      retainedBytes: BigInt(Buffer.byteLength(body)),
      async close() {
        await unlink(path);
        closed(name);
      },
    });
  };
}
