/********************************************************************************
 * 🗂️ @Script      : business_queries.sql
 * ✍️ @Auteur      : Abdulkadir GUVEN
 * 📅 @Date        : Le 4 août 2025
 * 🎯 @Objet       : Two versions of each query requested by Hugo
 *                  1) Before adding columns
 *                  2) After adding columns
 *
 * 🛢️ Tables cibles : `fact_sales` et `dim_calendar`
 * 🏷️Nouveaux champs dans `fact_sales` : quantity, unit_price, transaction_type, load_timestamp
 * 🏷️Nouveaux champs dans `dim_calendar` : full_date
 *
 * 🧭 Structure du fichier :
 *		⏮️ V1 = BEFORE new columns
 *   	⏭️ V2 = AFTER new columns
 *
 * ⚠️ Notes :
 *      - All variable names, aliases and column names are in English.
 *      - Comments may be in French.
 ********************************************************************************/


/******************************************************************************
* 🔎 DEMANDE 1 : Total Revenue for August 14
*******************************************************************************/

/* ⏮️ V1 — AVANT */
SELECT SUM(p.unit_price)
FROM fact_sales f
JOIN dim_calendar c ON c.date_id = f.date_id
JOIN dim_products p on p.ean = f.ean
WHERE c.day_of_month = 14 AND c.month = 8 AND c.year = 2024;
-- Result : 284 243.88


/* ⏭️ V2 — APRÈS */
SELECT SUM(f.unit_price * f.quantity) AS total_sales
FROM fact_sales f
JOIN dim_calendar c ON c.date_id = f.date_id
WHERE c.full_date = '2024-08-14';
-- Result : 284 243.88

/******************************************************************************
* 🔎 DEMANDE 2 : Calculate Revenue per customer for the top 10 customers
*******************************************************************************/

/* ⏮️ V1 — AVANT */
SELECT f.customer_id, SUM(p.unit_price) as revenue_per_customer
FROM public.fact_sales f
JOIN public.dim_products p ON f.ean = p.ean
GROUP BY f.customer_id
ORDER BY revenue_per_customer DESC
LIMIT 10;

/* ⏭️ V2 — APRÈS */
SELECT f.customer_id, SUM(f.unit_price * f.quantity) as revenue_per_customer
FROM public.fact_sales f
GROUP BY f.customer_id
ORDER BY revenue_per_customer DESC
LIMIT 10;

/*
Results:
|     customer_id        | revenue_per_customer |
|------------------------|----------------------|
| CUST-JNSOZSFORR88      |		846.86			|
| CUST-GM6VBAYAB8SF      |		666.86			|
| CUST-L2ST2JHI7K9O      |   	644.18			|
| CUST-WU7ZKQJE4L17      |   	608.93			|
| CUST-9WM83101QDTI      |   	582.03			|
| CUST-ZMAOVX8XYGJY      |   	576.39			|
| CUST-3K66CV0OHH7Q      |   	571.44			|
| CUST-CG23SXJDRNYR      |   	531.09			|
| CUST-D8IOFHVUFX3Y      |   	477.35			|
| CUST-IHN1HQRI7PYJ      |   	463.73			|
*/


/******************************************************************************
* 🔎 DEMANDE 3 : Calculate the share of Revenue collected per employee.
*******************************************************************************/

/* ⏮️ V1 — AVANT */
WITH employee_revenue AS(
	SELECT	e.first_name, e.last_name,
			SUM(p.unit_price) as revenue_per_employee
	FROM fact_sales f
	JOIN dim_products p ON p.ean = f.ean
	JOIN dim_employees e ON e.employee_id = f.employee_id
	GROUP BY e.employee_id, e.first_name, e.last_name
)
SELECT first_name, last_name,
		((revenue_per_employee
			/ NULLIF(SUM(revenue_per_employee) OVER(),0)) * 100.00
		)::DECIMAL(5,2)
			AS emp_rev_share_pct
FROM employee_revenue
ORDER BY emp_rev_share_pct DESC;

/* ⏭️ V2 — APRÈS */
WITH employee_revenue AS(
	SELECT	e.first_name, e.last_name,
			SUM(f.unit_price * f.quantity) as revenue_per_employee
	FROM fact_sales f
	JOIN dim_employees e ON e.employee_id = f.employee_id
	GROUP BY e.employee_id, e.first_name, e.last_name
)
SELECT first_name, last_name,
		((revenue_per_employee
			/ NULLIF(SUM(revenue_per_employee) OVER(),0)) * 100.00
		)::DECIMAL(5,2)
			AS emp_rev_share_pct
FROM employee_revenue
ORDER BY emp_rev_share_pct DESC;


/*
Results
|   first_name  |    last_name    |    score    |
|---------------|-----------------|-------------|
| Adélie        | Boulet          |    2.75     |
| Eugène        | Jacquier        |    2.72     |
| Charlène      | Delisle         |    2.46     |
| Pierre        | Manoury         |    2.33     |
| Tristan       | Arsenault       |    2.28     |
| Auriane       | Dufresne        |    2.24     |
| Abelin        | Dutertre        |    2.16     |
| Pierre        | Ange            |    2.15     |
| Arnaud        | Lièvremont      |    2.15     |
| Patricia      | Rodier          |    2.14     |
| Solène        | Deslys          |    2.11     |
| Claudine      | Gachet          |    2.09     |
| Victoria      | Baume           |    2.08     |
| Bruno         | Cazal           |    2.05     |
| Isaïe         | Escoffier       |    2.02     |
| Émilienne     | Blanchard       |    2.01     |
| Sabine        | Giraud          |    1.96     |
| Ugo           | Chevalier       |    1.96     |
| Anne          | Donnet          |    1.94     |
| Solange       | Jacquet         |    1.93     |
| Sacha         | Pélissier       |    1.93     |
| Joseph        | Courbet         |    1.92     |
| Emmanuel      | Grosjean        |    1.89     |
| Victoria      | Genet           |    1.88     |
| Yves          | Grinda          |    1.87     |
| Aimée         | Marchal         |    1.84     |
| Maïté         | Rochefort       |    1.82     |
| Gabrielle     | Granet          |    1.82     |
| Jean-Jacques  | Auch            |    1.81     |
| Ambre         | Besson          |    1.80     |
| Amand         | Coquelin        |    1.76     |
| Laure         | Maret           |    1.74     |
| Vincent       | Jacquier        |    1.68     |
| Radegonde     | Rémy            |    1.64     |
| Gwendoline    | Bonhomme        |    1.63     |
| Marie-Claire  | Poincaré        |    1.63     |
| Christian     | Vérany          |    1.62     |
| Pierre        | Beaumont        |    1.62     |
| Liliane       | Boissonade      |    1.61     |
| Nassima       | Picard          |    1.59     |
| Benjamin      | Boutroux        |    1.56     |
| Jean-Marc     | Beauvau         |    1.55     |
| Clara         | Morin           |    1.55     |
| Solange       | Valluy          |    1.52     |
| Jérémy        | Leloup          |    1.49     |
| Axelle        | Bruneau         |    1.49     |
| Lydie         | Rochefort       |    1.46     |
| Damien        | Courtet         |    1.37     |
| Adeline       | Vannier         |    1.36     |
| Sarah         | Grosjean        |    1.35     |
| Nathan        | Frère           |    1.31     |
| Eugénie       | Lussier         |    1.25     |
| Dimitri       | Cazenave        |    1.12     |
| Éva           | Bissonnette     |    1.06     |
| Jérémy        | Vasseur         |    0.98     |
| Robin         | Bechard         |    0.96     |
*/
