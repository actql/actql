import {connectEmbeddedLocal} from '../../../host-node/embedded-local.mjs';
import {replaySavedAppend} from './sheets-replay.fixture.mjs';
await replaySavedAppend(connectEmbeddedLocal, process.argv[2]);
