// Explicit, bounded standalone configuration. Embedded application providers
// never inherit an environment overlay, and this module registers no globals.
const signalNames = ['traces', 'metrics', 'logs'];
const resourceKeys = ['service.name', 'service.version', 'deployment.environment.name'];
const fail = code => { throw new TypeError(code); };
function headers(raw) {
  if (raw === undefined) return undefined;
  const result = Object.create(null);
  const items = raw.split(',');
  if (items.length > 16) fail('InvalidActQLOTelHeaders');
  for (const item of items) {
    const split = item.indexOf('=');
    if (split < 1) fail('InvalidActQLOTelHeaders');
    const key = item.slice(0, split).trim().toLowerCase();
    let value;
    try { value = decodeURIComponent(item.slice(split + 1).trim()); }
    catch { fail('InvalidActQLOTelHeaders'); }
    result[key] = value;
  }
  return result;
}
export function environmentOptions(options, environment = process.env) {
  if (options.environment !== true) return {options, source: 'explicit', diagnostics: []};
  if (['tracerProvider', 'meterProvider', 'loggerProvider'].some(key => options[key] !== undefined)) {
    fail('ApplicationProviderEnvironmentOverlayUnsupported');
  }
  const diagnostics = [];
  const read = key => {
    const value = environment[key];
    if (value === undefined) return undefined;
    if (typeof value !== 'string' || value.length > 4096) fail('InvalidActQLOTelEnvironment');
    return value.trim() === '' ? undefined : value;
  };
  if (read('OTEL_CONFIG_FILE') !== undefined || read('OTEL_EXPERIMENTAL_CONFIG_FILE') !== undefined) {
    fail('UnsupportedActQLOTelDeclarativeConfiguration');
  }
  const disabled = read('OTEL_SDK_DISABLED')?.trim().toLowerCase();
  if (disabled !== undefined && !['true', 'false'].includes(disabled)) {
    diagnostics.push('invalid_sdk_disabled_ignored');
  }
  if (disabled === 'true') return {options: {...options, traces: false, metrics: false, logs: false},
    source: 'environment+explicit', diagnostics};
  const generic = read('OTEL_EXPORTER_OTLP_ENDPOINT');
  const defaults = {};
  if (generic !== undefined) defaults.endpoint = generic;
  const sampler = read('OTEL_TRACES_SAMPLER')?.trim().toLowerCase();
  let sampleRate = 1;
  if (sampler !== undefined && sampler !== 'parentbased_traceidratio') {
    diagnostics.push('unsupported_sampler_ignored');
  }
  const argument = sampler === 'parentbased_traceidratio' ? read('OTEL_TRACES_SAMPLER_ARG') : undefined;
  if (argument !== undefined) {
    const number = Number(argument);
    if (Number.isFinite(number) && number >= 0 && number <= 1) sampleRate = number;
    else diagnostics.push('invalid_sampler_argument_ignored');
  }
  let timeout;
  for (const signal of signalNames) {
    const name = signal.toUpperCase();
    const exporter = read(`OTEL_${name}_EXPORTER`)?.trim().toLowerCase();
    const specific = read(`OTEL_EXPORTER_OTLP_${name}_ENDPOINT`);
    if (exporter !== undefined && !['none', 'otlp'].includes(exporter)) {
      diagnostics.push(`unsupported_${signal}_exporter_ignored`);
    }
    if (exporter === 'none') { defaults[signal] = false; continue; }
    const enabled = specific !== undefined || exporter === 'otlp' ||
      signal === 'traces' && generic !== undefined;
    if (!enabled) continue;
    if (specific === undefined && generic === undefined) {
      diagnostics.push(`${signal}_destination_missing`); defaults[signal] = false; continue;
    }
    const protocol = (read(`OTEL_EXPORTER_OTLP_${name}_PROTOCOL`) ??
      read('OTEL_EXPORTER_OTLP_PROTOCOL') ?? 'http/protobuf').trim().toLowerCase();
    if (protocol !== 'http/protobuf') fail('UnsupportedActQLOTelTransport');
    let destination = specific;
    if (destination === undefined) {
      let url;
      try { url = new URL(generic); } catch { fail('InvalidActQLOTelConfiguration'); }
      const suffix = `/v1/${signal}`;
      if (!url.pathname.endsWith(suffix)) url.pathname = `${url.pathname.replace(/\/$/u, '')}${suffix}`;
      destination = url.href;
    }
    const auth = headers(read(`OTEL_EXPORTER_OTLP_${name}_HEADERS`) ??
      read('OTEL_EXPORTER_OTLP_HEADERS'));
    defaults[signal] = {endpoint: destination,
      ...(auth === undefined ? {} : {headers: auth}),
      ...(signal === 'traces' ? {sampleRate} : {})};
    const rawTimeout = read(`OTEL_EXPORTER_OTLP_${name}_TIMEOUT`) ?? read('OTEL_EXPORTER_OTLP_TIMEOUT');
    if (rawTimeout !== undefined) {
      const value = Number(rawTimeout);
      if (!Number.isSafeInteger(value) || value <= 0) diagnostics.push(`invalid_${signal}_timeout_ignored`);
      else timeout = Math.min(timeout ?? 500, value, 500);
    }
  }
  const resource = {};
  const rawResource = read('OTEL_RESOURCE_ATTRIBUTES');
  if (rawResource !== undefined) {
    const pairs = rawResource.split(',');
    if (pairs.length > 32) fail('InvalidActQLOTelResource');
    for (const item of pairs) {
      const split = item.indexOf('=');
      if (split < 1) continue;
      const key = item.slice(0, split).trim();
      // Do not decode/copy a forbidden Resource value merely to discard it.
      if (!resourceKeys.includes(key)) continue;
      try { resource[key] = decodeURIComponent(item.slice(split + 1).trim()); }
      catch { fail('InvalidActQLOTelResource'); }
    }
  }
  const service = read('OTEL_SERVICE_NAME');
  if (service !== undefined) resource['service.name'] = service;
  const propagators = read('OTEL_PROPAGATORS')?.split(',').map(item => item.trim().toLowerCase());
  if (propagators !== undefined && propagators.some(item => !['none', 'tracecontext'].includes(item))) {
    fail('UnsupportedActQLOTelPropagator');
  }
  const resolved = {...defaults, ...options,
    resource: {...resource, ...options.resource},
    limits: {...(timeout === undefined ? {} : {exportTimeoutMs: timeout}), ...options.limits}};
  if (options.endpoint !== undefined) {
    for (const signal of signalNames) {
      if (options[signal] === undefined && defaults[signal] &&
          (signal === 'traces' || read(`OTEL_${signal.toUpperCase()}_EXPORTER`)?.toLowerCase() === 'otlp')) {
        let url;
        try { url = new URL(options.endpoint); } catch { fail('InvalidActQLOTelConfiguration'); }
        const suffix = `/v1/${signal}`;
        if (!url.pathname.endsWith(suffix)) url.pathname = `${url.pathname.replace(/\/$/u, '')}${suffix}`;
        resolved[signal] = {...defaults[signal], endpoint: url.href};
      }
    }
  }
  if (propagators?.includes('none') && options.correlation === undefined) {
    resolved.correlation = {include: ['run', 'task', 'attempt']};
  }
  return {options: resolved, source: 'environment+explicit', diagnostics};
}
