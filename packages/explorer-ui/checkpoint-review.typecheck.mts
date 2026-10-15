import type {Client,CheckpointSummary} from '@actql/sdk';
import {readWaitingCheckpoints,readCheckpointReview,reviewText} from './checkpoint-review.js';
import {createReadEpoch} from './read-model.js';
declare const client:Client;declare const checkpoint:CheckpointSummary;
const ticket=createReadEpoch().capture();
const page=await readWaitingCheckpoints(client,ticket);
const same:CheckpointSummary|undefined=page.items[0];
const read=await readCheckpointReview(client,checkpoint,ticket);
const kind:'utf8'|'binary'=reviewText(read).kind;
// @ts-expect-error A review projection does not supply a signature or approve callback.
read.approve();
// @ts-expect-error A view has no accepted approval or current permission Boolean.
const allowed:boolean=read.allowed;
void same;void kind;
