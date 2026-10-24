# NextLab data

This notice covers the data files only. It is separate from any license for NextLab's own code.

## `pendulum/` — fastR2 `Pendulum`

**Source:** the `Pendulum` dataset from the R package fastR2 (*Foundations and
Applications of Statistics Using R*, 2nd edition), package version 1.2.5 at the time it
was checked.
- Documentation: https://rpruim.github.io/fastR2/reference/Pendulum.html
- Original data file: https://raw.githubusercontent.com/rpruim/fastR2/main/data/pendulum.rda
- Package metadata: https://github.com/rpruim/fastR2/blob/main/DESCRIPTION

**Attribution:** the fastR2 documentation credits Calvin College physics students under
Professor Steve Plath. NextLab's author did not collect these data.

**License:** the fastR2 package declares `GPL (>=2)`. These files keep that source's
license and attribution. They are not CC0 or public domain, and they are not
self-collected data.

### Files
- **`fastR2_Pendulum_source.csv`** is an untouched snapshot of the source: 27 rows, columns
  `length,period,delta.length`, with values exactly as supplied.
  - SHA-256 of this CSV: `350f183b104381158b84ccf24870d428bc7e02e9853de46f32ebaf7007d90f37`.
- **`pendulum_length_period.csv`** is derived for the two-column uploader, with columns
  `length_m,period_s`.
  - It is made by keeping the first two source columns verbatim, without reformatting
    numbers, and renaming them.
  - SHA-256: `124754464b3a19bcbe32fad2008620cda80ae3d9292dce05d705e6933a1860e0`.

### Original columns
| Column | Meaning | Unit |
|---|---|---|
| `length` | pendulum length | m |
| `period` | reported period, measured by averaging over several swings | s |
| `delta.length` | stated accuracy of the length measurement | m |

### Hash and value check
- The source file `pendulum.rda`, downloaded on 2026-10-24, has SHA-256
  `4f288cadb6ad611b1eeb52ea92fd4d13b62356a0a490a28701e2add05de8c39a`. This matches the
  hash supplied with the build guide.
- Loading that file in R gives a `data.frame` with 27 rows and the same three columns.
  Its values match this snapshot exactly; R simply prints `4` where the CSV has `4.0`.

### Structure (checked by the backend tests)
- 27 records at nine distinct lengths, with three reported periods per length.
- All lengths and periods are positive and finite.
- The lengths are 0.101, 0.205, 0.411, 0.809, 1.485, 2.437, 4.0, 8.0 and 16.0 m.

### Known limitations
- Each period is a reported average over several swings, not an individual swing timing.
  The source does not state the number of swings averaged or the swing amplitude, and
  NextLab does not invent a more detailed collection protocol.
- `delta.length` is length accuracy, not period uncertainty. NextLab keeps it as source
  metadata and never plots it as a vertical error bar.
- NextLab's initial fitting method treats length as exact.
- The 16 m setting is a historical recorded measurement. It is not a suggestion that a
  trainee can build that apparatus.
- No value is generated or interpolated for an unrecorded length and presented as a
  physical measurement.
