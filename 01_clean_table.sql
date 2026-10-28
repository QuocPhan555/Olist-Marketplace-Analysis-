---- Module A.1.Audit - To test is it a unique key ? 

--Single keys: orders.order_id, customers.customer_id, products.product_id, sellers.seller_id, order_reviews.review_id
WITH key_values AS (
    SELECT 'orders' AS table_name, 'order_id' AS key_cols, order_id AS key_val FROM orders
    UNION ALL SELECT 'customers' , 'customer_id' , customer_id FROM customers
    UNION ALL SELECT 'products' , 'product_id', product_id FROM products
    UNION ALL SELECT 'seller', 'seller_id' , seller_id FROM sellers
    UNION ALL SELECT 'order_reviews',  'review_id', review_id FROM order_reviews
    UNION ALL SELECT 'order_reviews',  'order_id',  order_id  FROM order_reviews
-- Composite keys: order_items (order_id, order_item_id), order_payments (order_id, payment_sequential)
    UNION ALL SELECT  'order_items', 'order_id + order_item_id', order_id || '|' || order_item_id FROM order_items
    UNION ALL SELECT 'order_payments' , 'order_id + payment_sequential', order_id || '|' || payment_sequential FROM order_payments
)
SELECT table_name,
        key_cols, 
        COUNT (*)   AS total_value,
        COUNT (DISTINCT key_val) AS distinct_rows,
        COUNT (*) - COUNT(DISTINCT (key_val)) AS duplicate_rows,
        COUNT (*)  FILTER (WHERE key_val IS NULL OR TRIM(key_val) = '' ) AS null_keys,
        CASE WHEN COUNT(*) = COUNT(DISTINCT key_val) 
            AND COUNT (*) FILTER (WHERE key_val IS NULL OR TRIM(key_val) = '' ) = 0
        THEN 'yes' ELSE 'no' END AS is_unique
FROM key_values
GROUP BY table_name, key_cols
ORDER BY is_unique, duplicate_rows DESC; 

-- Review_id has 814 duplicated values. Is it real duplicated or the same IDs are used for different orders ? 
WITH dup_ids AS (
    SELECT review_id
    FROM order_reviews
    GROUP BY review_id
    HAVING COUNT(*) > 1
)
,
profile AS (
    SELECT  order_reviews.review_id,
            COUNT (*) AS total_rows,
            COUNT (DISTINCT order_id) AS n_orders,
            COUNT (DISTINCT review_score) AS n_scores,
            COUNT (DISTINCT review_comment_message) AS n_message
    FROM order_reviews 
    INNER JOIN dup_ids ON dup_ids.review_id = order_reviews.review_id  
    GROUP BY order_reviews.review_id
)
-- (SELECT 'dup_ids' AS step, COUNT(*) AS n FROM dup_ids
-- UNION ALL SELECT 'profile', COUNT(*) FROM profile -- 
SELECT CASE WHEN n_orders = 1 THEN 'true_copy_delelete' ELSE 'different_orders' END AS dup_type,
        CASE WHEN n_scores = 1 THEN 'same_scores_delete' ELSE 'different_score' END AS score_type,
        COUNT (*) AS n_review_ids,
        SUM(total_rows) AS n_rows
FROM profile
GROUP BY dup_type, score_type
ORDER BY n_review_ids;  


/* A1 · Task 1c — Reviews per order: distribution */

SELECT n_reviews,
       COUNT(*)                                            AS n_orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS pct_orders
FROM (
    SELECT order_id, COUNT(*) AS n_reviews
    FROM order_reviews
    GROUP BY order_id
) per_order
GROUP BY n_reviews
ORDER BY n_reviews;

/* A1 · Task 1d — Orders with 2+ reviews: do they disagree? */

SELECT order_id,
       COUNT(*)                         AS n_reviews,
       MIN(review_score)                AS min_score,
       MAX(review_score)                AS max_score,
       MIN(review_creation_date)        AS first_review,
       MAX(review_creation_date)        AS last_review
FROM order_reviews
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY n_reviews DESC, order_id
LIMIT 20;

-- 2. Checking Orphan Row ( the value has no match table it linked to)
-- For example, to check order_items → orders	Revenue that belongs to no order

WITH test_orphan AS (SELECT 'order_items -> orders' AS check_name,
       COUNT(*) FILTER (WHERE o.order_id IS NULL) AS orphan_rows,
       COUNT(*)                                   AS total_rows
FROM order_items oi
LEFT JOIN orders o ON o.order_id = oi.order_id
UNION ALL
-- order_items → products	Sales you can’t assign to a category
SELECT 'order_items → products',
        COUNT(*) FILTER (WHERE p.product_id IS NULL),
        COUNT(*)
FROM order_items oi
LEFT JOIN products p ON p.product_id = oi.product_id
UNION ALL 
-- order_items → sellers    Sales you can’t assign to a seller
 SELECT 'order_items → sellers',
           COUNT(*) FILTER (WHERE s.seller_id IS NULL),
           COUNT(*)
FROM order_items oi
LEFT JOIN sellers s ON s.seller_id = oi.seller_id
UNION ALL
--  orders → order_items    Orders with no revenue
SELECT 'orders → order_items',
        COUNT(*) FILTER (WHERE oi.order_id IS NULL),
        COUNT(DISTINCT o.order_id)
FROM orders o
LEFT JOIN order_items oi ON oi.order_id = o.order_id
UNION ALL
-- orders → order_payments    Orders that were never paid
SELECT 'orders → order_payments',
        COUNT(*) FILTER (WHERE op.order_id IS NULL),
        COUNT(DISTINCT o.order_id)
FROM orders o
LEFT JOIN order_payments op ON op.order_id = o.order_id
UNION ALL
SELECT 'products → category_translation',
         COUNT(DISTINCT p.product_category_name) FILTER (WHERE t.product_category_name IS NULL),
         COUNT(DISTINCT p.product_category_name)
FROM products p
LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
) 

SELECT 
    *,
    ROUND ((orphan_rows*100.0/total_rows ),2) AS pct_orphan
FROM test_orphan
ORDER BY orphan_rows DESC; 

SELECT o.order_status,
        COUNT (*) AS n_orders
FROM orders o
LEFT JOIN order_items oi ON oi.order_id = o.order_id
WHERE oi.order_id is NULL 
GROUP BY o.order_status
ORDER BY n_orders DESC; 

-- Q3. Can we trust the columns our KPIs depend on, and on how many rows? - Dealing with missing data 

--orders: order_approved_at, order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date
SELECT 
    'orders' AS checking_missing_table,
     COUNT(*) FILTER (WHERE order_approved_at IS NULL OR TRIM (order_approved_at) = '') AS oaa_miss ,
     COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL OR TRIM (order_delivered_carrier_date) = '') AS odcad_miss,
     COUNT(*) FILTER (WHERE order_status = 'delivered' AND ( order_delivered_customer_date IS NULL 
                                                            OR TRIM (order_delivered_customer_date) = '')) AS odcud_miss,
     COUNT(*) FILTER (WHERE order_estimated_delivery_date IS NULL OR TRIM (order_estimated_delivery_date) = '') AS oedd_miss,
    COUNT(*) AS total_rows
FROM orders
--WHERE order_status = 'delivered'
;
-- to see the missing value based on order_status as we consider only 'delivered' on the KPI reporting --
SELECT order_status,
       COUNT(*) AS total_rows,
       COUNT(*) FILTER (WHERE order_approved_at IS NULL OR TRIM(order_approved_at) = '')                         AS oaa_miss,
       COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL OR TRIM(order_delivered_carrier_date) = '')   AS odcad_miss,
       COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL OR TRIM(order_delivered_customer_date) = '') AS odcud_miss,
       COUNT(*) FILTER (WHERE order_estimated_delivery_date IS NULL OR TRIM(order_estimated_delivery_date) = '') AS oedd_miss
FROM orders
GROUP BY order_status
ORDER BY total_rows DESC;
SELECT 
    'products' AS checking_missing_table ,
    COUNT(*) FILTER (WHERE product_category_name IS NULL OR TRIM(CAST(product_category_name AS TEXT)) = '') AS pcn_miss,
    COUNT(*) FILTER (WHERE product_weight_g IS NULL OR TRIM(CAST(product_weight_g AS TEXT)) = '') AS pwg_miss,
    COUNT(*) AS total_rows
FROM products;

SELECT 
    'order_reviews' checking_missing_table,
    COUNT(*) FILTER (WHERE review_comment_message IS NULL OR TRIM(CAST(review_comment_message AS TEXT)) = '') AS rcm_miss,
    COUNT(*) AS total_rows
FROM order_reviews;

-- Transform date format 
WITH transform_date AS (
    SELECT order_id, order_status,
            order_purchase_timestamp::timestamp AS purchased,
            order_approved_at::timestamp AS approved,
            order_delivered_carrier_date::timestamp AS to_carrier,
           order_delivered_customer_date::timestamp AS delivered
    FROM orders
)
SELECT 
    COUNT(*) FILTER (WHERE approved < purchased) AS approved_before_purchase,
    COUNT(*) FILTER (WHERE to_carrier < approved)   AS carrier_before_approval,
    COUNT(*) FILTER (WHERE delivered  < purchased)  AS delivered_before_purchase,
    COUNT(*) FILTER (WHERE delivered  < to_carrier) AS delivered_before_carrier
FROM transform_date; 

-- Step 3 — Which months are complete?
-- Goal: find thin months at the start and end of the data, so the
WITH transform_date AS (
    SELECT order_id,
            order_purchase_timestamp::timestamp AS purchased
    FROM orders
),
monthly AS (
    SELECT DATE_TRUNC ('month', purchased)::date AS month_start,
    MIN(purchased)::date AS first_order_day,
    MAX(purchased)::date AS last_order_day,
    COUNT(*) AS n_orders,
    COUNT(DISTINCT purchased) AS day_with_orders
    FROM transform_date
    GROUP BY month_start
)
SELECT 
    first_order_day,
    last_order_day,
    ROUND (100*n_orders/ AVG(n_orders) OVER (),1) AS pct_of_avg_month,
    day_with_orders,
    n_orders
FROM monthly
ORDER BY month_start
;



-- Clean Review-- Assitance with AI 

/* 01_clean_tables.sql — Olist Marketplace Health Audit · Day 1 cleaning
   Cleans the original tables IN PLACE (same table names), essentials only:
     1. Correct data types (text → timestamp / numeric / integer)
     2. Remove duplicate reviews (DQ-01, DQ-02)
     3. Standardise zip codes and city names
     4. Add an English category with fallback (DQ-05), fix misspelled column names
     5. Primary keys + indexes on join columns (faster joins)
   Business filters (canceled orders, analysis window, late flag) are applied in the
   analysis queries, not here.
 
   Runs as ONE transaction: if any step fails, nothing is changed.
   Run it ONCE. Columns are already converted afterwards, so a second run fails;
   to start over, reload the CSVs with 00_setup_raw.sql.                              */
 
BEGIN;
 
/* 1. ORDERS — dates to timestamps --------------------------------------------------
   NULLIF(TRIM(x), '') turns empty strings into NULL so the cast cannot fail.          */
ALTER TABLE orders
    ALTER COLUMN order_purchase_timestamp      TYPE timestamp USING NULLIF(TRIM(order_purchase_timestamp), '')::timestamp,
    ALTER COLUMN order_approved_at             TYPE timestamp USING NULLIF(TRIM(order_approved_at), '')::timestamp,
    ALTER COLUMN order_delivered_carrier_date  TYPE timestamp USING NULLIF(TRIM(order_delivered_carrier_date), '')::timestamp,
    ALTER COLUMN order_delivered_customer_date TYPE timestamp USING NULLIF(TRIM(order_delivered_customer_date), '')::timestamp,
    ALTER COLUMN order_estimated_delivery_date TYPE timestamp USING NULLIF(TRIM(order_estimated_delivery_date), '')::timestamp;
 
ALTER TABLE orders ADD PRIMARY KEY (order_id);
CREATE INDEX ON orders (customer_id);
 
 
/* 2. ORDER ITEMS — money to numeric -------------------------------------------------- */
ALTER TABLE order_items
    ALTER COLUMN order_item_id       TYPE int           USING order_item_id::int,
    ALTER COLUMN shipping_limit_date TYPE timestamp     USING NULLIF(TRIM(shipping_limit_date), '')::timestamp,
    ALTER COLUMN price               TYPE numeric(10,2) USING price::numeric,
    ALTER COLUMN freight_value       TYPE numeric(10,2) USING freight_value::numeric;
 
ALTER TABLE order_items ADD PRIMARY KEY (order_id, order_item_id);
CREATE INDEX ON order_items (product_id);
CREATE INDEX ON order_items (seller_id);
 
 
/* 3. ORDER PAYMENTS — numbers to numeric/integer ------------------------------------- */
ALTER TABLE order_payments
    ALTER COLUMN payment_sequential   TYPE int           USING payment_sequential::int,
    ALTER COLUMN payment_installments TYPE int           USING payment_installments::int,
    ALTER COLUMN payment_value        TYPE numeric(10,2) USING payment_value::numeric;
 
ALTER TABLE order_payments ADD PRIMARY KEY (order_id, payment_sequential);
 
 
/* 4. ORDER REVIEWS — types, then one review per order (DQ-01, DQ-02) -----------------
   Keep the latest answered review per order; delete the rest.
   ctid = PostgreSQL's internal row address, used because no column is unique yet.     */
ALTER TABLE order_reviews
    ALTER COLUMN review_score            TYPE int       USING review_score::int,
    ALTER COLUMN review_creation_date    TYPE timestamp USING NULLIF(TRIM(review_creation_date), '')::timestamp,
    ALTER COLUMN review_answer_timestamp TYPE timestamp USING NULLIF(TRIM(review_answer_timestamp), '')::timestamp;
 
UPDATE order_reviews
SET review_comment_title   = NULLIF(TRIM(review_comment_title), ''),
    review_comment_message = NULLIF(TRIM(review_comment_message), '');
 
DELETE FROM order_reviews r
USING (
    SELECT ctid,
           ROW_NUMBER() OVER (PARTITION BY order_id
                              ORDER BY review_answer_timestamp DESC,
                                       review_creation_date DESC) AS rn
    FROM order_reviews
) d
WHERE r.ctid = d.ctid
  AND d.rn > 1;
 
ALTER TABLE order_reviews ADD PRIMARY KEY (order_id);   -- proves the dedup worked
 
 
/* 5. CUSTOMERS — 5-digit zips, one spelling per city -------------------------------- */
UPDATE customers
SET customer_zip_code_prefix = LPAD(TRIM(customer_zip_code_prefix), 5, '0'),
    customer_city  = TRANSLATE(LOWER(TRIM(customer_city)),
                               'áàâãäéèêíìîóòôõúùûüç', 'aaaaaeeeiiiooooouuuuc'),
    customer_state = UPPER(TRIM(customer_state));
 
ALTER TABLE customers ADD PRIMARY KEY (customer_id);
CREATE INDEX ON customers (customer_unique_id);
 
 
/* 6. SELLERS — same, plus remove extra text such as "sao paulo / sp" ---------------- */
UPDATE sellers
SET seller_zip_code_prefix = LPAD(TRIM(seller_zip_code_prefix), 5, '0'),
    seller_city  = TRIM(SPLIT_PART(SPLIT_PART(
                       TRANSLATE(LOWER(TRIM(seller_city)),
                                 'áàâãäéèêíìîóòôõúùûüç', 'aaaaaeeeiiiooooouuuuc'),
                       '/', 1), ',', 1)),
    seller_state = UPPER(TRIM(seller_state));
 
ALTER TABLE sellers ADD PRIMARY KEY (seller_id);
 
 
/* 7. PRODUCTS — fix column names, types, English category (DQ-05) ------------------- */
ALTER TABLE products RENAME COLUMN product_name_lenght        TO product_name_length;
ALTER TABLE products RENAME COLUMN product_description_lenght TO product_description_length;
 
ALTER TABLE products
    ALTER COLUMN product_name_length        TYPE int     USING NULLIF(TRIM(product_name_length), '')::int,
    ALTER COLUMN product_description_length TYPE int     USING NULLIF(TRIM(product_description_length), '')::int,
    ALTER COLUMN product_photos_qty         TYPE int     USING NULLIF(TRIM(product_photos_qty), '')::int,
    ALTER COLUMN product_weight_g           TYPE numeric USING NULLIF(TRIM(product_weight_g), '')::numeric,
    ALTER COLUMN product_length_cm          TYPE numeric USING NULLIF(TRIM(product_length_cm), '')::numeric,
    ALTER COLUMN product_height_cm          TYPE numeric USING NULLIF(TRIM(product_height_cm), '')::numeric,
    ALTER COLUMN product_width_cm           TYPE numeric USING NULLIF(TRIM(product_width_cm), '')::numeric;
 
-- English name; if no translation, readable Portuguese; if no category, 'Uncategorised'
ALTER TABLE products ADD COLUMN category TEXT;
 
UPDATE products p
SET category = COALESCE(
        (SELECT t.product_category_name_english
         FROM category_translation t
         WHERE t.product_category_name = p.product_category_name),
        INITCAP(REPLACE(p.product_category_name, '_', ' ')),
        'Uncategorised');
 
ALTER TABLE products ADD PRIMARY KEY (product_id);
 
COMMIT;
 
-- Refresh table statistics so the planner picks good join plans
ANALYZE;
 
 
/* CHECK — row counts after cleaning ------------------------------------------------- */
SELECT 'orders' AS table_name, COUNT(*) AS n_rows FROM orders
UNION ALL SELECT 'order_items',    COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews',  COUNT(*) FROM order_reviews
UNION ALL SELECT 'customers',      COUNT(*) FROM customers
UNION ALL SELECT 'sellers',        COUNT(*) FROM sellers
UNION ALL SELECT 'products',       COUNT(*) FROM products
ORDER BY n_rows DESC;
