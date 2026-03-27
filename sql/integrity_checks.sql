/********************************************************************************
 * 🗂️ @Script      : integrity_checks.sql
 * ✍️ @Auteur      : Abdulkadir GUVEN
 * 📅 @Date        : Le 5 août 2025
 * 🎯 @Objet       : Consistency checks based on the source file
 *                   (volume, aggregates, reference data) and constraint tests.
 *
 ********************************************************************************/


-- Test 1 : Attempt to insert an invalid month (13) into dim_calendar
-- MUST FAIL due to the chk_month_range constraint
INSERT INTO public.dim_calendar (date_id, year, month, day_of_month, month_name, day_of_week, quarter, full_date)
VALUES (99999, 2025, 13, 1, 'Month', 1, 'Q1', '2025-01-01');

-- Test 2 : Attempt to insert a negative price into dim_products
-- MUST FAIL due to the chk_unit_price_positive constraint
INSERT INTO public.dim_products (ean, category, department, product_label, unit_price)
VALUES ('1234567890123', 'Test', 'Test', 'Bad Product', -5.00);

-- Test 3 : Attempt to insert a username that already exists in dim_employees
-- First, we insert a valid employee
INSERT INTO public.dim_employees (employee_id, username, first_name, last_name)
VALUES ('test_id_123', 'test_user', 'Test', 'User');
-- Then, we try to insert another employee with the SAME username
-- MUST FAIL due to the uq_username constraint
INSERT INTO public.dim_employees (employee_id, username, first_name, last_name)
VALUES ('test_id_456', 'test_user', 'Another', 'Person');

-- CLEAN UP TEST DATA
-- Cleanup of the dim_employees table
DELETE FROM public.dim_employees WHERE employee_id = 'test_id_123';


-- Test of the foreign key (FK) constraint between fact_sales and dim_customers
-- This test MUST FAIL because the customer_id 'CUST-FAKE-ID' does not exist in the dim_customers table.

INSERT INTO public.fact_sales (
    sale_id, customer_id, employee_id, ean, date_id, ticket_id,
    -- New columns
    quantity,
    unit_price,
    transaction_type,
    load_timestamp
    )
VALUES (
    'FAKE-SALE-ID-001',
    'CUST-FAKE-ID',          -- This ID does not exist in dim_customers
    'some_employee_id',
    'some_ean',
    99999,
    't_fake',
    -- New columns
    1,                       -- Valid value for quantity
    99.99,                   -- Valid value for unit_price
    'INITIAL_SALE',          -- Valid value for transaction_type
    NOW()                    -- load_timestamp
);

-- COMPARE WITH SOURCE DATA

-- RETAIL SALES | Fact table | fact_sales

-- Should have 41 377 ✅
SELECT COUNT(*) FROM fact_sales;

-- Should have 13 ✅
SELECT COUNT(*) FROM fact_sales WHERE ticket_id = 't_1002'

-- PRODUCTS | Dimension table | dim_products

-- Should have 18 040 ✅
SELECT COUNT(*) FROM dim_products;

-- Should have 6,89 ✅
SELECT ROUND(AVG(unit_price),2) FROM dim_products;

-- CUSTOMERS | Dimension table | dim_customers

-- Should have 2 297 ✅
SELECT COUNT(*) FROM dim_customers;

-- Should have 2 ✅
SELECT COUNT(*) FROM dim_customers WHERE subscription_date='2020-01-05'


-- Should have 05/06/2020 ✅
SELECT subscription_date FROM dim_customers WHERE customer_id='CUST-MAXR3R0I03W8'


-- CALENDAR | Dimension table | dim_calendar

-- Should have 1 999 ✅
SELECT COUNT(*) FROM dim_calendar;

-- Should have 542 ✅
SELECT COUNT(*) FROM dim_calendar WHERE quarter='Q1'


-- EMPLOYEE | Dimension table | dim_employees

-- Should have 56 ✅
SELECT COUNT(*) FROM dim_employees;


-- Compares prices in the logs with prices populated in the dim_products table
WITH test as (
SELECT l.log_id, l.table_name, l.action_type, l.field_name,  l.row_id, p.ean,
		l.new_value as log_price, p.unit_price as real_price,
		(l.new_value::decimal(5,2) - p.unit_price::decimal(5,2)) as diff
FROM app_logs l
JOIN dim_products p ON l.row_id = p.ean
)
SELECT EAN, real_price, log_price, diff FROM test
-- WHERE field_name = 'unit_price' AND diff > 0;
