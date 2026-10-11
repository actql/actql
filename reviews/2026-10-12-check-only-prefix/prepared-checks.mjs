import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests("moon",process.argv.slice(1),{cwd:process.cwd()});';
const format = process.argv.includes('--format');
const info = process.argv.includes('--info');
process.exitCode = await runLocalCheck({root:process.cwd(), heavy:false,
  timeoutSeconds:60, graceSeconds:5, steps: format ? [{
    name:'Format only affected prefix owners and controls', command:'moon', args:['fmt',
      'src/stage_syntax/input.mbt','src/stage_syntax/stages.mbt','src/stage_syntax/prefix_test.mbt','src/stage_syntax/reuse.mbt',
      'src/stage_parameters/source.mbt','src/stage_parameters/operations.mbt',
      'src/stage_results/local_program.mbt','src/stage_results/wiring.mbt',
      'src/stage_results/checked_topology.mbt','src/stage_results/prefix_topology_test.mbt',
      'src/pipeline_check_context/prefix_sourceview_test.mbt'],
  }] : info ? [{name:'Generate actual prefix Owner interfaces', command:'moon',
    args:['info','--target','js','src/stage_syntax','src/stage_parameters','src/stage_results']},
  ] : [{name:'Prefix static ownership and existing strict publication controls',command:'node',
    args:['--input-type=module','-e',runner,'--target','js',
      'src/stage_syntax/prefix_test.mbt','src/stage_results/prefix_topology_test.mbt',
      'src/stage_results/checked_topology_test.mbt','src/stage_results/local_program_test.mbt',
      'src/pipeline_check_context/prefix_sourceview_test.mbt'],
  }]});
