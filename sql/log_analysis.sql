/********************************************************************************
* 🗂️ @Script      : log_analysis.sql
* ✍️ @Auteur      : Abdulkadir GUVEN
* 📅 @Date        : Le 5 août 2025
* 🎯 @Objet       : Analysis of integration logs and proof of Revenue gap (14–15 Aug 2024).
*                   - Identification of actors and their actions (INSERT/UPDATE/DELETE).
*                   - Focus 14/08 vs 15/08/2024: exclusive insertions on fact_sales.
*                   - Quantification of impacts: affected fields, tickets vs sales.
*                   - Calculation of Revenue linked to late sales and comparison to the observed gap.
*                   - Demonstration of robustness of the new model (transaction_type, locked prices) via BEGIN/ROLLBACK transaction.
*
* ⚠️ Notes :
*      - All variable names, aliases and column names are in English.
*      - Comments may be in French.
********************************************************************************/


-- =============================================================================
-- 1.GLOBAL LOG CONTEXT
-- =============================================================================

-- Query 1.1: How many records are in the log file?
SELECT COUNT(*) AS total_log_count FROM app_logs;
--Result:
/*
| total_log_count |
|----------------:|
|     207 489     |
*/


-- =============================================================================
-- 2.ANALYSIS OF MAIN ACTORS
-- =============================================================================

-- Query 2.1: Who are the main actors?
/* 	Key Observation:
 	A single user ('integration_user_id') is responsible for 99.99% of actions.
	This is clearly an automated ETL.
	Note: user 08c8b678f8e6f0caz05880ef4ebba10az was renamed to integration_user_id before loading
*/
SELECT user_id, COUNT(*) log_count
FROM app_logs
GROUP BY user_id
ORDER BY log_count DESC
LIMIT 5;

--Result:
/*
|     user_id                        |log_count |
|------------------------------------|----------|
| integration_user_id                | 207469   |
| dd595f0f0b3400df2908f0be7723dad4   |    2     |
| 6fa61d0ecae0b563fef18d36b2039c8e   |    2     |
| 23e50fd96a8129e057a79ba0d5575c93   |    1     |
| 342281771d02d2096972e38e78e7d6bd   |    1     |
*/


-- Query 2.2 : Which actor does what?
/* 	Key Observation:
	Employees only perform insertions.(INSERT)
	The integration process is the only one to modify or delete data.(UPDATE/DELETE)
*/

WITH per_action AS (
  SELECT
    action_type,
    BOOL_OR(user_id = 'integration_user_id') AS has_integration,
    COUNT(DISTINCT CASE WHEN user_id <> 'integration_user_id' THEN user_id END) AS employee_count
  FROM app_logs
  GROUP BY action_type
)
SELECT
  action_type,
  CASE
    WHEN has_integration AND employee_count > 0
		THEN 'integration_user_id + (' || employee_count || ' employees)'
    WHEN has_integration
		THEN 'integration_user_id'
    WHEN employee_count > 0
		THEN '(' || employee_count || ' employees)'
    ELSE 'Empty user_id'
  END AS users
FROM per_action
ORDER BY action_type;

/*
| action_type |           users                     |
|:-----------:|:-----------------------------------:|
|   DELETE    | integration_user_id                 |
|   INSERT    | integration_user_id + (18 employees)|
|   UPDATE    | integration_user_id                 |
*/


-- Query 2.3 : Which actor operates on which table?
/* 	Key Observation:
	Employees only operate on the customers table.
	The integration process is the ONLY one to modify the critical Revenue tables.
*/
WITH actors AS (
    SELECT table_name,
    CASE WHEN user_id = 'integration_user_id' THEN 'integration_user'
    ELSE 'employee'
    END AS actor_type
    FROM app_logs
)SELECT table_name,
    ARRAY_AGG(DISTINCT actor_type) AS actors
 FROM actors
 GROUP BY table_name

--Result:
/*
|   table_name   |        example_value       |
|:--------------:|:--------------------------:|
|  dim_customers |         {employee}         |
|  dim_employees |    {integration_user}      |
|  dim_products  |    {integration_user}      |
|   fact_sales   |    {integration_user}      |
*/

-- Query 2.4 : Which actor operates on which field?
/* 	Key Observation:
	Employees only operate on the subscription_date field of customers.
*/

SELECT
        user_id,table_name ,
        ARRAY_AGG(DISTINCT field_name) AS impacted_fields,
        ARRAY_AGG(DISTINCT action_type) AS action_types,
        COUNT(log_id) AS log_count
FROM app_logs
-- WHERE user_id != 'integration_user_id'
GROUP BY user_id, table_name
ORDER BY log_count DESC
/*
|      user_id         |   table_name    |      impacted_fields                | action_types     | log_count |
|:---------------------|:--------------:|:-----------------------------------:|:----------------: |----------:|
| integration_user_id  |   fact_sales   | {customer_id, ..., ticket_id}  	   |  {INSERT}        |  206885   |
| integration_user_id  |  dim_products  | {unit_price}                         |  {UPDATE}        |     575   |
| integration_user_id  |  dim_employees | {hash_mdp, NULL}                     | {DELETE,UPDATE}  |      9    |
| ...                  |  dim_customers | {subscription_date}                  |  {INSERT}        |    1~2    |
*/

-- Query 2.5 : Who is the main actor?
/* 	Key Observation:
	The integration user alone is responsible for 99.99% of actions performed in the database.
*/

WITH log_count AS(
    SELECT
        COUNT(user_id) FILTER (WHERE user_id = 'integration_user_id') AS int_user_log_count,
        COUNT(user_id) AS total_log_count
    FROM app_logs
)SELECT
    int_user_log_count,
    total_log_count,
    ROUND(
        (int_user_log_count::numeric / NULLIF(total_log_count,0)),
        4
    )
    AS rate
FROM log_count;

/*
| int_user_log_count | total_log_count |   rate   |
|:------------------:|:--------------:|:---------:|
|      207469        |    207489      |   0.9999  |
*/



-- =============================================================================
-- 3.ANALYSIS OF THE IMPACT OF CHANGES
-- =============================================================================

-- STEP 1

-- Query 3.1  : What types of actions took place and on which date?
/*	Key Observation:
	14/08 is a normal activity day (many INSERTs, a few UPDATEs).
	15/08 is an abnormal day: there are ONLY INSERTIONS, no updates.
	These insertions are the heart of the problem.
*/
SELECT
    action_type,
    -- Counts actions performed on August 14
    COUNT(*) FILTER (WHERE log_date = '2024-08-14') AS aug_14,
    -- Counts actions performed on August 15
    COUNT(*) FILTER (WHERE log_date = '2024-08-15') AS aug_15
FROM
    app_logs
GROUP BY
    action_type;

--Result:
/*
| action_type | aug_14  | aug_15 |
|-------------|--------:|-------:|
|   DELETE    |      2  |     0  |
|   INSERT    | 200010  |  6895  |
|   UPDATE    |    582  |     0  |
*/


-- STEP 2

-- Query 3.2  : What is the nature of the insertions on August 15?
/*	Key Observation:
	Proof:
	The 6895 insertions on August 15 concern EXCLUSIVELY the sales table (fact_sales).
*/
SELECT
    COUNT(*) FILTER( WHERE table_name = 'fact_sales') AS fact_sales,
    COUNT(*) FILTER( WHERE table_name = 'dim_products') AS dim_products
FROM app_logs
WHERE log_date = '2024-08-15' AND action_type='INSERT'
GROUP by action_type;

/*
| fact_sales | dim_products |
|-----------:|-------------:|
|      6895  |       0      |
*/


-- STEP 3

-- Query 3.3  : Which fields are impacted?
/*	Key Observation:
	The number of logs is identical (1379) for each key field of a sale
	(customer, date, product, employee, ticket). This confirms that 1,379 complete sale rows were indeed added.
*/
SELECT
field_name,
COUNT(*) as log_count
FROM
app_logs
WHERE
log_date = '2024-08-15'
AND table_name = 'fact_sales'
AND action_type = 'INSERT'
GROUP BY
field_name;

/*
|  field_name  | log_count |
|:------------:|----------:|
| customer_id  |     1379  |
| date_id      |     1379  |
| ean          |     1379  |
| employee_id  |     1379  |
| ticket_id    |     1379  |
*/


-- STEP 4

-- Query 3.4  : How many tickets are affected?
/*	Key Observation:
	A ticket may have been created on 14/08 and completed on 15/08.
	Therefore, to calculate the Revenue difference, one should not rely on ticket_id but rather on sale_id.
*/

SELECT
    COUNT(DISTINCT new_value) AS impacted_ticket_count
FROM
    app_logs
WHERE
    log_date = '2024-08-15'
    AND action_type = 'INSERT'
    AND table_name = 'fact_sales'
    AND field_name = 'ticket_id';
/*
| impacted_ticket_count |
|----------------------:|
|                  700  |
*/


-- STEP 5

-- Query 3.5 : What is the exact amount of the inserted sales?
-- Objective: Verify whether the Revenue from these late sales matches the observed gap.
/*	Conclusion:
	The amount matches EXACTLY the Revenue gap (284 243.88 - 275 186.59).
	The origin of the problem is now proven.
*/
SELECT
    SUM(f.quantity * f.unit_price) AS revenue_from_late_sales
FROM
    fact_sales f
WHERE
    f.sale_id IN (
        -- Retrieves the unique list of sale_id
        -- that were inserted in the logs on August 15.
        SELECT DISTINCT row_id
        FROM app_logs
        WHERE
            log_date = '2024-08-15'
            AND action_type = 'INSERT'
            AND table_name = 'fact_sales'
    );

/*
| revenue_from_late_sales |
|------------------------:|
|                 9057.29 |
*/

-- =============================================================================
-- CONCLUSION: THE SIMPLIFIED PROOF THANKS TO THE NEW MODEL 🏆
-- Objective: Demonstrate how the new 'transaction_type' field simplifies the Revenue gap analysis.
-- =============================================================================

SELECT
	SUM(f.quantity * f.unit_price) FILTER ( WHERE transaction_type = 'INITIAL_SALE') AS initial_sales,
	SUM(f.quantity * f.unit_price) FILTER ( WHERE transaction_type = 'ADJUSTMENT') 	 AS adjustments,
	SUM(f.quantity * f.unit_price) AS total_revenue
FROM fact_sales f
JOIN dim_calendar c ON c.date_id = f.date_id
WHERE c.full_date = '2024-08-14';

/*
| initial_sales  | adjustments | total_revenue  |
|:--------------:|:-----------:|:--------------:|
|  275 186.59    |   9 057.29  |   284 243.88   |
*/




/******************************************************************************
* 💥 FINAL DEMONSTRATION: PROOF OF ROBUSTNESS OF THE NEW MODEL
*******************************************************************************
* Scenario : A global price update (+15%) without historization is simulated
*            to prove the instability of the old Revenue calculation method.
*
* Method   : Use of a transaction (BEGIN...ROLLBACK) for a safe test
*            with no permanent impact on the database.
*******************************************************************************/

-- Starts a transaction to isolate our changes.
BEGIN;

-- --- 1. DEFINITION OF OUR "SOURCE OF TRUTH" ---
-- We store the correct and known Revenue in a variable for comparison.
-- NOTE: IN POSTGRESQL WE USE \set, IN OTHER SYSTEMS WE CAN USE DECLARE @variable.
-- For a generic script, it can be embedded directly in the query.
-- Let's say our reference Revenue is 284243.88

-- --- 2. THE DISASTER: GENERAL PRICE INCREASE ---
-- We increase ALL prices by 15% in the dimension table.
UPDATE dim_products
SET unit_price = unit_price * 1.15;

-- Message for console output
SELECT 'ACTION: All prices in dim_products have been increased by 15%.' as step_description;


-- --- 3. THE MOMENT OF TRUTH: COMPARISON OF BOTH METHODS ---
-- We calculate both Revenue figures and their gap relative to the truth.
SELECT
    -- Column 1: Revenue calculated with the old method (join)
    (SELECT SUM(p.unit_price) FROM fact_sales s JOIN dim_products p ON s.ean = p.ean)
    AS "Revenue (Legacy)",

    -- Column 2: Difference between the old method and the truth
    (SELECT SUM(p.unit_price) FROM fact_sales s JOIN dim_products p ON s.ean = p.ean) - 284243.88
    AS "Delta vs Truth (Legacy)",

    -- Column 3: Revenue calculated with the new method (locked price)
    (SELECT SUM(quantity * unit_price) FROM fact_sales)
    AS "Revenue (New)",

    -- Column 4: Difference between the new method and the truth
    (SELECT SUM(quantity * unit_price) FROM fact_sales) - 284243.88
    AS "Delta vs Truth (New)";


-- --- 4. CLEANUP ---
-- We cancel ALL changes made since the BEGIN.
ROLLBACK;

-- Final confirmation message
SELECT 'STATUS: Transaction cancelled. The database has been restored to its initial state.' as final_status;
