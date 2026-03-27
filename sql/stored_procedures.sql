/******************************************************************************
* 📦 STORED PROCEDURE: sp_populate_calendar
*******************************************************************************
* Objective: Generate or update the dim_calendar table for a given date
*            range, without having to re-run a full ETL process.
*******************************************************************************/

-- We use CREATE OR REPLACE to be able to improve the procedure later without dropping it
CREATE OR REPLACE PROCEDURE public.sp_populate_calendar(p_start_date DATE, p_end_date DATE)
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE NOTICE 'Début du peuplement de dim_calendar de % à %', p_start_date, p_end_date;

    -- We insert into the dim_calendar table
    INSERT INTO public.dim_calendar (
        date_id,
        full_date,
        year,
        month,
        day_of_month,
        month_name,
        day_of_week,
        quarter
    )
    SELECT
        -- Calculates the numeric key (number of days since 30/12/1899)
        d.generated_date - '1899-12-30'::DATE AS date_id,

        -- The full date
        d.generated_date AS full_date,

        -- Extracts the various date attributes
        EXTRACT(YEAR FROM d.generated_date) AS year,
        EXTRACT(MONTH FROM d.generated_date) AS month,
        EXTRACT(DAY FROM d.generated_date) AS day_of_month,
		LOWER(TO_CHAR(d.generated_date, 'TMMonth')) AS month_name,
        EXTRACT(ISODOW FROM d.generated_date) AS day_of_week, -- ISODOW: 1=Monday, 7=Sunday
        'Q' || EXTRACT(QUARTER FROM d.generated_date) AS quarter

    FROM (
        -- Generates a series of dates, one for each day in the range
        SELECT generate_series(p_start_date, p_end_date, '1 day'::interval)::DATE AS generated_date
    ) d
    -- Handles conflicts: if a date_id already exists, do nothing.
    -- This makes the procedure re-executable without creating duplicates.
    ON CONFLICT (date_id) DO NOTHING;

    RAISE NOTICE 'Peuplement de dim_calendar terminé.';
END;
$$;
