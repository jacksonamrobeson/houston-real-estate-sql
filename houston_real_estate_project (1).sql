-- =====================================================================
-- Project 4: Houston Real Estate Analysis (HCAD Public Data)
-- Author: Jackson Robeson
-- Source: Harris County Appraisal District (HCAD) Public Data
--         https://hcad.org/pdata/pdata-property-downloads.html
-- Tool: SQLite (DB Browser for SQLite)
-- =====================================================================


-- =====================================================================
-- SECTION 1: RAW DATA IMPORT
-- =====================================================================
-- The raw file real_acct.txt (833MB, 1,627,329 rows covering all of
-- Harris County) was imported directly into DB Browser using
-- File > Import > Table from CSV file, with these settings:
--   - Field separator: Tab
--   - Quote character: none (a stray quote character in the raw file
--     broke the default import; disabling quote handling fixed it)
--   - Column names in first line: checked
--   - Table name: staging_properties
-- This section is not re-runnable SQL, since the import happens
-- through DB Browser's UI rather than a SQL statement.


-- =====================================================================
-- SECTION 2: EXPLORING THE RAW DATA
-- =====================================================================

-- Confirm the full import succeeded
SELECT COUNT(*) FROM staging_properties;
-- Result: 1,627,329 rows

-- Find every neighborhood-description variant matching target areas
SELECT DISTINCT Market_Area_1_Dscr
FROM staging_properties
WHERE Market_Area_1_Dscr LIKE '%Montrose%'
   OR Market_Area_1_Dscr LIKE '%Heights%'
   OR Market_Area_1_Dscr LIKE '%River Oaks%';

-- Check what property types (state_class codes) exist within the
-- target neighborhoods, to identify the single-family code
SELECT DISTINCT state_class, COUNT(*) as cnt
FROM staging_properties
WHERE Market_Area_1_Dscr IN (
    'Montrose/ Museum/ Midtown',
    '1F Montrose, Fourth Ward Areas',
    'Heights/ Washington Ave',
    'Heights',
    '1F Heights, Brooksmith, Norhill Areas',
    '1F River Oaks Area'
)
GROUP BY state_class
ORDER BY cnt DESC;
-- Result: A1 (single-family residential) = 25,044 of these rows,
-- confirming it as the correct filter code.

-- West University Place isn't labeled as its own market area in HCAD's
-- system -- it's grouped under "Bellaire, West University." Isolated
-- it instead by its zip code.
SELECT COUNT(*)
FROM staging_properties
WHERE site_addr_3 = 77005
AND state_class = 'A1';
-- Result: 7,468


-- =====================================================================
-- SECTION 3: BUILD THE CLEAN PROPERTIES TABLE
-- =====================================================================

CREATE TABLE properties (
    acct TEXT PRIMARY KEY,
    address TEXT NOT NULL,
    neighborhood TEXT NOT NULL,
    zip_code TEXT,
    year_built INTEGER,
    building_sqft INTEGER,
    land_sqft INTEGER,
    land_value REAL,
    improvement_value REAL,
    total_appraised_value REAL,
    total_market_value REAL,
    prior_land_value REAL,
    prior_improvement_value REAL,
    prior_total_appraised_value REAL,
    prior_total_market_value REAL
);

-- Filter staging_properties down to the 32,512 target single-family
-- properties across all four neighborhoods, and insert them into the
-- clean table
INSERT INTO properties(acct, address, neighborhood, zip_code, year_built, building_sqft, land_sqft)
SELECT acct, site_addr_1, Market_Area_1_Dscr, site_addr_3, yr_impr, bld_ar, land_ar
FROM staging_properties
WHERE (Market_Area_1_Dscr IN (
    'Montrose/ Museum/ Midtown',
    '1F Montrose, Fourth Ward Areas',
    'Heights/ Washington Ave',
    'Heights',
    '1F Heights, Brooksmith, Norhill Areas',
    '1F River Oaks Area'
) OR (site_addr_3=77005)) AND (state_class='A1');
-- Result: 32,512 rows inserted

-- Normalize the six messy neighborhood text variants into four clean labels
UPDATE properties
SET neighborhood =
CASE
    WHEN neighborhood IN ('Montrose/ Museum/ Midtown', '1F Montrose, Fourth Ward Areas') THEN 'Montrose'
    WHEN neighborhood IN ('Heights/ Washington Ave', 'Heights', '1F Heights, Brooksmith, Norhill Areas') THEN 'Heights'
    WHEN neighborhood = '1F River Oaks Area' THEN 'River Oaks'
    WHEN zip_code = '77005' THEN 'West University'
    ELSE neighborhood
END;
-- Result: 32,512 rows affected

-- Bring in the appraisal value columns, matched by account number
UPDATE properties
SET land_value = staging_properties.land_val,
    improvement_value = staging_properties.bld_val,
    total_appraised_value = staging_properties.tot_appr_val,
    total_market_value = staging_properties.tot_mkt_val,
    prior_land_value = staging_properties.prior_land_val,
    prior_improvement_value = staging_properties.prior_bld_val,
    prior_total_appraised_value = staging_properties.prior_tot_appr_val,
    prior_total_market_value = staging_properties.prior_tot_mkt_val
FROM staging_properties
WHERE properties.acct = staging_properties.acct;
-- Result: 32,512 rows affected


-- =====================================================================
-- SECTION 4: DATA QUALITY CHECK
-- =====================================================================

-- Confirm completeness of the value columns after the join-update
SELECT COUNT(*) as total_rows,
       COUNT(land_value) as has_land_value,
       COUNT(total_appraised_value) as has_appraised_value
FROM properties;
-- Result: 32,512 total | 32,022 with values (~1.5% gap, consistent
-- with normal administrative data gaps in HCAD's records)


-- =====================================================================
-- SECTION 5: ANALYSIS -- AVERAGE, MEDIAN & SPREAD
-- =====================================================================

-- Average appraised value and property count per neighborhood
SELECT neighborhood,
       COUNT(*) AS num_properties,
       AVG(total_appraised_value) AS avg_appraised_value,
       MIN(total_appraised_value) AS min_appraised_value,
       MAX(total_appraised_value) AS max_appraised_value
FROM properties
GROUP BY neighborhood;

-- Median appraised value per neighborhood, using a window function +
-- subquery (SQLite has no built-in MEDIAN function). Run once per
-- neighborhood, swapping the WHERE clause each time.
SELECT total_appraised_value
FROM (
    SELECT total_appraised_value,
           ROW_NUMBER() OVER (ORDER BY total_appraised_value) AS rn,
           COUNT(*) OVER () AS total_count
    FROM properties
    WHERE neighborhood = 'River Oaks'
)
WHERE rn = (total_count + 1) / 2;
-- Repeat with 'Heights', 'Montrose', 'West University'


-- =====================================================================
-- SECTION 6: ANALYSIS -- YEAR-OVER-YEAR GROWTH & PRICE PER SQFT
-- =====================================================================

-- Average year-over-year appreciation, per neighborhood
SELECT neighborhood,
       AVG( (total_appraised_value - prior_total_appraised_value) / prior_total_appraised_value * 100 ) AS avg_yoy_pct_change
FROM properties
GROUP BY neighborhood;

-- Average price per square foot, per neighborhood
SELECT neighborhood,
       AVG( total_appraised_value / building_sqft ) AS avg_price_per_sqft
FROM properties
GROUP BY neighborhood;


-- =====================================================================
-- SECTION 7: ANALYSIS -- AGE BRACKETS (SIMPSON'S PARADOX)
-- =====================================================================

-- Blended across all neighborhoods (misleading on its own -- see below)
SELECT
    CASE
        WHEN (2026 - year_built) < 25 THEN 'Under 25 years'
        WHEN (2026 - year_built) < 50 THEN '25-49 years'
        WHEN (2026 - year_built) < 100 THEN '50-99 years'
        ELSE '100+ years'
    END AS age_bracket,
    COUNT(*) AS num_properties,
    AVG(total_appraised_value) AS avg_value
FROM properties
GROUP BY age_bracket;

-- Same age brackets, broken out by neighborhood -- reveals the
-- blended trend above was reversed within every single neighborhood
-- (a genuine Simpson's Paradox)
SELECT
    neighborhood,
    CASE
        WHEN (2026 - year_built) < 25 THEN 'Under 25 years'
        WHEN (2026 - year_built) < 50 THEN '25-49 years'
        WHEN (2026 - year_built) < 100 THEN '50-99 years'
        ELSE '100+ years'
    END AS age_bracket,
    COUNT(*) AS num_properties,
    AVG(total_appraised_value) AS avg_value
FROM properties
GROUP BY neighborhood, age_bracket;


-- =====================================================================
-- SECTION 8: ANALYSIS -- LAND-TO-BUILDING RATIO
-- =====================================================================

SELECT neighborhood,
       AVG( land_sqft / building_sqft ) AS avg_land_to_building_ratio
FROM properties
GROUP BY neighborhood;


-- =====================================================================
-- SECTION 9: ANALYSIS -- STANDARD DEVIATION & COEFFICIENT OF VARIATION
-- =====================================================================
-- SQLite has no built-in STDEV function; both are assembled by hand
-- from their underlying formulas.

SELECT neighborhood,
       AVG(total_appraised_value) AS avg_value,
       SQRT( AVG(total_appraised_value * total_appraised_value) - AVG(total_appraised_value) * AVG(total_appraised_value) ) AS std_dev,
       SQRT( AVG(total_appraised_value * total_appraised_value) - AVG(total_appraised_value) * AVG(total_appraised_value) ) / AVG(total_appraised_value) AS coefficient_of_variation
FROM properties
GROUP BY neighborhood;


-- =====================================================================
-- SECTION 10: ANALYSIS -- CORRELATION (SQFT vs. APPRAISED VALUE)
-- =====================================================================
-- Pearson correlation coefficient, also hand-built since SQLite has
-- no built-in CORR function. Numerator = covariance; denominator =
-- the product of both variables' standard deviations.

SELECT neighborhood,
       ( AVG(building_sqft * total_appraised_value) - AVG(building_sqft) * AVG(total_appraised_value) )
       /
       ( SQRT( AVG(building_sqft * building_sqft) - AVG(building_sqft) * AVG(building_sqft) )
         *
         SQRT( AVG(total_appraised_value * total_appraised_value) - AVG(total_appraised_value) * AVG(total_appraised_value) )
       ) AS correlation
FROM properties
GROUP BY neighborhood;


-- =====================================================================
-- END OF SCRIPT
-- =====================================================================

