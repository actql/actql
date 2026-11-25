// Render only the retained, disclosed SDK observation supplied by the facade.
// References are data. Presentation neither performs their operations nor
// substitutes a partial fact set when the caller's output budget is too small.
import {getOperationPresentationInfo, localizeOperation} from './operation-presentation.mjs';
import type {OperationFormatOptions} from './index.d.ts';

const utf8 = new TextEncoder();
const safeJson = (value: unknown) => JSON.stringify(value).replace(
  /[<>&\u007f-\u009f\u061c\u200e\u200f\u2028-\u202e\u2066-\u2069]/gu,
  (character: string) => '\\u' + character.charCodeAt(0).toString(16).padStart(4, '0'));
const html = (value: string) => value.replace(/[&<>"']/gu, (character: string) =>
  ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'} as Record<string, string>)[character]);

export function formatOperationExplanation(explanation: unknown, domain: string, options?: OperationFormatOptions): string | undefined {
  if (explanation === undefined) return undefined;
  // Capture before reading application-owned display options. A hostile locale
  // getter may edit the original error/response, never this retained observation.
  let snapshot: Parameters<typeof localizeOperation>[0];
  try { snapshot = JSON.parse(JSON.stringify(explanation)); }
  catch { return undefined; }
  let format: string, maxBytes: number, locale: string | undefined;
  try {
    format = options?.format ?? 'text';
    maxBytes = options?.maxBytes ?? 65536;
  } catch { return undefined; }
  try { locale = options?.locale; } catch { locale = 'en'; }
  if (!['text', 'html', 'json'].includes(format) || !Number.isSafeInteger(maxBytes) ||
      maxBytes < 1024 || maxBytes > 1048576) return undefined;
  const presentation = getOperationPresentationInfo({locale});
  const localized = localizeOperation(snapshot, domain, {locale: presentation.locale})!;
  let output;
  if (format === 'json') output = safeJson({domain, explanation: localized, presentation});
  else {
    const {summary, hint, ...facts} = localized;
    const classification = domain === 'observation' ? facts.kind : facts.observation;
    const heading = domain + '/' + classification + ': ' + summary;
    const data = safeJson(facts);
    output = format === 'html'
      ? '<section><h2>' + html(heading) + '</h2>' +
        (hint === undefined ? '' : '<p>' + html(hint) + '</p>') +
        '<pre>' + html(data) + '</pre></section>'
      : [heading, hint, data].filter(value => value !== undefined).join('\n');
  }
  return utf8.encode(output).length <= maxBytes ? output : undefined;
}
