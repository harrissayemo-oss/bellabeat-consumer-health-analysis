-- ====================================================================
-- BELLABEAT CASE STUDY: FULL DATA INGESTION, CLEANING & ANALYSIS
-- Database: bellabeat_db
-- ====================================================================

-- --------------------------------------------------------------------
-- PHASE 1 & 2: RAW DATA STAGING TABLES
-- --------------------------------------------------------------------

-- 1. Daily Activity Raw Table
DROP TABLE IF EXISTS daily_activity_raw;
CREATE TABLE daily_activity_raw (
    id BIGINT,
    activity_date VARCHAR(50),
    total_steps INT,
    total_distance NUMERIC,
    tracker_distance NUMERIC,
    logged_activities_distance NUMERIC,
    very_active_distance NUMERIC,
    moderately_active_distance NUMERIC,
    light_active_distance NUMERIC,
    sedentary_active_distance NUMERIC,
    very_active_minutes INT,
    fairly_active_minutes INT,
    lightly_active_minutes INT,
    sedentary_minutes INT,
    calories INT
);

-- 2. Sleep Day Raw Table
DROP TABLE IF EXISTS sleep_day_raw;
CREATE TABLE sleep_day_raw (
    id BIGINT,
    sleep_day VARCHAR(50),
    total_sleep_records INT,
    total_minutes_asleep INT,
    total_time_in_bed INT
);

-- 3. Hourly Steps Raw Table
DROP TABLE IF EXISTS hourly_steps_raw;
CREATE TABLE hourly_steps_raw (
    id BIGINT,
    activity_hour VARCHAR(50),
    step_total INT
);


-- --------------------------------------------------------------------
-- PHASE 3: PROCESS & CLEANING
-- --------------------------------------------------------------------

-- 1. Clean Daily Activity: Cast dates and extract day of week
DROP TABLE IF EXISTS daily_activity_clean;
CREATE TABLE daily_activity_clean AS
SELECT 
    id,
    TO_DATE(activity_date, 'MM/DD/YYYY') AS activity_date,
    TO_CHAR(TO_DATE(activity_date, 'MM/DD/YYYY'), 'Day') AS day_of_week,
    total_steps,
    total_distance,
    tracker_distance,
    logged_activities_distance,
    very_active_distance,
    moderately_active_distance,
    light_active_distance,
    sedentary_active_distance,
    very_active_minutes,
    fairly_active_minutes,
    lightly_active_minutes,
    sedentary_minutes,
    calories
FROM daily_activity_raw;

-- 2. Clean Sleep Day: Deduplicate using DISTINCT and calculate awake time
DROP TABLE IF EXISTS sleep_day_clean;
CREATE TABLE sleep_day_clean AS
SELECT DISTINCT
    id,
    TO_DATE(sleep_day, 'MM/DD/YYYY') AS sleep_date,
    TO_CHAR(TO_DATE(sleep_day, 'MM/DD/YYYY'), 'Day') AS day_of_week,
    total_sleep_records,
    total_minutes_asleep,
    total_time_in_bed,
    (total_time_in_bed - total_minutes_asleep) AS minutes_awake_in_bed
FROM sleep_day_raw;

-- 3. Clean Hourly Steps: Cast timestamps, extract date and integer hour
DROP TABLE IF EXISTS hourly_steps_clean;
CREATE TABLE hourly_steps_clean AS
SELECT 
    id,
    TO_TIMESTAMP(activity_hour, 'MM/DD/YYYY HH12:MI:SS AM') AS activity_timestamp,
    CAST(TO_TIMESTAMP(activity_hour, 'MM/DD/YYYY HH12:MI:SS AM') AS DATE) AS activity_date,
    EXTRACT(HOUR FROM TO_TIMESTAMP(activity_hour, 'MM/DD/YYYY HH12:MI:SS AM')) AS hour_of_day,
    step_total
FROM hourly_steps_raw;

-- 4. Unified Daily Master Table (Activity + Sleep Inner Join)
DROP TABLE IF EXISTS daily_activity_sleep_clean;
CREATE TABLE daily_activity_sleep_clean AS
SELECT 
    a.id,
    a.activity_date,
    a.day_of_week,
    a.total_steps,
    a.total_distance,
    a.very_active_minutes,
    a.fairly_active_minutes,
    a.lightly_active_minutes,
    a.sedentary_minutes,
    a.calories,
    s.total_sleep_records,
    s.total_minutes_asleep,
    s.total_time_in_bed,
    s.minutes_awake_in_bed
FROM daily_activity_clean a
INNER JOIN sleep_day_clean s
    ON a.id = s.id 
    AND a.activity_date = s.sleep_date;


-- --------------------------------------------------------------------
-- PHASE 4: ANALYZE & AGGREGATE METRICS
-- --------------------------------------------------------------------

-- Analysis 1: Overall Baseline Health Averages
SELECT 
    ROUND(AVG(total_steps), 0) AS avg_daily_steps,
    ROUND(AVG(total_distance), 2) AS avg_daily_distance_km,
    ROUND(AVG(very_active_minutes), 1) AS avg_very_active_mins,
    ROUND(AVG(fairly_active_minutes), 1) AS avg_fairly_active_mins,
    ROUND(AVG(lightly_active_minutes), 1) AS avg_lightly_active_mins,
    ROUND(AVG(sedentary_minutes), 1) AS avg_sedentary_mins,
    ROUND(AVG(sedentary_minutes) / 60.0, 1) AS avg_sedentary_hours,
    ROUND(AVG(total_minutes_asleep), 1) AS avg_minutes_asleep,
    ROUND(AVG(total_minutes_asleep) / 60.0, 1) AS avg_hours_asleep,
    ROUND(AVG(minutes_awake_in_bed), 1) AS avg_mins_awake_in_bed
FROM daily_activity_sleep_clean;

-- Analysis 2: User Activity Tier Segmentation
WITH user_daily_averages AS (
    SELECT 
        id,
        ROUND(AVG(total_steps), 0) AS avg_steps
    FROM daily_activity_sleep_clean
    GROUP BY id
)
SELECT 
    CASE 
        WHEN avg_steps < 5000 THEN 'Sedentary (< 5,000)'
        WHEN avg_steps BETWEEN 5000 AND 7499 THEN 'Lightly Active (5,000 - 7,499)'
        WHEN avg_steps BETWEEN 7500 AND 9999 THEN 'Fairly Active (7,500 - 9,999)'
        ELSE 'Very Active (10,000+)'
    END AS user_activity_tier,
    COUNT(*) AS total_users,
    ROUND((COUNT(*) * 100.0 / SUM(COUNT(*)) OVER ()), 1) AS percentage_of_users
FROM user_daily_averages
GROUP BY user_activity_tier
ORDER BY total_users DESC;

-- Analysis 3: Day-of-the-Week Trends
SELECT 
    TRIM(day_of_week) AS day_of_week,
    ROUND(AVG(total_steps), 0) AS avg_steps,
    ROUND(AVG(sedentary_minutes) / 60.0, 1) AS avg_sedentary_hours,
    ROUND(AVG(total_minutes_asleep) / 60.0, 1) AS avg_sleep_hours,
    ROUND(AVG(minutes_awake_in_bed), 0) AS avg_restless_mins
FROM daily_activity_sleep_clean
GROUP BY TRIM(day_of_week)
ORDER BY 
    CASE TRIM(day_of_week)
        WHEN 'Monday' THEN 1
        WHEN 'Tuesday' THEN 2
        WHEN 'Wednesday' THEN 3
        WHEN 'Thursday' THEN 4
        WHEN 'Friday' THEN 5
        WHEN 'Saturday' THEN 6
        WHEN 'Sunday' THEN 7
    END;

-- Analysis 4: 24-Hour Intraday Step Pattern
SELECT 
    hour_of_day,
    ROUND(AVG(step_total), 0) AS avg_steps_per_hour
FROM hourly_steps_clean
GROUP BY hour_of_day
ORDER BY hour_of_day ASC;

-- Analysis 5: Pearson Correlation Coefficients
SELECT 
    ROUND(CAST(CORR(total_steps, total_minutes_asleep) AS NUMERIC), 3) AS corr_steps_vs_sleep,
    ROUND(CAST(CORR(sedentary_minutes, total_minutes_asleep) AS NUMERIC), 3) AS corr_sedentary_vs_sleep,
    ROUND(CAST(CORR(total_steps, minutes_awake_in_bed) AS NUMERIC), 3) AS corr_steps_vs_restlessness,
    ROUND(CAST(CORR(sedentary_minutes, minutes_awake_in_bed) AS NUMERIC), 3) AS corr_sedentary_vs_restlessness
FROM daily_activity_sleep_clean;