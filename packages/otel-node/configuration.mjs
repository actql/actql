// Explicit application configuration; no OTel environment fallbacks, resource
// detection, default localhost destination or transport inference.
import {createHostObservationConnection} from '@actql/local-node/observation';
export const managedLimits = Object.freeze({payloadBytes: 65536,
  windowBytes: 262144, windowRecords: 256, windowMs: 60000,
  exportTimeoutMs: 500, shutdownMs: 1000, responseBytes: 4096});
const signals = ['traces', 'metrics', 'logs'];
const fail = () => { throw new TypeError('InvalidActQLOTelConfiguration'); };
function endpoint(value) {
  let url;
  try { url = new URL(value); } catch { fail(); }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password ||
      url.search || url.hash || url.href.length > 2048) fail();
  return url.href;
}
export function observationConfiguration(options = {}) {
  if (!options || typeof options !== 'object' || Array.isArray(options) ||
      Object.keys(options).some(key => !['endpoint', 'traces', 'metrics', 'logs',
        'transport', 'host', 'limits', 'scope', 'revision', 'include', 'exclude',
        'correlation', 'projectionLimits', 'tracerProvider', 'meterProvider', 'loggerProvider'].includes(key)) ||
      options.transport !== undefined && options.transport !== 'http/protobuf' ||
      options.host !== undefined && options.host !== 'node') fail();
  // Validate bounded labels, selectors and projection caps before constructing
  // any SDK/provider. Use the Host's validation, not another rule table.
  createHostObservationConnection({deliver() {}, scope: options.scope,
    revision: options.revision, include: options.include, exclude: options.exclude,
    correlation: options.correlation, limits: options.projectionLimits});
  const selected = {};
  for (const signal of signals) {
    let setting = options[signal];
    if (setting === undefined && signal === 'traces' && options.endpoint !== undefined) {
      const base = new URL(endpoint(options.endpoint));
      base.pathname = `${base.pathname.replace(/\/$/u, '')}/v1/traces`;
      setting = {endpoint: base.href};
    }
    if (setting === undefined || setting === false) continue;
    if (!setting || typeof setting !== 'object' || Array.isArray(setting) ||
        Object.keys(setting).some(key => !['endpoint', 'sampleRate'].includes(key)) ||
        typeof setting.endpoint !== 'string' || signal !== 'traces' &&
          setting.sampleRate !== undefined) fail();
    const sampleRate = setting.sampleRate ?? 1;
    if (!Number.isFinite(sampleRate) || sampleRate < 0 || sampleRate > 1) fail();
    selected[signal] = Object.freeze({endpoint: endpoint(setting.endpoint), sampleRate});
  }
  const limits = {...managedLimits};
  if (options.limits !== undefined) {
    if (!options.limits || typeof options.limits !== 'object' || Array.isArray(options.limits)) fail();
    for (const [key, value] of Object.entries(options.limits)) {
      if (!Object.hasOwn(limits, key) || key === 'windowMs' && value !== limits[key] ||
          !Number.isSafeInteger(value) ||
          value < 1 || value > limits[key]) fail();
      limits[key] = value;
    }
  }
  if (limits.payloadBytes > limits.windowBytes) fail();
  const applicationOwned = ['tracerProvider', 'meterProvider', 'loggerProvider']
    .some(key => options[key] !== undefined);
  if (applicationOwned && Object.keys(selected).length !== 0) fail();
  for (const [key, method] of [['tracerProvider', 'getTracer'],
    ['meterProvider', 'getMeter'], ['loggerProvider', 'getLogger']]) {
    if (options[key] !== undefined && typeof options[key]?.[method] !== 'function') fail();
  }
  return Object.freeze({signals: Object.freeze(selected), limits: Object.freeze(limits),
    applicationOwned});
}
