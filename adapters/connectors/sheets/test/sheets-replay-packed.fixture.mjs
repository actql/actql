import {connect} from '@actql/node';
import {replaySavedAppend} from './sheets-replay.fixture.mjs';
await replaySavedAppend(connect, process.argv[2]);
