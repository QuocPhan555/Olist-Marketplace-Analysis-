-- Q1. Is the business growing steadily ?  
-- Why: Understanding growth comes from more orders or from bigger orders
-- Steps:
--    1. CTE: one row per month with GMV, number of orders and AOV.
--    2. LAG() to get the previous month's value, then compute % MoM change.
WITH monthly AS (
    SELECT DATE_TRUNC('month', o.order_purchase_timestamp)::DATE AS month,
            COUNT (DISTINCT o.order_id) AS num_order,
            SUM(oi.price) as gmv
    FROM orders o 
    INNER JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status NOT IN ('cancelled', 'unavailable') 
        AND o.order_purchase_timestamp > '2017-01-01'
        AND o.order_purchase_timestamp < '2018-09-01'
    GROUP BY 1
)
SELECT 
    month,
    num_order,
    ROUND(gmv,1) AS gmv_brl, -- sum of price value (revenue/month) -- 
    ROUND (gmv/num_order,1) AS aov_brl, -- avg of order -- we wanna know the growing because that we have more orders or customer buy more items for each order
    ROUND (100.0*(gmv/LAG(gmv) OVER w-1),1) AS mom_pct, -- Month by Month, we know the growth compared to the last month 
    ROUND (100.0*(gmv/LAG(gmv,12) OVER w-1),1) AS yoy_pct -- Year by Year, comparing the growth of month this year with the same month of last year 
    FROM monthly
WINDOW w AS (ORDER BY month)
ORDER BY month ;


-- Q2. Of all orders placed, how many make it through each step to a satisfied customer, and where do we lose the most? 
-- Step to complete one order placement:  Placed → Approved → Handed to carrier (Shipped) → Delivered → On time → Rated 4-5 stars
-- Steps:
--    1. Flag each order for every step it reached.
--    2. Count orders per step, then compute % kept vs the previous step in total orders

WITH step AS (
    SELECT 
            o.order_approved_at IS NOT NULL AS approved,
            o.order_delivered_carrier_date IS NOT NULL AS shipped,
            (o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL) AS delivered, 
            o.order_delivered_customer_date::date <= o.order_estimated_delivery_date::date AS on_time,
            o_r.review_score AS score_feedback
    FROM orders o
    LEFT JOIN order_reviews o_r ON o_r.order_id = o.order_id
    WHERE o.order_purchase_timestamp > '2017-01-01'
    AND o.order_purchase_timestamp < '2018-09-01'
    ),
    --building the funnel
point_at_each_stage AS (
        SELECT COUNT(*) AS placed, 
        COUNT(*) FILTER (WHERE approved) AS approved,
        COUNT(*) FILTER (WHERE shipped) AS shipped,
        COUNT(*) FILTER (WHERE delivered) AS delivered,
        COUNT(*) FILTER (WHERE delivered AND on_time) AS on_time, -- combining the previous condition to see how many orders delivered on time 
        COUNT(*) FILTER (WHERE delivered AND on_time AND score_feedback >= 4) AS satisfied_customers -- orders delivered on time and received good score (above 4 stars)
        FROM step 
    )
    --SELECT * FROM point_at_each_stage paes LIMIT 10 ;-- to check the value at each step in order complement 
    SELECT
        v.step,
        v.stage,
        v.n                                                     AS total_orders,
        ROUND(100.0 * v.n / paes.placed, 1)                     AS pct_placed_orders,
        ROUND(100.0 * v.n / LAG(v.n) OVER (ORDER BY v.step), 1) AS pct_previous_stage
    FROM point_at_each_stage paes
    CROSS JOIN LATERAL (VALUES (1, 'Placed',            paes.placed),
                            (2, 'Approved',          paes.approved),
                            (3, 'Handed to carrier', paes.shipped),
                            (4, 'Delivered',         paes.delivered),
                            (5, 'On time',           paes.on_time),
                            (6, 'Rated 4-5 stars',   paes.satisfied_customers)
                    ) AS v(step, stage, n)
    ORDER BY v.step;


-- Q3. To understand the rentention of customer - if customer come back and how fast ?
-- Why: Repeat customers are cheaper than new ones, so retention shows long-term health.
WITH repurchase_order AS (
    SELECT c.customer_unique_id,
            o.order_purchase_timestamp::date AS order_day,
            ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp) AS number_order,
            LEAD (o.order_purchase_timestamp::date) OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp) AS next_day
    FROM orders o
    INNER JOIN customers c ON o.customer_id = c.customer_id::text
    WHERE o.order_status NOT IN ('canceled' , 'unavailable')
)
SELECT COUNT(*) FILTER (WHERE number_order = 1) AS customer_buy,

        COUNT(*) FILTER (WHERE number_order = 2) AS repeat_customer,
        ROUND ((100.0*COUNT(*) FILTER (WHERE number_order = 2) / COUNT(*) FILTER (WHERE number_order = 1)),2) AS retention_rate,
        COUNT(*) FILTER (WHERE order_day = next_day) AS second_order_same_day, -- in case customer split the bill for the same day, 
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY next_day-order_day) FILTER (WHERE number_order = 1 and next_day IS NOT NULL) AS median_2nd_order
FROM repurchase_order; 

-- Q4. To see the basket value (the frequent of group items ) and which basket size drive revenue ? 
    -- Steps: 1. CTE make the one row per order with number of items and basket value
    --        2. Grouping by basket size (I make it until 4 and 5+ items). 
    --        3. Using window function (SUM() OVER()) to calculate the %revenue in total order

WITH basket AS(
    SELECT oi.order_id,
        COUNT(*) AS n_items,
        SUM(oi.price) AS basket_value
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp >= '2017-01-01'
        AND o.order_purchase_timestamp <= '2018-09-01'
        AND o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY oi.order_id
)
SELECT 
    CASE WHEN n_items >= 5 THEN '+5' ELSE n_items::text END AS item_in_basket,
    COUNT(*) AS n_orders,
    ROUND((100.0* COUNT(*)/ SUM(COUNT(*)) OVER()),1) AS percent_order, -- to see share of order the whole total items
    ROUND(AVG(basket_value),1) AS avg_basket, -- avg of order basket 
    ROUND(100.0 *SUM(basket_value)/ SUM(SUM(basket_value)) OVER (),1) AS percent_gmv -- to see share of value
FROM basket 
GROUP BY n_items
ORDER BY n_items; 

-- Q4. To see which products are usually bought together ?

WITH pair_products AS (
    SELECT DISTINCT p.product_category_name, oi.order_id
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
)
SELECT  pp_a.product_category_name AS cat_a,
        pp_b.product_category_name AS cat_b,
        COUNT(*) AS count_together,
FROM pair_products pp_a 
JOIN pair_products pp_b ON pp_a.order_id = pp_b.order_id AND pp_a.product_category_name < pp_b.product_category_name
GROUP BY cat_a,cat_b
ORDER BY count_together DESC
LIMIT 10 ;


-- Q5. Which category drive the most revenue and is it get good feedback (review score from 4) from customers ? 
-- Steps: 1. CTE one row per category with revenue, orders and average review.
--        2. RANK() by revenue, % of total revenue, running cumulative 

WITH rev_cat AS (
    SELECT 
    p.product_category_name,
    SUM(oi.price) AS rev_value, -- the total price of products sold 
    COUNT(DISTINCT oi.order_id) AS n_orders,
    ROUND(AVG(r.review_score),1) AS avg_review -- review score 
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    LEFT JOIN order_reviews r ON oi.order_id = r.order_id    
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    AND o.order_purchase_timestamp >= '2017-01-01'
    AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY p.product_category_name
    ORDER BY rev_value DESC
)
SELECT

    RANK() OVER (ORDER BY rev_value DESC) AS rank,
    product_category_name,
    ROUND(rev_value,1) AS sales_brl, -- to see which category drive the most revenue , value of product sold
    n_orders,
    ROUND(avg_review,2) AS avg_review, -- to check if the order get the satisfied review score 
    ROUND ((100.0*rev_value/ SUM(rev_value) OVER ()),1) AS percent_sales, -- the share of revenue 
    ROUND ((100.0*SUM(rev_value) OVER (ORDER BY rev_value DESC)/SUM(rev_value) OVER ()),1) AS cumulated_rev_value
FROM rev_cat
ORDER BY rank
LIMIT 10; 

--Q6. When an order arrives late, how much do customer reviews drop ? 
-- To see if delivery rate is worth to invest in. Raising 2 sub-business questions :
--      1. late order get worse review, and see delivery is major factor ? 
--      2. What is the average date late for orders ? 
-- Step to do: Calculate Actual_delivered - Estimated_delivered and sorted into 'early', 'on_time', 'late'

WITH late_deliver AS (
    SELECT 
    o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date AS late_days,
    r.review_score AS score
    FROM orders o 
    JOIN order_reviews r ON o.order_id=r.order_id
    WHERE o.order_status NOT IN ('canceled','unavailable')
        AND o.order_status = 'delivered'
        AND o.order_delivered_customer_date IS NOT NULL 
        AND o.order_purchase_timestamp >= '2017-01-01'
        AND o.order_purchase_timestamp < '2018-09-01'
)
SELECT CASE WHEN late_days <= -7 THEN '1. 7+ days early'
            WHEN late_days <= 0 THEN '2. 0-6 days early'
            WHEN late_days <= 3 THEN '3. 1-3 days late'
            WHEN late_days <= 7 THEN '4. 4-7 days late'
            ELSE '5. 7+ days late'
        END AS type_days_late,
        COUNT(*) AS number_order,
        ROUND (100.0*COUNT(*)/SUM(COUNT(*)) OVER(),1) AS pct_orders, -- see the share of each type order late in total order 
        ROUND (AVG(score),1) AS avg_score,
        ROUND (100.0*avg((score <= 2)::int),1) AS pct_bad_reviews -- share of order has bad scores
FROM late_deliver
GROUP BY type_days_late
ORDER BY type_days_late;

-- Q7. If the first order'customer is late, does it likely come back ?
--- The revenue lost = customer_lost * future_value_orders
---Step: Count how many orders are purchased per customer, check if the first order is late and the percentage they come back ? 

WITH come_back AS (
    SELECT c.customer_unique_id,
        CASE WHEN o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL 
            THEN o.order_delivered_customer_date::date > o.order_estimated_delivery_date::date 
        END AS is_late, -- check the order is late 
    ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY o.order_purchase_timestamp) AS order_number, -- ranking the order per each customer
    COUNT(*) OVER (PARTITION BY customer_unique_id) AS total_orders -- total orders each customer buy 
    FROM orders o 
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled','unavailable')
        AND o.order_purchase_timestamp >= '2017-01-01'
        AND o.order_purchase_timestamp < '2018-09-01'
)
SELECT 
    CASE WHEN is_late THEN 'First Order Late' ELSE 'First Order NOT Late' END AS checking_first_order,
    COUNT(*) AS customers,
    ROUND (100.0*AVG((total_orders >1)::int),1) AS repeat_purchase_rate, 
    ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct_customers --see 
FROM come_back
WHERE order_number = 1 AND is_late IS NOT NULL --- the first orders are selected 
GROUP BY checking_first_order; 



