import {createCheckDocumentSession, resolveCheckTextRangeEncoding,
  type Client, type CheckPositionEncoding, type CheckTextRange} from '@actql/sdk';
declare const client: Client;
const encoding: CheckPositionEncoding = 'utf-8';
const session = createCheckDocumentSession(client, {text: 'SELECT (', version: -1, positionEncoding: encoding});
session.update('SELECT (', 0);
const observation = await session.check({format: 'sql'});
const rendered: string | undefined = session.format(observation, {format: 'json', locale: 'ja'});
// @ts-expect-error The document session uses its negotiated position encoding.
session.format(observation, {positionEncoding: 'utf-32'});
void rendered;
if (observation.outcome.outcome === 'completed') {
  const location = observation.outcome.report.reasons[0]?.location;
  if (location) {
    const range: CheckTextRange | undefined = session.resolveTextRange(observation, location);
    const utf8: CheckTextRange<'utf-8'> | undefined =
      resolveCheckTextRangeEncoding(observation.outcome, location, 'utf-8');
    void range; void utf8;
  }
}
// @ts-expect-error Unknown encodings are not implicitly UTF-16.
createCheckDocumentSession(client, {text: '', version: 1, positionEncoding: 'unknown'});
// @ts-expect-error A check explicitly supplies its source format.
session.check({});
session.close();
