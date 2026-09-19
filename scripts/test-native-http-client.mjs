import {execFileSync, spawn} from 'node:child_process';
import {once} from 'node:events';
import {createServer} from 'node:https';
import {mkdtemp, mkdir, readFile, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';

const scratchRoot = process.env.ACTQL_TEST_SCRATCH_ROOT;
if (typeof scratchRoot !== 'string' || scratchRoot.length === 0) {
  throw new Error('ACTQL_TEST_SCRATCH_ROOT is required');
}
await mkdir(scratchRoot, {recursive: true});
const root = await mkdtemp(join(scratchRoot, 'native-http-'));

const openssl = (...arguments_) => execFileSync(
  'openssl',
  arguments_,
  {cwd: root, stdio: 'ignore'},
);

const issue = (authority, name, extension) => {
  openssl('genrsa', '-out', `${name}.key`, '2048');
  openssl(
    'req', '-new', '-key', `${name}.key`, '-out', `${name}.csr`,
    '-subj', `/CN=${name}`,
  );
  openssl(
    'x509', '-req', '-in', `${name}.csr`, '-CA', `${authority}.crt`,
    '-CAkey', `${authority}.key`, '-CAcreateserial', '-out', `${name}.crt`,
    '-days', '1', ...(extension === undefined ? [] : ['-extfile', extension]),
  );
};

let server;
try {
  openssl('genrsa', '-out', 'ca.key', '2048');
  openssl(
    'req', '-x509', '-new', '-key', 'ca.key', '-out', 'ca.crt',
    '-subj', '/CN=ActQL Native HTTP Test CA', '-days', '1',
  );
  openssl('genrsa', '-out', 'foreign-ca.key', '2048');
  openssl(
    'req', '-x509', '-new', '-key', 'foreign-ca.key',
    '-out', 'foreign-ca.crt', '-subj', '/CN=Foreign Test CA', '-days', '1',
  );
  await writeFile(
    join(root, 'server.ext'),
    'subjectAltName=DNS:localhost,IP:127.0.0.1\n' +
      'extendedKeyUsage=serverAuth\n',
  );
  await writeFile(
    join(root, 'client.ext'),
    'extendedKeyUsage=clientAuth\n',
  );
  issue('ca', 'server', 'server.ext');
  issue('ca', 'client', 'client.ext');
  issue('foreign-ca', 'foreign-client', 'client.ext');
  server = createServer({
    key: await readFile(join(root, 'server.key')),
    cert: await readFile(join(root, 'server.crt')),
    ca: await readFile(join(root, 'ca.crt')),
    requestCert: true,
    rejectUnauthorized: true,
  }, async (request, response) => {
    if (request.url === '/disconnect') {
      request.socket.destroy();
      return;
    }
    if (request.method !== 'POST' || request.url !== '/probe') {
      response.writeHead(404).end();
      return;
    }
    const chunks = [];
    let length = 0;
    for await (const chunk of request) {
      length += chunk.length;
      if (length > 65_536) {
        request.destroy();
        return;
      }
      chunks.push(chunk);
    }
    const body = Buffer.concat(chunks).toString('utf8');
    if (body !== '{"probe":true}' && body !== '{}') {
      response.writeHead(400).end();
      return;
    }
    response.writeHead(200, {'content-type': 'application/json'});
    response.end('{"accepted":true}');
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  if (address === null || typeof address === 'string') {
    throw new Error('native HTTP test listener has no TCP address');
  }
  const moon = join(
    process.env.MOON_HOME ?? '',
    'bin',
    'moon',
  );
  const library = process.env.ACTQL_TEST_NATIVE_HTTP_LIBRARY ??
    (process.platform === 'darwin'
      ? '/usr/lib/libcurl.4.dylib'
      : 'libcurl.so.4');
  const child = spawn(
    moon,
    ['test', 'src/platform_native/http_client', '--target', 'native'],
    {
      cwd: new URL('../', import.meta.url),
      env: {
        ...process.env,
        ACTQL_TEST_NATIVE_HTTP_LIBRARY: library,
        ACTQL_TEST_NATIVE_HTTP_URL: `https://127.0.0.1:${address.port}`,
        ACTQL_TEST_NATIVE_HTTP_CA: join(root, 'ca.crt'),
        ACTQL_TEST_NATIVE_HTTP_CERT: join(root, 'client.crt'),
        ACTQL_TEST_NATIVE_HTTP_KEY: join(root, 'client.key'),
        ACTQL_TEST_NATIVE_HTTP_BAD_CERT: join(root, 'foreign-client.crt'),
        ACTQL_TEST_NATIVE_HTTP_BAD_KEY: join(root, 'foreign-client.key'),
      },
      stdio: 'inherit',
    },
  );
  const [code, signal] = await once(child, 'exit');
  if (code !== 0) {
    throw new Error(`native HTTP test failed: ${code ?? signal}`);
  }
} finally {
  if (server !== undefined) {
    server.close();
    await once(server, 'close');
  }
  await rm(root, {recursive: true, force: true});
}
