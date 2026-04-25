#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import process from 'node:process'

import { resolveBinary } from './binary'
import { GitStageLinesError } from './errors'

try {
  const resolved = resolveBinary({ excludePath: process.argv[1] })
  const result = spawnSync(resolved.command, [...resolved.argsPrefix, ...process.argv.slice(2)], {
    env: process.env,
    shell: false,
    stdio: 'inherit',
  })

  if (result.error) {
    throw result.error
  }

  if (result.signal) {
    console.error(`git-stage-lines: terminated with signal ${result.signal}`)
    process.exit(1)
  }

  process.exit(result.status ?? 0)
} catch (error) {
  const message = error instanceof Error ? error.message : String(error)
  console.error(`git-stage-lines: ${message}`)
  process.exit(error instanceof GitStageLinesError && error.reason === 'binary_not_found' ? 127 : 1)
}
