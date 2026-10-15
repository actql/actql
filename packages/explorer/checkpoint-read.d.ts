import type {Client} from '@actql/sdk';
import type {ReadTicket} from '@actql/explorer-ui/read-model';
import type {CheckpointPageModel,ReviewReference,ReviewObservation} from '@actql/explorer-ui/checkpoint-review';
export function readWaitingCheckpoints(client:Partial<Pick<Client,'checkpoints'>>,ticket:ReadTicket):Promise<CheckpointPageModel>;
export function readCheckpointReview(client:Partial<Pick<Client,'reviewCheckpoint'>>,reference:ReviewReference,ticket:ReadTicket):Promise<ReviewObservation>;
