create or replace procedure api_setup
as
-- run this procedure first to create the tables
/* the call
begin
	api_setup;
end;
*/
begin
-- create the API Staging table. This table stores the API calls as a log and the
-- resultant JSON or HTML data.

execute immediate q'[
CREATE TABLE "API_STAGING" (
	"STAGING_PK" NUMBER generated by default on null as identity, 
	"SCHEMA_NAME" VARCHAR2(30), 
	"API_NAME" VARCHAR2(100), 
	"API_MODULE" VARCHAR2(100), 
	"DATA_TYPE" VARCHAR2(100), 
	"ACTION" VARCHAR2(100), 
	"ACTION_DATE" DATE, 
	"BASE_URL" VARCHAR2(1000), 
	"APPEND" VARCHAR2(2000), 
	"URL" VARCHAR2(4000), 
	"STATUS_CODE" VARCHAR2(10), 
	"JSON_RESPONSE" CLOB, 
	"HTTP_RESPONSE" CLOB, 
	"BODY" CLOB, 
	"DELETE_OK" DATE )
	]';
execute immediate q'[CREATE UNIQUE INDEX "API_STAGING_PK" ON "API_STAGING" ("STAGING_PK")]';
execute immediate q'[ALTER TABLE "API_STAGING" ADD CONSTRAINT "API_STAGING_PK" PRIMARY KEY ("STAGING_PK") USING INDEX  ENABLE]';

-- This table corresponds to the JSON output from the PublicAPI site as of May 2021
execute immediate q'[
CREATE TABLE "API_PUBLICAPI" (
	"PUBLICAPI_PK" NUMBER generated by default on null as identity, 
	"API_NAME" VARCHAR2(250), 
	"DESCRIPTION" VARCHAR2(1000), 
	"AUTH" VARCHAR2(100), 
	"HTTPS" VARCHAR2(10), 
	"CORS" VARCHAR2(100),
	"LINK" VARCHAR2(4000), 
	"CATEGORY" VARCHAR2(2000), 
	"LAST_UPDATE" DATE)
	]';
execute immediate q'[CREATE UNIQUE INDEX "API_PUBLICAPI_PK" ON "API_PUBLICAPI" ("PUBLICAPI_PK")]';
execute immediate q'[ALTER TABLE "API_PUBLICAPI" ADD CONSTRAINT "API_PUBLICAPI_PK" PRIMARY KEY ("PUBLICAPI_PK") USING INDEX ENABLE]';
end api_setup;