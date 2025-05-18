-- PRO. VIEW: Avg LOS (minute) for emergency and urgent care
DROP VIEW IF EXISTS prod_emergency_urgentcare_los;
CREATE VIEW prod_emergency_urgentcare_los AS (
	SELECT 	encounterclass,
			ROUND(AVG(TIMESTAMPDIFF(MINUTE, start, stop)),2) AS minutes
	FROM 	encounters
	WHERE 	encounterclass IN('emergency', 'urgentcare')
	GROUP BY 1
	ORDER BY 2 DESC
);

-- PRO. VIEW: Inpatient ALOS (days) is 1.53, well below national avg of 5.5 for inpatient ALOS 
DROP VIEW IF EXISTS prod_inpatient_alos;
CREATE VIEW prod_inpatient_alos AS (
	SELECT 	ROUND(AVG(TIMESTAMPDIFF(DAY, start, stop)),2) AS 'inpatient_ALOS (days)'
	FROM 	encounters
	WHERE	encounterclass = 'inpatient'
);

-- Staging table to find readmission rate and which patients were readmissioned (referenced in prod_top_medical_reasons view)
DROP TABLE IF EXISTS staging_inpatient_read; 
CREATE TABLE staging_inpatient_read AS (
	WITH prev_dc AS (
		-- Step 1: Flag admissions that need further review & filter out following CMS definition of admissions
		SELECT	patient_id, start AS admission_date, stop AS dc_date, description,
				(CASE WHEN code IN(183495009, 305408004, 310061009, 86013001, 56876005)
					THEN 'needs review' ELSE NULL END) as needs_review, -- FLAGS POTENTIAL PLANNED ADMISSIONS (e.g., orthopedic, gynecology, reevals)
				LAG(stop) OVER(PARTITION BY patient_id ORDER BY start) AS previous_dc
		FROM 	encounters 
		WHERE 	description NOT LIKE '%hospice%' -- HOSPICE IS NOT CONSIDERED FOR READMISSION RATES
				AND code <> 410410006 -- 'SCREENING SURVEILLANCE' FALLS UNDER PLANNED/ROUTINE SERVICES 
				AND encounterclass = 'inpatient'), -- ONLY INPATIENT ADMISSIONS CONSIDERED FOR READMISSION RATES 
	
    dc_diff AS (
		-- Step 2: Add days since last DC 
		SELECT		patient_id, admission_date, dc_date, description, needs_review, previous_dc,
					TIMESTAMPDIFF(DAY, previous_dc, admission_date) AS days_since_dc
			FROM 	prev_dc),
		
	is_re AS (	
		-- Step 3: Flag DCs that were less than 1 day for further review & create "is readmission" column  
		SELECT 		patient_id, admission_date, dc_date, description, needs_review, previous_dc, days_since_dc,
					(CASE WHEN days_since_dc = 0 
						THEN 'review if dc' ELSE NULL END) AS review_last_dc,
					(CASE WHEN previous_dc IS NOT NULL 
						AND days_since_dc BETWEEN 1 AND 30 
						THEN 'yes' ELSE NULL END) AS is_readmission
			FROM 	dc_diff)

SELECT 	* 
FROM 	is_re
);

-- PRO. VIEW: Readmission rate for hospital is 45.11%, well above national rate of 14.56%
DROP VIEW IF EXISTS prod_readmission_rate;
CREATE VIEW prod_readmission_rate AS (
	SELECT 	COUNT(*) - COUNT(is_readmission) AS index_admissions,
			COUNT(is_readmission) AS readmissions,
			ROUND(COUNT(is_readmission) / (COUNT(*) - COUNT(is_readmission)) *100, 2) AS readmission_rate
	FROM 	staging_inpatient_read
);

-- PRO. VIEW: Avg spending per episode & MSPB ratio 
DROP VIEW IF EXISTS prod_mspb_ratio;
CREATE VIEW prod_mspb_ratio AS (
	WITH inpatient_encounters AS (
		-- Step 1: Identify inpatient encounters as anchor events/admissions 
				-- & include dates that define a CMS episode (3 days before admissions & 30 days after DC)
		SELECT 
			encounter_id AS anchor_encounter_id,
			patient_id,
			START AS admission_date,
			STOP AS discharge_date,
			DATE_SUB(start, INTERVAL 3 DAY) AS pre_admission_start,
			DATE_ADD(stop, INTERVAL 30 DAY) AS post_discharge_end
		FROM encounters
		WHERE encounterclass = 'inpatient' AND payer_id = 2 -- CMS MSPB only considers Medicare patients and uses inpatient admissions as anchors
	),

	related_encounters AS (
		-- Step 2: Join encounters with inpatient encounters to identify related claims
		SELECT 
			ie.anchor_encounter_id,
			e.encounter_id AS related_encounter_id,
			e.patient_id,
			e.start AS encounter_start,
			e.stop AS encounter_stop,
			ie.pre_admission_start,
			ie.post_discharge_end,
			e.total_claim_cost
		FROM encounters e
		JOIN inpatient_encounters ie 
			ON e.patient_id = ie.patient_id
			AND e.start BETWEEN ie.pre_admission_start AND ie.post_discharge_end
	),
    
	cost_and_claims AS (
     -- Step 3: Add up all claims for each episode and number of claims per episode
		SELECT 	anchor_encounter_id,
				patient_id,
				SUM(total_claim_cost) AS total_mspb_cost,
				COUNT(related_encounter_id) AS total_related_claims
		FROM 	related_encounters
		GROUP BY 1,2
		ORDER BY 3 DESC)

SELECT 	ROUND(AVG(total_mspb_cost)) AS avg_spending_per_episode,
			ROUND(AVG(total_mspb_cost) / 16698, 2) AS mspb_ratio
FROM 	cost_and_claims
);


-- PRO. VIEW: TCOC for all patients besides Medicare (same logic as above)
DROP VIEW IF EXISTS prod_tcoc;
CREATE VIEW prod_tcoc AS (
	WITH inpatient_encounters AS (
		-- Step 1: Identify inpatient encounters as anchor event/admission for all patients besides Medicare
		SELECT 
			encounter_id AS anchor_encounter_id,
			patient_id,
			START AS admission_date,
			STOP AS discharge_date,
			DATE_SUB(start, INTERVAL 3 DAY) AS pre_admission_start,
			DATE_ADD(stop, INTERVAL 30 DAY) AS post_discharge_end
		FROM encounters
		WHERE encounterclass = 'inpatient' AND payer_id <> 2 -- Filter out Medicare patients
	),

	related_encounters AS (
		-- Step 2: Join encounters with inpatient episodes to identify related claims
		SELECT 
			ie.anchor_encounter_id,
			e.encounter_id AS related_encounter_id,
			e.patient_id,
			e.start AS encounter_start,
			e.stop AS encounter_stop,
			ie.pre_admission_start,
			ie.post_discharge_end,
			e.total_claim_cost
		FROM encounters e
		JOIN inpatient_encounters ie 
			ON e.patient_id = ie.patient_id
			AND e.start BETWEEN ie.pre_admission_start AND ie.post_discharge_end
	),
    
	cost_and_claims AS (
		 -- Step 3: Add up all claims for each episode and number of claims per episode
		SELECT 	anchor_encounter_id,
				patient_id,
				SUM(total_claim_cost) AS total_cost,
				COUNT(related_encounter_id) AS total_related_claims
		FROM 	related_encounters
		GROUP BY 1,2
		ORDER BY 3 DESC
	)

SELECT 	ROUND(AVG(total_cost)) AS avg_total_cost_of_care
FROM 	cost_and_claims
);

-- PRO. VIEW: Top medical reasons for readmissions (CHF, breast CA, HLD, lung CA)
DROP VIEW IF EXISTS prod_top_medical_reasons;
CREATE VIEW prod_top_medical_reasons AS (
	WITH read_p AS (SELECT 	patient_id,
							COUNT(is_readmission) AS num_readmissions
					FROM 	staging_inpatient_read
					GROUP BY 1
					HAVING 	num_readmissions > 0)

	SELECT 	e.reasondescription,
			COUNT(e.encounter_id) AS num_encounters,
			SUM(COUNT(e.encounter_id)) OVER() AS total_encounters,
			ROUND(COUNT(e.encounter_id) / SUM(COUNT(e.encounter_id)) OVER() * 100) AS pct
	FROM 	encounters e INNER JOIN read_p rp
			ON e.patient_id = rp.patient_id
	WHERE reasondescription IS NOT NULL
	GROUP BY 1
	ORDER BY 2 DESC
);

-- FINANCIAL ANALYSIS OF NON COVERAGE:
-- PROD. VIEW: ~62% of total claim costs have no payer coverage 
DROP VIEW IF EXISTS prod_non_coverage_breakdown;
CREATE VIEW prod_non_coverage_breakdown AS (
	SELECT
		ROUND(SUM(total_claim_cost) / 1000000, 2) AS total_claim_cost_million,
		ROUND(SUM(CASE WHEN payer_coverage = 0.00 THEN total_claim_cost ELSE 0 END) / 1000000, 2) AS non_covered_claim_cost_million,
		ROUND(SUM(CASE WHEN payer_coverage <> 0.00 THEN total_claim_cost ELSE 0 END) / 1000000, 2) AS covered_claim_cost_million
	FROM encounters
);

-- PROD. VIEW: Ambulatory, urgent care, and outpatient non covered costs make up for ~80% of non covered costs
DROP VIEW IF EXISTS prod_noncov_claims_by_class;
CREATE VIEW prod_noncov_claims_by_class AS (
	SELECT 	encounterclass,
			ROUND(SUM(total_claim_cost) / 1000000, 2) AS 'class_non_covered (million)',
			ROUND(SUM(SUM(total_claim_cost)) OVER() / 1000000, 2) AS 'grand_total (million)',
			ROUND(SUM(total_claim_cost) / SUM(SUM(total_claim_cost)) OVER() * 100) AS pct
	FROM 	encounters
	WHERE 	payer_coverage = 0.00
	GROUP BY 1
	ORDER BY 2 DESC
);

-- OPERATIONAL ANALYSIS OF NON COVERAGE:
-- PROD. VIEW: Ambulatory, outpatient, and urgentcares services make up for 84% of non coverage encounters, ambulatory being 48% of all encounters
DROP VIEW IF EXISTS prod_noncov_encounters_by_class;
CREATE VIEW prod_noncov_encounters_by_class AS (
	SELECT 	encounterclass, 
			COUNT(encounter_id) AS num_encounters,
			SUM(COUNT(encounter_id)) OVER() AS total_encounters,
			ROUND(COUNT(encounter_id) / SUM(COUNT(encounter_id)) OVER() * 100) AS pct
	FROM 	encounters
	WHERE 	payer_coverage = 0.00
	GROUP BY 1
	ORDER BY 2 DESC
);

-- Encounter for problem (procedure) code makes up for 33% of services not covered in ambulatory care (Granular detail, not for dashboard)
SELECT 	description,
		COUNT(encounter_id) AS num_encounters,
        SUM(COUNT(encounter_id)) OVER() AS total_encounters,
        ROUND(COUNT(encounter_id) / SUM(COUNT(encounter_id)) OVER() * 100, 2) AS pct
FROM 	encounters
WHERE 	payer_coverage = 0.00 AND encounterclass = 'ambulatory'
GROUP BY 1
ORDER BY 2 DESC
LIMIT 5;

-- PROD. VIEW: Renal dialysis makes up for 64% of Encounter for problem (procedure) code in ambulatory care
-- and is the third most expensive avg base cost for ambulatory care procedures at ~$1K per encounter 
DROP VIEW IF EXISTS prod_top_amb_procedure_cost;
CREATE VIEW prod_top_amb_procedure_cost AS (
	WITH amb_no_coverage AS (SELECT	encounter_id, patient_id
							FROM 	encounters
							WHERE 	payer_coverage = 0.00 AND encounterclass = 'ambulatory' AND description = 'Encounter for problem (procedure)'),
							
		descrip_pro AS (SELECT 	p.encounter_id, p.description, p.base_cost
						FROM 	procedures p 
								INNER JOIN amb_no_coverage anc ON p.patient_id = anc.patient_id AND p.encounter_id = anc.encounter_id),

		count_cost AS (SELECT 	description,
								ROUND(AVG(base_cost),2) AS avg_base_cost,
								COUNT(encounter_id) AS num_encounters
						FROM 	descrip_pro
						GROUP BY 1)

	SELECT 	description, avg_base_cost, 
			ROW_NUMBER() OVER(ORDER BY avg_base_cost DESC) AS expensive_avgbasecost_rank,
			num_encounters,
			SUM(num_encounters) OVER() AS total_encounters, 
			ROUND(num_encounters / SUM(num_encounters) OVER() * 100)AS pct
	FROM count_cost
	ORDER BY pct DESC
);

-- PROD. VIEW: Of those patients, ALL of them were uninsured
DROP VIEW IF EXISTS prod_top_amb_procedure_uninsured;
CREATE VIEW prod_top_amb_procedure_uninsured AS (
	WITH renal_p AS (SELECT	e.encounter_id, e.payer_id, p.description
					FROM 	encounters e INNER JOIN procedures p ON e.encounter_id = p.encounter_id
					WHERE 	e.payer_coverage = 0.00 AND e.encounterclass = 'ambulatory' 
							AND e.description = 'Encounter for problem (procedure)' AND p.description = 'Renal dialysis (procedure)')

	SELECT 	payers.name, 
			COUNT(rp.encounter_id) AS num_encounters,
			SUM(COUNT(rp.encounter_id)) OVER () AS total_encounters,
			ROUND(COUNT(rp.encounter_id) / SUM(COUNT(rp.encounter_id)) OVER () * 100) AS pct
	FROM 	payers INNER JOIN renal_p rp
			ON payers.payer_id = rp.payer_id
	GROUP BY 1 
	ORDER BY 2
);

-- Urgent care clinic (procedure) code makes up for 100% of services not covered in urgent care (Granular detail, not for dashboard)
SELECT 	description,
		COUNT(encounter_id) AS num_encounters,
        SUM(COUNT(encounter_id)) OVER() AS total_encounters,
        ROUND(COUNT(encounter_id) / SUM(COUNT(encounter_id)) OVER() * 100, 2) AS pct
FROM 	encounters
WHERE 	payer_coverage = 0.00 AND encounterclass = 'urgentcare'
GROUP BY 1
ORDER BY 2 DESC;

-- PROD. VIEW: Electrical cardioversion makes up for 79% of Urgent care clinic (procedure) code in urgent care,
-- and is the highest avg base for urgent care procedures at $26,134 per encounter 
DROP VIEW IF EXISTS prod_top_urgentcare_procedure_cost;
CREATE VIEW prod_top_urgentcare_procedure_cost AS (
	WITH no_coverage AS (SELECT	encounter_id, patient_id
							FROM 	encounters
							WHERE 	payer_coverage = 0.00 AND encounterclass = 'urgentcare' AND description = 'Urgent care clinic (procedure)'),
							
		descrip_pro AS (SELECT 	p.encounter_id, p.description, p.base_cost
						FROM 	procedures p 
								INNER JOIN no_coverage nc ON p.patient_id = nc.patient_id AND p.encounter_id = nc.encounter_id),

		count_cost AS (SELECT 	description,
								ROUND(AVG(base_cost),2) AS avg_base_cost,
								COUNT(encounter_id) AS num_encounters
						FROM 	descrip_pro
						GROUP BY 1)

	SELECT 	description, avg_base_cost, 
			ROW_NUMBER() OVER(ORDER BY avg_base_cost DESC) AS expensive_avgbasecost_rank,
			num_encounters,
			SUM(num_encounters) OVER() AS total_encounters, 
			ROUND(num_encounters / SUM(num_encounters) OVER() * 100)AS pct
	FROM count_cost
	ORDER BY pct DESC
);

-- PROD. VIEW: Of those patients, ALL of them were uninsured
DROP VIEW IF EXISTS prod_top_urgentcare_procedure_uninsured;
CREATE VIEW prod_top_urgentcare_procedure_uninsured AS (
	WITH eletric_c AS (SELECT	e.encounter_id, e.payer_id, p.description
					FROM 	encounters e INNER JOIN procedures p ON e.encounter_id = p.encounter_id
					WHERE 	e.payer_coverage = 0.00 AND e.encounterclass = 'urgentcare' 
							AND e.description = 'Urgent care clinic (procedure)' AND p.description = 'Electrical cardioversion')

	SELECT 	payers.name, 
			COUNT(ec.encounter_id) AS num_encounters,
			SUM(COUNT(ec.encounter_id)) OVER () AS total_encounters,
			ROUND(COUNT(ec.encounter_id) / SUM(COUNT(ec.encounter_id)) OVER () * 100) AS pct
	FROM 	payers INNER JOIN eletric_c ec
			ON payers.payer_id = ec.payer_id
	GROUP BY 1 
	ORDER BY 2
);

-- PROD. VIEW: 65% of non coverages are from uninsured patients in all settings
DROP VIEW IF EXISTS prod_noncov_encounters_by_insurance;
CREATE VIEW prod_noncov_encounters_by_insurance AS (
	SELECT 	payers.name, 
			COUNT(e.encounter_id) AS num_encounters,
			SUM(COUNT(e.encounter_id)) OVER () AS total_encounters,
			ROUND(COUNT(e.encounter_id) / SUM(COUNT(e.encounter_id)) OVER () * 100) AS pct
	FROM 	payers INNER JOIN encounters e
			ON payers.payer_id = e.payer_id
	WHERE 	e.payer_coverage = 0.00
	GROUP BY 1
	ORDER BY 2 DESC
);

-- PROD. VIEW: This is a problem if about a third of encounters were from uninsured patients, the second highest insurance group
DROP VIEW IF EXISTS prod_all_encounters_by_insurance;
CREATE VIEW prod_all_encounters_by_insurance AS (
	SELECT 	payers.name, 
			COUNT(e.encounter_id) AS num_encounters,
			SUM(COUNT(e.encounter_id)) OVER () AS total_encounters,
			ROUND(COUNT(e.encounter_id) / SUM(COUNT(e.encounter_id)) OVER () * 100) AS pct
	FROM 	payers INNER JOIN encounters e
			ON payers.payer_id = e.payer_id
	GROUP BY 1
	ORDER BY 2 DESC
);