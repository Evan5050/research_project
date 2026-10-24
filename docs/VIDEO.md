# Submission video outline (about 2.5 minutes)

This outline assumes a five-minute limit; check the event's actual rule. Record the
running app at about 1366×768. Run `./nextlab`, wait for READY, then click **Reset demo**
before you start recording.

**0:00 to 0:15. The problem.** Show the app on screen. It is for a trainee extending a series
of measurements, who should write down each model's prediction before measuring and often
doesn't.

**0:15 to 1:15. The demo loop.** Follow `docs/DEMO.md` from 10 to 75 s, at a slower pace.
- Show the observed data and the three models.
- Click Recommend and read the 16 m label and the three frozen predictions.
- Click Reveal and read 7.79 s, the comparison, and the 11-SD miss.
- Click Update and read "What changed", including the higher validation error.
- Click Download record and open the JSON for a few seconds.

**1:15 to 1:30. Your own data.** Click **Use my data**. Load the sample CSV (or a small
file of your own) and show the column choice and the feasible settings. Then click Start
over.

**1:30 to 1:55. How it works.** Show `README.md` or a simple diagram, and cover these
points:
- A Julia core for the fits, the validation, the weights and the choice of setting.
- A stateless API.
- A React page.
- Snapshot hashes, so frozen predictions cannot be altered.
- Built with Claude Code as an AI coding assistant.

**1:55 to 2:20. Source versus evaluation.**
- The demo data is recorded, public data, credited to its source.
- The benchmark is simulated, and its protocol was committed before the run.
- Show the benchmark section of the page and say the result plainly. NextLab beat random
  choice in 11 of 16 conditions. Against endpoints then largest gaps, there was no clear
  difference in 14 of 16.

**2:20 to 2:40. Limits and next steps.**
- No user testing yet.
- The noise model is too simple for the pendulum data.
- Next, test it with experimental researchers, and compare it with existing design tools.

That leaves well over two minutes of margin under a five-minute limit.
