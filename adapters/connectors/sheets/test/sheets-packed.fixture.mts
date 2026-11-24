import {connect as connectEmbeddedLocal} from '@actql/node';
import {connect} from '@actql/sdk';
import {canonicalJson} from '@actql/sdk/host-port';
import {publishSource as publishInstalledSource,
  publishEffect as publishInstalledEffect} from '@actql/local-node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {fixtureCertificates, openHttpsExchangeFixture} from '../../../site-node/https-exchange-fixture.mjs';
import {registerSheetsAcceptance} from './sheets-public-acceptance.fixture.mjs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

await registerSheetsAcceptance({connect, connectEmbeddedLocal,
  openInstalledRemoteHttpHost, publishInstalledSource, publishInstalledEffect,
  canonicalJson, fixtureCertificates, openHttpsExchangeFixture,
  replayEntry: new URL('./sheets-replay-packed.fixture.mjs', import.meta.url),
  scratch: join(tmpdir(), 'actql-packed-sheets')});
