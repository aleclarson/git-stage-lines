import { hello } from '../../src/npm/index'

test('exports the current placeholder API', () => {
  expect(hello).toBe('world')
})
