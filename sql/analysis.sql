-- =====================================================================
-- Olist E-Commerce: business questions answered in SQL
-- Each query starts with "-- name: <id>" so Python can run it by name
-- (see src/queries.py). Revenue = item price of orders that were not
-- canceled or unavailable; freight is reported separately.
-- =====================================================================


-- name: overall_kpis
-- Q1. How big is the business in the analysis window?
SELECT COUNT(*)                                   AS orders,
       COUNT(DISTINCT customer_unique_id)         AS customers,
       ROUND(SUM(items_value), 0)                 AS revenue,
       ROUND(AVG(items_value), 2)                 AS avg_order_value,
       ROUND(100.0 * AVG(is_late), 1)             AS late_delivery_pct,
       ROUND(AVG(delivery_days), 1)               AS avg_delivery_days,
       ROUND(AVG(review_score), 2)                AS avg_review_score
FROM fact_orders
WHERE status NOT IN ('canceled', 'unavailable');


-- name: monthly_trend
-- Q2. How do orders and revenue develop month by month?
WITH monthly AS (
    SELECT month,
           COUNT(*)            AS orders,
           SUM(items_value)    AS revenue
    FROM fact_orders
    WHERE status NOT IN ('canceled', 'unavailable')
    GROUP BY month
)
SELECT month,
       orders,
       ROUND(revenue, 0)                                    AS revenue,
       ROUND(revenue / orders, 2)                           AS avg_order_value,
       ROUND(100.0 * (revenue - LAG(revenue) OVER w)
                   / LAG(revenue) OVER w, 1)                AS revenue_mom_pct
FROM monthly
WINDOW w AS (ORDER BY month)
ORDER BY month;


-- name: top_categories
-- Q3. Which categories drive revenue? (Pareto: cumulative share)
WITH by_category AS (
    SELECT category,
           COUNT(DISTINCT order_id)   AS orders,
           SUM(price)                 AS revenue,
           AVG(price)                 AS avg_item_price
    FROM fact_order_items
    WHERE status NOT IN ('canceled', 'unavailable')
    GROUP BY category
)
SELECT category,
       orders,
       ROUND(revenue, 0)                                                    AS revenue,
       ROUND(avg_item_price, 2)                                             AS avg_item_price,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 1)                     AS share_pct,
       ROUND(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC
                                        ROWS UNBOUNDED PRECEDING)
                   / SUM(revenue) OVER (), 1)                               AS cumulative_pct
FROM by_category
ORDER BY revenue DESC;


-- name: late_delivery_vs_review
-- Q4. Does late delivery hurt customer satisfaction?
SELECT CASE
           WHEN delay_days <= -7 THEN '1. 7+ days early'
           WHEN delay_days <=  0 THEN '2. 0-6 days early'
           WHEN delay_days <=  3 THEN '3. 1-3 days late'
           WHEN delay_days <=  7 THEN '4. 4-7 days late'
           ELSE                       '5. 8+ days late'
       END                                              AS delay_bucket,
       COUNT(*)                                         AS orders,
       ROUND(AVG(review_score), 2)                      AS avg_review_score,
       ROUND(100.0 * AVG(review_score <= 2), 1)         AS negative_review_pct
FROM fact_orders
WHERE status = 'delivered'
  AND delay_days IS NOT NULL
  AND review_score IS NOT NULL
GROUP BY delay_bucket
ORDER BY delay_bucket;


-- name: monthly_delivery
-- Q5. Is delivery performance getting better or worse?
SELECT month,
       COUNT(*)                          AS delivered_orders,
       ROUND(100.0 * AVG(is_late), 1)    AS late_delivery_pct,
       ROUND(AVG(delivery_days), 1)      AS avg_delivery_days,
       ROUND(AVG(promised_days), 1)      AS avg_promised_days,
       ROUND(AVG(review_score), 2)       AS avg_review_score
FROM fact_orders
WHERE status = 'delivered'
  AND is_late IS NOT NULL
GROUP BY month
ORDER BY month;


-- name: delivery_by_state
-- Q6. Which regions get the slowest and most expensive deliveries?
SELECT customer_state,
       COUNT(*)                                                 AS delivered_orders,
       ROUND(AVG(delivery_days), 1)                             AS avg_delivery_days,
       ROUND(100.0 * AVG(is_late), 1)                           AS late_delivery_pct,
       ROUND(100.0 * SUM(freight_value) / SUM(items_value), 1)  AS freight_to_price_pct,
       ROUND(AVG(review_score), 2)                              AS avg_review_score
FROM fact_orders
WHERE status = 'delivered'
  AND is_late IS NOT NULL
GROUP BY customer_state
HAVING COUNT(*) >= 100
ORDER BY late_delivery_pct DESC;


-- name: payment_mix
-- Q7. How do customers pay?
SELECT payment_type,
       COUNT(*)                                             AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)   AS share_pct,
       ROUND(AVG(payment_value), 2)                         AS avg_payment_value,
       ROUND(AVG(installments), 1)                          AS avg_installments
FROM fact_orders
WHERE status NOT IN ('canceled', 'unavailable')
  AND payment_type IS NOT NULL
GROUP BY payment_type
ORDER BY orders DESC;


-- name: installments_vs_value
-- Q8. Do credit-card customers who pay in installments buy bigger baskets?
SELECT CASE
           WHEN installments = 1  THEN '1. 1x (paid in full)'
           WHEN installments <= 3 THEN '2. 2-3x'
           WHEN installments <= 6 THEN '3. 4-6x'
           ELSE                        '4. 7x or more'
       END                              AS installment_group,
       COUNT(*)                         AS orders,
       ROUND(AVG(payment_value), 2)     AS avg_payment_value
FROM fact_orders
WHERE status NOT IN ('canceled', 'unavailable')
  AND payment_type = 'credit_card'
GROUP BY installment_group
ORDER BY installment_group;


-- name: customer_retention
-- Q9. How many customers come back for a second order?
WITH per_customer AS (
    SELECT customer_unique_id,
           COUNT(*) AS n_orders
    FROM fact_orders
    WHERE status NOT IN ('canceled', 'unavailable')
    GROUP BY customer_unique_id
)
SELECT COUNT(*)                                AS customers,
       SUM(n_orders > 1)                       AS repeat_customers,
       ROUND(100.0 * AVG(n_orders > 1), 2)     AS repeat_rate_pct,
       ROUND(AVG(n_orders), 3)                 AS orders_per_customer
FROM per_customer;


-- name: top_sellers
-- Q10. Who are the top 10 sellers, and how well do they deliver?
SELECT seller_id,
       seller_state,
       COUNT(DISTINCT order_id)                 AS orders,
       ROUND(SUM(price), 0)                     AS revenue,
       ROUND(100.0 * AVG(is_late), 1)           AS late_delivery_pct,
       ROUND(AVG(review_score), 2)              AS avg_review_score
FROM fact_order_items
WHERE status NOT IN ('canceled', 'unavailable')
GROUP BY seller_id, seller_state
ORDER BY revenue DESC
LIMIT 10;


-- name: data_quality_checks
-- Sanity checks run before trusting any number above.
SELECT 'orders in analysis window'                     AS check_name, COUNT(*) AS value FROM fact_orders
UNION ALL
SELECT 'orders without items',                         COUNT(*) FROM fact_orders WHERE items_count IS NULL
UNION ALL
SELECT 'orders without payment',                       COUNT(*) FROM fact_orders WHERE payment_value IS NULL
UNION ALL
SELECT 'orders without review',                        COUNT(*) FROM fact_orders WHERE review_score IS NULL
UNION ALL
SELECT 'delivered orders without delivery date',       COUNT(*) FROM fact_orders WHERE status = 'delivered' AND delivered_customer_at IS NULL
UNION ALL
SELECT 'orders where payment differs from price+freight by > 1', COUNT(*)
FROM fact_orders
WHERE ABS(payment_value - (items_value + freight_value)) > 1;
