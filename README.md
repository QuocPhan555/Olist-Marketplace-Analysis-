# Olist Marketplace Health Audit

**Is our growth healthy? A SQL analysis of 99,000 e-commerce orders that finds why growth stalled and what to do about it.**

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-SQL-336791?logo=postgresql&logoColor=white)
![Data](https://img.shields.io/badge/data-Olist%20(Kaggle)-20BEFF)
![Status](https://img.shields.io/badge/status-SQL%20complete%20-brightgreen)

A Brazilian marketplace grew fast in 2017, then stopped growing in 2018. Acting as an external analyst hired by the CEO, I cleaned 9 tables of real transaction data in PostgreSQL and answered 7 business questions: where growth comes from, why customers don't return, and what late delivery really costs. The findings are concrete with data support and four practical actions that leaders board can trust

---

## Table of contents

1. [The business problem](#the-business-problem)
2. [Key findings](#key-findings)
3. [Recommendations for the CEO](#recommendations-for-the-ceo)
4. [How I solved it](#how-i-solved-it)
5. [Installation](#installation)
6. [Skills demonstrated](#skills-demonstrated)
7. [License](#license)

---

## The business problem

**From the CEO:** *"Orders grew every month in 2017, but now I'm not sure we are growing well. Are customers coming back? Are we keeping our delivery promises? Which categories matter? And every team reports different numbers. I need facts I can defend in front of the board."*

| # | CEO question | Analysis |
|---|---|---|
| 1 | Are we growing, and is it healthy? | Monthly sales trend, month-on-month and year-on-year |
| 2 | Where do we lose orders? | Order fulfilment funnel |
| 3 | Do customers come back? | Repeat-purchase rate, time to second order |
| 4 | Can each customer spend more? | Basket size, categories bought together |
| 5 | Which categories carry the business? | Category ranking, revenue concentration, ratings |
| 6 | What does late delivery cost us? | Delivery timing vs review scores |
| 7 | Does a late first order stop customers returning? | Repeat rate by first-order experience |

---
---

## Key findings

**Analysis window:** Jan 2017 – Aug 2018. **Sales** = value of products sold (GMV), cancelled orders excluded. **Currency** = Brazilian Real (BRL)

### 1. Are we growing, and is it healthy? Growth has increased 
- Jan–Aug 2018 sales: **7.39M BRL, +137%** vs the same months of 2017.
- But the monthly level stopped rising: sales peaked at ~1.0M BRL in Mar–May 2018 and fell to 0.85M in August (**−14%**). Orders fell **10.6%** from January to August.


### 2. Where do we lose orders? In the order process through steps: Placed → Approved → Handed to carrier (Shipped) → Delivered → On time → Rated
| step | stage           | total_orders | pct_placed_orders | pct_previous_stage |
|-----:|:----------------|-------------:|------------------:|-------------------:|
| 1    | Placed          | 99092        | 100.0             | NULL               |
| 2    | Approved        | 98957        | 99.9              | 99.9               |
| 3    | Handed to carrier | 97376      | 98.3              | 98.4               |
| 4    | Delivered       | 96203        | 97.1              | 98.8               |
| 5    | On time         | 89672        | 90.5              | 93.2               |
| 6    | Rated 4-5 stars | 73734        | 74.4              | 82.2               |

- 98.3% of orders reach the carrier and 97.1% are delivered.
- **6,531 delivered orders (6.8%) arrive late**, and only **74.4%** of orders end with an on-time, 4–5★ customer.

### 3. Do customers come back? Customers buy once and do not come back
- Of 94,990 customers, only **3.04%** returned on a later day 
- Growth depends almost entirely on finding new customers, which explains the 2018 slowdown.

### 4.  Can each customer spend more? The first basket is small and usually customer buy home and baby products together
- **90% of orders contain one item** (avg 130 BRL) and make 85% of sales. Two-item baskets are worth 175 BRL (+34%).
- Fewer than 1% of orders mix categories; when they do, it's around two missions: **home** (bed/bath + furniture/decor) and **baby** (baby + toys).

### 5.  Which categories carry the business? No specific product drives the most revenue; home categories underperform
- The top category (Health & beauty) is only **9.3%** of sales; the top 10 make 62%. No single-category risk.
- **Watches & gifts** ranks #2 in sales with 40% fewer orders: 214 BRL per order vs 110–143 for volume categories.
- The lowest ratings (3.9) are in **Bed/bath/table, Furniture & decor** and Computer accessories.

### 6.  What does late delivery cost us? 20% orders are late and most of them get bad reviews 
- 79% of orders arrive **7+ days before** the promised date: delivery estimates are very cautious.
- Just 1–3 days late triples the bad-review rate (**32% vs 9–11%**); 7+ days late → **79%** bad reviews.
- Late orders are 6.7% of orders but cause **~33% of all bad reviews**.

### 7. Does a late first order stop customers returning? Late delivery is not why customers leave
- First order late: 2.6% return; on time: 3.1%. A real but small effect (~4k BRL).
- Even after a perfect first order, 97% never return

---

## Recommendations for the CEO

| # | Action | Reasons | Estimated impact |
|:-:|:-------|:--------|:-----------------|
| 1 | **Launch a second-order programme** (follow-up within 30 days, voucher), starting with Health & Beauty, where products are re-bought | Only 3.04% of customers come back to re-purchase. We should turn one-time buyers into loyal customers, starting with Health & Beauty, the top-ranked category | Each +1 pt of repeat rate ≈ **955 orders ≈ 131k BRL** |
| 2 | **Grow the first basket**: "bought together" recommendations and bundles in home and baby; test a free-shipping threshold above 130 BRL | 90% of orders contain only one item | 5% of single-item orders becoming two-item ≈ **198k BRL** |
| 3 | **Fix the worst delays and tighten delivery estimates**: start with orders 7+ days late; test shorter promises where delivery is reliable | Re-check the logistics process to reduce delayed deliveries | Up to **~3,300 fewer bad reviews (−27%)** |
| 4 | **Fix product and listing quality in home categories** before using them for bundles | Home categories rank at the bottom of customer preference | Protects the categories with the most cross-selling |

---
## How I solved it

**1. Audit before analysis.** I loaded the raw CSVs as text, then measured every problem before fixing anything: duplicate keys, orphan records, missing dates, illogical event order, partial months. 

**2. Clean once, in SQL.** One script converts types, removes duplicates, standardises city names and zip codes, translates categories.

**3. One query per business question,** each kept short, with the question, method and caveats in its header.

**Data:** [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) · ~100k orders, 2016–2018, 9 related tables (orders, items, payments, reviews, customers, sellers, products, translations, geolocation).
```
olist-marketplace-sql/
├── README.md
└── sql/
    ├── 00_setup_raw.sql       # create tables, load CSVs as text
    ├── 01_clean_tables.sql    # types, deduplication, standardisation, keys
    └── 02_business_question_analysis.sql        # 7 business questions
```
---
## Installation

**Prerequisites:** PostgreSQL 13+ and `psql` (or any SQL client such as VS Code + SQLTools).

1. Download the 9 CSV files from [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) into a `dataset/` folder.
2. Create a database:
```bash
   createdb -U postgres olist
```
3. Create the tables, then load the CSVs (edit the folder path in the script first):
```bash
   psql -U postgres -d olist -f sql/00_setup_raw.sql
```

---
---

## Skills demonstrated

- **Business framing:** turning a CEO's worries into 7 measurable questions, and every result into an action with a sized impact.
- **Advanced SQL:**

| Technique | Used for |
|---|---|
| CTEs | Step-by-step logic in every query |
| Window functions (`LAG`, `LEAD`, `ROW_NUMBER`, `RANK`, running `SUM`) | Growth rates, first/second orders, Pareto shares |
| `FILTER`, `CASE` | One-scan funnels and KPI tables |
| `LEFT JOIN` anti-joins, self-joins | Orphan checks, categories bought together |
| Date functions, casting, `COALESCE` / `NULLIF` | Delivery timing, safe types and division |
| `UNION ALL` | Data-quality scorecards |

---
---
## License

- **Code:** [MIT License](LICENSE).
- **Data:** Olist public dataset, distributed on Kaggle under **CC BY-NC-SA 4.0** — not included in this repository; download it from the source.

---

**Author:** Phan — MSc Advanced Applied Economics, Université de Caen Normandie

