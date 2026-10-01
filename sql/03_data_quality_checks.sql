-- 03_data_quality_checks.sql
USE olist_analytics;

-- Row counts after import
SELECT 'customers' t, COUNT(*) n FROM customers UNION ALL
SELECT 'orders', COUNT(*) FROM orders UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items UNION ALL
SELECT 'order_payments', COUNT(*) FROM order_payments UNION ALL
SELECT 'order_reviews', COUNT(*) FROM order_reviews UNION ALL
SELECT 'products', COUNT(*) FROM products UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers UNION ALL
SELECT 'category_translation', COUNT(*) FROM category_translation;

-- 1. Order statuses
SELECT order_status, COUNT(*) AS orders
FROM orders GROUP BY order_status ORDER BY orders DESC;

-- 2. Delivered orders missing a delivery date
SELECT COUNT(*) FROM orders
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL;

-- 3. Orders delivered before purchase (impossible)
SELECT COUNT(*) FROM orders
WHERE order_delivered_customer_date < order_purchase_timestamp;

-- 4. Orders with more than one review
SELECT COUNT(*) FROM (
    SELECT order_id FROM order_reviews GROUP BY order_id HAVING COUNT(*) > 1
) t;

-- 5. Products with no English category name
SELECT COUNT(*) FROM products p
LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
WHERE t.product_category_name IS NULL;

-- 6. Orders per month (which months have full data?)
SELECT DATE_FORMAT(order_purchase_timestamp,'%Y-%m') AS month, COUNT(*) AS orders
FROM orders GROUP BY month ORDER BY month;
