import { defineConfig } from 'tsdown'
import ApiSnapshot from 'tsnapi/rolldown'

export default defineConfig({
  entry: ['src/npm/index.ts', 'src/npm/cli.ts'],
  format: ['esm'],
  dts: true,
  plugins: [ApiSnapshot()],
})
