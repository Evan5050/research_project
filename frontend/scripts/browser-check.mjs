// Drive a real headless Chromium through the NextLab demo loop via the DevTools protocol.
// No extra dependencies (Node's built-in WebSocket and fetch).
//   CHROME="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
//     node frontend/scripts/browser-check.mjs http://127.0.0.1:8080 /tmp/nextlab-shots
import { spawn } from 'node:child_process'
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const url = process.argv[2] ?? 'http://127.0.0.1:8080'
const out = process.argv[3] ?? join(tmpdir(), 'nextlab-shots')
const chrome = process.env.CHROME ?? '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser'
mkdirSync(out, { recursive: true })
const port = 9333
const browser = spawn(chrome, [
  '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${mkdtempSync(join(tmpdir(), 'nl-prof-'))}`,
  '--no-first-run', '--no-default-browser-check', '--disable-extensions', 'about:blank',
], { stdio: 'ignore' })

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
let failures = 0
const check = (label, ok, detail = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${label}${detail ? ` — ${detail}` : ''}`)
  if (!ok) failures++
}

async function connect() {
  for (let i = 0; i < 50; i++) {
    try {
      const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()
      const page = targets.find((t) => t.type === 'page')
      if (page) return page.webSocketDebuggerUrl
    } catch {}
    await sleep(200)
  }
  throw new Error('browser did not start')
}

const ws = new WebSocket(await connect())
await new Promise((r) => ws.addEventListener('open', r, { once: true }))
let id = 0
const waiting = new Map()
const listeners = []
ws.addEventListener('message', (ev) => {
  const msg = JSON.parse(ev.data)
  if (msg.id && waiting.has(msg.id)) {
    const { resolve, reject } = waiting.get(msg.id)
    waiting.delete(msg.id)
    if (msg.error) reject(new Error(msg.error.message))
    else resolve(msg.result)
  } else if (msg.method) listeners.forEach((l) => l(msg))
})
const send = (method, params = {}) =>
  new Promise((resolve, reject) => {
    const n = ++id
    waiting.set(n, { resolve, reject })
    ws.send(JSON.stringify({ id: n, method, params }))
  })
const evaluate = async (expr) => {
  const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true })
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description ?? ''))
  return r.result.value
}
const text = () => evaluate('document.body.innerText')
async function waitFor(expr, label, ms = 15000) {
  const t0 = Date.now()
  while (Date.now() - t0 < ms) {
    if (await evaluate(expr)) return true
    await sleep(100)
  }
  check(`wait: ${label}`, false, 'timed out')
  return false
}
const primary = () => evaluate(`(() => { const b = document.querySelector('button.primary'); return b ? { label: b.innerText, disabled: b.disabled } : null })()`)
const clickPrimary = () => evaluate(`document.querySelector('button.primary').click()`)
const clickButton = (label) => evaluate(`[...document.querySelectorAll('button')].find(b => b.innerText.trim() === ${JSON.stringify(label)}).click()`)
let shot = 0
async function screenshot(name, full = false) {
  const r = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: full })
  const file = join(out, `${String(++shot).padStart(2, '0')}-${name}.png`)
  writeFileSync(file, Buffer.from(r.data, 'base64'))
  console.log(`     screenshot ${file}`)
}
const viewport = (w, h) => send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false })

const apiCalls = []
listeners.push((m) => {
  if (m.method === 'Network.requestWillBeSent' && m.params.request.url.includes('/api/')) apiCalls.push(new URL(m.params.request.url).pathname)
})
await send('Page.enable')
await send('Runtime.enable')
await send('Network.enable')
await viewport(1366, 768)
await send('Page.navigate', { url })

// 1. Load and compare
await waitFor(`document.querySelector('button.primary')?.innerText === 'Recommend next measurement' && !document.querySelector('button.primary').disabled`, 'initial analysis')
await waitFor(`!!document.querySelector('.plot-canvas .main-svg')`, 'plot rendered')
await sleep(400)
let t = await text()
check('initial: 3 lengths, 9 observations shown', t.includes('3 lengths') && t.includes('9 period observations'))
check('initial: hidden lengths explained', t.includes('stay hidden for replay'))
check('initial: source label and attribution', t.includes('Recorded pendulum measurements') && t.includes('Calvin College'))
const axes = await evaluate(`[...document.querySelectorAll('.plot-canvas .xtitle, .plot-canvas .ytitle')].map(e => e.textContent)`)
check('plot axis labels with units', axes.some((a) => a.includes('(m), log scale')) && axes.some((a) => a.includes('Reported period (s)')), JSON.stringify(axes))
const legend = await evaluate(`[...document.querySelectorAll('.plot-canvas .legendtext')].map(e => e.textContent)`)
check('legend lists the three models', ['Linear', 'Square root', 'Restricted quadratic'].every((n) => legend.includes(n)), JSON.stringify(legend))
const cards = await evaluate(`[...document.querySelectorAll('.card')].map(c => c.innerText.replace(/\\s+/g, ' '))`)
check('three model cards with formula, validation error and support', cards.length === 3 && cards.every((c) => c.includes('Validation error') && c.includes('Relative support')), cards.join(' | '))
check('no reveal button before a snapshot exists', !(await text()).includes('Reveal recorded measurement'))
const above = await evaluate(`(() => { const b = document.querySelector('button.primary').getBoundingClientRect(); const p = document.querySelector('.plot-canvas').getBoundingClientRect(); return { button: b.bottom, plot: p.bottom } })()`)
check('primary action and plot above the fold at 1366x768', above.button < 768 && above.plot < 768, JSON.stringify(above))
await screenshot('initial-1366x768')
await evaluate(`document.querySelector('details.assumptions').open = true`)
t = await text()
check('assumptions separate repeat variation from uncertainty of a mean; spread not a confidence interval',
  t.includes('Variation among repeats') && t.includes('Uncertainty of a setting mean') && t.includes('not a confidence interval'))
await evaluate(`document.querySelector('details.assumptions').open = false`)

// 2. Recommend (with a same-tick double click)
const before = apiCalls.filter((p) => p === '/api/recommend').length
await evaluate(`(() => { const b = document.querySelector('button.primary'); b.click(); b.click() })()`)
await waitFor(`document.querySelector('button.primary')?.innerText.startsWith('Reveal recorded measurement')`, 'snapshot frozen')
check('double click sent one recommend request', apiCalls.filter((p) => p === '/api/recommend').length - before === 1)
t = await text()
check('recommendation shows 16 m and frozen predictions', t.includes('Next measurement: 16 m') && t.includes('Frozen predictions'))
check('extrapolation beyond measured range stated', t.includes('every model is extrapolating'))
check('space-filling choice labelled honestly', t.includes('Space-filling validation point') && t.includes('not chosen to tell the models apart'))
check('numerical separation explanation', /Support-weighted model spread here: [0-9.]+ s, [0-9.]+× the uncertainty of a setting mean/.test(t))
check('off-scale predictions disclosed', t.includes('Off scale:'))
await screenshot('recommended')

// 3. Reveal
await clickPrimary()
await waitFor(`document.body.innerText.includes('Recorded at 16 m')`, 'revealed')
t = await text()
check('reveal shows the three recorded periods and mean', t.includes('7.68, 8.01, 7.68') && t.includes('Mean 7.79 s'))
check('errors use frozen predictions; not refitted yet', t.includes('Errors are observed mean − frozen prediction') && t.includes('have not been refitted'))
const p3 = await primary()
check('next action is Update (recommend blocked until update)', p3?.label === 'Update models with the new observations', JSON.stringify(p3))
await screenshot('revealed')

// 4. Update
await clickPrimary()
await waitFor(`document.body.innerText.includes('What changed after adding 16 m')`, 'updated')
t = await text()
check('update shows support and validation error changes', t.includes('→'))
check('history keeps the earlier prediction', t.includes('Prediction history') && t.includes('16 m'))
check('observed counts updated to 4 lengths, 12 observations', t.includes('4 lengths') && t.includes('12 period observations'))
await screenshot('updated')

// 5. Repeat
await clickPrimary()
await waitFor(`document.body.innerText.includes('Next measurement: 8 m')`, 'second recommendation')
t = await text()
check('zero weighted spread is explained, with the unweighted range shown',
  t.includes('holds essentially all the relative support') && t.includes('unweighted predictions still range from'))
await screenshot('second-recommendation')

// 6. Reset mid-cycle
await clickButton('Reset demo')
await waitFor(`document.querySelector('button.primary')?.innerText === 'Recommend next measurement' && document.body.innerText.includes('9 period observations')`, 'reset')
t = await text()
check('reset clears history and snapshot', !t.includes('Prediction history') && !t.includes('Next measurement:'))

// 7. Request failures, intercepted in the browser: unavailable, invalid data, stale response
let fetchMode = null
const held = []
listeners.push((m) => {
  if (m.method !== 'Fetch.requestPaused') return
  const rid = m.params.requestId
  if (fetchMode === 'fail') void send('Fetch.failRequest', { requestId: rid, errorReason: 'ConnectionRefused' })
  else if (fetchMode === 'invalid')
    void send('Fetch.fulfillRequest', {
      requestId: rid, responseCode: 422, responseHeaders: [{ name: 'Content-Type', value: 'application/json' }],
      body: Buffer.from(JSON.stringify({ error: 'The experiment context is inconsistent.',
        fields: [{ field: 'context.observed', message: 'Observed rows do not match the recorded demo data.' }] })).toString('base64'),
    })
  else if (fetchMode === 'hold') held.push(rid)
  else void send('Fetch.continueRequest', { requestId: rid })
})
await send('Fetch.enable', { patterns: [{ urlPattern: '*/api/recommend*' }, { urlPattern: '*/api/demo/reveal*' }] })

fetchMode = 'fail'
await clickPrimary()
await waitFor(`document.body.innerText.includes('Backend unavailable')`, 'unavailable banner')
check('backend failure shown, primary action re-enabled', !(await primary())?.disabled)
await screenshot('backend-unavailable')

fetchMode = null
await clickPrimary()
await waitFor(`document.body.innerText.includes('Next measurement: 16 m') && !document.body.innerText.includes('Backend unavailable')`, 'recovered after failure')
fetchMode = 'invalid'
await clickPrimary()
await waitFor(`document.body.innerText.includes('The experiment context is inconsistent.')`, 'invalid-data banner')
t = await text()
check('invalid data shows field-level message; snapshot kept, reveal still offered',
  t.includes('context.observed') && (await primary())?.label.startsWith('Reveal recorded measurement'))
await screenshot('invalid-data')

fetchMode = 'hold'
await clickButton('Reset demo')
await waitFor(`document.querySelector('button.primary')?.innerText === 'Recommend next measurement' && !document.querySelector('button.primary').disabled`, 'reset before stale test')
await clickPrimary()
for (let i = 0; i < 50 && held.length === 0; i++) await sleep(100)
check('recommend request is held in flight', held.length === 1)
await clickButton('Reset demo')
await waitFor(`document.querySelector('button.primary')?.innerText === 'Recommend next measurement' && !document.querySelector('button.primary').disabled`, 'reset while request in flight')
fetchMode = null
await send('Fetch.continueRequest', { requestId: held.pop() })
await sleep(1500)
t = await text()
check('stale response after reset is ignored (no snapshot appears)', !t.includes('Next measurement:') && (await primary())?.label === 'Recommend next measurement')
await send('Fetch.disable')

// 7b. Run the replay to completion; record which honest states the real data produce.
const seen = { kinds: [], lowSeparation: false, poorFit: false, increasedError: false }
for (let cycle = 1; cycle <= 7; cycle++) {
  if ((await text()).includes('Replay complete')) break
  await clickPrimary()
  await waitFor(`document.querySelector('button.primary')?.innerText.startsWith('Reveal') || document.body.innerText.includes('Replay complete')`, `cycle ${cycle} recommend`)
  t = await text()
  if (t.includes('Replay complete')) break
  seen.kinds.push(t.includes('Largest model disagreement') ? 'disagreement' : 'space-filling')
  seen.lowSeparation ||= t.includes('Low separation')
  seen.poorFit ||= t.includes('Poor fit (heuristic)')
  if (t.includes('Low separation')) await screenshot(`low-separation-cycle${cycle}`)
  await clickPrimary()
  await waitFor(`document.querySelector('button.primary')?.innerText.startsWith('Update')`, `cycle ${cycle} reveal`)
  await clickPrimary()
  await waitFor(`document.body.innerText.includes('What changed after adding') || document.body.innerText.includes('Replay complete')`, `cycle ${cycle} update`)
  seen.poorFit ||= (await text()).includes('Poor fit (heuristic)')
}
t = await text()
check('replay reaches the no-candidates state', t.includes('Replay complete') && (await primary()) === null)
check('history has one row per revealed length', (await evaluate(`document.querySelectorAll('.history tbody tr').length`)) === 6)
console.log(`     replay choices: ${seen.kinds.join(', ')}; low-separation shown: ${seen.lowSeparation}; poor-fit shown: ${seen.poorFit}`)
await screenshot('replay-complete', true)
await clickButton('Reset demo')
await waitFor(`document.querySelector('button.primary')?.innerText === 'Recommend next measurement'`, 'reset after completion')
await clickPrimary()
await waitFor(`document.body.innerText.includes('Next measurement: 16 m')`, 'recommend after reset')

// 8. Smaller laptop viewport
await viewport(1280, 720)
await sleep(500)
const small = await evaluate(`(() => { const b = document.querySelector('button.primary').getBoundingClientRect(); return { bottom: b.bottom, width: document.documentElement.scrollWidth } })()`)
check('1280x720: primary action visible, no horizontal scroll', small.bottom < 720 && small.width <= 1280, JSON.stringify(small))
await screenshot('recommended-1280x720')
await viewport(1366, 768)
await waitFor(`document.body.innerText.includes('Benchmark evidence (simulation, not pendulum data)') && document.body.innerText.includes('No clear difference')`, 'benchmark loaded')
await screenshot('full-page', true)

console.log(failures === 0 ? '\nBrowser check passed.' : `\n${failures} check(s) failed.`)
ws.close()
browser.kill()
process.exit(failures === 0 ? 0 : 1)
