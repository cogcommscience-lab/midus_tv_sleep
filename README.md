# More TV, Less (or More) Sleep?

Analysis code for Kee, Huskey, & Blozis, a preregistered study of whether
daily TV viewing predicts that night's sleep duration in adults, using
daily diary data from three MIDUS samples: MIDUS 2, MIDUS 3, and the MIDUS
Refresher 1.

- **Preregistration:** <https://osf.io/a42dg/overview>
- **Preprint:** coming soon

## What's here

```
data/                     where the ICPSR data files go (not included; see below)
scripts/
├── midus_2/              MIDUS 2
├── midus_3/              MIDUS 3
├── midus_refresher/      MIDUS Refresher 1
└── cross_wave/           analyses that combine waves
```

Each script is an R Markdown file (`.Rmd`), posted alongside its knitted
output (`.html`), so you can read the code and results without running
anything. In each wave folder:

- `*_data_structuring`: builds the analysis datasets from the ICPSR files.
- `*_modeling_fulltime_standard`: the primary, preregistered analysis
  (full-time, standard-shift workers).

Scripts are added as they are finalized.

## Data

MIDUS data are distributed by ICPSR and can't be redistributed, so this
repository contains no raw data, analysis datasets, or fitted models. To
reproduce the analyses, download the R (`.rda`) versions of these files
from ICPSR and put them in `data/`:

| Sample | ICPSR study | File |
|---|---|---|
| MIDUS 2 survey | [04652 v8](https://doi.org/10.3886/ICPSR04652.v8) | `04652-0001-Data.rda` |
| MIDUS 2 daily diary | [26841 v2](https://doi.org/10.3886/ICPSR26841.v2) | `26841-0001-Data.rda` |
| MIDUS 2 Milwaukee (restricted use) | [22840 v7](https://doi.org/10.3886/ICPSR22840.v7) | `22840-0001-Data-REST.rda` |
| MIDUS 3 survey | [36346 v7](https://doi.org/10.3886/ICPSR36346.v7) | `36346-0001-Data.rda` |
| MIDUS 3 daily diary | [38529 v1](https://doi.org/10.3886/ICPSR38529.v1) | `38529-0001-Data.rda` |
| MIDUS 3 Milwaukee (restricted use) | [37120 v5](https://doi.org/10.3886/ICPSR37120.v5) | `37120-0001-Data-REST.rda` |
| MIDUS Refresher 1 survey | [36532 v4](https://doi.org/10.3886/ICPSR36532.v4) | `36532-0001-Data.rda` |
| MIDUS Refresher 1 daily diary | [37083 v2](https://doi.org/10.3886/ICPSR37083.v2) | `37083-0001-Data.rda` |

The restricted-use Milwaukee files require an ICPSR restricted-data
agreement. They supply three health variables for Milwaukee participants;
without them the scripts still run, and only the sample that excludes
participants with those health conditions changes.

## Running the code

Knit the scripts in R (models use `brms`). All paths are relative to each
script's folder, so nothing needs editing.

1. Knit each wave's `*_data_structuring.Rmd` first.
2. Then knit that wave's modeling scripts.

Fitted models are cached next to the scripts, so re-knitting reloads them
instead of refitting. A first run of a modeling script can take several
hours. R and package versions are listed at the end of each HTML.

## License

See [LICENSE](LICENSE).
