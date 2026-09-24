import {retainedMatrix} from './fixtures.mjs';

process.stdout.write(JSON.stringify(retainedMatrix().map((fixture, index) => ({
  index: String(index).padStart(2, '0'),
  caseId: fixture.id,
}))) + '\n');
