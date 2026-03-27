/********************************************************************************
 * 🗂️ @Script      : create_schema.sql
 * ✍️ @Auteur      : Abdulkadir GUVEN
 * 📅 @Date        : Le 4 août 2025
 * 📝 @Description : This script creates the final star schema for the
 * 					 SuperSmartMarket audit prototype.
 *
 * 🔑 Contenu clé	:
 *		- 📸 Price snapshot at the time of the sale and loading traceability in the fact table.
 *		- 🏷️ Standardization of types and names (en_US, snake_case).
 *		- 🔒 Integrity constraints (PK/FK, UNIQUE, targeted CHECKs).
 *		- 🧹 Exclusion of non-relevant data.
 *		- 🚀 Essential indexes for joins.
 *
 * ⚠️ Notes			:
 *      - All variable names, aliases and column names are in English.
 *      - Comments may be in French.
 ********************************************************************************/

-- =============================================================================
-- SECTION 0: ENVIRONMENT CLEANUP
-- Tables are dropped in reverse dependency order for cleanliness.
-- CASCADE handles the removal of constraints that depend on the tables.
-- =============================================================================
DROP TABLE IF EXISTS public.fact_sales CASCADE;
DROP TABLE IF EXISTS public.dim_calendar CASCADE;
DROP TABLE IF EXISTS public.dim_customers CASCADE;
DROP TABLE IF EXISTS public.dim_employees CASCADE;
DROP TABLE IF EXISTS public.dim_products CASCADE;
DROP TABLE IF EXISTS public.app_logs CASCADE;


-- =============================================================================
-- SECTION 1: CREATION OF DIMENSION TABLES
-- =============================================================================

-- -----------------------------------------------------
-- Table: dim_calendar
-- -----------------------------------------------------
CREATE TABLE public.dim_calendar (
    date_id INTEGER NOT NULL,
    year SMALLINT NOT NULL,
    month SMALLINT NOT NULL,
    day_of_month SMALLINT NOT NULL,
    month_name VARCHAR(9) NOT NULL,
    day_of_week SMALLINT NOT NULL,
    quarter VARCHAR(2) NOT NULL,
	full_date DATE NOT NULL,

    CONSTRAINT pk_date_id PRIMARY KEY (date_id),
    CONSTRAINT chk_month_range CHECK (month BETWEEN 1 AND 12),
    CONSTRAINT chk_day_of_month_range CHECK (day_of_month BETWEEN 1 AND 31),
    CONSTRAINT chk_day_of_week_range CHECK (day_of_week BETWEEN 1 AND 7),
    CONSTRAINT chk_quarter_values CHECK (quarter IN ('Q1', 'Q2', 'Q3', 'Q4'))
);

-- -----------------------------------------------------
-- Table: dim_customers
-- -----------------------------------------------------
CREATE TABLE public.dim_customers (
    customer_id VARCHAR(17) NOT NULL,
    subscription_date DATE NOT NULL,

    CONSTRAINT pk_customer_id PRIMARY KEY (customer_id)
);

-- -----------------------------------------------------
-- Table: dim_products
-- -----------------------------------------------------
CREATE TABLE public.dim_products (
    ean VARCHAR(13) NOT NULL,
    category VARCHAR(50) NOT NULL,
    department VARCHAR(50) NOT NULL,
    product_label VARCHAR(50) NOT NULL,
	/* Reference catalogue price (excluding promotions/discounts). The price actually paid
	at the time of the transaction is recorded in fact_sales.unit_price. */
    unit_price NUMERIC(10,2) NOT NULL,

    CONSTRAINT pk_ean PRIMARY KEY (ean),
    CONSTRAINT chk_unit_price_positive CHECK (unit_price >= 0)
);


-- -----------------------------------------------------
-- Table: dim_employees
-- -----------------------------------------------------
CREATE TABLE public.dim_employees (
    employee_id VARCHAR(32) NOT NULL,
    username VARCHAR(30) NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    start_date DATE, -- NULLABLE
    email VARCHAR(50), -- NULLABLE, pending business validation

    CONSTRAINT pk_employee_id PRIMARY KEY (employee_id),
    CONSTRAINT uq_username UNIQUE (username)
);



-- =============================================================================
-- SECTION 2: CREATION OF THE FACT TABLE
-- =============================================================================


-- -----------------------------------------------------
-- Table: fact_sales (Fact table)
-- -----------------------------------------------------
CREATE TABLE public.fact_sales (
    sale_id VARCHAR(35) NOT NULL,
    customer_id VARCHAR(17) NOT NULL,
    employee_id VARCHAR(32) NOT NULL,
    ean VARCHAR(13) NOT NULL,
    date_id INTEGER NOT NULL,
    ticket_id VARCHAR(10) NOT NULL,

	-- Corrective measures integrated:
    unit_price NUMERIC(10,2) NOT NULL, 		-- Price locked at the time of the sale
    transaction_type VARCHAR(20) NOT NULL, 	-- Identifies initial sales vs. late sales
	load_timestamp TIMESTAMPTZ NOT NULL,	-- Ensures loading traceability
	/*	Column added for robustness and future analyses.
    	For this POC, the value will be fixed at 1, as each source row represents one unit. */
	quantity INTEGER NOT NULL,

    CONSTRAINT pk_sale_id PRIMARY KEY (sale_id),

    -- Quality constraints
    CONSTRAINT chk_transaction_type CHECK (transaction_type IN ('INITIAL_SALE', 'ADJUSTMENT')),
    CONSTRAINT chk_valid_quantity_for_transaction
    		CHECK (
    		-- Rule for initial sales: quantity must be > 0
    		(transaction_type = 'INITIAL_SALE' AND quantity > 0)
    		OR
    		-- For all other transaction types (such as 'ADJUSTMENT'), everything is allowed.
    		(transaction_type <> 'INITIAL_SALE')
			),


	-- Foreign key definitions
	CONSTRAINT fk_sales_to_products FOREIGN KEY (ean) REFERENCES public.dim_products (ean),
	CONSTRAINT fk_sales_to_customers FOREIGN KEY (customer_id) REFERENCES public.dim_customers (customer_id),
	CONSTRAINT fk_sales_to_employees FOREIGN KEY (employee_id) REFERENCES public.dim_employees (employee_id),
	CONSTRAINT fk_sales_to_calendar FOREIGN KEY (date_id) REFERENCES public.dim_calendar (date_id)
);

-- =============================================================================
-- SECTION 3: CREATION OF THE AUDIT TABLE (LOGS)
-- =============================================================================

CREATE TABLE public.app_logs (
    log_id SERIAL PRIMARY KEY, -- A new simple primary key
    user_id VARCHAR(32),
    log_date DATE,			   -- Date of the action.
    action_type VARCHAR(10),   -- INSERT, UPDATE, DELETE...
    table_name VARCHAR(50),    -- Impacted table (dim_products, fact_sales...).
    row_id VARCHAR(50),        -- ID of the impacted row (EAN, sale_id...).
    field_name VARCHAR(50),    -- Modified field (e.g.: unit_price).
    new_value VARCHAR(255)     -- The new value, stored as text for flexibility
);


-- =============================================================================
-- SECTION 4: CREATION OF INDEXES FOR QUERY OPTIMIZATION
-- Objective: Speed up joins and filters, which are at the core of
--           all analytical queries on a star schema.
-- =============================================================================
-- Indexes on foreign keys of the fact table
CREATE INDEX idx_fact_sales_ean ON public.fact_sales (ean);
CREATE INDEX idx_fact_sales_customer_id ON public.fact_sales (customer_id);
CREATE INDEX idx_fact_sales_employee_id ON public.fact_sales (employee_id);
CREATE INDEX idx_fact_sales_date_id ON public.fact_sales (date_id);

-- Index on a frequently filtered column in a dimension
CREATE INDEX idx_dim_calendar_full_date ON public.dim_calendar (full_date);


-- =============================================================================
-- SECTION 5: PERMANENT DOCUMENTATION (COMMENTS)
-- =============================================================================
COMMENT ON TABLE public.fact_sales IS 'Fact table containing each individual sale row. It is the central table of the star schema.';
COMMENT ON COLUMN public.fact_sales.date_id IS 'Numeric key (e.g.: 45518) for joining with the dim_calendar table.';


