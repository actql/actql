import type {Client, SubmissionOptions} from '@actql/sdk';

declare const client: Client;
const selected: SubmissionOptions = {readOnly: true};
client.start({}, selected);
client.startSource('SELECT 1', {format: 'sql', readOnly: true});
client.startSource('SELECT 1', {format: 'sql', readOnly: true, stopBefore: 'commit'});
client.startSource('SELECT 1', {format: 'sql'});
client.sql('SELECT 1');
// @ts-expect-error Only the explicit true restriction is admitted.
client.start({}, {readOnly: false});
// @ts-expect-error Null cannot remove a selected continuation restriction.
client.start({}, {readOnly: null});
// @ts-expect-error A short query cannot opt back into an Effect Program.
client.sql('SELECT 1', {}, {readOnly: false});
// @ts-expect-error Unknown packet spellings are not the original choice.
client.start({}, {readonly: true});
