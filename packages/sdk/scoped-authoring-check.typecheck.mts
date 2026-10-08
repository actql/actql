import type {Client, CheckOutcome, CheckTextOptions, ProgramCheckOptions} from '@actql/sdk';
import {createCheckDocumentSession, createCheckSupplementationSession} from '@actql/sdk';
declare const client: Client;
declare const program: Record<string, unknown>;
const text = 'SELECT @x AS n';
const checked: Promise<CheckOutcome> = client.check(text, {
  kind: 'text', scope: 'template_only', format: 'sql', parameterDeclarations: {x: {type: 'number'}},
});
const structured: Promise<CheckOutcome> = client.check(program, {kind: 'program', scope: 'template_only'});
client.check(program, {kind: 'program', scope: 'bound_input', parameters: {x: null}});
client.check(text, {kind: 'text', scope: 'bound_input', format: 'aql-text'});
// @ts-expect-error Scope cannot be omitted.
client.check(text, {kind: 'text', format: 'sql'});
// @ts-expect-error Input kind cannot be inferred from a string.
client.check(text, {scope: 'bound_input', format: 'sql'});
// @ts-expect-error A Program cannot borrow the text overload.
client.check(program, {kind: 'text', scope: 'template_only', format: 'sql'});
// @ts-expect-error Template scope has no submitted bindings.
client.check(text, {kind: 'text', scope: 'template_only', format: 'sql', parameters: {}});
// @ts-expect-error Null is still a submitted bindings member.
const invalid: ProgramCheckOptions = {kind: 'program', scope: 'template_only', parameters: null};
// @ts-expect-error Structured input has no text format selection.
client.check(program, {kind: 'program', scope: 'template_only', format: 'sql'});
const document = createCheckDocumentSession(client, {text, version: 1});
const documentOptions: CheckTextOptions = {scope: 'template_only', format: 'sql'};
document.check(documentOptions);
// @ts-expect-error A document session also requires scope on every call.
document.check({format: 'sql'});
const supplement = createCheckSupplementationSession(client, {maxAttempts: 3});
supplement.check(program, {kind: 'program', scope: 'template_only'});
supplement.check(text, {kind: 'text', scope: 'bound_input', format: 'sql', parameters: {x: 1}});
void [checked, structured, invalid];
