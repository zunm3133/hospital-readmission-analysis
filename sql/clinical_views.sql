CREATE VIEW IF NOT EXISTS vw_readmission_by_diagnosis AS
SELECT
    diag_category,
    COUNT(*)                                         AS total_encounters,
    SUM(readmitted_30)                               AS readmissions,
    ROUND(100.0 * SUM(readmitted_30) / COUNT(*), 2) AS readmission_rate_pct,
    ROUND(AVG(time_in_hospital), 2)                  AS avg_los_days,
    ROUND(AVG(num_medications), 1)                   AS avg_medications
FROM encounters
GROUP BY diag_category
ORDER BY readmission_rate_pct DESC;


CREATE VIEW IF NOT EXISTS vw_patient_risk_profile AS
SELECT
    patient_nbr,
    COUNT(*)                                              AS total_visits,
    SUM(readmitted_30)                                    AS total_readmissions,
    ROUND(AVG(time_in_hospital), 1)                       AS avg_los,
    ROUND(AVG(num_medications), 1)                        AS avg_medications,
    MAX(number_inpatient)                                 AS max_prior_inpatient,
    MAX(age_numeric)                                      AS age,
    CASE
        WHEN SUM(readmitted_30) >= 2                      THEN 'High Risk'
        WHEN SUM(readmitted_30) = 1                       THEN 'Medium Risk'
        ELSE                                                   'Low Risk'
    END                                                   AS risk_tier
FROM encounters
GROUP BY patient_nbr;

CREATE VIEW IF NOT EXISTS vw_admission_performance AS
SELECT
    admission_type,
    COUNT(*)                                              AS encounters,
    ROUND(100.0 * SUM(readmitted_30) / COUNT(*), 2)      AS readmission_rate_pct,
    ROUND(AVG(time_in_hospital), 2)                       AS avg_los,
    ROUND(AVG(num_lab_procedures), 1)                     AS avg_lab_procedures,
    ROUND(AVG(number_diagnoses), 1)                       AS avg_diagnoses
FROM encounters
WHERE admission_type IS NOT NULL
    AND admission_type NOT IN ('Not Available','NULL','Not Mapped')
GROUP BY admission_type
ORDER BY readmission_rate_pct DESC;


with engine.connect() as conn:
    sql_file = (ROOT / 'sql' / 'clinical_views.sql').read_text()
    # Split by semicolon and execute each statement
    statements = [s.strip() for s in sql_file.split(';') if s.strip()]
    for stmt in statements:
        try:
            conn.execute(stmt)
            print(f'Executed: {stmt[:60]}...')
        except Exception as e:
            print(f'Error: {e}')
    conn.commit()
print('All views created')


q1 = """
SELECT
    age,
    COUNT(*)                                              AS encounters,
    SUM(readmitted_30)                                    AS readmissions,
    ROUND(100.0 * SUM(readmitted_30) / COUNT(*), 2)      AS readmission_rate_pct,
    ROUND(AVG(100.0 * SUM(readmitted_30) / COUNT(*))
        OVER (ORDER BY age
              ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING), 2) AS smoothed_rate
FROM encounters
GROUP BY age
ORDER BY age
"""
df_q1 = pd.read_sql(q1, engine)
print(df_q1.to_string(index=False))


q2 = """
WITH patient_summary AS (
    SELECT
        patient_nbr,
        COUNT(*)                                          AS total_visits,
        SUM(readmitted_30)                                AS readmission_count,
        ROUND(AVG(time_in_hospital), 1)                   AS avg_los,
        ROUND(AVG(num_medications), 1)                    AS avg_meds,
        MAX(age_numeric)                                  AS age,
        MAX(diag_category)                                AS primary_diagnosis
    FROM encounters
    GROUP BY patient_nbr
    HAVING SUM(readmitted_30) >= 1
)
SELECT
    primary_diagnosis,
    COUNT(*)                                              AS high_risk_patients,
    ROUND(AVG(readmission_count), 2)                      AS avg_readmissions,
    ROUND(AVG(avg_los), 1)                                AS avg_los_days,
    ROUND(AVG(avg_meds), 1)                               AS avg_medications,
    ROUND(AVG(age), 0)                                    AS avg_age
FROM patient_summary
GROUP BY primary_diagnosis
ORDER BY high_risk_patients DESC
"""
df_q2 = pd.read_sql(q2, engine)
print(df_q2.to_string(index=False))
df_q2.to_csv('../data/processed/high_risk_patients.csv', index=False)


q3 = """
SELECT
    CASE
        WHEN num_medications <= 5  THEN '1-5 medications'
        WHEN num_medications <= 10 THEN '6-10 medications'
        WHEN num_medications <= 15 THEN '11-15 medications'
        WHEN num_medications <= 20 THEN '16-20 medications'
        ELSE '20+ medications'
    END                                                   AS med_group,
    COUNT(*)                                              AS patients,
    ROUND(100.0 * SUM(readmitted_30) / COUNT(*), 2)      AS readmission_rate_pct,
    ROUND(AVG(time_in_hospital), 2)                       AS avg_los,
    ROUND(AVG(number_diagnoses), 1)                       AS avg_diagnoses
FROM encounters
GROUP BY med_group
ORDER BY readmission_rate_pct DESC
"""
df_q3 = pd.read_sql(q3, engine)
print(df_q3.to_string(index=False))
