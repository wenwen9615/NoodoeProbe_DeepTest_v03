"""第12週：簡易庫存補貨判斷（純 Python，方便單元測試）。"""


def needs_restock(quantity: int, threshold: int = 10) -> bool:
    """庫存量低於門檻時需要補貨；等於門檻時不補貨。"""
    if isinstance(quantity, bool) or not isinstance(quantity, int) or quantity < 0:
        raise ValueError("quantity 必須是非負整數")
    if isinstance(threshold, bool) or not isinstance(threshold, int) or threshold < 0:
        raise ValueError("threshold 必須是非負整數")
    return quantity < threshold


def restock_items(products: list[dict], threshold: int = 10) -> list[str]:
    """回傳需要補貨的商品名稱清單。"""
    result = []
    for product in products:
        if needs_restock(product["quantity"], threshold):
            result.append(product["name"])
    return result


if __name__ == "__main__":
    import json
    from pathlib import Path

    products = json.loads(Path(__file__).with_name("products.json").read_text(encoding="utf-8"))
    print("需要補貨的商品：", ", ".join(restock_items(products)) or "無")
