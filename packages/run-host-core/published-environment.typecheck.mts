import {preparePublishedEnvironment, publishedEnvironmentMatches, prepareSourceProgram,
  restoreSourceProgram, prepare, prepareProgram, prepareEffect} from '@actql/run-host-core';
import type {CheckEnvironment, SubmittedIntent, SourceProgramOriginals,
  PreparedPublishedEnvironment} from '@actql/run-host-core';
declare const environment: CheckEnvironment;
declare const intent: SubmittedIntent;
declare const originals: SourceProgramOriginals;
const retained: PreparedPublishedEnvironment = preparePublishedEnvironment(environment, 'publication');
const same: boolean = publishedEnvironmentMatches(retained, environment, 'publication');
prepareSourceProgram(intent, environment, 'publication', retained);
restoreSourceProgram(originals, environment, retained);
prepare('program', 'json', environment, undefined, retained);
prepareProgram('program', 'json', environment, undefined, retained);
prepareEffect('program', 'json', environment, undefined, retained);
// @ts-expect-error A publication wire is not a nominal prepared Environment.
prepareSourceProgram(intent, environment, 'publication', 'publication');
// @ts-expect-error Caller DATA cannot replace the original admitted Environment.
preparePublishedEnvironment({}, 'publication');
void same;
