// Keep ordinary TAP diagnostics, then retain Node's structured cases and counts.
// The final process summary can count an empty selected file as one pass.
import {tap} from 'node:test/reporters';
import type {TestEvent} from 'node:test/reporters';
import type {EventData} from 'node:test';

type ObservedError = Error & {failureType?: unknown; code?: unknown; operator?: unknown; exitCode?: unknown; signal?: unknown};

export default async function* reporter(source: Parameters<typeof tap>[0]): AsyncGenerator<string, void, unknown> {
  const summaries: EventData.TestSummary[] = [];
  const cases: {name: string; file?: string; passed: boolean; skipped: boolean; todo: boolean;
    failureType?: unknown; errorCode?: unknown; errorMessage?: string; operator?: unknown;
    exitCode?: unknown; signal?: unknown}[] = [];
  const diagnostics: EventData.TestDiagnostic[] = [];
  async function* observe(): AsyncGenerator<TestEvent, void, unknown> {
    for await (const event of source) {
      if (event.type === 'test:summary') summaries.push(event.data);
      if (event.type === 'test:diagnostic' && event.data.file !== undefined) {
        diagnostics.push(event.data);
      }
      if (event.type === 'test:pass' || event.type === 'test:fail') {
        const {name, file, skip, todo, details} = event.data;
        const error = (details as {error?: ObservedError} | undefined)?.error;
        const cause = (error?.cause ?? error) as ObservedError | undefined;
        // Node attaches process exits to the file error, not an assertion cause.
        cases.push({name, file, passed: event.type === 'test:pass',
          skipped: Boolean(skip), todo: Boolean(todo),
          failureType: error?.failureType, errorCode: cause?.code ?? error?.code,
          errorMessage: cause?.message, operator: cause?.operator,
          exitCode: error?.exitCode, signal: error?.signal});
      }
      yield event;
    }
  }
  yield* tap(observe());
  for (const entry of cases) {
    yield `ACTQL_TEST_CASE ${JSON.stringify(entry)}\n`;
  }
  for (const entry of diagnostics) {
    yield `ACTQL_TEST_DIAGNOSTIC ${JSON.stringify(entry)}\n`;
  }
  for (const summary of summaries) {
    yield `ACTQL_TEST_SUMMARY ${JSON.stringify(summary)}\n`;
  }
}
