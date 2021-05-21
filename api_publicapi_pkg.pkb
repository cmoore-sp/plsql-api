create or replace PACKAGE BODY API_PUBLICAPI_PKG
as
-------------------------------------------------------------------------------
-- API for Public APIs
-- 	This template is being provided for educational purposes for our colleagues
--	in the Oracle and Oracle APEX development world.
--	This package is based on standards development at Storm Petrel LLC and by
--	Christina Moore. 
--	Please use and adapt this template to suit your needs. This code is in the 
-- 	public domain with no warrenty or guarentees. Have fun.
--
--		May 2021
-------------------------------------------------------------------------------


	g_app_id					pls_integer									:= 110; -- this must be a valid APEX application in your schema/workspace
	g_page_id					pls_integer									:= 1; 	-- this must be a valid page within your APEX application (above)
	g_apex_user				varchar2(30)								:= 'api_public';
	
	amp								constant varchar2(1)				:= chr(38);	
	quote							constant varchar2(5)				:= '%27';
	underbar					constant varchar2(1)				:= chr(95);
	space							constant varchar2(5)				:= '%20';

	g_https_host			constant varchar2(50)				:= 'publicapis.org';
	g_set_proxy				constant boolean						:= false; --false = use wallet\
	g_wallet_path			constant varchar2(100) 			:= 'file:/oracle/admin/wallet/';
	g_wallet_pwd			constant varchar2(100) 			:= 'xxxxxxxxxxx';
	g_proxy						constant varchar2(50)				:= 'https_proxy.internal/'; 
	g_url_base				constant varchar2(100)			:= 'https://api.publicapis.org/';

	g_qdf							constant varchar2(20)				:= 'YYYY-MM-DD'; -- query date format
	g_ISO8601_format	constant varchar2(30) 			:= 'YYYY-MM-DD"T"HH24:MI:SS"Z"';
	g_api_name				constant varchar2(30)   	 	:= 'Public API';
	
	-- Reference Notes on Debug Levels
	-- c_log_level_error					1 -- critical error 
	-- c_log_level_warn  					2 -- less critical error 
	-- c_log_level_info 					4 -- default level if debugging is enabled (for example, used by apex_application.debug) 
	-- c_log_level_app_enter 			5 -- application: messages when procedures/functions are entered 
	-- c_log_level_app_trace 			6 -- application: other messages within procedures/functions 
	-- c_log_level_engine_enter 	8 -- Application Express engine: messages when procedures/functions are entered 
	-- c_log_level_engine_trace 	9 -- Application Express engine: other messages within procedures/functions 	

	-- to debug, let to "app_trace" and uncomment the line
	--g_debug_level			constant pls_integer				:= apex_debug.c_log_level_app_trace; --(1 error, 2 warn, 3 info, 5 app enter, 6 app trace)
	g_debug_level			constant pls_integer				:= apex_debug.c_log_level_warn ; --(1 error, 2 warn, 3 info, 5 app enter, 6 app trace)

--------------------------------------------------------------------------------
--		I N T E R N A L    P R O C E D U R E S
--------------------------------------------------------------------------------
procedure error_trap (
	P_STAGING_PK			in number
	) 
as
--------------------------------------------------------------------------------
-- Trap error data 
-- 
-- EDuVall 08may2020
--
-- Modifications
--		cmoore 06may2021 - incorporating APEX_DEBUG
--	
/* the call
error_trap(r_staging.staging_pk);
*/
--------------------------------------------------------------------------------
	PRAGMA 							AUTONOMOUS_TRANSACTION; -- capture data even if there is a subsequent rollback
	r_staging						api_staging%rowtype;
	l_select_count			number;

	l_procedure					varchar2(200)		:= 'api_publicapi_pkg.error_log';
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

	select count(1) into l_select_count from api_staging where staging_pk = nvl(P_STAGING_PK,-1);
	if l_select_count <> 0 then
		select * into r_staging from api_staging where staging_pk = P_STAGING_PK;
		apex_debug.warn ('%s %s %s',r_staging.api_name || ' - ' || r_staging.api_module, 
					'HTTP Status Code: ' || r_staging.status_code, r_staging.url	);
	else
		apex_debug.warn ( 'API warning Staging PK invalid %s', 
					r_staging.api_name || ' - ' || r_staging.api_module	);

	end if;
	if nvl(v('APP_USER'),'-') = g_apex_user then
		apex_session.detach;	
	end if;
	exception when others then
		apex_debug.error('Critical error %s', sqlerrm);		
		apex_session.detach;	
		raise; 
end error_trap;

function date_to_json (
	p_date in date
	) return varchar
as
--------------------------------------------------------------------------------
-- Accept standard Oracle date and return JSON date (ISO8601 format)
-- cmoore/sduvall nov2019
/* the call
	l_json_date := date_to_json(l_date);
*/
--------------------------------------------------------------------------------
begin
	return to_char(p_date, g_ISO8601_format) ;
end date_to_json;

function json_to_date (
	p_json_date in varchar2
	) return timestamp
as
--------------------------------------------------------------------------------------------------------------------------------
-- Converts JSON date (ISO8601 format) and returns Oracle Date
-- 
/* the call
	l_date := json_to_date(l_json_date);
*/
--------------------------------------------------------------------------------------------------------------------------------
begin
	return to_timestamp(p_json_date, g_ISO8601_format) ;
end json_to_date;

function response_type (
	P_RESPONSE			in clob
	) return varchar2
--------------------------------------------------------------------------------------------------------------------------------
-- tests for JSON data, returns XML or JSON
-- 
/* the call
l_response_type := response_type(l_response);
*/
--------------------------------------------------------------------------------------------------------------------------------
as
	l_response_5			varchar(10);
	l_response_type		varchar2(20);
begin
	l_response_5 := dbms_lob.substr(P_RESPONSE,5);
	case
		when substr(l_response_5,1,2) = '{"' then l_response_type := 'JSON';
		when substr(l_response_5,1,1) = '<' then l_response_type :=  'XML';
		else  l_response_type := 'Unknown';
	end case;
	return l_response_type;
end response_type;

function set_proxy (
	P_URL					in varchar2,
	P_PROCEDURE		in varchar2
	) return varchar2
as
-------------------------------------------------------------------------------
-- tests for, then replaces PROXY within the URL
-- We often use an internal Apache proxy/reverse proxy to bypass Oracle's Wallet and challenges with SSL certificates.
-- when we do this, the outbound call is HTTP instead of HTTPS.
--
/* the call
	l_url := set_proxy(l_url,l_procedure);
*/
-------------------------------------------------------------------------------
	l_url				varchar2(1000);
begin
	if g_set_proxy then
		if instr(P_URL, g_proxy) > 0 then
			l_url := P_URL; -- looks like the proxy is present
		else
			l_url := replace(P_URL,'https://','http://' || g_proxy);
		end if;
	else
		l_url := P_URL; -- proxy not needed
	end if;
	return l_url;
end set_proxy;

procedure rest_header_set
as
-------------------------------------------------------------------------------
-- set headers. You can add headers as needed following the API directions
-- for your selected environment.
-------------------------------------------------------------------------------
begin
	apex_web_service.g_request_headers.delete();
	apex_web_service.g_request_headers(1).name := 'Accept';
	apex_web_service.g_request_headers(1).value := '*/*';
end rest_header_set;

function rest_delete (
	P_URL						in varchar2,
	P_STATUS_CODE		out varchar2,
	P_PROCEDURE			in varchar2
	) return clob
--------------------------------------------------------------------------------------------------------------------------------
-- does the APEX REST call and gets the status code
-- 
/* the call
l_response := rest_delete(l_url,l_status_code, l_procedure);
*/
--------------------------------------------------------------------------------------------------------------------------------
as
	l_response			clob;
begin
	rest_header_set;
	l_response 	:= APEX_WEB_SERVICE.MAKE_REST_REQUEST(
		p_url               => P_URL,
		p_http_method       => 'DELETE'
		);
	P_STATUS_CODE	:= apex_web_service.g_status_code;
	return l_response;
end rest_delete;

function rest_get (
	P_URL						in varchar2,
	P_STATUS_CODE		out varchar2,
	P_PROCEDURE			in varchar2
	) return clob
--------------------------------------------------------------------------------------------------------------------------------
-- does the APEX REST call and gets the status code
-- 
/* the call
l_response := rest_get(l_url,l_status_code, l_procedure);
*/
--------------------------------------------------------------------------------------------------------------------------------
as
	l_response			clob;
begin
	rest_header_set;
	if g_set_proxy then
		l_response 	:= apex_web_service.make_rest_request(
			p_url               => P_URL,
			p_http_method       => 'GET',
			p_https_host  			=> g_https_host
			);
	else
		l_response 	:= apex_web_service.make_rest_request(
			p_url               => P_URL,
			p_http_method       => 'GET',
			p_wallet_path				=> g_wallet_path,
			p_wallet_pwd				=> g_wallet_pwd,
			p_https_host  			=> g_https_host
			);	
	end if; -- set proxy
	P_STATUS_CODE	:= apex_web_service.g_status_code;
	return l_response;
end rest_get;

function rest_patch (
	P_URL						in varchar2,
	P_BODY					in clob,
	P_STATUS_CODE		out varchar2,	
	P_PROCEDURE			in varchar2
	) return clob
--------------------------------------------------------------------------------------------------------------------------------
-- does the APEX REST patch call and gets the status code for Paypal
-- 
/* the call
l_response := rest_patch(
	P_URL					=> l_url,
	P_BODY				=> l_body,
	P_STATUS_CODE	=> l_status_code, 
	P_PROCEDURE		=> l_procedure
	);
*/
--------------------------------------------------------------------------------------------------------------------------------
as
	l_response			clob;
	l_error_trace		boolean := false;
begin
	rest_header_set;
	l_response 	:= apex_web_service.make_rest_request(
			p_url               => P_URL,
			p_http_method       => 'PATCH',
			p_body							=> P_BODY
			);
	P_STATUS_CODE	:= apex_web_service.g_status_code;
	return l_response;
end rest_patch;

function rest_put (
	P_URL						in varchar2,
	P_BODY					in clob,
	P_STATUS_CODE		out varchar2,	
	P_PROCEDURE			in varchar2
	) return clob
--------------------------------------------------------------------------------------------------------------------------------
-- does the APEX REST call and gets the status code
-- 
/* the call
l_response := rest_get(l_url,l_status_code, l_procedure);
*/
--------------------------------------------------------------------------------------------------------------------------------
as
	l_response			clob;
	l_error_trace		boolean := false;
begin
	rest_header_set;
	l_response 	:= apex_web_service.make_rest_request(
			p_url               => P_URL,
			p_http_method       => 'PUT',
			p_body							=> P_BODY	
			);
	P_STATUS_CODE	:= apex_web_service.g_status_code;
	return l_response;
end rest_put;

procedure write_staging_data (
	R_STAGING			in out api_staging%ROWTYPE
	) 
as
--------------------------------------------------------------------------------------------------------------------------------
-- Writes captured Data to STAGING 
-- 
-- EDuVall 08may2020
--
-- Modifications
--	
/* the call
write_staging_data(r_staging);
*/
--------------------------------------------------------------------------------------------------------------------------------
	PRAGMA 							AUTONOMOUS_TRANSACTION; -- capture data even if there is a subsequent rollback
	l_procedure					varchar2(200)		:= 'api_publicapi_pkg.write_staging';
	l_error_trace				boolean					:= false;
begin
	insert into api_staging values r_staging;
	commit;
end write_staging_data;

function write_staging_data (
	R_STAGING			in out api_staging%ROWTYPE
	) return number
as
--------------------------------------------------------------------------------------------------------------------------------
-- Writes captured Data to STAGING 
-- 
-- SDuVall 08may2020
--
-- Modifications
--	
/* the call
write_staging_data(r_staging);
*/
--------------------------------------------------------------------------------------------------------------------------------
	PRAGMA 							AUTONOMOUS_TRANSACTION; -- capture data even if there is a subsequent rollback
	l_procedure					varchar2(200)		:= 'api_publicapi_pkg.write_staging_data';
begin
	insert into api_staging (
			schema_name,
			api_name,
			api_module,
			data_type,
			action,
			action_date,
			base_url,
			append,
			url,
			status_code,
			json_response,
			http_response,
			delete_ok
		)values (
			r_staging.schema_name,
			r_staging.api_name,
			r_staging.api_module,
			r_staging.data_type,
			r_staging.action,
			r_staging.action_date,
			r_staging.base_url,
			r_staging.append,
			r_staging.url,
			r_staging.status_code,
			r_staging.json_response,
			r_staging.http_response,
			r_staging.delete_ok		
		) returning staging_pk into r_staging.staging_pk;
	commit;
	return r_staging.staging_pk;
end write_staging_data;

--------------------------------------------------------------------------------
--		E X T E R N A L    P R O C E D U R E S
--------------------------------------------------------------------------------

procedure entry_get 
--------------------------------------------------------------------------------------------------------------------------------
-- cmoore 07may2021
-- Get a list of public API 
--
--
/*
begin
	api_publicapi_pkg.entry_get;
end;
*/
--------------------------------------------------------------------------------------------------------------------------------
as
	r_staging				api_staging%ROWTYPE;
	l_url_begin     varchar2(4000):= g_url_base; 
  l_skip          number 				:= 0;
	l_safety_valve	number				:= 1;
	l_valve_pop			number				:= 100; -- max # to prevent run-away process
	l_result_count  number				:= 1;
	l_counter       number 				:= 1;  
	l_temp_date     date;
	l_temp_varchar  varchar2(1024); 

	l_procedure			varchar2(100) := 'api_publicAPI_pkg.entry_get';
begin	
	if v('APP_ID') is null then
		apex_session.create_session(
			p_app_id => g_app_id,
			p_page_id => g_page_id,
			p_username => g_apex_user);      
	end if; -- app_id null
  apex_debug.enable(p_level => g_debug_level);        
  apex_debug.message('Debug enabled on %s',l_procedure); 

	-- validate parameters
		-- no parameters

	r_staging.append			:= 'entries' ;
	r_staging.base_url    := set_proxy(l_url_begin, l_procedure);
	r_staging.url 				:= r_staging.base_url || r_staging.append;
	r_staging.api_name		:= g_api_name;
	r_staging.api_module	:= l_procedure;
	r_staging.action			:= 'GET';
	r_staging.action_date	:= sysdate;	
	r_staging.data_type		:= 'Entries';

	-- Sample does not have large data sets but a controlled loop can be used
	-- to perform multiple GETs

	-- while (nvl(l_result_count,0) <> 0 and l_safety_valve <= l_valve_pop) loop

		r_staging.json_response := rest_get (
			P_URL					=>	r_staging.url, 
			P_STATUS_CODE	=>	r_staging.status_code, 
			P_PROCEDURE		=>	l_procedure
			);

		-- HTTP status code of 2xx is good. We keep the JSON response
		if  r_staging.status_code like '2%' then
			r_staging.http_response := null;
		else
			-- otherwise, put the REST GET response into the HTTP data 
			r_staging.http_response := r_staging.json_response;
			r_staging.json_response	:= null;
		end if; -- response type

		r_staging.staging_pk 	:= write_staging_data(r_staging);	

		-- if there is an error, stop the GETs if in a loop.
		if r_staging.status_code not like '2%' then
			error_trap(r_staging.staging_pk);
			l_safety_valve 	:= l_valve_pop + 1; -- kill the effort. Don't duplicate errors
			l_result_count	:= 0;
		end if;

		apex_debug.trace('trace %s %s %s',l_procedure,'r_staging.status_code', r_staging.status_code); 

		-- Sample does not have large data sets, but this sample code can be used get repeatedly.
		-- refer to your sites API instructions on how to do their style of pagination
		l_skip 								:= l_skip + l_result_count; --l_skip is how many times to skip l_skip_number of records
		r_staging.url 				:= r_staging.base_url || r_staging.append || amp || '$skip=' || trim(to_char(l_skip));	--adding that skip # to the url for next go round
		l_counter							:= l_counter + l_result_count;
		l_safety_valve 				:= l_safety_valve + 1; -- prevent endless loop
		-- end loop; --inner loop counts/skips get all related data

	api_publicapi_staging.entry_get; -- shift JSON data from API to Oracle Table
	if nvl(v('APP_USER'),'-') = g_apex_user then
		apex_session.detach;	
	end if;
	exception when others then
		r_staging.status_code := 'FAIL';
		write_staging_data(r_staging); -- write the API staging data even upon failure
		apex_debug.error('Critical error %s', sqlerrm);		
		apex_session.detach;	
		raise; 				
end entry_get;

end API_PUBLICAPI_PKG;
