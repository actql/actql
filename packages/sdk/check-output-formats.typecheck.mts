import {formatCheckOutcome, type CheckFormatOptions, type CheckInput} from '@actql/sdk';
const input: CheckInput = {kind: 'text', documentId: 'source', revision: 'rev:fixture', text: 'SELECT ('};
const options: CheckFormatOptions = {format: 'json', locale: 'ja', maxBytes: 2048, currentInputs: [input]};
const rendered: string | undefined = formatCheckOutcome({}, options);
// @ts-expect-error Unknown output formats cannot become an implicit display mode.
formatCheckOutcome({}, {format: 'shell'});
void rendered;
