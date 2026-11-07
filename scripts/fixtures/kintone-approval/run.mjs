// Copy this directory and its record-approval sibling into a normal installation.
import {connect} from '@actql/node';
import {runRecordApprovalCommand} from '../record-approval/command.mjs';
import {kintoneUpdateCase} from '../record-approval/cases.mjs';
import {runKintoneApprovalPhase} from './workflow.mjs';

await runRecordApprovalCommand({argv: process.argv.slice(2),
  programDirectory: new URL('.', import.meta.url), connect,
  runPhase: runKintoneApprovalPhase, createDefinition: kintoneUpdateCase});
