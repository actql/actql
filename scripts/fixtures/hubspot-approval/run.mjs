// Copy this directory and its record-approval sibling into a normal installation.
import {connect} from '@actql/node';
import {runRecordApprovalCommand} from '../record-approval/command.mjs';
import {hubspotUpdateCase} from '../record-approval/cases.mjs';
import {runHubSpotApprovalPhase} from './workflow.mjs';

await runRecordApprovalCommand({argv: process.argv.slice(2),
  programDirectory: new URL('.', import.meta.url), connect,
  runPhase: runHubSpotApprovalPhase, createDefinition: hubspotUpdateCase});
