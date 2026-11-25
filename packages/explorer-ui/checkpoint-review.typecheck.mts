import type {ReviewReference, CheckpointEntry} from './checkpoint-review.js';
import {reviewText} from './checkpoint-review.js';
import {createExplorerBrowserSource} from '../explorer/browser-source.js';

declare const checkpoint: ReviewReference;
const source = createExplorerBrowserSource({origin: 'http://127.0.0.1:3210'});
const page = await source.checkpoints();
const same: CheckpointEntry | undefined = page.items[0];
const read = await source.reviewCheckpoint(checkpoint);
const kind: 'utf8' | 'binary' = reviewText(read).kind;
// @ts-expect-error A review projection does not supply a signature or approve callback.
read.approve();
// @ts-expect-error A view has no accepted approval or current permission Boolean.
const allowed: boolean = read.allowed;
void same;
void kind;
