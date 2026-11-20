// Internal connection-string admission. The returned description is safe to
// inspect; only the transport boundary explicitly retrieves its credential.
// This module performs no discovery, authentication, connection or file I/O.
const credentials = new WeakMap();
const component = /^(?:[A-Za-z0-9._~!$&'()*+,;=:@-]|%[0-9A-Fa-f]{2})+$/u;
const credentialComponent = /^(?:[A-Za-z0-9._~!$&'()*+,;=-]|%[0-9A-Fa-f]{2})+$/u;
const invalid = () => { throw new TypeError('InvalidConnectionString'); };
const decode = value => {
  try { return decodeURIComponent(value); }
  catch { return invalid(); }
};
export const validConnectionStringCredential = value =>
  typeof value === 'string' && value.length > 0 && value.length <= 8192 &&
  !/[^\u0021-\u00ff]|\u007f/u.test(value);

// Canonical numeric targets only. Hostnames are never classified by DNS.
export const isLoopbackEndpointHostname = hostname => typeof hostname === 'string' &&
  (hostname === '[::1]' || /^127(?:\.(?:0|[1-9][0-9]{0,2})){3}$/u.test(hostname) &&
    hostname.split('.').every(part => Number(part) <= 255));

export function parseConnectionString(input) {
  if (typeof input !== 'string' || !input.isWellFormed() ||
      input.length > 16384 || /[\u0000-\u0020\u007f\\]/u.test(input)) invalid();
  // Inspect the original components before URL normalization can remove dot
  // segments or reinterpret an unescaped credential delimiter.
  const match = /^actql:\/\/([^/?#]+)\/([^/?#]+)(?:\?([^#]*))?$/iu.exec(input);
  if (match === null) invalid();
  const [, authority, encodedWorkspace, query] = match;
  // One explicit opt-in. Unknown, repeated, encoded and empty query fields
  // cannot silently select a different transport.
  if (query !== undefined && query !== 'transport=http') invalid();
  const protocol = query === undefined ? 'https:' : 'http:';
  if (!component.test(encodedWorkspace)) invalid();
  const workspaceId = decode(encodedWorkspace);
  if (!workspaceId || workspaceId.length > 256 ||
      workspaceId === '.' || workspaceId === '..' ||
      /[\u0000-\u001f\u007f/\\]/u.test(workspaceId)) invalid();

  let target = authority, credential;
  const separator = authority.indexOf('@');
  if (separator !== -1) {
    if (authority.indexOf('@', separator + 1) !== -1) invalid();
    const userinfo = authority.slice(0, separator);
    if (!userinfo.startsWith('token:')) invalid();
    const encodedCredential = userinfo.slice('token:'.length);
    if (!credentialComponent.test(encodedCredential)) invalid();
    credential = decode(encodedCredential);
    if (!validConnectionStringCredential(credential)) invalid();
    target = authority.slice(separator + 1);
  }
  // A connection string identifies one network Host. Embedded Local remains
  // an explicit constructor; neither localhost nor failure starts a daemon.
  if (!target || target.includes('%')) invalid();
  let endpoint;
  try {
    const url = new URL(`${protocol}//${target}/`);
    if (url.username || url.password || url.pathname !== '/' ||
        url.search || url.hash || !url.hostname) invalid();
    if (protocol === 'http:') {
      if (url.port === '0') invalid();
      const hostname = target.startsWith('[')
        ? target.slice(0, target.indexOf(']') + 1) : target.split(':')[0];
      if (hostname.toLowerCase() === 'localhost') {
        // Pin localhost before Fetch. Hosts files, DNS or family fallback
        // cannot redirect an unencrypted bearer credential off loopback.
        url.hostname = '127.0.0.1';
      } else if (!isLoopbackEndpointHostname(hostname) &&
          !(hostname.startsWith('[') && url.hostname === '[::1]')) invalid();
      if (!isLoopbackEndpointHostname(url.hostname)) invalid();
    }
    endpoint = url.origin;
  } catch { invalid(); }
  const description = Object.freeze({endpoint: `${endpoint}/`, workspaceId});
  if (credential !== undefined) credentials.set(description, credential);
  return description;
}

// This internal accessor is deliberately separate from enumerable description
// data. Cloning, JSON, inspection and diagnostics do not copy the credential.
export const connectionStringCredential = description =>
  credentials.get(description);
