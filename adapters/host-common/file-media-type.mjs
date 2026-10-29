// Default inference for already validated logical file paths. Reported or
// explicitly configured media types remain separate facts owned by callers.
const mediaTypes = Object.freeze({txt: 'text/plain', md: 'text/markdown',
  csv: 'text/csv', json: 'application/json', jsonl: 'application/x-ndjson',
  pdf: 'application/pdf', png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg',
  xml: 'application/xml'});

export function defaultFileMediaType(path) {
  if (typeof path !== 'string') throw new TypeError('File path must be a string');
  const name = path.slice(path.lastIndexOf('/') + 1), dot = name.lastIndexOf('.');
  if (dot < 0) return 'application/octet-stream';
  const suffix = name.slice(dot + 1);
  const extension = /^[A-Za-z0-9]+$/u.test(suffix) ? suffix.toLowerCase() : '';
  return Object.hasOwn(mediaTypes, extension) ? mediaTypes[extension] : 'application/octet-stream';
}
