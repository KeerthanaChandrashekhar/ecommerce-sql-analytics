-- 02_cleaning.sql : convert text dates to DATETIME and add foreign keys
USE olist_analytics;
SET SQL_SAFE_UPDATES = 0;

-- Blank text -> NULL
UPDATE orders SET order_approved_at = NULL WHERE order_approved_at = '';
UPDATE orders SET order_delivered_carrier_date = NULL WHERE order_delivered_carrier_date = '';
UPDATE orders SET order_delivered_customer_date = NULL WHERE order_delivered_customer_date = '';

-- Real date types
ALTER TABLE orders
    MODIFY order_purchase_timestamp DATETIME,
    MODIFY order_approved_at DATETIME,
    MODIFY order_delivered_carrier_date DATETIME,
    MODIFY order_delivered_customer_date DATETIME,
    MODIFY order_estimated_delivery_date DATETIME;

ALTER TABLE order_items MODIFY shipping_limit_date DATETIME;

ALTER TABLE order_reviews
    MODIFY review_creation_date DATETIME,
    MODIFY review_answer_timestamp DATETIME;

-- Foreign keys (relational links)
ALTER TABLE orders         ADD FOREIGN KEY (customer_id) REFERENCES customers(customer_id);
ALTER TABLE order_items    ADD FOREIGN KEY (order_id)    REFERENCES orders(order_id);
ALTER TABLE order_items    ADD FOREIGN KEY (product_id)  REFERENCES products(product_id);
ALTER TABLE order_items    ADD FOREIGN KEY (seller_id)   REFERENCES sellers(seller_id);
ALTER TABLE order_payments ADD FOREIGN KEY (order_id)    REFERENCES orders(order_id);
ALTER TABLE order_reviews  ADD FOREIGN KEY (order_id)    REFERENCES orders(order_id);
