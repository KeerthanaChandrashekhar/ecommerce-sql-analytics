-- 04_analysis_queries.sql
-- Rules: delivered orders only; trends limited to Jan 2017 - Aug 2018;
-- reviews averaged per order before joining; customers counted by customer_unique_id.
USE olist_analytics;

-- A. Headline numbers
SELECT COUNT(DISTINCT o.order_id) AS orders,
       COUNT(DISTINCT c.customer_unique_id) AS customers,
       ROUND(SUM(oi.price),2) AS revenue,
       ROUND(SUM(oi.price)/COUNT(DISTINCT o.order_id),2) AS avg_order_value
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered';

-- B. Monthly revenue and MoM growth (LAG runs before the date filter)
WITH monthly AS (
    SELECT DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
           ROUND(SUM(oi.price), 2) AS revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY month
)
SELECT month, revenue, mom_growth_pct
FROM (
    SELECT month, revenue,
           ROUND((revenue - LAG(revenue) OVER (ORDER BY month))
                 / LAG(revenue) OVER (ORDER BY month) * 100, 2) AS mom_growth_pct
    FROM monthly
) t
WHERE month BETWEEN '2017-01' AND '2018-08';

-- C. Top 10 categories by revenue
SELECT COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
       COUNT(DISTINCT oi.order_id) AS orders,
       ROUND(SUM(oi.price), 2) AS revenue
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY category
ORDER BY revenue DESC
LIMIT 10;

-- D. Repeat purchase rate
SELECT COUNT(*) AS customers,
       SUM(order_count > 1) AS repeat_customers,
       ROUND(100 * SUM(order_count > 1) / COUNT(*), 2) AS repeat_rate_pct
FROM (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS order_count
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
) t;

-- E1. Percent of orders delivered late
SELECT COUNT(*) AS delivered_orders,
       SUM(order_delivered_customer_date > order_estimated_delivery_date) AS late_orders,
       ROUND(100 * SUM(order_delivered_customer_date > order_estimated_delivery_date) / COUNT(*), 2) AS late_pct
FROM orders
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL;

-- E2. Review score: late vs on time
WITH order_review AS (
    SELECT order_id, AVG(review_score) AS score
    FROM order_reviews GROUP BY order_id
)
SELECT CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 'Late' ELSE 'On time' END AS delivery_status,
       COUNT(*) AS orders,
       ROUND(AVG(r.score), 2) AS avg_review
FROM orders o
JOIN order_review r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
GROUP BY delivery_status;

-- F. RFM customer segmentation (summary by segment)
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
),
segmented AS (
    SELECT *,
           CASE WHEN frequency > 1 THEN 'Repeat customer'
                WHEN r_score = 4 AND m_score = 4 THEN 'Champion (recent, high spend)'
                WHEN r_score <= 2 AND m_score >= 3 THEN 'At risk (high spend, lapsed)'
                WHEN r_score = 4 THEN 'New customer'
                ELSE 'Low value' END AS segment
    FROM scored
)
SELECT segment,
       COUNT(*) AS customers,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_customers,
       ROUND(SUM(monetary), 2) AS revenue,
       ROUND(100 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 2) AS pct_revenue
FROM segmented
GROUP BY segment
ORDER BY revenue DESC;

-- G. Top 15 sellers with rank within their state (sellers with 20+ orders)
WITH order_review AS (
    SELECT order_id, AVG(review_score) AS score
    FROM order_reviews GROUP BY order_id
),
seller_orders AS (
    SELECT oi.seller_id, oi.order_id,
           SUM(oi.price) AS revenue,
           DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) AS delivery_days
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY oi.seller_id, oi.order_id,
             o.order_delivered_customer_date, o.order_purchase_timestamp
),
seller_stats AS (
    SELECT so.seller_id, s.seller_state,
           COUNT(*) AS orders,
           ROUND(SUM(so.revenue), 2) AS revenue,
           ROUND(AVG(so.delivery_days), 1) AS avg_delivery_days,
           ROUND(AVG(r.score), 2) AS avg_review
    FROM seller_orders so
    JOIN sellers s ON so.seller_id = s.seller_id
    LEFT JOIN order_review r ON so.order_id = r.order_id
    GROUP BY so.seller_id, s.seller_state
    HAVING COUNT(*) >= 20
)
SELECT *,
       RANK() OVER (PARTITION BY seller_state ORDER BY revenue DESC) AS rank_in_state
FROM seller_stats
ORDER BY revenue DESC
LIMIT 15;

-- H. Revenue and delivery speed by customer state
SELECT c.customer_state,
       COUNT(DISTINCT o.order_id) AS orders,
       ROUND(SUM(oi.price), 2) AS revenue,
       ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)), 1) AS avg_delivery_days
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY revenue DESC;
