// Copy this authored fixture closure to an ordinary installed consumer. Product
// imports are public package exports; artifact and fixture Sources stay separate.
import test from 'node:test';
import * as node from '@actql/node';
import * as httpHost from '@actql/local-node/http-host';
import {publicSnowflakePackageFixture} from './snowflake-public-package.fixture.mjs';
import {assertSnowflakePublicRead} from './snowflake-public-read-case.fixture.mjs';

for (const entrance of ['Local', 'HTTPS']) test(
  `installed public ${entrance} Snowflake SQL preserves decimal38 and NULL through Named Result and attach`, async t => {
    const f = await publicSnowflakePackageFixture(t, entrance, node, httpHost);
    await assertSnowflakePublicRead(t, f, entrance);
  });
