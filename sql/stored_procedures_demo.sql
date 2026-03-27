/******************************************************************************
* 🧪 SECURE DEMONSTRATION OF THE STORED PROCEDURE
*******************************************************************************
* Objective: Show the effectiveness of the sp_populate_calendar procedure
*            without permanently altering the database.
*******************************************************************************/

-- Starts a transaction to isolate our actions
BEGIN;

-- 1. We check the initial state: no data for 2019
SELECT 'État initial' AS step, COUNT(*) AS count_2019 FROM dim_calendar WHERE year = 2019;

-- 2. We call the procedure to generate dates for 2019
CALL public.sp_populate_calendar('2019-01-01', '2019-12-31');
SELECT 'Procédure exécutée' AS step;

-- 3. We verify that all 365 days of 2019 have been added
SELECT 'État après appel' AS step, COUNT(*) AS count_2019 FROM dim_calendar WHERE year = 2019;
-- We can even look at what the data looks like
SELECT * FROM dim_calendar WHERE year = 2019 LIMIT 5;

-- 4. We cancel everything!
ROLLBACK;
SELECT 'Transaction annulée, base restaurée' AS final_status;

-- 5. We verify again that the database has returned to its initial state
SELECT 'État final' AS step, COUNT(*) AS count_2019 FROM dim_calendar WHERE year = 2019;
