import type { StageLinesErrorResult } from './types'

export class GitStageLinesError extends Error {
  reason: string
  exitCode?: number
  result?: StageLinesErrorResult
  stderr?: string

  constructor(
    message: string,
    options: {
      reason: string
      exitCode?: number
      result?: StageLinesErrorResult
      stderr?: string
      cause?: unknown
    },
  ) {
    super(message, { cause: options.cause })
    this.name = 'GitStageLinesError'
    this.reason = options.reason
    this.exitCode = options.exitCode
    this.result = options.result
    this.stderr = options.stderr
  }
}
