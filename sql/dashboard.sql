-- =====================================================================
-- Olist E-Commerce: aggregates for the interactive dashboard
-- Every row is split by customer state and month/year, and stores sums
-- and counts (never averages), so the dashboard can re-aggregate any
-- filter combination and still match sql/analysis.sql exactly.
-- =====================================================================


-- name: dashboard_monthly
SELECT month,
       customer_state                     AS state,
       COUNT(*)                           AS orders,
       ROUND(TOTAL(items_value), 2)       AS revenue,
       SUM(is_late IS NOT NULL)           AS delivered,
       TOTAL(is_late)                     AS late,
       TOTAL(delivery_days)               AS delivery_days_sum,
       TOTAL(review_score)                AS review_sum,
       COUNT(review_score)                AS review_n
FROM fact_orders
WHERE status NOT IN ('canceled', 'unavailable')
GROUP BY month, customer_state
ORDER BY month, customer_state;


-- name: dashboard_categories
SELECT category,
       customer_state                     AS state,
       substr(month, 1, 4)                AS year,
       COUNT(DISTINCT order_id)           AS orders,
       ROUND(SUM(price), 2)               AS revenue
FROM fact_order_items
WHERE status NOT IN ('canceled', 'unavailable')
GROUP BY category, customer_state, year;


-- name: dashboard_delay_reviews
SELECT CASE
           WHEN delay_days <= -7 THEN '7+ days early'
           WHEN delay_days <=  0 THEN '0-6 days early'
           WHEN delay_days <=  3 THEN '1-3 days late'
           WHEN delay_days <=  7 THEN '4-7 days late'
           ELSE                       '8+ days late'
       END                                AS bucket,
       customer_state                     AS state,
       substr(month, 1, 4)                AS year,
       COUNT(*)                           AS orders,
       SUM(review_score <= 2)             AS negative,
       SUM(review_score)                  AS review_sum
FROM fact_orders
WHERE status = 'delivered'
  AND delay_days IS NOT NULL
  AND review_score IS NOT NULL
GROUP BY bucket, customer_state, year;


-- name: dashboard_payments
SELECT payment_type,
       customer_state                     AS state,
       substr(month, 1, 4)                AS year,
       COUNT(*)                           AS orders,
       ROUND(SUM(payment_value), 2)       AS value_sum
FROM fact_orders
WHERE status NOT IN ('canceled', 'unavailable')
  AND payment_type IS NOT NULL
GROUP BY payment_type, customer_state, year;
