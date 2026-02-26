CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE document_embeddings (
    id bigserial PRIMARY KEY,
    content TEXT,
    embedding vector(3) -- Data type for vectors with 1536 dimensions
);

select * from document_embeddings;


insert into document_embeddings (content, embedding) values ('demo', '[0.12, 0.45, -0.48]');


drop table document_embeddings;

select count(*) from staging;

drop table staging;

select * from staging limit 5;

de


select count(*), count(distinct(author)) from staging;

drop table if exists user_journey;

-- Create user journey table
create table user_journey as 
select
	author, score, selftext, subreddit, title, timestamp,
	lag(timestamp) over (partition by author order by timestamp) as prev_post_time,
	lag(subreddit) over (partition by author order by timestamp) as prev_subreddit,
	row_number() over (partition by author order by timestamp) as event_index
from staging
where 
	-- remove all the content that is removed or deleted
	-- selftext not in ('[removed]', '[deleted]', '')
	-- remove all the content that is null
	-- and 
	selftext is not null
	-- remove all the content that has no analytical value, content with num words < 10
	and array_length(regexp_split_to_array(trim(selftext), '\s+'), 1) >= 10;


select * from user_journey limit 50;

select * from user_journey where author = '-____--__-___----__';

drop table user_sample;


select count(author)
from user_journey
where event_index >= 4;

select distinct subreddit
from user_journey uj;

update user_journey uj set subreddit = lower(uj.subreddit);

select * from analytical_sample_users asu limit 10;

update analytical_sample_users asu
set subreddit = lower(asu.subreddit);


drop table clinical_weighted_journeys;


CREATE TABLE clinical_weighted_journeys AS
WITH base_levels AS (
    -- Step 1: Assign the numeric risk levels
    SELECT 
        author,
        selftext,
        title,
        timestamp,
        subreddit,
        CASE 
            WHEN subreddit = 'suicidewatch' THEN 1 
            WHEN subreddit IN ('depression', 'lonely') THEN 2
            WHEN subreddit IN ('mentalhealth', 'anxiety') THEN 3
            ELSE 4 
        END AS risk_level
    FROM analytical_sample_users
),
edge_calculations AS (
    -- Step 2: Calculate the transitions (LEAD) using those levels
    SELECT 
        author,
        subreddit AS current_sub,
        risk_level AS current_level,
        LEAD(subreddit) OVER (PARTITION BY author ORDER BY timestamp) AS next_sub,
        LEAD(risk_level) OVER (PARTITION BY author ORDER BY timestamp) AS next_level,
        EXTRACT(EPOCH FROM (LEAD(timestamp) OVER (PARTITION BY author ORDER BY timestamp) - timestamp)) / 86400 AS days_to_next
    FROM base_levels
)
-- Step 3: Final Aggregation
SELECT 
    author,
    string_agg(
        current_sub || '(L' || current_level || ')' || 
        CASE 
            WHEN next_sub IS NOT NULL 
            THEN ' --(' || ROUND(days_to_next::numeric, 1) || 'd)--> ' 
            ELSE '' 
        END, 
        '' ORDER BY author
    ) AS clinical_trajectory,
    -- Count times the user moved to a higher risk level (e.g., L3 to L2)
    SUM(CASE WHEN current_level > next_level THEN 1 ELSE 0 END) AS total_escalations
FROM edge_calculations
GROUP BY author;

select * from  clinical_weighted_journeys limit 5;

select count(*), count(distinct author) from clinical_weighted_journeys cwj;

alter table clinical_weighted_journeys add primary key (author);

ALTER TABLE clinical_weighted_journeys DROP column bio_factors, drop column psych_factors, drop column social_factors;

select * from author_journey_factors;

select * 
from author_journey_factors
where author='throwusallaway1776';
-- lonely(L2) --(253.3d)--> lonely(L2) --(0.6d)--> lonely(L2) --(38.4d)--> lonely(L2)
-- depression(L2) --(6.9d)--> depression(L2) --(19.0d)--> mentalhealth(L3) --(4.8d)--> mentalhealth(L3) --(98.2d)--> depression(L2) --(9.1d)--> mentalhealth(L3) --(49.8d)--> lonely(L2)



--- perform data analysis

-- clean transitions table - edges 
CREATE TABLE transitions AS
WITH user_arrays AS (
    -- 1. Create an array of states: [lonely(L2), lonely(L2), lonely(L2)]
    -- 2. Create an array of weights: [253.3, 0.6, 38.4]
    SELECT 
        author,
        regexp_split_to_array(clinical_trajectory, '\s--\([\d.]+d\)-->\s') as states,
        ARRAY(SELECT (regexp_matches(clinical_trajectory, '\(([\d.]+)d\)', 'g'))[1]::float) as weights
    FROM author_journey_factors
)
SELECT 
    author,
    states[i] AS src_state,
    weights[i] AS days_to_next,
    states[i+1] AS dst_state
FROM user_arrays, 
-- Generate an index for every transition (1 to N-1)
generate_subscripts(weights, 1) AS i;

select * from author_journey_factors limit 10;


-- create a feature table -- the node attributes
-- CREATE TABLE node_features AS
WITH expanded_factors AS (
    SELECT 
        author,
        -- Force the text column to be treated as jsonb
        (new_factors::jsonb)->0 as f_obj
    FROM author_journey_factors ajf 
)
SELECT 
    author,
    CASE 
        WHEN jsonb_typeof(f_obj->'bio') = 'array' THEN jsonb_array_length(f_obj->'bio')
        WHEN f_obj->'bio' IS NOT NULL THEN 1 ELSE 0 
    END as bio_dim,
    CASE 
        WHEN jsonb_typeof(f_obj->'psycho') = 'array' THEN jsonb_array_length(f_obj->'psycho')
        WHEN f_obj->'psycho' IS NOT NULL THEN 1 ELSE 0 
    END as psycho_dim,
    CASE 
        WHEN jsonb_typeof(f_obj->'socio') = 'array' THEN jsonb_array_length(f_obj->'socio')
        WHEN f_obj->'socio' IS NOT NULL THEN 1 ELSE 0 
    END as socio_dim,
    f_obj as raw_factors
FROM expanded_factors;


select
	column_name, data_type, udt_name
from information_schema."columns" c 
where table_name = 'author_journey_factors'
	and column_name = 'new_factors';

select author,
	new_factors2::jsonb_in->0 as first_element
from author_journey_factors ajf ;



SELECT 
    author,
    -- Extract everything between "bio": [ and ] and count the elements
    (SELECT count(*) 
     FROM regexp_split_to_table(
         substring(factors from '"bio":\s*\[(.*?)\]'), 
         ','
     ) WHERE trim(substring(factors from '"bio":\s*\[(.*?)\]')) <> '') AS bio_dim,

    -- Extract "psycho" dimension
    (SELECT count(*) 
     FROM regexp_split_to_table(
         substring(factors from '"psycho":\s*\[(.*?)\]'), 
         ','
     ) WHERE trim(substring(factors from '"psycho":\s*\[(.*?)\]')) <> '') AS psycho_dim,

    -- Extract "socio" dimension
    (SELECT count(*) 
     FROM regexp_split_to_table(
         substring(factors from '"socio":\s*\[(.*?)\]'), 
         ','
     ) WHERE trim(substring(factors from '"socio":\s*\[(.*?)\]')) <> '') AS socio_dim
FROM users;SELECT 
    author,
    -- Extract everything between "bio": [ and ] and count the elements
    (SELECT count(*) 
     FROM regexp_split_to_table(
         substring(factors from '"bio":\s*\[(.*?)\]'), 
         ','
     ) WHERE trim(substring(factors from '"bio":\s*\[(.*?)\]')) <> '') AS bio_dim,

    -- Extract "psycho" dimension
    (SELECT count(*) 
     FROM regexp_split_to_table(
         substring(factors from '"psycho":\s*\[(.*?)\]'), 
         ','
     ) WHERE trim(substring(factors from '"psycho":\s*\[(.*?)\]')) <> '') AS psycho_dim,

    -- Extract "socio" dimension
    (SELECT count(*) 
     FROM regexp_split_to_table(
         substring(factors from '"socio":\s*\[(.*?)\]'), 
         ','
     ) WHERE trim(substring(factors from '"socio":\s*\[(.*?)\]')) <> '') AS socio_dim
FROM users;



select * from transitions limit 10;





