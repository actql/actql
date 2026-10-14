import type {Client, CheckTextOptions} from '@actql/sdk';
import type {ClientSourceFormat} from '@actql/client-wire';
declare const client: Client;
const format: ClientSourceFormat = 'aql';
const check: CheckTextOptions = {format, scope: 'bound_input',
  parameterDeclarations: {p: {type: 'number', nullable: false}}};
void client.check('SELECT @p AS id', {...check, parameters: {p: 1}});
void client.startSource('SELECT @p AS id', {format, parameterDeclarations: check.parameterDeclarations,
  parameters: {p: 1}});
// @ts-expect-error Unknown spellings are not source format discovery.
const unsupported: ClientSourceFormat = 'aql2';
void unsupported;
