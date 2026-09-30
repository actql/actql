// HTTPS servers for the native bearer credential tests. They verify the
// server side only (no client certificate is requested), so a bearer client
// is authenticated by its Authorization header alone. The fixture owns the
// credential files it hands to the test and can replace them atomically on
// request, which lets the test observe that every request rereads the file.
import {once} from 'node:events';
import {createServer} from 'node:https';
import {chmod, mkdir, rename, symlink, writeFile} from 'node:fs/promises';
import {join} from 'node:path';

const tokenA = 'bearer-token-a';
const tokenB = 'bearer-token-b.~+/==';
const controlToken = 'bearer-control';
const maxToken = 'm'.repeat(4096);

async function readBody(request) {
  const chunks = [];
  let length = 0;
  for await (const chunk of request) {
    length += chunk.length;
    if (length > 65_536) throw new Error('bearer fixture body too large');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

function reply(response, status, body) {
  response.writeHead(status, {'content-type': 'application/json'});
  response.end(JSON.stringify(body));
}

async function replaceAtomically(directory, name, content, mode) {
  const temporary = join(directory, `.${name}.next`);
  await writeFile(temporary, content, {mode});
  await chmod(temporary, mode);
  await rename(temporary, join(directory, name));
}

async function listen(server, host) {
  server.listen(0, host);
  await once(server, 'listening');
  const address = server.address();
  if (address === null || typeof address === 'string') {
    throw new Error('bearer fixture listener has no TCP address');
  }
  return `https://${host}:${address.port}`;
}

export async function startNativeBearerServers({host, key, cert, root}) {
  const directory = join(root, 'bearer');
  await mkdir(directory, {recursive: true, mode: 0o700});
  const files = {
    rotating: [`${tokenA}\n`, 0o600],
    control: [`${controlToken}\n`, 0o600],
    max: [maxToken, 0o600],
    'group-readable': [`${tokenA}\n`, 0o640],
    empty: ['', 0o600],
    oversized: ['o'.repeat(4097), 0o600],
    'invalid-characters': ['bearer token a\n', 0o600],
    'two-newlines': [`${tokenA}\n\n`, 0o600],
  };
  for (const [name, [content, mode]] of Object.entries(files)) {
    await writeFile(join(directory, name), content, {mode});
    await chmod(join(directory, name), mode);
  }
  await symlink(join(directory, 'rotating'), join(directory, 'symlink'));
  let expected = tokenA;
  let probes = 0;
  const foreignRequests = [];
  const foreign = createServer({key, cert}, async (request, response) => {
    await readBody(request);
    if (request.url === '/foreign/landing-count') {
      reply(response, 200, {requests: foreignRequests.length,
        authorized: foreignRequests.filter(item => item.authorization)
          .length});
      return;
    }
    foreignRequests.push({url: request.url,
      authorization: request.headers.authorization !== undefined});
    reply(response, 200, {landed: true});
  });
  const foreignOrigin = await listen(foreign, host);
  const bearer = createServer({key, cert}, async (request, response) => {
    const body = await readBody(request);
    const authorization = request.headers.authorization;
    const control = authorization === `Bearer ${controlToken}`;
    switch (`${request.method} ${request.url}`) {
      case 'POST /bearer/probe':
        probes += 1;
        if (authorization !== `Bearer ${expected}`) {
          reply(response, 401, {authorized: false});
          return;
        }
        reply(response, 200, {authorized: true});
        return;
      case 'PUT /bearer/put':
        probes += 1;
        if (authorization !== `Bearer ${expected}`) {
          reply(response, 401, {authorized: false});
          return;
        }
        reply(response, 200, {stored: body.length});
        return;
      case 'POST /bearer/max':
        reply(response, authorization === `Bearer ${maxToken}` ? 200 : 401,
          {max: true});
        return;
      case 'POST /bearer/redirect':
        response.writeHead(307, {location: `${foreignOrigin}/landing`});
        response.end();
        return;
      case 'POST /bearer/rotate-to-b':
        if (!control) break;
        await replaceAtomically(directory, 'rotating', `${tokenB}\n`, 0o600);
        expected = tokenB;
        reply(response, 200, {rotated: true});
        return;
      case 'POST /bearer/rotate-to-shared-mode':
        if (!control) break;
        await replaceAtomically(directory, 'rotating', 'bearer-token-c\n',
          0o644);
        expected = 'bearer-token-c';
        reply(response, 200, {rotated: true});
        return;
      case 'POST /bearer/probes':
        if (!control) break;
        reply(response, 200, {probes});
        return;
      default:
        break;
    }
    reply(response, control ? 404 : 403, {refused: true});
  });
  const origin = await listen(bearer, host);
  return {
    origin,
    foreignOrigin,
    directory,
    // Authorization header value expected by the mutual TLS server's
    // combined-authentication route.
    controlAuthorization: `Bearer ${controlToken}`,
    async close() {
      bearer.close();
      foreign.close();
      await Promise.all([once(bearer, 'close'), once(foreign, 'close')]);
    },
  };
}
