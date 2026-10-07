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

export function parseConnectionString(input) {
  if (typeof input !== 'string' || !input.isWellFormed() ||
      input.length > 16384 || /[\u0000-\u0020\u007f\\]/u.test(input)) invalid();
  // Inspect the original components before URL normalization can remove dot
  // segments or reinterpret an unescaped credential delimiter.
  const match = /^actql:\/\/([^/?#]+)\/([^/?#]+)$/iu.exec(input);
  if (match === null) invalid();
  const [, authority, encodedWorkspace] = match;
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
    const url = new URL(`https://${target}/`);
    if (url.username || url.password || url.pathname !== '/' ||
        url.search || url.hash || !url.hostname) invalid();
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
