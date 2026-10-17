import {connect} from '../../../../packages/sdk/index.mjs';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost,
  publishInstalledSource, publishInstalledEffect} from '../../../host-node/embedded-local.mjs';
import {fixtureCertificates, openHttpsExchangeFixture} from '../../../site-node/https-exchange-fixture.mjs';
import {registerSheetsAcceptance} from './sheets-public-acceptance.fixture.mjs';
import {fileURLToPath} from 'node:url';
// The existing Sheets gate owns the pure declaration/recovery regressions too.
// Packed acceptance continues to import only its portable public fixtures.
import './sheets-range-command.test.mjs';
import './sheets-clear-command.test.mjs';
import './sheets-clear-profile.test.mjs';
import '../../../host-common/captured-effect-dependency-schemas.test.mjs';

await registerSheetsAcceptance({connect, connectEmbeddedLocal,
  openInstalledRemoteHttpHost, publishInstalledSource, publishInstalledEffect,
  canonicalJson, fixtureCertificates, openHttpsExchangeFixture,
  replayEntry: new URL('./sheets-replay-source.fixture.mjs', import.meta.url),
  scratch: fileURLToPath(new URL('../../../../_build/sheets-host/', import.meta.url))});
