// Source-qualified public callers, not an installed npm/Local Python release.
import test from 'node:test';
import {publicSnowflakeFixture} from './public-snowflake.fixture.mjs';
import {assertSnowflakePublicRead} from './snowflake-public-read-case.fixture.mjs';

for (const entrance of ['Local', 'HTTPS']) test(
  `public ${entrance} Snowflake SQL preserves decimal38 and NULL through Named Result and attach`, async t => {
    const f = await publicSnowflakeFixture(t, entrance);
    await assertSnowflakePublicRead(t, f, entrance);
  });

test('public Local Snowflake submits the original Query and preserves its filter', async t => {
  const f = await publicSnowflakeFixture(t, 'Local');
  await assertSnowflakePublicRead(t, f, 'Local', {filtered: true});
});
