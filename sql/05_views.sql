-- 05_views.sql : clean views used by the Tableau dashboard
USE olist_analytics;

-- One row per item in a delivered order. Count orders with COUNT(DISTINCT order_id).
CREATE VIEW vw_sales_detail AS
SELECT o.order_id,
       oi.order_item_id,
       DATE(o.order_purchase_timestamp) AS order_date,
       DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
       c.customer_unique_id,
       c.customer_city,
       c.customer_state,
       COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
       oi.seller_id,
       s.seller_state,
       oi.price,
       oi.freight_value,
       DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) AS delivery_days,
       CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1
            WHEN o.order_delivered_customer_date IS NOT NULL THEN 0 END AS is_late,
       r.avg_review_score
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
JOIN customers c ON o.customer_id = c.customer_id
JOIN products p ON oi.product_id = p.product_id
JOIN sellers s ON oi.seller_id = s.seller_id
LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
LEFT JOIN (SELECT order_id, AVG(review_score) AS avg_review_score
           FROM order_reviews GROUP BY order_id) r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered';

-- One row per customer with RFM segment
CREATE VIEW vw_customer_rfm AS
WITH rfm AS (
    SELECT c.customer_unique_id,
           DATEDIFF((SELECT MAX(order_purchase_timestamp) FROM orders),
                    MAX(o.order_purchase_timestamp)) AS recency_days,
           COUNT(DISTINCT o.order_id) AS frequency,
           SUM(p.payment_value) AS monetary
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_payments p ON o.order_id = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
scored AS (
    SELECT *,
           NTILE(4) OVER (ORDER BY recency_days DESC) AS r_score,
           NTILE(4) OVER (ORDER BY monetary) AS m_score
    FROM rfm
)
SELECT customer_unique_id, recency_days, frequency,
       ROUND(monetary, 2) AS monetary, r_score, m_score,
       CASE WHEN frequency > 1 THEN 'Repeat customer'
            WHEN r_score = 4 AND m_score = 4 THEN 'Champion (recent, high spend)'
            WHEN r_score <= 2 AND m_score >= 3 THEN 'At risk (high spend, lapsed)'
            WHEN r_score = 4 THEN 'New customer'
            ELSE 'Low value' END AS segment
FROM scored;
