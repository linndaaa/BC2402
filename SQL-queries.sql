-- Question 1
SELECT distinct location 
FROM covid.country
WHERE continent = "Asia";

-- Question 2
SELECT distinct location
FROM covid.caseinfo
WHERE date="2020-04-01" AND total_cases >10 AND
location in 
(SELECT location
FROM covid.country
WHERE continent = "Asia" or continent ="Europe");

-- Question 3
SELECT distinct location
FROM covid.caseinfo
WHERE total_cases < 10000 AND date>="2020-04-01" AND date<="2020-04-20" 
AND location in
(SELECT location
FROM covid.country
WHERE continent = "Africa");

-- Question 4
SELECT distinct location 
FROM covid.country
WHERE location NOT IN
(SELECT DISTINCT location
FROM covid.caseinfo
WHERE total_tests !="");

-- Question 5
SELECT month, sum(new_cases)
FROM (SELECT *, MONTH(date) AS month FROM covid.caseinfo) as newtable1
GROUP BY month;

-- Question 6
SELECT continent, month, SUM(new_cases) 
FROM (SELECT *, month(date) as month FROM covid.caseinfo) as newtable2 NATURAL JOIN covid.country
GROUP BY continent, month;

-- Question 7
SELECT DISTINCT country
FROM covid.response 
WHERE country in (SELECT country FROM covid.eucountries) 
AND Response_measure LIKE "%mask%";

-- Question 8
DROP VIEW IF EXISTS covid.tempTable;
DROP VIEW IF EXISTS covid.maxTable;

UPDATE covid.response SET country = "Czech Republic"
WHERE country = "Czechia";

CREATE VIEW covid.maxTable AS
(SELECT c1, s1, e1, COUNT(c2) AS count
FROM 
(SELECT *
FROM 
(SELECT Country AS c1, Response_measure AS m1, date_start AS s1, date_end AS e1 
FROM covid.response
WHERE Response_measure = "MasksMandatory" 
AND Country IN (SELECT country FROM covid.eucountries)
) AS windows
INNER JOIN 
(SELECT Country AS c2, Response_measure AS m2, date_start AS s2, date_end AS e2 
FROM covid.response
WHERE Response_measure = "MasksMandatory" 
AND Country IN (SELECT country FROM covid.eucountries)
) AS overlapping_windows
WHERE 
date(s1) BETWEEN date(s2) AND date(e2)
AND windows.c1 != overlapping_windows.c2
ORDER BY windows.s1, overlapping_windows.c2
) AS table0 GROUP BY c1, s1, e1 ORDER BY COUNT DESC);

CREATE VIEW covid.tempTable AS (
SELECT max(s1) AS start, min(e2) AS end 
FROM 
(SELECT DISTINCT *
FROM 
(SELECT Country AS c1, Response_measure AS m1, date_start AS s1, date_end AS e1 
FROM covid.response 
WHERE Response_measure = "MasksMandatory" 
AND Country IN (SELECT country FROM covid.eucountries)
) AS windows
INNER JOIN 
(SELECT Country AS c2, Response_measure AS m2, date_start AS s2, date_end AS e2 
FROM covid.response
WHERE Response_measure = "MasksMandatory" 
AND Country in (select country from covid.eucountries)
) AS overlapping_windows
WHERE 
date(s1) BETWEEN date(s2) AND date(e2)
AND windows.c1 != overlapping_windows.c2
AND c1 LIKE (SELECT c1 FROM 
(SELECT * FROM covid.maxTable) AS table1 LIMIT 1)
AND s1 LIKE (SELECT s1 FROM 
(SELECT * FROM covid.maxTable) AS table1 LIMIT 1)
) AS table2
);

SELECT * FROM covid.tempTable;

-- Question 9
SELECT date, SUM(new_cases) AS totalCases FROM covid.caseinfo 
WHERE location IN (SELECT location FROM covid.country WHERE continent="Europe" OR continent="North America")
AND date BETWEEN (SELECT start FROM covid.tempTable) AND (SELECT end FROM covid.tempTable)
GROUP BY date;

-- Question 10
SET @test = 0, @id=0, @count=0;

SELECT table_2.country FROM 
(
SELECT id AS country, MAX(count) as CONSEC
from 
(
SELECT 
 @count := if(new_cases = 0 and Location = @id, @count+1, 0) as count,
 @test := new_cases,
 @id := Location as id
FROM
(SELECT location, date, total_cases, new_cases
FROM covid.caseinfo
WHERE total_cases > 50) AS table_1
) 
AS table_2
GROUP BY id
) as table_2
WHERE consec > 14;

-- Question 11
-- Set sql mode if not it will not work --
SET sql_mode = '';

-- Ensure the following does not exist --
DROP TABLE IF EXISTS covid.flattenCurve;
DROP TABLE IF EXISTS covid.q11;
DROP PROCEDURE IF EXISTS covid.insertIfUptick;
DROP PROCEDURE IF EXISTS covid.secondWave;

-- Create flattenCurve table which has list of countries which flatten the curve --
set @test = 0, @id=0, @count=0, @date=0, @total=0;
create table covid.flattenCurve as (
select id, min(date) as date  
from (select * 
from 
(select   
@count := if(new_cases = 0 and Location = @id, @count+1, 0) as count,  
@test := new_cases,  @id := Location as id,  @date := date as date,  
@total := total_cases as total 
from 
(select distinct location, date, total_cases, new_cases 
from covid.caseinfo where total_cases > 50) 
as table_1) as table_2 
where count = 14) as table_3 group by id);

-- Add rowID to index flattenCurve table --
ALTER TABLE `covid`.`flattenCurve` 
ADD COLUMN `rowID` INT NOT NULL AUTO_INCREMENT AFTER `date`,
ADD PRIMARY KEY (`rowID`);

-- Procedure to insert country into a table q11 if uptick is observed --
DELIMITER //
CREATE PROCEDURE covid.insertIfUptick(
	IN inputDate date,
    IN inputLoc varchar(255)
)
BEGIN
	INSERT INTO covid.q11 (Country)
	select location from (    
 SELECT x.location, x.date, x.new_cases, SUM(y.new_cases) as rollingSum
   FROM (select *
		from caseinfo
		where Location = inputLoc
		and date >= date(inputDate) order by date desc) x 
   JOIN (select *
		from caseinfo
		where Location = inputLoc
		and date >= date(inputDate) order by date desc) y 
     ON y.date BETWEEN x.date - INTERVAL 7-1 DAY 
    AND x.date GROUP BY x.date, x.new_cases, x.location
    ) as table_1 where rollingSum > 50 limit 1;
END //
DELIMITER ;

-- Create q11 table which is the answer to q11 --
CREATE TABLE covid.q11 (
  Country VARCHAR(255) NULL);

-- Create procedure that will run through the entire flattenCurve table to check for upticks with the checkIfUptick function --
DELIMITER //
CREATE PROCEDURE covid.secondWave()
BEGIN
DECLARE n INT DEFAULT 0;
DECLARE i INT DEFAULT 1;
DECLARE tempDate date;
DECLARE tempLoc varchar(255);
SELECT COUNT(*) FROM covid.flattenCurve INTO n;
WHILE i<=n DO
	select id from covid.flattenCurve where rowID = i into tempLoc;
	select date from covid.flattenCurve where rowID = i into tempDate;
	Call insertIfUptick(tempDate, tempLoc);
	SET i = i + 1;
END WHILE;
END //
DELIMITER ;

call covid.secondWave();
select distinct * from covid.q11;

-- Question 12
select country_region from
(select country_region, 
sum(retail_and_recreation_percent_change_from_baseline) as rr 
from covid.mobilities
group by country_region
order by rr desc
limit 3) as table1;

select country_region from
(select country_region, 
sum(grocery_and_pharmacy_percent_change_from_baseline) as gp
from covid.mobilities
group by country_region
order by gp desc
limit 3) as table1;

select country_region from
(select country_region, 
sum(parks_percent_change_from_baseline) as p
from covid.mobilities 
group by country_region
order by p desc
limit 3) as table1;

select country_region from
(select country_region, 
sum(transit_stations_percent_change_from_baseline) as ts
from covid.mobilities 
group by country_region
order by ts desc
limit 3) as table1;

select country_region from
(select country_region, 
sum(workplaces_percent_change_from_baseline) as w
from covid.mobilities
group by country_region
order by w desc
limit 3) as table1;

select country_region from
(select country_region, 
sum(residential_percent_change_from_baseline) as r
from covid.mobilities
group by country_region
order by r desc	
limit 3) as table1;

-- Question 13
SELECT country_region, date, retail_and_recreation_percent_change_from_baseline, workplaces_percent_change_from_baseline, grocery_and_pharmacy_percent_change_from_baseline
from covid.mobilities
WHERE country_region = "Indonesia" AND  
date >= (SELECT date FROM covid.caseinfo 
WHERE total_cases >= 20000 AND location = "Indonesia"
LIMIT 1)