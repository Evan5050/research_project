# Presentation pack

The live script is in `docs/DEMO.md`. Every on-screen claim in it was checked against the
running app on 2026-10-24, from a reset, in headless Brave at 1366×768. The clicks
respond in about 0.02 s. The spoken duration (181 words, about 72 s at 150 words per
minute) is an estimate, so time yourself once.

## The six criteria, as a judge can see them

| Criterion | What to point at | Honest status |
|---|---|---|
| Effort removed | The Recommend → Reveal → Update clicks, which replace fitting, comparing and note-taking by hand. The exported `nextlab-record-<id>.json`, which holds the frozen predictions, the later values and the update order without anyone writing them down. | Shown in the software. No time-on-task measurement or user test exists, so don't claim a saving. |
| One central capability | The "Frozen predictions (fixed before the reveal)" table at 16 m, followed by the reveal comparing against exactly those numbers. | Visible |
| Original combination | The Prediction history row, which ties each recommendation, its frozen predictions and the observed mean together. The methods underneath are established. | Unvalidated. There has been no prior-art check, so don't call it novel. |
| Useful, perceptible output | The orange note: "Even the closest frozen prediction (Square root) missed by 11.2 SDs of a mean". This is something a plain curve fit would not have told you. | The output is perceptible. Usefulness to researchers is unvalidated. |
| Bounded scope linked to a larger purpose | The header source label "Recorded pendulum measurements", the Assumptions and data notes, and the README's "Out of scope" list. | Visible |
| Technical choices fit the problem | The Benchmark evidence section (labelled simulation) with its reproduce command, and the 386 backend tests plus the R `lm()` cross-check in the README. | Visible. No speed comparison was made. |

## Recording checklist

1. **Start and prewarm.** In a terminal, run `./nextlab` from the project root. Wait for
   `NextLab READY at http://127.0.0.1:8080`, which takes about 15 s. Confirm that
   `curl -s http://127.0.0.1:8080/api/ready` shows `"ready":true`.
2. **Reset.** Open http://127.0.0.1:8080 and click **Reset demo**. Check that the panel reads
   "Known now: 3 lengths, 9 period observations" and that step 2, Recommend, is current.
3. **Readability.**
   - Browser window about 1366×768, zoom at 100%. Use 110% if the recording will be scaled down.
   - Turn on Do Not Disturb.
   - Close other windows, tabs and the bookmarks bar.
   - Hide the terminal unless you are showing READY.
4. **Record the sequence**, following `docs/DEMO.md`: Recommend, read the three frozen
   predictions, Reveal, read the comparison, Update, read "What changed", Download record.
5. **Evidence.** Scroll to "Benchmark evidence (simulation, not pendulum data)" and read one
   result. Include the "no clear advantage" line.
6. **Source and limitation.** Say that the data comes from the fastR2 Pendulum dataset,
   credited to Calvin College physics students under Prof. Steve Plath, and that I did not
   collect it. State one limitation: the noise model is too simple for these data (the
   11-SD miss).
7. **Check the file.** Play the saved recording from start to finish, confirm the audio, and
   compare its length with the event's limit. That limit is unknown here; `docs/VIDEO.md`
   assumes five minutes.

## Fallback (if the live demo fails)

These are real captures and outputs from the run above; none is a mockup. They show what
the app produced. They do not prove that a live deployment works.

1. Play the recorded video, once it exists.
2. Step through the screenshots in `docs/presentation/`:
   - `1-start.png`
   - `2-recommended.png` (16 m, and the frozen 33.5, 8.12 and 965 s)
   - `3-revealed.png` (mean 7.79 s, and the 11.2-SD note)
   - `4-updated.png` (validation error rose)
   - `5-benchmark.png` (simulation label and table)
3. Open `docs/presentation/example-record.json` and `example-observations.csv`, the export
   from that same run. The CSV's `origin` column separates `recorded_initial_subset` from
   `revealed_recorded_value`.
4. If a laptop is available but the server won't start, say so directly. Don't present
   the screenshots as live.

## Event page check

No event page, URL or event information was ever supplied in this working session, so
I could not check the current submission fields, deadlines or prize rules. Nothing here
assumes them. Check the official page yourself. If it gives conflicting times, work to the
earlier one until the organizers clarify. Don't assume that a sponsor-prize entry also
counts for another track.

## What you still need to do (none of this is done yet)

1. **The event page.** Find the official page and note:
   - the submission deadline and any separate deadline for creating the entry
   - the required fields
   - the video length limit
   - the AI-use disclosure rules
   - the judging schedule
2. **The repository.** Decide whether to make `github.com/Evan5050/research_project` public,
   then push the current commits; the local `benchmark` branch is ahead of `main`. Put that
   repository URL into the submission.
3. **The video.** Record it with the checklist above, play it back, check its length, and
   upload it to whatever host the event requires.
4. **The Devpost text.** Paste and edit `docs/DEVPOST.md`.
   - Fill in your name, team and affiliation.
   - Check the AI-assistance paragraph against the event's rules and your own account of your role.
   - Remove its "Missing fields" section.
5. **The submission.** Submit the entry yourself, then open the published entry and check
   that the links and video work.
6. **Judging.** Attend if it is in person. Before your slot, run `./nextlab` and click
   **Reset demo**, and keep the fallback files open in another window.
