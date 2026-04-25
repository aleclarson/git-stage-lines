export { findBinary } from './binary'
export { GitStageLinesError } from './errors'
export { checkStageLines, dryRunStageLines, stageLines, stageLinesSync } from './run'

export type {
  FindBinaryOptions,
  StageLinesCheckedResult,
  StageLinesDryRunResult,
  StageLinesErrorResult,
  StageLinesMode,
  StageLinesNoopResult,
  StageLinesOptions,
  StageLinesRange,
  StageLinesResult,
  StageLinesSuccessResult,
} from './types'
