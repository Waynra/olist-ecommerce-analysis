"""Download the Olist public e-commerce dataset (MIT license) into data/raw/.

Source: https://github.com/olist/work-at-olist-data
Run from the project root:
    python src/download_data.py
"""
from pathlib import Path
from urllib.request import urlretrieve

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "data" / "raw"
BASE_URL = "https://raw.githubusercontent.com/olist/work-at-olist-data/master/datasets"

FILES = [
    "olist_customers_dataset.csv",
    "olist_orders_dataset.csv",
    "olist_order_items_dataset.csv",
    "olist_order_payments_dataset.csv",
    "olist_order_reviews_dataset.csv",
    "olist_products_dataset.csv",
    "olist_sellers_dataset.csv",
    "product_category_name_translation.csv",
]


def main():
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    for name in FILES:
        target = RAW_DIR / name
        if target.exists():
            print(f"skip  {name} (already downloaded)")
            continue
        print(f"get   {name}")
        urlretrieve(f"{BASE_URL}/{name}", target)


if __name__ == "__main__":
    main()
