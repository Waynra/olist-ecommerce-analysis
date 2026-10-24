-- =====================================================================
-- Olist E-Commerce: database schema (SQLite)
-- Raw-but-cleaned tables. The analysis-ready fact tables are built
-- from these in sql/transform.sql after the data is loaded.
-- =====================================================================

DROP TABLE IF EXISTS fact_order_items;
DROP TABLE IF EXISTS fact_orders;
DROP TABLE IF EXISTS reviews;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS sellers;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id         TEXT PRIMARY KEY,   -- one id per order
    customer_unique_id  TEXT NOT NULL,      -- the real person (use this for retention)
    zip_prefix          TEXT,
    city                TEXT,
    state               TEXT
);

CREATE TABLE sellers (
    seller_id   TEXT PRIMARY KEY,
    zip_prefix  TEXT,
    city        TEXT,
    state       TEXT
);

CREATE TABLE products (
    product_id          TEXT PRIMARY KEY,
    category            TEXT NOT NULL,      -- English name, 'unknown' when missing
    name_length         INTEGER,
    description_length  INTEGER,
    photos_qty          INTEGER,
    weight_g            REAL,
    length_cm           REAL,
    height_cm           REAL,
    width_cm            REAL
);

CREATE TABLE orders (
    order_id               TEXT PRIMARY KEY,
    customer_id            TEXT NOT NULL REFERENCES customers (customer_id),
    status                 TEXT NOT NULL,
    purchased_at           TEXT NOT NULL,   -- 'YYYY-MM-DD HH:MM:SS'
    approved_at            TEXT,
    delivered_carrier_at   TEXT,
    delivered_customer_at  TEXT,
    estimated_delivery_at  TEXT
);

CREATE TABLE order_items (
    order_id           TEXT NOT NULL REFERENCES orders (order_id),
    order_item_id      INTEGER NOT NULL,
    product_id         TEXT NOT NULL REFERENCES products (product_id),
    seller_id          TEXT NOT NULL REFERENCES sellers (seller_id),
    shipping_limit_at  TEXT,
    price              REAL NOT NULL,
    freight_value      REAL NOT NULL,
    PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE payments (
    order_id            TEXT NOT NULL REFERENCES orders (order_id),
    payment_sequential  INTEGER NOT NULL,
    payment_type        TEXT NOT NULL,
    installments        INTEGER NOT NULL,
    payment_value       REAL NOT NULL,
    PRIMARY KEY (order_id, payment_sequential)
);

CREATE TABLE reviews (
    order_id     TEXT PRIMARY KEY REFERENCES orders (order_id),  -- one review per order after cleaning
    review_id    TEXT NOT NULL,
    score        INTEGER NOT NULL CHECK (score BETWEEN 1 AND 5),
    has_comment  INTEGER NOT NULL,
    created_at   TEXT,
    answered_at  TEXT
);

CREATE INDEX idx_orders_customer   ON orders (customer_id);
CREATE INDEX idx_orders_purchased  ON orders (purchased_at);
CREATE INDEX idx_items_product     ON order_items (product_id);
CREATE INDEX idx_items_seller      ON order_items (seller_id);
