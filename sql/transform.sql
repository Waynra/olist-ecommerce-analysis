-- =====================================================================
-- Olist E-Commerce: analysis-ready fact tables
-- Runs after the cleaned data is loaded (see src/build_database.py).
-- Materialising these as tables (instead of views) keeps every
-- analysis query fast, because the joins and window functions below
-- run once instead of on every query.
-- =====================================================================

DROP TABLE IF EXISTS fact_order_items;
DROP TABLE IF EXISTS fact_orders;

-- ---------------------------------------------------------------------
-- fact_orders: one row per order with value, payment, delivery, review.
-- Analysis window is Jan 2017 - Aug 2018: the months before and after
-- have fewer than 1,000 orders each and are incomplete.
-- ---------------------------------------------------------------------
CREATE TABLE fact_orders AS
WITH items AS (
    SELECT order_id,
           COUNT(*)                    AS items_count,
           COUNT(DISTINCT seller_id)   AS sellers_count,
           SUM(price)                  AS items_value,
           SUM(freight_value)          AS freight_value
    FROM order_items
    GROUP BY order_id
),
pay AS (
    SELECT order_id,
           SUM(payment_value)  AS payment_value,
           MAX(installments)   AS installments
    FROM payments
    GROUP BY order_id
),
main_pay AS (   -- payment type that covered the largest part of the order
    SELECT order_id, payment_type
    FROM (
        SELECT order_id, payment_type,
               ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY payment_value DESC) AS rn
        FROM payments
    )
    WHERE rn = 1
)
SELECT o.order_id,
       c.customer_unique_id,
       c.state                                        AS customer_state,
       o.status,
       o.purchased_at,
       strftime('%Y-%m', o.purchased_at)              AS month,
       i.items_count,
       i.sellers_count,
       i.items_value,
       i.freight_value,
       p.payment_value,
       p.installments,
       mp.payment_type,
       o.delivered_customer_at,
       o.estimated_delivery_at,
       ROUND(julianday(o.estimated_delivery_at) - julianday(o.purchased_at), 1)       AS promised_days,
       ROUND(julianday(o.delivered_customer_at) - julianday(o.purchased_at), 1)       AS delivery_days,
       CAST(julianday(date(o.delivered_customer_at))
          - julianday(date(o.estimated_delivery_at)) AS INTEGER)                      AS delay_days,
       CASE WHEN o.delivered_customer_at IS NULL THEN NULL
            WHEN date(o.delivered_customer_at) > date(o.estimated_delivery_at) THEN 1
            ELSE 0 END                                                                AS is_late,
       r.score                                        AS review_score
FROM orders o
JOIN customers c        ON c.customer_id = o.customer_id
LEFT JOIN items i       ON i.order_id    = o.order_id
LEFT JOIN pay p         ON p.order_id    = o.order_id
LEFT JOIN main_pay mp   ON mp.order_id   = o.order_id
LEFT JOIN reviews r     ON r.order_id    = o.order_id
WHERE o.purchased_at >= '2017-01-01'
  AND o.purchased_at <  '2018-09-01';

CREATE UNIQUE INDEX idx_fact_orders_id    ON fact_orders (order_id);
CREATE INDEX        idx_fact_orders_month ON fact_orders (month);

-- ---------------------------------------------------------------------
-- fact_order_items: one row per item with category and seller, inside
-- the same analysis window. Used for category and seller analysis.
-- ---------------------------------------------------------------------
CREATE TABLE fact_order_items AS
SELECT oi.order_id,
       oi.order_item_id,
       oi.product_id,
       p.category,
       oi.seller_id,
       s.state            AS seller_state,
       oi.price,
       oi.freight_value,
       f.month,
       f.status,
       f.customer_state,
       f.is_late,
       f.review_score
FROM order_items oi
JOIN fact_orders f  ON f.order_id   = oi.order_id
JOIN products p     ON p.product_id = oi.product_id
JOIN sellers s      ON s.seller_id  = oi.seller_id;

CREATE INDEX idx_fact_items_order    ON fact_order_items (order_id);
CREATE INDEX idx_fact_items_category ON fact_order_items (category);
