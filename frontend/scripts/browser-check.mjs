// Drive a real headless Chromium through the NextLab demo loop via the DevTools protocol.
// No extra dependencies (Node's built-in WebSocket and fetch).
//   CHROME="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
//     node frontend/scripts/browser-check.mjs http://127.0.0.1:8080 /tmp/nextlab-shots
import { spawn } from 'node:child_process'
import { unlinkSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from 'node:fs'
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
const pageErrors = []
listeners.push((m) => {
  if (m.method === 'Runtime.exceptionThrown') pageErrors.push(m.params.exceptionDetails.exception?.description ?? m.params.exceptionDetails.text)
  if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') pageErrors.push(m.params.args.map((a) => a.value ?? a.description).join(' '))
})
await send('Runtime.enable')
await send('Network.enable')
const allRequests = []
listeners.push((m) => {
  if (m.method === 'Network.requestWillBeSent') allRequests.push(m.params.request.url)
})
await send('Network.setBlockedURLs', { urls: ['https://*'] })
await viewport(1366, 768)
await send('Page.navigate', { url })

// 0. Readiness: the server reports warmed-up code paths.
const ready = await (await fetch(`${url}/api/ready`)).json()
check('server reports ready after warmup', ready.ready === true && ready.checks.some((c) => c.name === 'warmed_up' && c.ok), JSON.stringify(ready.warmup))

// 1. Load and compare
await waitFor(`document.querySelector('button.primary')?.innerText === 'Recommend next measurement' && !document.querySelector('button.primary').disabled`, 'initial analysis')
await waitFor(`!!document.querySelector('.plot-canvas .main-svg')`, 'plot rendered')
await sleep(400)
let t = await text()
check('initial: 3 lengths, 9 observations shown', t.includes('3 lengths') && t.includes('9 period observations'))
check('initial: hidden lengths explained', t.includes('Hidden for replay'))
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
// Keyboard: Tab reaches the main controls, and the focused primary action shows an outline.
const focused = []
let primaryOutline = null
for (let i = 0; i < 25; i++) {
  await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9 })
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9 })
  const f = await evaluate(`(() => { const e = document.activeElement; const s = getComputedStyle(e); return { text: (e.innerText || e.getAttribute('aria-label') || e.tagName).trim().slice(0, 40), primary: e.classList.contains('primary'), outline: s.outlineStyle + ' ' + s.outlineWidth } })()`)
  focused.push(f.text)
  if (f.primary) primaryOutline = f.outline
}
check('keyboard Tab reaches mode switch, record, reset, primary action and expandable details',
  ['Use my data', 'Download record (JSON + CSV)', 'Reset demo', 'Recommend next measurement', 'Assumptions and data notes'].every((x) => focused.includes(x)),
  focused.slice(0, 12).join(' | '))
check('focused primary action has a visible outline', primaryOutline !== null && !primaryOutline.startsWith('none'), String(primaryOutline))
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
  seen.kinds.push(t.includes('Discriminating measurement') ? 'disagreement' : 'space-filling')
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


// 9. Uploaded-data workflow and exports
const dl = mkdtempSync(join(tmpdir(), 'nl-downloads-'))
await send('Page.setDownloadBehavior', { behavior: 'allow', downloadPath: dl })
const files = mkdtempSync(join(tmpdir(), 'nl-csv-'))
const setValue = (label, value) => evaluate(`(() => {
  const el = document.querySelector('[aria-label="${label}"]')
  const proto = el.tagName === 'SELECT' ? HTMLSelectElement.prototype : HTMLInputElement.prototype
  Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, ${JSON.stringify(String(value))})
  el.dispatchEvent(new Event(el.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true }))
})()`)
async function chooseFile(path) {
  const { root } = await send('DOM.getDocument', { depth: -1 })
  const { nodeId } = await send('DOM.querySelector', { nodeId: root.nodeId, selector: 'input[type=file]' })
  await send('DOM.setFileInputFiles', { files: [path], nodeId })
}
async function waitDownload(prefix, ms = 10000) {
  const t0 = Date.now()
  while (Date.now() - t0 < ms) {
    const f = readdirSync(dl).find((n) => n.startsWith(prefix) && !n.endsWith('.crdownload'))
    if (f) return readFileSync(join(dl, f), 'utf8')
    await sleep(100)
  }
  check(`download ${prefix}`, false, 'not found')
  return ''
}
const loadButton = () => evaluate(`[...document.querySelectorAll('button')].find(b => b.innerText.startsWith('Load data')).click()`)

// Demo export after a reveal but before Update: revealed values marked, nothing unrevealed included.
await clickButton('Reset demo')
await waitFor(`document.querySelector('button.primary')?.innerText === 'Recommend next measurement'`, 'demo ready for export test')
await clickPrimary()
await waitFor(`document.querySelector('button.primary')?.innerText.startsWith('Reveal')`, 'demo snapshot for export')
await clickPrimary()
await waitFor(`document.querySelector('button.primary')?.innerText.startsWith('Update')`, 'demo revealed for export')
await clickButton('Download record (JSON + CSV)')
const demoJson = await waitDownload('nextlab-record-')
const demoCsv = await waitDownload('nextlab-observations-')
const demoRec = JSON.parse(demoJson).record
check('demo export: replay run type, source link, revealed values marked, not yet refitted',
  demoRec.run_type === 'recorded_data_replay' && demoRec.source.provenance.documentation_url.includes('fastR2') &&
  demoRec.observations.filter((o) => o.origin === 'revealed_recorded_value').length === 3 &&
  demoRec.cycles[0].refit_after_observation === false)
const hiddenNow = [1.87, 1.82, 1.85, 2.43, 2.35, 2.46, 3.07, 3.24, 3.13, 4.17, 3.83, 4.02, 5.55, 5.56, 5.75]
check('demo export contains no unrevealed recorded values', !hiddenNow.some((v) => new RegExp(`(?<![0-9.])${String(v).replace('.', '\\.')}(?![0-9])`).test(demoJson)))
check('demo observations CSV: header with units and 12 rows', demoCsv.startsWith('Pendulum length (m),Reported period (s),origin,cycle\n') && demoCsv.trim().split('\n').length === 13)
for (const f of readdirSync(dl)) unlinkSync(join(dl, f))

// Switch to "Use my data": demo state is cleared, nothing hidden.
await clickButton('Use my data')
await waitFor(`document.body.innerText.includes('Download a sample CSV')`, 'upload form')
check('switching dataset clears the demo history', !(await text()).includes('Prediction history'))

// Sample CSV download, then upload it.
const sample = await evaluate(`fetch('/api/sample.csv').then(r => r.text())`)
check('sample CSV is the derived two-column pendulum file', sample.startsWith('length_m,period_s\n0.101,0.72\n') && sample.trim().split('\n').length === 28)
writeFileSync(join(files, 'sample.csv'), sample)
await chooseFile(join(files, 'sample.csv'))
await waitFor(`document.body.innerText.includes('27 data rows')`, 'sample preview')
await setValue('Input unit', 'm'); await setValue('Response unit', 's')
await loadButton()
await waitFor(`document.body.innerText.includes('all uploaded rows are observed') && document.querySelector('button.primary')?.innerText === 'Recommend next measurement'`, 'sample loaded')
t = await text()
check('sample upload: 9 distinct values, 27 rows, nothing hidden', t.includes('9 distinct length_m values, 27 rows') && t.includes('nothing is hidden'))

// Malformed value: row-level message, nothing loaded.
await clickButton('Start over')
writeFileSync(join(files, 'bad.csv'), 'x,y\n1,2\n2,abc\n4,5\n')
await waitFor(`!!document.querySelector('input[type=file]')`, 'upload form again')
await chooseFile(join(files, 'bad.csv'))
await waitFor(`document.body.innerText.includes('3 data rows')`, 'bad preview')
await loadButton()
await waitFor(`document.body.innerText.includes('Data row 2: y')`, 'malformed row message')
check('malformed value reported with its data row', (await text()).includes('Data row 2: y ("abc") must be a finite number'))
await screenshot('upload-malformed')

// Quoted / BOM / CRLF file with a run column: choose x and y; repeated settings kept.
await clickButton('Start over')
writeFileSync(join(files, 'dose.csv'), '﻿run,"dose level",response\r\n1,1,"2.1"\r\n2,1,2.3\r\n3,2,2.9\r\n4,4,4.2\r\n5,4,4.0\r\n')
await waitFor(`!!document.querySelector('input[type=file]')`, 'upload form for dose')
await chooseFile(join(files, 'dose.csv'))
await waitFor(`document.body.innerText.includes('5 data rows')`, 'dose preview')
check('quoted header read through BOM/CRLF', (await evaluate(`[...document.querySelectorAll('.preview th')].map(e => e.innerText)`)).join('|') === 'run|dose level|response')
await setValue('Input column', 1); await setValue('Response column', 2)
await setValue('Input label', 'Dose'); await setValue('Input unit', 'mg')
await setValue('Response label', 'Response'); await setValue('Response unit', 'a.u.')
await setValue('Feasible range lower bound', 5); await setValue('Feasible range upper bound', 1)
await loadButton()
await waitFor(`document.body.innerText.includes('Upper bound must be greater than the lower bound')`, 'invalid bounds message')
check('invalid bounds rejected with a field message', (await text()).includes('bounds.hi'))
await setValue('Feasible range lower bound', 1); await setValue('Feasible range upper bound', 4); await setValue('Feasible range step', 0.5)
await setValue('Explicit feasible settings', '6')
await loadButton()
await waitFor(`document.querySelector('button.primary')?.innerText === 'Recommend next measurement'`, 'dose loaded')
t = await text()
check('repeats kept: 3 distinct Dose values, 5 rows; one setting marked as extrapolation',
  t.includes('3 distinct Dose values, 5 rows') && t.includes('8 settings, 1–6 mg') && t.includes('1 beyond the observed range'))
const ax2 = await evaluate(`[...document.querySelectorAll('.plot-canvas .xtitle, .plot-canvas .ytitle')].map(e => e.textContent)`)
check('plot uses the user labels and units, linear axis for a narrow range', ax2.includes('Dose (mg)') && ax2.includes('Response (a.u.)'), JSON.stringify(ax2))

// Recommend -> enter the measured value by hand -> compare -> update.
await clickPrimary()
await waitFor(`!!document.querySelector('[aria-label="Measured values"]')`, 'measurement entry')
t = await text()
const xSel = await evaluate(`document.querySelector('.rec h2').innerText`)
check('frozen recommendation shown before any measurement; no reveal button in upload mode', t.includes('fixed before the measurement') && !t.includes('Reveal recorded measurement'), xSel)
await screenshot('upload-recommended')
await setValue('Measured values', '5.1, x')
await evaluate(`[...document.querySelectorAll('button')].find(b => b.innerText === 'Record measurement').click()`)
await waitFor(`document.body.innerText.includes('"x" is not a number')`, 'bad entry message')
await setValue('Measured values', '5.1, 5.3')
await evaluate(`[...document.querySelectorAll('button')].find(b => b.innerText === 'Record measurement').click()`)
await waitFor(`document.body.innerText.includes('2 values you entered')`, 'entered values compared')
t = await text()
check('entered values compared with the frozen predictions, models not refitted', t.includes('Entered at') && t.includes('Mean 5.2 a.u.') && t.includes('have not been refitted'))
await screenshot('upload-entered')
await clickPrimary()
await waitFor(`document.body.innerText.includes('What changed after adding')`, 'upload update')
check('update refits with the entered rows (7 rows)', (await text()).includes('7 rows'))
await screenshot('upload-updated')

// Settings change discards a pending recommendation.
await clickPrimary()
await waitFor(`!!document.querySelector('[aria-label="Measured values"]')`, 'second upload recommendation')
await evaluate(`document.querySelector('details.settings').open = true`)
await setValue('Explicit feasible settings', '3, 5')
await evaluate(`[...document.querySelectorAll('button')].find(b => b.innerText === 'Apply settings').click()`)
await waitFor(`!document.querySelector('[aria-label="Measured values"]') && document.querySelector('button.primary')?.innerText === 'Recommend next measurement'`, 'settings applied')
check('changing feasible settings discards the pending recommendation', (await text()).includes('2 settings, 3–5 mg'))

// Export the uploaded run.
await clickButton('Download record (JSON + CSV)')
const upJson = await waitDownload('nextlab-record-')
const upCsv = await waitDownload('nextlab-observations-')
const up = JSON.parse(upJson)
const r = up.record
check('upload export: run type, source name, units, formulas, method version',
  r.run_type === 'user_uploaded_data' && r.source.name === 'dose.csv' && r.variables.x.unit === 'mg' &&
  r.method.version === 'nextlab-core-1' && r.method.models.map((m) => m.formula).join('|') === 'y = a·x + b|y = a·√x + b|y = a·x² + b')
check('upload export: 5 uploaded rows, 2 entered in cycle 1, update recorded, frozen predictions kept',
  r.observations.filter((o) => o.origin === 'uploaded_file').length === 5 &&
  r.observations.filter((o) => o.origin === 'entered_manually' && o.cycle === 1).length === 2 &&
  r.cycles.length === 1 && r.cycles[0].refit_after_observation === true && r.cycles[0].frozen_predictions.length === 3 &&
  Math.abs(r.cycles[0].comparison.observed_mean - 5.2) < 1e-12)
check('upload export: feasible settings, noise assumption, stable ids', JSON.stringify(r.feasible_settings) === '[3,5]' &&
  r.noise_assumption.stated_response_sd === null && up.record_id.length === 64 && r.cycles[0].snapshot_id.length === 64)
check('upload observations CSV', upCsv.startsWith('Dose (mg),Response (a.u.),origin,cycle\n') && upCsv.trim().split('\n').length === 8)
writeFileSync(join(out, 'upload-export.json'), upJson)
writeFileSync(join(out, 'upload-observations.csv'), upCsv)
console.log(`     upload example: recommended ${r.cycles[0].selected_x} mg; entered ${r.cycles[0].later_observations.map((o) => o.y).join(', ')}; closest ${r.cycles[0].comparison.closest_model}`)

// Back to the demo.
await clickButton('Built-in demonstration')
await waitFor(`document.body.innerText.includes('9 period observations') && document.querySelector('button.primary')?.innerText === 'Recommend next measurement'`, 'back to demo')
check('switching back restores the built-in demo start', (await text()).includes('Recorded pendulum measurements'))


// 10. Audit checks: Julia responses are what is displayed and exported; double clicks; switching mid-request.
const bodies = new Map()   // path -> latest response body (JSON)
const pendingIds = new Map()
listeners.push((m) => {
  if (m.method === 'Network.responseReceived' && m.params.response.url.includes('/api/')) pendingIds.set(m.params.requestId, new URL(m.params.response.url).pathname)
  if (m.method === 'Network.loadingFinished' && pendingIds.has(m.params.requestId)) {
    const path = pendingIds.get(m.params.requestId)
    pendingIds.delete(m.params.requestId)
    send('Network.getResponseBody', { requestId: m.params.requestId }).then((b) => { try { bodies.set(path, JSON.parse(b.body)) } catch {} }).catch(() => {})
  }
})
const count = (path) => apiCalls.filter((x) => x === path).length
const sig3 = (v) => String(Number(v.toPrecision(3)))
await clickButton('Reset demo')
await waitFor(`document.querySelector('button.primary')?.innerText === 'Recommend next measurement'`, 'audit: demo ready')
bodies.delete('/api/recommend')
await clickPrimary()
await waitFor(`document.querySelector('button.primary')?.innerText.startsWith('Reveal')`, 'audit: frozen')
for (let i = 0; i < 30 && !bodies.has('/api/recommend'); i++) await sleep(100)
const recSnap = bodies.get('/api/recommend')?.snapshot
t = await text()
check('displayed frozen predictions are the Julia /api/recommend values', !!recSnap &&
  recSnap.record.models.every((m) => t.includes(`${sig3(m.predicted_y)} s`)) && t.includes(`Next measurement: ${recSnap.record.x} m`))
let before2 = count('/api/demo/reveal')
await evaluate(`(() => { const b = document.querySelector('button.primary'); b.click(); b.click() })()`)
await waitFor(`document.querySelector('button.primary')?.innerText.startsWith('Update')`, 'audit: revealed')
await sleep(300)
check('double click on Reveal sends one reveal request', count('/api/demo/reveal') - before2 === 1)
const rv = bodies.get('/api/demo/reveal')
check('comparison uses the frozen predictions, not a refit', !!rv &&
  rv.comparison.models.every((c) => c.predicted_y === recSnap.record.models.find((m) => m.id === c.id).predicted_y))
before2 = count('/api/analyze')
await evaluate(`(() => { const b = document.querySelector('button.primary'); b.click(); b.click() })()`)
await waitFor(`document.body.innerText.includes('What changed after adding')`, 'audit: updated')
await sleep(300)
check('double click on Update sends one refit and adds one history row', count('/api/analyze') - before2 === 1 &&
  (await evaluate(`document.querySelectorAll('.history tbody tr').length`)) === 1)
for (const f of readdirSync(dl)) unlinkSync(join(dl, f))
await clickButton('Download record (JSON + CSV)')
const auditRec = JSON.parse(await waitDownload('nextlab-record-')).record
check('exported frozen predictions equal the pre-reveal snapshot exactly',
  JSON.stringify(auditRec.cycles[0].frozen_predictions) === JSON.stringify(recSnap.record.models) && auditRec.cycles[0].snapshot_id === recSnap.snapshot_id)
for (const f of readdirSync(dl)) unlinkSync(join(dl, f))

// Dataset switch while a recommend request is in flight: the late response must not appear anywhere.
fetchMode = 'hold'
await send('Fetch.enable', { patterns: [{ urlPattern: '*/api/recommend*' }] })
await clickPrimary()
for (let i = 0; i < 50 && held.length === 0; i++) await sleep(100)
await clickButton('Use my data')
await waitFor(`document.body.innerText.includes('Download a sample CSV')`, 'audit: switched mid-request')
fetchMode = null
await send('Fetch.continueRequest', { requestId: held.pop() })
await sleep(1200)
t = await text()
check('late response after a dataset switch is ignored', t.includes('Download a sample CSV') && !t.includes('Next measurement:'))
await send('Fetch.disable')

// Constant responses with identical repeats: the stated reason must be zero variability, not unknown noise.
writeFileSync(join(files, 'const.csv'), 'x,y\n1,3\n1,3\n2,3\n2,3\n4,3\n')
await chooseFile(join(files, 'const.csv'))
await waitFor(`document.body.innerText.includes('5 data rows')`, 'audit: const preview')
await loadButton()
await waitFor(`document.querySelector('button.primary')?.innerText === 'Recommend next measurement'`, 'audit: const loaded')
await clickPrimary()
await waitFor(`!!document.querySelector('[aria-label="Measured values"]')`, 'audit: const recommended')
t = await text()
check('zero-variability repeats are described as such (not as unknown noise)', t.includes('Repeats show zero variability') && !t.includes('Measurement noise is unknown'))

// Settings cannot be applied while a request is in flight.
fetchMode = 'hold'
await send('Fetch.enable', { patterns: [{ urlPattern: '*/api/observe*' }] })
await setValue('Measured values', '3')
await evaluate(`[...document.querySelectorAll('button')].find(b => b.innerText === 'Record measurement').click()`)
for (let i = 0; i < 50 && held.length === 0; i++) await sleep(100)
await evaluate(`document.querySelector('details.settings').open = true`)
const applyDisabled = await evaluate(`(() => { const b = [...document.querySelectorAll('button')].find(b => b.innerText === 'Apply settings'); return b ? b.disabled : 'absent' })()`)
check('feasible settings cannot change while a measurement request is in flight', applyDisabled === true || applyDisabled === 'absent', String(applyDisabled))
fetchMode = null
await send('Fetch.continueRequest', { requestId: held.pop() })
for (let i = 0; i < 40 && !(await text()).includes('1 value you entered') && !(await text()).includes('snapshot was altered'); i++) await sleep(100)
check('constant-response measurement accepted after the browser JSON round trip (signed-zero snapshot)',
  (await text()).includes('1 value you entered'), (await text()).includes('snapshot was altered') ? 'rejected: snapshot was altered' : '')
await send('Fetch.disable')
const constSnap = bodies.get('/api/recommend')?.snapshot
check('precondition: the snapshot holds -0 and JSON.stringify writes it as 0', !!constSnap &&
  constSnap.record.models.some((m) => Object.is(m.a, -0)) && JSON.stringify(constSnap).includes('"a":0,'))
await clickPrimary()
await waitFor(`document.body.innerText.includes('What changed after adding')`, 'constant: update')
for (const f of readdirSync(dl)) unlinkSync(join(dl, f))
await clickButton('Download record (JSON + CSV)')
const constRec = JSON.parse(await waitDownload('nextlab-record-')).record
check('constant-response export: entered value in cycle 1, refit recorded, frozen predictions kept',
  constRec.observations.filter((o) => o.origin === 'entered_manually' && o.cycle === 1).length === 1 &&
  constRec.cycles[0].refit_after_observation === true && constRec.cycles[0].snapshot_id === constSnap.snapshot_id)
for (const f of readdirSync(dl)) unlinkSync(join(dl, f))

// Degenerate inputs (no family can be fitted): no dead Recommend loop.
await clickButton('Start over')
writeFileSync(join(files, 'degenerate.csv'), 'x,y\n1,1\n1.000000000000001,2\n1.000000000000002,3\n')
await waitFor(`!!document.querySelector('input[type=file]')`, 'audit: upload form for degenerate')
await chooseFile(join(files, 'degenerate.csv'))
await waitFor(`document.body.innerText.includes('3 data rows')`, 'audit: degenerate preview')
await setValue('Explicit feasible settings', '2')
await loadButton()
await waitFor(`document.body.innerText.includes('None of the three families could be fitted')`, 'audit: degenerate analysed')
const prim = await primary()
check('no Recommend action is offered when no model can be fitted', prim === null || prim.disabled === true, JSON.stringify(prim))
await screenshot('audit-degenerate')

// Same-tick double click on Record measurement sends one observe request.
await clickButton('Start over')
await waitFor(`!!document.querySelector('input[type=file]')`, 'audit: upload form for double entry')
await chooseFile(join(files, 'dose.csv'))
await waitFor(`document.body.innerText.includes('5 data rows')`, 'audit: dose preview again')
await setValue('Input column', 1); await setValue('Response column', 2)
await loadButton()
await waitFor(`document.querySelector('button.primary')?.innerText === 'Recommend next measurement'`, 'audit: dose loaded again')
await clickPrimary()
await waitFor(`!!document.querySelector('[aria-label="Measured values"]')`, 'audit: dose recommended again')
await setValue('Measured values', '5.1')
before2 = count('/api/observe')
await evaluate(`(() => { const b = [...document.querySelectorAll('button')].find(b => b.innerText === 'Record measurement'); b.click(); b.click() })()`)
await waitFor(`document.body.innerText.includes('1 value you entered')`, 'audit: double entry')
await sleep(300)
check('double click on Record measurement sends one observe request, one history row', count('/api/observe') - before2 === 1 &&
  (await evaluate(`document.querySelectorAll('.history tbody tr').length`)) === 1)

const external = allRequests.filter((u) => !/^(http:\/\/(127\.0\.0\.1|localhost)(:\d+)?\/|data:|blob:|about:)/.test(u))
check('no requests outside localhost (https blocked for the whole run)', external.length === 0, external.slice(0, 3).join(' '))
check('no uncaught page errors', pageErrors.length === 0, pageErrors.slice(0, 3).join(' | ').slice(0, 400))
console.log(failures === 0 ? '\nBrowser check passed.' : `\n${failures} check(s) failed.`)
ws.close()
browser.kill()
process.exit(failures === 0 ? 0 : 1)
