// Render only the retained, disclosed SDK observation supplied by the facade.
// References are data. Presentation neither performs their operations nor
// substitutes a partial fact set when the caller's output budget is too small.
import {getOperationPresentationInfo, localizeOperation} from './operation-presentation.mjs';

const utf8 = new TextEncoder();
const safeJson = value => JSON.stringify(value).replace(
  /[<>&\u007f-\u009f\u061c\u200e\u200f\u2028-\u202e\u2066-\u2069]/gu,
  character => '\\u' + character.charCodeAt(0).toString(16).padStart(4, '0'));
const html = value => value.replace(/[&<>"']/gu, character =>
  ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'})[character]);

export function formatOperationExplanation(explanation, domain, options) {
  if (explanation === undefined) return undefined;
  // Capture before reading application-owned display options. A hostile locale
  // getter may edit the original error/response, never this retained observation.
  let snapshot;
  try { snapshot = JSON.parse(JSON.stringify(explanation)); }
  catch { return undefined; }
  let format, maxBytes, locale;
  try {
    format = options?.format ?? 'text';
    maxBytes = options?.maxBytes ?? 65536;
  } catch { return undefined; }
  try { locale = options?.locale; } catch { locale = 'en'; }
  if (!['text', 'html', 'json'].includes(format) || !Number.isSafeInteger(maxBytes) ||
      maxBytes < 1024 || maxBytes > 1048576) return undefined;
  const presentation = getOperationPresentationInfo({locale});
  const localized = localizeOperation(snapshot, domain, {locale: presentation.locale});
  let output;
  if (format === 'json') output = safeJson({domain, explanation: localized, presentation});
  else {
    const {summary, hint, ...facts} = localized;
    const heading = domain + '/' + facts.observation + ': ' + summary;
    const data = safeJson(facts);
    output = format === 'html'
      ? '<section><h2>' + html(heading) + '</h2>' +
        (hint === undefined ? '' : '<p>' + html(hint) + '</p>') +
        '<pre>' + html(data) + '</pre></section>'
      : [heading, hint, data].filter(value => value !== undefined).join('\n');
  }
  return utf8.encode(output).length <= maxBytes ? output : undefined;
}
