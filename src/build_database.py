"""Clean the raw Olist CSV files and load them into a SQLite database.

Steps (ELT):
    1. sql/schema.sql      create empty tables
    2. clean_* functions   clean each CSV with pandas and load it
    3. sql/transform.sql   build the analysis-ready fact tables

Run from the project root:
    python src/build_database.py

Output:
    data/olist.db                   cleaned tables + fact tables
    reports/data_cleaning_log.md    what was changed and why
"""
import sqlite3
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "data" / "raw"
DB_PATH = ROOT / "data" / "olist.db"
SCHEMA_PATH = ROOT / "sql" / "schema.sql"
TRANSFORM_PATH = ROOT / "sql" / "transform.sql"
LOG_PATH = ROOT / "reports" / "data_cleaning_log.md"

log_lines = []


def log(message):
    print(message)
    log_lines.append(f"- {message}")


def read_raw(name):
    return pd.read_csv(RAW_DIR / f"{name}.csv")


def as_sql_text(series):
    """SQLite has no datetime type, so store timestamps as 'YYYY-MM-DD HH:MM:SS' text."""
    return series.dt.strftime("%Y-%m-%d %H:%M:%S")


def clean_customers():
    df = read_raw("olist_customers_dataset").rename(columns={
        "customer_zip_code_prefix": "zip_prefix",
        "customer_city": "city",
        "customer_state": "state",
    })
    df["zip_prefix"] = df["zip_prefix"].astype(str).str.zfill(5)
    log(f"customers: {len(df):,} rows, {df['customer_unique_id'].nunique():,} unique people "
        "(customer_id changes on every order, so retention uses customer_unique_id)")
    return df


def clean_sellers():
    df = read_raw("olist_sellers_dataset").rename(columns={
        "seller_zip_code_prefix": "zip_prefix",
        "seller_city": "city",
        "seller_state": "state",
    })
    df["zip_prefix"] = df["zip_prefix"].astype(str).str.zfill(5)
    log(f"sellers: {len(df):,} rows, no changes needed")
    return df


def clean_products():
    df = read_raw("olist_products_dataset").rename(columns={
        # the source file misspells "length"
        "product_name_lenght": "name_length",
        "product_description_lenght": "description_length",
        "product_photos_qty": "photos_qty",
        "product_weight_g": "weight_g",
        "product_length_cm": "length_cm",
        "product_height_cm": "height_cm",
        "product_width_cm": "width_cm",
    })
    translation = read_raw("product_category_name_translation")
    to_english = dict(zip(translation["product_category_name"],
                          translation["product_category_name_english"]))

    missing = df["product_category_name"].isna()
    untranslated = ~missing & ~df["product_category_name"].isin(to_english)
    log(f"products: fixed misspelled column names (lenght -> length)")
    log(f"products: {missing.sum():,} products had no category -> set to 'unknown'")
    log(f"products: {df.loc[untranslated, 'product_category_name'].nunique()} categories had no English "
        f"translation ({', '.join(sorted(df.loc[untranslated, 'product_category_name'].unique()))}) "
        "-> kept the Portuguese name")

    df["category"] = (df["product_category_name"].map(to_english)
                      .fillna(df["product_category_name"])
                      .fillna("unknown"))
    return df.drop(columns="product_category_name")


def clean_orders():
    df = read_raw("olist_orders_dataset").rename(columns={
        "order_status": "status",
        "order_purchase_timestamp": "purchased_at",
        "order_approved_at": "approved_at",
        "order_delivered_carrier_date": "delivered_carrier_at",
        "order_delivered_customer_date": "delivered_customer_at",
        "order_estimated_delivery_date": "estimated_delivery_at",
    })
    ts_cols = ["purchased_at", "approved_at", "delivered_carrier_at",
               "delivered_customer_at", "estimated_delivery_at"]
    for col in ts_cols:
        df[col] = pd.to_datetime(df[col], errors="coerce")

    delivered_no_date = (df["status"] == "delivered") & df["delivered_customer_at"].isna()
    log(f"orders: {delivered_no_date.sum()} orders marked 'delivered' have no delivery date "
        "-> kept, but left out of delivery-time metrics")

    not_delivered_with_date = (df["status"] != "delivered") & df["delivered_customer_at"].notna()
    log(f"orders: {not_delivered_with_date.sum()} orders have a delivery date but a different status "
        "(e.g. canceled after delivery) -> delivery date removed so they don't count as delivered")
    df.loc[not_delivered_with_date, "delivered_customer_at"] = pd.NaT

    before_purchase = df["delivered_customer_at"] < df["purchased_at"]
    if before_purchase.any():
        log(f"orders: {before_purchase.sum()} orders delivered before they were purchased -> delivery date removed")
        df.loc[before_purchase, "delivered_customer_at"] = pd.NaT
    else:
        log("orders: checked that no order is delivered before it was purchased")

    in_window = (df["purchased_at"] >= "2017-01-01") & (df["purchased_at"] < "2018-09-01")
    log(f"orders: {len(df):,} rows loaded; {in_window.sum():,} fall inside the analysis window "
        "Jan 2017 - Aug 2018 (other months have < 1,000 orders and are incomplete)")

    for col in ts_cols:
        df[col] = as_sql_text(df[col])
    return df


def clean_order_items():
    df = read_raw("olist_order_items_dataset").rename(columns={"shipping_limit_date": "shipping_limit_at"})
    df["shipping_limit_at"] = as_sql_text(pd.to_datetime(df["shipping_limit_at"]))
    log(f"order_items: {len(df):,} rows, no missing values")
    return df


def clean_payments():
    df = read_raw("olist_order_payments_dataset").rename(columns={"payment_installments": "installments"})
    undefined = df["payment_type"] == "not_defined"
    log(f"payments: removed {undefined.sum()} rows with payment_type 'not_defined'")
    df = df[~undefined].copy()

    zero_installments = df["installments"] < 1
    log(f"payments: {zero_installments.sum()} rows had 0 installments -> set to 1")
    df.loc[zero_installments, "installments"] = 1
    return df


def clean_reviews():
    df = read_raw("olist_order_reviews_dataset")
    df["review_creation_date"] = pd.to_datetime(df["review_creation_date"])
    df["review_answer_timestamp"] = pd.to_datetime(df["review_answer_timestamp"])

    n_before = len(df)
    df = (df.sort_values("review_answer_timestamp")
            .drop_duplicates(subset="order_id", keep="last"))
    log(f"reviews: {n_before - len(df):,} orders had more than one review -> kept the latest one "
        f"({len(df):,} reviews left)")

    return pd.DataFrame({
        "order_id": df["order_id"],
        "review_id": df["review_id"],
        "score": df["review_score"],
        "has_comment": df["review_comment_message"].notna().astype(int),
        "created_at": as_sql_text(df["review_creation_date"]),
        "answered_at": as_sql_text(df["review_answer_timestamp"]),
    })


def main():
    tables = {
        "customers": clean_customers(),
        "sellers": clean_sellers(),
        "products": clean_products(),
        "orders": clean_orders(),
        "order_items": clean_order_items(),
        "payments": clean_payments(),
        "reviews": clean_reviews(),
    }

    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(DB_PATH) as conn:
        conn.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
        for name, df in tables.items():
            df.to_sql(name, conn, if_exists="append", index=False)
        conn.executescript(TRANSFORM_PATH.read_text(encoding="utf-8"))

        orphan_items = conn.execute(
            "SELECT COUNT(*) FROM order_items oi LEFT JOIN orders o USING (order_id) WHERE o.order_id IS NULL"
        ).fetchone()[0]
        n_fact_orders = conn.execute("SELECT COUNT(*) FROM fact_orders").fetchone()[0]
        n_fact_items = conn.execute("SELECT COUNT(*) FROM fact_order_items").fetchone()[0]
    log(f"check: {orphan_items} order items without a matching order")
    log(f"check: fact_orders has {n_fact_orders:,} orders, fact_order_items has {n_fact_items:,} items")

    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    LOG_PATH.write_text("# Data cleaning log\n\nGenerated by `src/build_database.py`.\n\n"
                        + "\n".join(log_lines) + "\n", encoding="utf-8")
    print(f"\nDatabase written to {DB_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
