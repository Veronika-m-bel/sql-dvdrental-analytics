-- ============================================================
-- Database: PostgreSQL (dvdrental)
-- Author: Veronika-m-bel
-- Description: Analytical queries, business metrics & QA data validation
-- ============================================================


-- ============================================================
-- SECTION 1: DATA INTEGRITY & ANOMALY DETECTION 
-- ============================================================

-- 1.1. Поиск аренд без оплат (поиск потерянных платежей/аномалий)
SELECT              
    r.rental_id,
    p.payment_id
FROM rental r
LEFT JOIN payment p ON  r.rental_id =  p.rental_id
WHERE r.rental_id<1600 and r.rental_id>1200  and p.payment_id IS null 
order by r.rental_id;

-- 1.2. Поиск городов, где не открыты магазины 
SELECT 
    c.city_id,
    c.city
FROM city c
WHERE c.city_id NOT IN (
    -- Подзапрос: находим все city_id, где физически есть магазины
    SELECT ad.city_id
    FROM store s
    JOIN address ad ON s.address_id = ad.address_id
)
ORDER BY c.city_id;

-- 1.3. Свежие фильмы, у которых отсутствует запись в инвентаре
select 
f.film_id,
f.title,
inv.inventory_id
from film f 
left join inventory inv on f.film_id=inv.film_id 
WHERE f.last_update >= (
    -- Находим самую последнюю дату в таблице и отнимаем от нее 1 од
    SELECT MAX(last_update) - INTERVAL '1 year' FROM film
) and inv.inventory_id is null
order by f.title asc;

-- ============================================================
-- SECTION 2: BUSINESS & SALES ANALYTICS
-- ============================================================

-- 2.1. Рейтинг сотрудников по количеству проданных аренд
SELECT 
    s.staff_id,
    s.first_name,
    s.last_name,
    COUNT(r.rental_id) AS total_rentals 
FROM staff s
JOIN rental r ON s.staff_id = r.staff_id
GROUP BY s.staff_id, s.first_name, s.last_name 
ORDER BY total_rentals DESC;  

-- 2.2. Помесячная динамика сумм продаж за весь период
SELECT --Суммы продаж по месяцам
    TO_CHAR(r.rental_date, 'YYYY-MM') AS rental_month, 
    SUM(p.amount) AS total_amount                
FROM rental r
left join payment p on r.rental_id=p.rental_id
GROUP BY TO_CHAR(rental_date, 'YYYY-MM')
ORDER BY rental_month DESC;


-- 2.3. Анализ дневной активности аренд за последний доступный месяц в базе
SELECT 
    DATE(rental_date) AS rental_day, 
    COUNT(rental_id) AS daily_rentals
FROM rental
WHERE rental_date >= (
    -- Находим самую последнюю дату в таблице и отнимаем от нее 1 месяц
    SELECT MAX(rental_date) - INTERVAL '1 month' FROM rental
)
GROUP BY DATE(rental_date)
ORDER BY rental_day DESC;

-- 2.4. Средний чек покупок за 2006 год (с округлением)
SELECT 
    round(avg(p.amount),2) AS average_receipt_2006               
FROM rental r 
join payment p on r.rental_id=p.rental_id
where TO_CHAR(r.rental_date, 'YYYY') = '2006';


-- 2.5. Рейтинг магазинов по прибыли с выводом физических адресов
SELECT 
    s.store_id, 
    ad.address as store_address_1,
    ad.address2 as store_address_2,
    SUM(p.amount) AS total_amount                
FROM payment p
join staff st on p.staff_id=st.staff_id
join store s on st.store_id=s.store_id 
join address ad on s.address_id=ad.address_id
GROUP BY s.store_id, ad.address, ad.address2
ORDER BY total_amount DESC;

-- 2.6. Топ-100 самых популярных (арендуемых) фильмов
select 
f.film_id,
f.title,
f.release_year,
count(r.rental_id) as rental_count
from film f
join inventory inv on f.film_id=inv.film_id 
join rental r on inv.inventory_id=r.inventory_id
group by f.film_id,f.title,f.release_year
order by rental_count desc
limit 100;

-- 2.7. Распределение каталога фильмов по возрастным рейтингам
SELECT 
    rating,                     
    COUNT(film_id) AS total_films 
FROM film
GROUP BY rating                 
ORDER BY total_films DESC;   


-- ============================================================
-- SECTION 3: ADVANCED ANALYTICS & CTE
-- ============================================================

-- 3.1. Сегментация клиентов: поиск покупателей с количеством аренд ниже среднего (CTE)
WITH average_rentals_by_cus AS (
    SELECT --Собираем пулл кол-ва аренд по покупателю
        customer_id,
        count(rental_id) AS rental_count
    FROM rental
    GROUP BY customer_id
)
SELECT --Выводим покупателей с низким кол-вом аренд
cus.customer_id, 
    cus.first_name,
    cus.last_name,
    arbc.rental_count
FROM average_rentals_by_cus arbc
join customer cus on arbc.customer_id=cus.customer_id
where
    arbc.rental_count < (
    select ROUND(AVG(rental_count), 2) AS average_rental_count --Считаем среднее кол-во аренд (26.78)
    FROM average_rentals_by_cus arbc )
order by cus.customer_id;

-- 3.2. Поиск фильмов, продолжительность которых выше средней по базе
SELECT
    title, 
    length
FROM film
WHERE length > (
    SELECT AVG(length) 
    FROM film
)
ORDER BY length ASC;

-- 3.3. Поиск всех покупателей, проживающих в одном городе с клиентом #1 (Вложенные подзапросы)
SELECT customer_id, first_name, last_name 
FROM customer
WHERE address_id IN (
    -- Собираем пулл адресов по городу
    SELECT address_id 
    FROM address 
    WHERE city_id = (
        -- А город мы ищем от адреса заданного покупателя
        SELECT ad.city_id 
        FROM address ad
        join customer cus on ad.address_id=cus.address_id
        WHERE cus.customer_id = 1
    )
);

-- 3.4. Первые 100 пар «фильм — актёр» с сортировкой
 SELECT 
    f.title AS film_title,
    f.film_id as film_id,
    ac.actor_id as actor_id,
    ac.first_name  AS actor_first_name,
    ac.last_name  AS actor_last_name
FROM film f
JOIN film_actor fac ON f.film_id = fac.film_id
JOIN actor ac       ON fac.actor_id = ac.actor_id
order by f.film_id asc
LIMIT 100;

-- 3.5. Список актёров для конкретного фильма 
select 
f.title as film,
ac.first_name as name
from actor ac
join film_actor fac on ac.actor_id = fac.actor_id
join film f on fac.film_id=f.film_id  where fac.film_id=1
limit 20;

