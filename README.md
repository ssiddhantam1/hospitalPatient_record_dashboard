
# End-to-End Healthcare Patient Record Data Pipeline & Dynamic Dashboard

This project focuses on building a comprehensive data pipeline and dynamic dashboard for healthcare patient records, aiming to enhance efficiency, reduce costs, and improve patient outcomes within a value-based care framework.

## 📊 About the Data

The project utilizes a synthetic dataset of approximately 1,000 patients and 75,000 encounters from Massachusetts General Hospital (2011–2022). This dataset includes demographic information, insurance details, and medical encounters/procedures. Key variables such as encounter times, cost coverage, payer specifics, and clinical descriptions facilitate in-depth analysis of operational efficiency, financial trends, and patient outcomes.

## 🏥 Stakeholders & Business Outcomes

This project is designed to provide strategic insights and operational improvements for various healthcare stakeholders:

* **Hospital Leadership**: Gains strategic insights to improve reimbursements and resource allocation, aligning with value-based care metrics.
* **Care Coordination Teams**: Equipped to identify high-risk patients, enabling targeted interventions and improved patient care.
* **Financial Planners**: Receives data-driven insights for cost optimization and enhanced financial stability.

The overall goal is to support value-based care initiatives by improving metrics tied to reimbursements, uncovering inefficiencies, and aligning operations with long-term financial stability.

## 📏 Measurement Plan (Defining KPIs)

Leveraging the SEPTEE Model and Value-Based Purchasing (VBP) Efficiency Metrics, the project focuses on key performance indicators (KPIs) to measure efficiency:

* **Operational KPIs:**
    * Average Length of Stay (ALOS)
    * Readmission Rate
* **Financial KPIs:**
    * Medicare Spending Per Episode (MSPB) ratio
    * Average Spending Per Episode
    * Total Cost of Care (TCOC)
    * Non-Covered Costs
    * Cost Breakdown by Encounter Class & Procedures

## 🔧 Process

The project involved a robust data pipeline and dashboard development process:

1.  **ETL Pipeline**: A Python-based ETL (Extract, Transform, Load) pipeline was built for data cleaning and normalization, specifically addressing ZIP codes, dates, and IDs.
2.  **Database Design**: Relational schemas and staging tables were designed in MySQL to support scalable and dynamic queries.
3.  **Dynamic Dashboard**: A Power Query dashboard was developed and dynamically linked to MySQL, enabling real-time updates of KPIs.

## 📈 Key Insights

Analysis of the data revealed critical insights:

* **Readmission Trends**: A significant 45.11% of inpatient admissions were readmissions, which is substantially higher than the national benchmark of 14.56%.
* **High Chronic Condition Prevalence**: 86% of readmissions were attributed to prevalent chronic conditions such as CHF, breast cancer, HLD, or lung cancer.
* **Financial Vulnerabilities**: Uninsured patients were responsible for approximately 62% ($63M) of non-covered costs, with ambulatory care contributing the most ($21M and 48% of encounters).
* **Cost Drivers**: Ambulatory renal dialysis care and urgent care cardioversion services were identified as key cost contributors.

## 📍 Why These Insights Matter

These insights are crucial for:

* **Resource Allocation**: Guiding the focus of resources towards high-cost areas like ambulatory care and enhancing care coordination for high-risk patients.
* **Financial Strategies**: Informing strategies to secure funding and mitigate financial risks by understanding the impact of uninsured costs.
* **Enhanced Patient Care**: Providing recommendations for reducing readmissions, ultimately improving patient outcomes and satisfaction.

## 💡 Recommendations

Based on the insights, the following recommendations are put forth:

* **Care Coordination**: Introduce care managers for high-risk patients and evaluate integrated care models.
* **Chronic Condition Focus**: Target condition-specific readmissions with specialized clinics and support programs.
* **Ambulatory Care Efficiency**: Investigate constraints affecting ambulatory care to optimize operations.
* **Preventive Services Expansion**: Collaborate with non-profits and local health departments for preventive care initiatives.
* **SDOH Data Collection**: Collect metrics related to Social Determinants of Health (SDOH) like transportation, housing, and employment for equity-driven interventions.


---
