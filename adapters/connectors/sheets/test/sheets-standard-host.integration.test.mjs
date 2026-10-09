import {connect} from '../../../../packages/sdk/index.mjs';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost,
  publishInstalledSource, publishInstalledEffect} from '../../../host-node/embedded-local.mjs';
import {fixtureCertificates, openHttpsExchangeFixture} from '../../../site-node/https-exchange-fixture.mjs';
import {registerSheetsAcceptance} from './sheets-public-acceptance.fixture.mjs';
import {fileURLToPath} from 'node:url';

await registerSheetsAcceptance({connect, connectEmbeddedLocal,
  openInstalledRemoteHttpHost, publishInstalledSource, publishInstalledEffect,
  canonicalJson, fixtureCertificates, openHttpsExchangeFixture,
  replayEntry: new URL('./sheets-replay-source.fixture.mjs', import.meta.url),
  scratch: fileURLToPath(new URL('../../../../_build/sheets-host/', import.meta.url))});
