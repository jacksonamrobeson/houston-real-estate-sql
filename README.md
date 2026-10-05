# Houston Real Estate Analysis: SQL Project

An analysis of 32,512 real single-family homes across four Houston neighborhoods (Heights, Montrose, River Oaks, West University Place), built in SQLite from Harris County Appraisal District (HCAD) public data.

**Full write-up:** [What 32,000 Houston Homes Taught Me About Outliers (My First SQL Project)](https://jacksonamrobeson.blogspot.com/2026/08/what-32000-houston-homes-taught-me.html)

## Overview

HCAD publishes the county's full property appraisal records as public downloads. The raw account file (`real_acct.txt`) is 833MB and covers about 1.6 million properties. This project turns that file into a clean, analyzable dataset and uses SQL to compare the four neighborhoods.

## Data Source

- **Harris County Appraisal District (HCAD)**, Public Data portal, Real Property Data export (`real_acct.txt`)
- https://hcad.org/pdata/pdata-property-downloads.html
- The raw data file is not included in this repository. It is large and freely available from HCAD.

## Pipeline

1. **Import:** loaded the raw tab-delimited file into a SQLite staging table (1,627,329 rows)
2. **Explore:** identified the neighborhood label variants and property-type codes in HCAD's data
3. **Filter:** kept single-family residential properties (`state_class = 'A1'`) in the four target areas. West University is not labeled as its own market area in HCAD's system, so it was isolated by zip code (77005)
4. **Clean:** normalized six neighborhood text variants into four labels with `CASE WHEN`
5. **Enrich:** joined appraisal values from the staging table into the clean `properties` table with `UPDATE ... FROM`
6. **Analyze:** average, median, spread, growth, age, land use, and correlation by neighborhood

Result: **32,512 single-family properties** with addresses, neighborhoods, year built, square footage, and current and prior-year appraised values.

## Key Findings

1. **Averages can mislead.** River Oaks' average appraised value ($3.84M) is 37% above its median ($2.80M), driven by a small number of ultra-high-value properties.
2. **West University is appreciating fastest** (5.9% average year-over-year), ahead of River Oaks.
3. **Older homes only look cheaper when blended.** Within every neighborhood, 100+ year old homes were among the highest-value bracket (a Simpson's Paradox).
4. **Montrose is built up, not out.** Its land-to-building ratio (0.81) is the only one below 1.0.
5. **River Oaks is the most volatile market**, with a coefficient of variation of 0.83 even after adjusting for price level.
6. **Size predicts value everywhere**, most strongly in River Oaks and West University (r about 0.86) and least in Montrose (r about 0.74).

## SQL Techniques Used

- CSV import into staging tables
- Multi-condition `WHERE` logic (`IN`, `OR`, `AND`, parentheses grouping)
- `CASE WHEN` for label normalization and age bucketing
- `UPDATE ... FROM` for join-based updates
- Window functions (`ROW_NUMBER() OVER`) and subqueries for medians
- Hand-built standard deviation, coefficient of variation, and Pearson correlation (SQLite has none built in)

## Repository Contents

| File | Description |
|---|---|
| `houston_real_estate_project.sql` | The full, commented script: table build, cleaning, and every analysis query |
| `README.md` | This file |

## Limitations

- **Appraised values, not sale prices.** Texas is a non-disclosure state, so transaction prices are not public record.
- **No bedroom or bathroom counts.** The HCAD files checked (Building Information, Fixtures) do not include them.
- **Owner names excluded on purpose.** They are public record but were not needed for this analysis.
- About 1.5% of properties (490 rows) have no appraised value in HCAD's data.

## Tools

SQLite, DB Browser for SQLite
