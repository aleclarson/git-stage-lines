export type StageLinesMode = 'new' | 'old' | 'both'

export type StageLinesRange = number | [number, number]

export type StageLinesOptions = {
  file: string
  ranges: string | StageLinesRange[]

  mode?: StageLinesMode

  cwd?: string
  binaryPath?: string

  dryRun?: boolean
  check?: boolean
  allowEmpty?: boolean
  verbose?: boolean

  context?: number

  env?: Record<string, string | undefined>
  signal?: AbortSignal
}

export type FindBinaryOptions = {
  binaryPath?: string
  cwd?: string
  env?: Record<string, string | undefined>
}

export type StageLinesResult =
  | StageLinesSuccessResult
  | StageLinesCheckedResult
  | StageLinesDryRunResult
  | StageLinesNoopResult
  | StageLinesErrorResult

export type StageLinesSuccessResult = {
  status: 'staged'
  file: string
  ranges: string[]
  mode: StageLinesMode
  selected_changes: number
  skipped_changes: number
  patch_applied: true
  would_apply?: boolean
}

export type StageLinesCheckedResult = {
  status: 'checked'
  file: string
  ranges: string[]
  mode: StageLinesMode
  selected_changes: number
  skipped_changes: number
  patch_applied: false
  would_apply: true
}

export type StageLinesDryRunResult = {
  status: 'dry-run'
  file: string
  ranges: string[]
  mode: StageLinesMode
  selected_changes: number
  skipped_changes: number
  patch_applied: false
  would_apply: true
  patch: string
}

export type StageLinesNoopResult = {
  status: 'noop'
  file: string
  ranges: string[]
  mode: StageLinesMode
  selected_changes: 0
  skipped_changes: number
  patch_applied: false
  would_apply?: boolean
  reason: 'no_matching_changes' | 'empty_patch' | 'no_unstaged_changes'
}

export type StageLinesErrorResult = {
  status: 'error'
  reason: string
  message: string
  file?: string
  ranges?: string[]
  exit_code?: number
  stderr?: string
}
