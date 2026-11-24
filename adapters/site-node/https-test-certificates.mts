// Test-only TLS material shared by source and packed acceptance harnesses.
// Certificate preparation must not import a checkout's compiled runtime.
import {execFileSync} from 'node:child_process';
import {X509Certificate} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';

function openssl(root: string, ...arguments_: string[]) {
  execFileSync('openssl', arguments_, {cwd: root, stdio: 'ignore'});
}

function issueCertificate(root: string, name: string, subject: string, extensionFile?: string) {
  openssl(root, 'genrsa', '-out', `${name}.key`, '2048');
  openssl(root, 'req', '-new', '-key', `${name}.key`, '-out', `${name}.csr`, '-subj', subject);
  openssl(root, 'x509', '-req', '-in', `${name}.csr`, '-CA', 'ca.crt',
    '-CAkey', 'ca.key', '-CAcreateserial', '-out', `${name}.crt`, '-days', '1',
    ...(extensionFile === undefined ? [] : ['-extfile', extensionFile]));
}

export async function certificates(root: string) {
  openssl(root, 'genrsa', '-out', 'ca.key', '2048');
  openssl(root, 'req', '-x509', '-new', '-key', 'ca.key', '-out', 'ca.crt',
    '-subj', '/CN=ActQL Remote Test CA', '-days', '1');
  await writeFile(join(root, 'site.ext'), 'subjectAltName=DNS:localhost,IP:127.0.0.1\n');
  issueCertificate(root, 'site', '/CN=localhost', 'site.ext');
  issueCertificate(root, 'coordinator', '/CN=coordinator-a');
  issueCertificate(root, 'foreign', '/CN=foreign-coordinator');
  const read = (name: string) => readFile(join(root, name));
  const coordinatorCertificate = await read('coordinator.crt');
  return Object.freeze({
    ca: await read('ca.crt'),
    siteKey: await read('site.key'),
    siteCertificate: await read('site.crt'),
    coordinatorKey: await read('coordinator.key'),
    coordinatorCertificate,
    coordinatorFingerprint: new X509Certificate(coordinatorCertificate).fingerprint256,
    foreignKey: await read('foreign.key'),
    foreignCertificate: await read('foreign.crt'),
  });
}
