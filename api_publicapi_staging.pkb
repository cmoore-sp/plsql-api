create or replace PACKAGE BODY api_publicapi_staging as

	g_app_id				constant pls_integer		:= 110; -- this must be a valid APEX application in your schema/workspace
	g_page_id				constant pls_integer		:= 1; 	-- this must be a valid page within your APEX application (above)
	g_apex_user			constant varchar2(30)		:= 'api_public';

	-- Reference Notes on Debug Levels
	-- c_log_level_error					1 -- critical error 
	-- c_log_level_warn  					2 -- less critical error 
	-- c_log_level_info 					4 -- default level if debugging is enabled (for example, used by apex_application.debug) 
	-- c_log_level_app_enter 			5 -- application: messages when procedures/functions are entered 
	-- c_log_level_app_trace 			6 -- application: other messages within procedures/functions 
	-- c_log_level_engine_enter 	8 -- Application Express engine: messages when procedures/functions are entered 
	-- c_log_level_engine_trace 	9 -- Application Express engine: other messages within procedures/functions 	

	-- to debug, set to level_app_trace (6) 
	-- to run for normal error trap, run with level_warn (2)
	--g_debug_level		constant pls_integer		:= apex_debug.c_log_level_app_trace; --(1 error, 2 warn, 3 info, 5 app enter, 6 app trace)
	g_debug_level		constant pls_integer		:= apex_debug.c_log_level_warn ; --(1 error, 2 warn, 3 info, 5 app enter, 6 app trace)
	-- For more information: 
	--		https://docs.oracle.com/en/database/oracle/application-express/20.1/aeapi/APEX_DEBUG.html
	
	-- Hints on Managing debug messages
	--		1) You can view some debug messages in APEX. Go to select app, Util, then debug messages
	--		2) Not all appear here, so use a query to the view APEX_DEBUG_MESSAGES
/*
select * 
from apex_debug_messages
order by 1 desc;	
*/
	-- You can clean up messages with apex_debug.remove_debug_by_app or by age or by view or session. 
	-- here is an example. This will not remove Errors and Warnings (Level 1 and 2). 
	-- You can also use APEX to remove debu messages (select app, Util, debug messages)
/*
begin
	apex_debug.remove_debug_by_app(
		p_application_id => to_number(xxx_app_id));
end;
*/

--------------------------------------------------------------------------------------------------------------------------------
--		I N T E R N A L    P R O C E D U R E S
--------------------------------------------------------------------------------------------------------------------------------

function json_to_date (
		P_JSON_DATE in varchar2
		) return date
as
--------------------------------------------------------------------------------------------------------------------------------
-- Find the Oracle date from json date
-- cmoore/eduvall nov2019
--
/*
begin
	l_oracle_date := json_to_date(l_date_json);
end;
*/
--------------------------------------------------------------------------------------------------------------------------------
	l_procedure						varchar2(100)		:= 'api_publicapi_staging.json_to_date';
	l_error_trace					boolean					:= false;
begin
	return to_date(substr(P_JSON_DATE,1,16),'YYYY-MM-DD"T"HH24:MI') ;
end json_to_date;

function api_publicAPI_MD5 (
	P_ROW								in api_publicAPI%rowtype
	) return varchar2
as
	l_procedure					varchar2(100)			:= 'api_publicapi_staging.api_publicAPI_MD5';
begin  
	-- please convert all values to VARCHAR with consistent formats and manage nulls
	-- such as to_char("P_ACTION_DATE",'yyyymmddhh24:mi:ss'), etc
	return apex_util.get_hash(
		apex_t_varchar2(
			 nvl(P_ROW.api_name,'^')
			,nvl(P_ROW.description,'^')
			,nvl(P_ROW.auth,'^')
			,nvl(P_ROW.https,'^')
			,nvl(P_ROW.cors,'^')
			,nvl(P_ROW.link,'^')
			,nvl(P_ROW.category,'^')
		));		
end api_publicAPI_MD5;

--------------------------------------------------------------------------------------------------------------------------------
--		E X T E R N A L    P R O C E D U R E S
--------------------------------------------------------------------------------------------------------------------------------
procedure entry_get
--------------------------------------------------------------------------------------------------------------------------------
-- This procedures loops through the API_STAGING table 
--		then extracts the JSON data and prepares it for
--		inserting or updating Oracle tables.
--
--	Occasionally JSON data starts with a [ character which means that the entire
--	set of data is an array from the first element.
-- 	In this case start your JSON query with:
--		(s.json_response, '$[*]' columns
-- 	This feature is poorly documented.
--
--	With Respect to the JSON_table query, we recommend using Oracle field names
--	that closely match the JSON element names. There are times when the JSON
--	element name is an Oracle reserved word or will otherwise lend to confusion.
--	Matching at this point improves debugging!
--
--	We tend to have a table that matches the JSON structure. We stage the data
--	in an Oracle table. Then we have another process that merges the Oracle 
--	data into the application data. This gives us a chance to validate keys
--	and maintain referential integrity.
--
-- Modifications
--
--
/*
begin
	api_publicapi_staging.entry_get;
end;
*/
--------------------------------------------------------------------------------------------------------------------------------
as
	l_select_count				number					:= 0;
	r_publicAPI_local			api_publicAPI%rowtype;
	r_publicAPI_remote		api_publicAPI%rowtype;
	l_local_hash					varchar2(32767);
	l_remote_hash					varchar2(32767);

	l_procedure						varchar2(200)		:= 'api_publicapi_staging.entry_get';

begin
	if v('APP_ID') is null then
		apex_session.create_session(
			p_app_id 		=> g_app_id,
			p_page_id 	=> g_page_id,
			p_username	=> g_apex_user
			);      
	end if;   
  apex_debug.enable(p_level => g_debug_level);  -- (1 critical, 2 warn, 3 info, 6 trace)       
  apex_debug.trace('Debug enabled on %s', l_procedure); -- runs only if info or more


	for j in (
	select 
		 s.staging_pk                                       
		,json.count
		,json.api_name
		,json.description
		,json.auth
		,json.https
		,json.cors 
		,json.link
		,json.category
		from api_staging s,
			json_table
			(s.json_response, '$' columns
				count										number		path	'$.count',
				nested path '$.entries[*]' columns
				(
				api_name         				varchar2(255)   path '$.API'
				,description						varchar2(255)   path '$.Description'			
				,auth                		varchar2(255)   path '$.Auth'  
				,https               		varchar2(255)   path '$.HTTPS'
				,cors          					varchar2(255)   path '$.Cors'
				,link              			varchar2(255)   path '$.Link'
				,category             	varchar2(255)   path '$.Category'	
				)
			) json
		where api_module = 'api_openapi.entry_get'	and delete_ok is null and status_code = 200
		order by json.api_name
	) loop

		-- find the unique data field or primary key for the API data
		-- search for the match in your own data
		select count(1) into l_select_count from api_publicAPI where api_name = j.api_name;
		apex_debug.trace('trace %s %s %s',l_procedure,'j.api_name', j.api_name); -- runs only if debug
		apex_debug.trace('trace %s %s %s',l_procedure, 'l_select_count', l_select_count); -- runs only if debug

		-- if no matching data found (Yes, you can use the SQL MERGE feature)
		case
			when l_select_count = 0 then
				insert into api_publicAPI (
					 api_name
					,description
					,auth
					,https
					,cors
					,link
					,category
					,last_update
				) values (
					 j.api_name
					,j.description
					,j.auth
					,j.https
					,j.cors
					,j.link
					,j.category
					,sysdate
				); 
			when l_select_count = 1 then
				select * into r_publicAPI_local from api_publicAPI where api_name = j.api_name;
				--select * into r_publicAPI_remote from api_publicAPI where api_name = j.api_name;	
				
				r_publicAPI_remote.api_name		  :=	j.api_name;
				r_publicAPI_remote.description  := 	j.description;
				r_publicAPI_remote.auth        	:=	j.auth;
				r_publicAPI_remote.https       	:=	j.https;
				r_publicAPI_remote.cors        	:=	j.cors;
				r_publicAPI_remote.link        	:=	j.link;
				r_publicAPI_remote.category    	:=	j.category;
				
				-- Test to see if the data changed from last time.
				-- Some API data sets have a last refresh date or a hash. In that case
				-- use the API reference points instead of the calculated MD5.
				-- calculate the MD5 has for local and remote
				l_local_hash	:= api_publicAPI_MD5(r_publicAPI_local);
				l_remote_hash	:= api_publicAPI_MD5(r_publicAPI_remote);
				apex_debug.trace('trace %s %s %s',l_procedure,'l_local_hash', l_local_hash); -- runs only if debug
				apex_debug.trace('trace %s %s %s',l_procedure, 'l_remote_hash', l_remote_hash); -- runs only if debug
				if l_local_hash <> l_remote_hash then
					update api_publicAPI set
						description   =  r_publicAPI_remote.description  
						,auth         =  r_publicAPI_remote.auth        
						,https        =  r_publicAPI_remote.https       
						,cors         =  r_publicAPI_remote.cors        
						,link         =  r_publicAPI_remote.link        
						,category     =  r_publicAPI_remote.category    
						,last_update  =  r_publicAPI_remote.last_update 
					where api_name = j.api_name;
					apex_debug.trace('trace %s %s %s',l_procedure, 'Update Row', 'Yes'); -- runs only if debug
				else
					apex_debug.trace('trace %s %s %s',l_procedure, 'Update Row', 'No'); -- runs only if debug
				end if; -- hashes do not match, therefore data is new
			else
				apex_debug.warn('Warning %s %s %s',l_procedure,'API Name is not unique for:', j.api_name); 
		end case; -- insert or update?

		-- tag the API Staging row as ready to delete. 
		-- Write a procedure that runs with Scheduler.job to delete from api_staging 
		-- 	where delete_ok is x days or when not null

		update api_staging set 
			delete_ok = sysdate
			where staging_pk = j.staging_pk;
	end loop;--  loop JSON data/JSON array
	commit;
  apex_session.detach; -- forces any debug/error messages to be written to APEX_DEBUG_MESSAGES
	exception when others then
		apex_debug.error('Critical error %s', sqlerrm);		
		apex_session.detach;
end entry_get;

end api_publicapi_staging;