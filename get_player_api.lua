remote_servers = {
	{ host="http://ott.com:8080", user="xx", pass="xx", ua="iptvsmartersplayer" }
}

const FLAG_DELETED              = 0x30
const FLAG_DISABLED             = 0x80

const FLAG_CLIENT_EXPIRED       = 0x01000000

const FLAG_CATEGORY_LIVE        = 0x00000100
const FLAG_CATEGORY_SERIE       = 0x00000200
const FLAG_CATEGORY_LIST        = 0x00000400
const FLAG_CATEGORY_ADULT       = 0x00000800
--
const CAT_LIST                  = 0x001
const CAT_GROUP                 = 0x002
const CAT_LIVE                  = 0x010
const CAT_MOVIE                 = 0x020
const CAT_SERIE                 = 0x040
const CAT_RADIO                 = 0x080
const CAT_LIVE_LIST             = 0x011
const CAT_MOVIE_LIST            = 0x021
const CAT_SERIE_LIST            = 0x041
const CAT_RADIO_LIST            = 0x081
const CAT_LIVE_GROUP            = 0x012
const CAT_MOVIE_GROUP           = 0x022
const CAT_SERIE_GROUP           = 0x042
const CAT_RADIO_GROUP           = 0x082
------------------

-- 0=youtube-dl, 1=wget
WGET       = 1
-- use direct link or redirection link
RELOCATION = 0
--
SERVER_EPISODE_NAME = 0
-- User agent
USER_AGENT = "NSPlayer/9.0.0.4503"

const SERVER_ID   = 0
const season_len  = 2
const episode_len = 2

PROXY = db.server.getbyid(SERVER_ID);

remote_server = request.param("remote_server")
if is_nil(remote_server) then remote_server=1 else remote_server=intval(remote_server) end

if (remote_servers[remote_server]) then
	HOST = remote_servers[remote_server].host;
	USER = remote_servers[remote_server].user;
	PASS = remote_servers[remote_server].pass;
	HDRS = remote_servers[remote_server].hdrs;
	if (remote_servers[remote_server].ua) then USER_AGENT = remote_servers[remote_server].ua; end
	if (remote_servers[remote_server].srv) then SLAVE = db.server.getbyid( remote_servers[remote_server].srv ); end;
end

-- add all new episodes in server
function serie_check_local_episodes(serieid)
	serie = db.category.getseriebyid(serieid)
	if is_nil(serie) then return end

	-- getLast Episode/Seaon
	season = 0; episode = 0; serverid = SERVER_ID
	if is_nil(serie.list) then season = 1; episode = 1;
	else
		for j in serie.list do
			vod = db.vod.getbyid(j)
			if (vod) then
				if (vod.season==0 && vod.episode==0) then write( serie.name,': Failed, Please update season/episodes'); return;
				end
				if (vod.season>season) then season = vod.season; episode = vod.episode; serverid = vod.serverid
				elseif (vod.season==season) then
					if (vod.episode>episode) then episode = vod.episode; serverid = vod.serverid; end
				end
			end
		end
		episode = episode+1
	end

	dir = os.path.dirname(serie.pattern); if is_nil(dir) then return end

	srv = db.server.getbyid(serverid); if is_nil(srv) then return end
	write('<br><br>', dir)
	files = db.server.list(srv, dir); if is_nil(files) then return end
	write(' (', length(files),')')

	while (season and episode) do
		while (true) do
			write('<br>Check Season=',season,' , Episode=',episode)
			found = nil
			for f in files do
				if (f.episode==episode && f.season==season) then found = f; break; end
			end
			if (found) then
				fullpath = dir..'/'..found.path
				--write(ext, ", Found size = ",result.size)
				vod = db.vod.getbypath(fullpath)
				if (vod) then
					tabcat = { id=serie.id, list_add={ vod.id } }
					if (db.category.update(tabcat)) then write(' +Category') end
				else
					name = serie.name..' s'..string.zfill(season,season_len)..'e'..string.zfill(episode,episode_len)
					table = { name=name, path = fullpath, serverid=serverid, episode=episode, season=season }
					vod = db.vod.insert(table)
					if is_nil(vod) then break end
					write(' +DB -> id=', vod.id)
					tabcat = { id=serie.id, list_add={ vod.id } }
					if (db.category.update(tabcat)) then write(' +Category') end
				end
				episode += 1;
			else break; end
		end
		if (episode==1) then break end
		season = season+1
		episode = 1
	end

end

function get_serie_episodes(remoteid)
	path = HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_series_info&series_id="..remoteid;
	write('<br>URL =',path)

	if (PROXY) then
		r = db.server.urlContent(PROXY,  path, HDRS ); if is_nil(r) then return end
		r = JSON.parse(r); if is_nil(r) then return; end
	else
		r = JSON.getUrl( path, HDRS ); if is_nil(r) then return end
	end
	if is_nil(r.info) then return end
	if is_nil(r.episodes) then return end

	write('<br> #', r.info.name )
	for i,j in r.episodes do
		for ep in j do
			if (length(ep.direct_source)) then url = ep.direct_source
			else url = HOST.."/series/"..USER.."/"..PASS.."/"..ep.id..'.'..ep.container_extension end
			if (RELOCATION) then url = URL.getLocation(url) end
			if (length(url)) then
				if (ep.container_extension) then ext = ep.container_extension else ext = URL.getExtension(url) end
				if (SERVER_EPISODE_NAME) then name = ep.title
				else name = r.info.name..' s'..string.zfill(ep.season,2)..'e'..string.zfill(ep.episode_num,2) end
				if (ext) then name = name..'.'..ext end
				if (WGET) then
					write('<br>wget -t 10 -c -O "',name,'" "',url,'" --user-agent="',USER_AGENT,'"')
				else
					write('<br>sleep 1; youtube-dl -o "',name,'" "',url,'" --user-agent "',USER_AGENT,'"')
				end
			else
				write('<br>## episode not found ', ep.title)
			end
		end
	end
end


function copy_serie_infos(remoteid,localid)
	path = HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_series_info&series_id="..remoteid;
	write('<br>URL =',path)

	if (PROXY) then
		r = db.server.urlContent(PROXY,  path, HDRS ); if is_nil(r) then return end
		r = JSON.parse(r); if is_nil(r) then return; end
	else
		r = JSON.getUrl( path, HDRS ); if is_nil(r) then return end
	end
	if is_nil(r.info) then return end
	if is_nil(r.episodes) then return end

	write('<br> #', r.info.name )

	cat = db.category.update({ id=intval(localid), icon=r.info.cover, plot=r.info.plot, cast=r.info.cast, director=r.info.director
		, rating=r.info.rating, youtube_trailer=r.info.youtube_trailer, genre=r.info.genre });
	if (cat) then
		write('<br> Info Updated');
		write('<br> icon = ', cat.icon);

	end
end

--# return url to selected episode
function get_new_episodes(remoteid,localid)
	path = HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_series_info&series_id="..remoteid;
	write('<br>URL =',path)

	if (PROXY) then
		r = db.server.urlContent(PROXY,  path, HDRS ); if is_nil(r) then return end
		r = JSON.parse(r); if is_nil(r) then return; end
	else
		r = JSON.getUrl( path, HDRS ); if is_nil(r) then return end
	end
	if is_nil(r.info) then return end
	if is_nil(r.episodes) then return end

	-- getLast Episode/Season
	season = 0; episode = 0; serverid = SERVER_ID
	serie = db.category.getseriebyid(localid)
	if is_nil(serie) then return end
	pattern = serie.pattern;

	if is_nil(serie.list) then season = 1; episode = 1;
	else
		for j in serie.list do
			vod = db.vod.getbyid(j)
			if (vod) then
				pattern = os.path.dirname(vod.path);
				if (vod.season==0 && vod.episode==0) then write( serie.name,': Failed, Please update season/episodes'); return;
				end
				if (vod.season>season) then season = vod.season; episode = vod.episode; serverid = vod.serverid
				elseif (vod.season==season) then
					if (vod.episode>episode) then episode = vod.episode; serverid = vod.serverid; end
				end
			end
		end
		episode = episode+1
	end

	if (season>0) then
		write('<br>Next Episode: ', serie.name,' s', string.zfill(season,2),'e', string.zfill(episode,2) ) 

		write('<br><div style="padding:10px; display:flex; justify-content:space-between;position:sticky;top:0px;background-color:#f8f8f8;"><select id="serie_id" style="width:20%"><option selected value=',serie.id,'>',serie.name,'</option>')
		write('</select><input style="width:55%; padding:3px;" id="serie_path" placeholder="Download Path" value="',pattern,'" oninput="check_input();"> <button  title="Create Diretory" id="serie_button" onclick="create_dir()" style="font-size:16px"> &#10010; </button> <select style="width:20%" id="serie_server" onchange="check_dir()">');
		x = db.server.getfirst()
		while (x) do
			if ( !(x.flags&(FLAG_DELETED|FLAG_DISABLED)) ) then
				if (x.id==serverid) then write('<option selected value="',x.id,'">',x.name,'</option>');
				else write('<option value="',x.id,'">',x.name,'</option>'); end
			end
			x = x._next
		end
		write('</select></div>')

		write('<table class="listView" width="100%"><thead><tr class=header><th class="colCheck" onclick="toggleRows(this.parentNode)"><i class="chkBox chk-on"></i></th><th width="50px">Season</th><th width="50px">Episode</th><th>URL</th><th width="50px"><button class="button" onclick=\'exec_download_all_episodes(this)\'>Download</button></th></tr></thead><tbody>')
		while (true) do
			-- check remote episode
			eplist = r.episodes[strval(season)]
			if is_nil(eplist) then
				if (episode>1) then episode=1; season+=1; continue; end
				break;
			end
			found = 0;
			for ep in eplist do
				if (ep.episode_num==episode) then
					if (length(ep.direct_source)) then epUrl = ep.direct_source
					else epUrl = HOST.."/series/"..USER.."/"..PASS.."/"..ep.id..'.'..ep.container_extension end
					if (RELOCATION) then epUrl = URL.getLocation(epUrl) end
					if (length(epUrl)) then
						if (ep.container_extension) then ext = ep.container_extension else ext = URL.getExtension(epUrl) end
						if (SERVER_EPISODE_NAME) then epPath = ep.title..'.'..ext;
						else epPath = serie.name..' s'..string.zfill(season,2)..'e'..string.zfill(episode,2)..'.'..ext end

						write('<tr data-season="',season,'" data-episode="',episode,'" data-url="',epUrl,'" data-path="',epPath,'">'
							,'<td class="colCheck" onclick=\'this.parentNode.classList.toggle("checked")\'><i class="chkBox chk-on"></i></td><td>'
							,season,'</td><td>',episode,'</td><td>',epUrl,'<br> -> ',epPath
							,'</td><td><button class="button" class="button" onclick=\'exec_download_episode(this)\'>Download</button> </td><tr>');
					else
						write('<br>## episode not found ', ep.title)
					end
					found = 1;
					break
				end
			end
			if (found) then episode += 1;
			elseif (episode>1) then episode=1; season+=1;
			else break; end
		end
		write('</tbody></table>');
	end

	write([[<script>

	function create_dir() {
		let path = document.querySelector("#serie_path").value;
		let server_id = document.querySelector("#serie_server").value;

		var xhr = new XMLHttpRequest();
		xhr.addEventListener("load", function(event_) {
	        var json = JSON.parse(this.responseText);
			if (json && json.status) {
				term_write('\n Directory "'+path+'" Created\n');
			}
		}, false);
		url = '?remote_server='+1+'&ajax=create_directory&server_id='+server_id+'&path='+encodeURIComponent(path);
		xhr.open("GET", url, true);
		xhr.send(null);
	}
	function check_dir() {
		let path = document.querySelector("#serie_path").value;
		let server_id = document.querySelector("#serie_server").value;

		var xhr = new XMLHttpRequest();
		xhr.addEventListener("load", function(event_) {
	        var json = JSON.parse(this.responseText);
			let x = document.querySelector("#serie_button");
			if (json && json.status) { x.innerHTML ='&#9989;'; x.onclick = null; }
			else { x.innerHTML ='&#10010;'; x.onclick = create_dir; }
		}, false);
		url = '?remote_server='+1+'&ajax=check_directory&server_id='+server_id+'&path='+encodeURIComponent(path);
		xhr.open("GET", url, true);
		xhr.send(null);
	}
	function check_input()
	{
		clearTimeout(check_input.t);
		check_input.t = setTimeout( function(){ check_dir(); }, 1000);
	}

	function exec_download_episode(e, next) {
		let row = getAncestorByTag(e, "TR");
		let season = row.dataset.season;
		let episode = row.dataset.episode;
		let epUrl = row.dataset.url;
		let epPath = row.dataset.path;
		let serie_id = document.querySelector("#serie_id").value;
		let serie_path = document.querySelector("#serie_path").value;
		let server_id = document.querySelector("#serie_server").value;
		epCmd = 'wget --user-agent="]],USER_AGENT,[[" --continue "'+epUrl+'" -t 10 -c -O "'+serie_path+'/'+epPath+'"';
		term_text = '';
		term_line = '';
		term_write(epCmd+'\n')
		url = 'ws://]],db.gethostname(),':',db.getport(),request.path()
			,[[?action=download_episode&serie_id='+serie_id+'&server_id='+server_id+'&season='+season+'&episode='+episode+'&cmd='+encodeURIComponent(epCmd);
		console.log(url);
		var socket = new WebSocket(url);
		socket.onopen = function (event) { term_write('Starting...\n') }
		socket.onmessage = function (event) { term_write(event.data); }
		socket.onclose = function (event) {
			term_write('\n-- Download Finished.\n');
			row.classList.remove("active");
			row.classList.add("success");
			if (next) {
				row.classList.remove("checked");
				while (row) {
					row = row.nextSibling;
					if (row && row.classList.contains("checked") && row.dataset.path && row.dataset.url) break;
				}
				if (row) setTimeout( function() { exec_download_episode(row, true); }, 1000);
			}
		}
	}

	function exec_download_all_episodes(e) {
		let row = getAncestorByTag(e, "TR");
		if (row) row.classList.remove("checked");
		let tab = getAncestorByTag(e, "TABLE");
		row = tab.querySelector("tbody tr.checked");
		while (row) {
			if (row && row.classList.contains("checked") && row.dataset.path && row.dataset.url) break;
			row = row.nextSibling;
		}
		if (row) exec_download_episode(row, true);
	}

	</script>]]);

end

function download_episode()
	server_id = request.param("server_id"); if is_nil(server_id) then return end
	serie_id = request.param("serie_id"); if is_nil(serie_id) then return end
	ep_season = request.param("season"); if is_nil(serie_id) then return end
	ep_episode = request.param("episode"); if is_nil(serie_id) then return end
	cmd = request.param("cmd");  if is_nil(cmd) then return end
	if (websocket.handshake()>=12) then
		server = db.server.getbyid(server_id); if is_nil(server) then return end
		write("<br>cmd = ",cmd)
		data = db.server.system(server, cmd);
		if (data!=0) then
			write("\nFailed")
		else
			write("\nSuccess");
			serie = db.category.getseriebyid(serie_id);
			if (serie) then
				pattern = serie.pattern;
				-- getLast Episode/Seaon
				season = 0; episode = 0;
				if is_nil(serie.list) then season = 1; episode = 1;
				else
					for j in serie.list do
						vod = db.vod.getbyid(j)
						if (vod) then
							pattern = os.path.dirname(vod.path);
							if (vod.season==0 && vod.episode==0) then write( serie.name,': Failed, Please update season/episodes'); return; end
							if (vod.season>season) then season = vod.season; episode = vod.episode;
							elseif (vod.season==season) then
								if (vod.episode>episode) then episode = vod.episode;end
							end
						end
					end
					episode = episode+1
				end

				dir = pattern; if is_nil(dir) then return end
				files = db.server.liststat(server, dir); if is_nil(files) then return end
				while (1) do
					write('\nSerie=',serie.name,' Searching S',string.zfill(season,season_len),' E', string.zfill(episode,episode_len));
					found = 0;
					for f in files do
						if (f.episode==episode && f.season==season) then
							if (f.size < 9000000) then
								db.server.remove(server, dir..'/'..f.path);
								write(" Failed.");
								return;
							end
							epName = serie.name..' s'..string.zfill(season,season_len)..'e'..string.zfill(episode,episode_len);
							epPath = dir..'/'..f.path;
							table = { name=epName, path = epPath, serverid=server.id, episode=episode, season=season }
							vod = db.vod.insert(table)
							if is_nil(vod) then break end
							write('Found: ', epPath,' +DB -> id=', vod.id)
							tabcat = { id=serie.id, list_add={ vod.id } }
							if (db.category.update(tabcat)) then write(' +Category') end
							found = 1;
							break;
						end
					end
					if (!found) then
						if (episode==1) then break; end
						season += 1;
						episode = 1;
						if ( intval(ep_season)!=season || intval(ep_episode)!=episode ) then break; end
					else episode += 1; end
				end
			end
		end
	end
end

--# return url to selected episode
function dld_new_episodes(remoteid, localid)
	path = HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_series_info&series_id="..remoteid;
	if (PROXY) then
		r = db.server.urlContent(PROXY,  path, HDRS ); if is_nil(r) then return end
		r = JSON.parse(r); if is_nil(r) then return; end
	else
		r = JSON.getUrl( path, HDRS ); if is_nil(r) then return end
	end
	if is_nil(r.info) then return end
	if is_nil(r.episodes) then return end

	-- getLast Episode/Season
	season = 0; episode = 0; serverid = SERVER_ID
	serie = db.category.getseriebyid(localid)
	if is_nil(serie) then return end
	pattern = serie.pattern;

	if is_nil(serie.list) then season = 1; episode = 1;
	else
		for j in serie.list do
			vod = db.vod.getbyid(j)
			if (vod) then
				pattern = os.path.dirname(vod.path);
				if (vod.season==0 && vod.episode==0) then write( serie.name,': Failed, Please update season/episodes'); return;
				end
				if (vod.season>season) then season = vod.season; episode = vod.episode; serverid = vod.serverid
				elseif (vod.season==season) then
					if (vod.episode>episode) then episode = vod.episode; serverid = vod.serverid; end
				end
			end
		end
		episode = episode+1
	end

	if (season>0) then
		write('<br>Next Episode: ', serie.name,' s', string.zfill(season,2),'e', string.zfill(episode,2),'<br><br>' )

		while (true) do
			-- check remote episode
			eplist = r.episodes[strval(season)]
			if is_nil(eplist) then
				if (episode>1) then episode=1; season+=1; continue; end
				break;
			end
			found = 0;
			for ep in eplist do
				if (ep.episode_num==episode) then
					if (length(ep.direct_source)) then epUrl = ep.direct_source
					else epUrl = HOST.."/series/"..USER.."/"..PASS.."/"..ep.id..'.'..ep.container_extension end
					if (RELOCATION) then epUrl = URL.getLocation(epUrl) end
					if (length(epUrl)) then
						if (ep.container_extension) then ext = ep.container_extension else ext = URL.getExtension(epUrl) end
						if (SERVER_EPISODE_NAME) then epPath = ep.title..'.'..ext;
						else epPath = serie.name..' s'..string.zfill(season,2)..'e'..string.zfill(episode,2)..'.'..ext end
						write('<br>wget --user-agent="',USER_AGENT,'" --continue "',epUrl,'" -t 10 -c -O "',pattern,'/',epPath,'"');
					else
						write('<br>## episode not found ', ep.title)
					end
					found = 1;
					break
				end
			end
			if (found) then episode += 1;
			elseif (episode>1) then episode=1; season+=1;
			else break; end
		end
	end
end


function get_all_series_episodes00()
	catid = request.param("catid"); if is_nil(catid) then return end

	path = HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_series&category_id="..catid;
	write('<br>URL =',path)
	if (PROXY) then
		r = db.server.urlContent(PROXY,  path, HDRS ); if is_nil(r) then return end
		r = JSON.parse(r); if is_nil(r) then return; end
	else
		r = JSON.getUrl( path, HDRS ); if is_nil(r) then return end
	end

	for serie in r do
		if (serie.series_id && serie.name) then
			--write("<br> Serie: ", serie.name,' (',serie.series_id,')' )
			-- check with local series
			cat = db.category.getfirst()
			while (cat) do
				if ( !(cat.flags&(FLAG_DELETED|FLAG_DISABLED|FLAG_CATEGORY_LIVE|FLAG_CATEGORY_LIST)) && (cat.flags&FLAG_CATEGORY_SERIE) ) then
					if ( string.lower(cat.name)==string.lower(serie.name) ) then
						get_new_episodes(serie.series_id,cat.id)
					end
				end
				cat = cat._next
			end
		end
	end
end


function get_all_series_episodes()
	catid = request.param("catid"); if is_nil(catid) then return end

	path = HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_series&category_id="..catid;
	-- write('<br>URL =',path)
	if (PROXY) then
		r = db.server.urlContent(PROXY,  path, HDRS ); if is_nil(r) then return end
		r = JSON.parse(r); if is_nil(r) then return; end
	else
		r = JSON.getUrl( path, HDRS ); if is_nil(r) then return end
	end

	for serie in r do
		if (serie.series_id && serie.name) then
			get_serie_episodes( serie.series_id );
		end
	end

end

function create_directory()
	server_id = request.param("server_id"); if is_nil(server_id) then return end
	path = request.param("path"); if is_nil(path) then return end

	server = db.server.getbyid(server_id);
	if (server) then
		if ( !db.server.system(server, 'mkdir "'..path..'"') ) then
			write('{"status":1}');
			return true;
		end
	end
end


function add_serie()
	remoteid = request.param("remoteid"); if is_nil(remoteid) then return end

	path = HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_series_info&series_id="..remoteid;
	if (PROXY) then
		r = db.server.urlContent(PROXY,  path, HDRS ); if is_nil(r) then return end
		r = JSON.parse(r); if is_nil(r) then return; end
	else
		r = JSON.getUrl( path, HDRS ); if is_nil(r) then return end
	end

		
	if (r.info) then
		x = r.info;
		serie_name = r.info.name.replace('\n','').replace('\r','').replace('\t','').strip();

		path = request.param("path");
		if (path && length(path)) then
			path = path..'/'..serie_name.lower().replace(' ', '.').replace('"', '.').replace('\'', '.').replace('&', 'and').replace(',', '.').replace(':', '.').replace('-', '.').replace('...', '.').replace('..', '.');
		end

		audio = nil;
		subtitle = nil;
		category_id = request.param("category_id");
		if (category_id) then
			cat = db.category.getbyid(category_id);
			if (cat) then audio = cat.lang; subtitle = cat.subtitle; end

		end

		cat = request.param("category_id");
		if (cat) then lang = cat.lang; else lang=nil; end

		serie = db.category.insert({ flags=FLAG_CATEGORY_SERIE, type=CAT_SERIE, name=serie_name, icon=r.info.cover, plot=r.info.plot, cast=r.info.cast
			, director=r.info.director, genre=r.info.genre, youtube_trailer=r.info.youtube_trailer, rating=r.info.rating, pattern=path, lang=audio, subtitle=subtitle });
		if (serie) then
			write('{"id":',serie.id,',"name":"',serie.name,'","icon":"',serie.icon,'"');
			if (path && length(path)) then
				server_id = request.param("server_id");
				if (server_id) then
					server = db.server.getbyid(server_id);
					if (server) then db.server.system(server, 'mkdir "'..path..'"'); end
				end
			end

			if (cat) then
				if ( db.category.update({ id=cat, list_top={serie.id} }) ) then write(',"category":',cat); end
			end
			write('}');
		end
	end
end


function get_series()
	remote_id = request.param("catid"); if is_nil(remote_id) then return end
	local_id = request.param("local_id"); if (local_id) then local_id = intval(local_id); end

	path = HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_series&category_id="..remote_id
	write('<br>URL =',path)
	if (PROXY) then
		r = db.server.urlContent(PROXY,  path, HDRS ); if is_nil(r) then return end
		r = JSON.parse(r); if is_nil(r) then return; end
	else
		r = JSON.getUrl( path, HDRS ); if is_nil(r) then return end
	end

	write('<br>Total Series = ', length(r))

	write('<br><div style="padding:10px; display:flex; justify-content:space-between;position:sticky;top:0px;background-color:#f8f8f8;">');
	write('<select style="width:20%" id="serie_category" onchange="category_changed()"><option value=0>Select Category</option>');
	path = "";
	x = db.category.getfirst()
	while (x) do
		if ( !(x.flags&(FLAG_DELETED|FLAG_DISABLED)) && (x.type==CAT_SERIE_LIST) ) then
			if (local_id && x.id==local_id) then write('<option selected value=',x.id,'>',x.name,'</option>'); path = x.pattern;
			else write('<option value=',x.id,'>',x.name,'</option>'); end
		end
		x = x._next
	end
	write('</select><input style="width:55%; padding:3px;" id="serie_path" placeholder="Category Diretory" value="',path,'" oninput="check_input();"> <button title="Create Diretory" id="serie_button" onclick="create_dir()" style="font-size:16px"> &#10010; </button> <select style="width:20%" id="serie_server" onchange="check_dir();">');
	x = db.server.getfirst()
	while (x) do
		if ( !(x.flags&(FLAG_DELETED|FLAG_DISABLED)) ) then
			write('<option value="',x.id,'">',x.name,'</option>');
		end
		x = x._next
	end
	write('</select></div>')

	write('<table class="listView" width="100%"><thead><tr class=header> <th class="colCheck" onclick="toggleRows(this.parentNode)"><i class="chkBox chk-on"></i></th> <th width="70px">Logo</th><th width="70px">ID</th><th>Serie Name</th><th width="70px">Actions</th><th width="70px">Logo*</th><th width="55px">ID*</th><th>Local Serie</th></tr></thead><tbody>')
	TABLE.sortby(r,"last_modified");
	for serie in r do
		if (serie.series_id && serie.name) then
			--write("<br> Serie: ", serie.name,' (',serie.series_id,')' )
			-- check with local series

			write('\n<tr data-name="',serie.name,'" data-cover="',serie.cover,'" data-series_id="',serie.series_id,'" data-iptv="',remote_server,'">'
				,'<td class="colCheck" onclick=\'this.parentNode.classList.toggle("checked")\'><i class="chkBox chk-on"></i></td>');

			write('<td><img height="50px" src="',serie.cover,'"></td><td>',serie.series_id,'<br>',os.date("%d-%m-%Y",intval(serie.last_modified)),'</td><td>',serie.name
				,'<br><a href="?remote_server=',remote_server,'&action=get_serie_episodes&remoteid=',serie.series_id,'">get_serie_episodes</a> </td>'
				,'<td><a href=# onclick="add_serie(this,',remote_server,',',serie.series_id,')">Add Serie</a><br>');

			if (local_id) then
				cat = db.serie.getbyname(serie.name, CAT_SERIE, intval(local_id));
				if ( cat && !(cat.flags&(FLAG_DELETED|FLAG_DISABLED)) && (cat.type==CAT_SERIE) ) then
					write('<br><a href="?remote_server=',remote_server,'&action=copy_serie_infos&remoteid=',serie.series_id,'&localid=',cat.id,'">Copy Infos</a> </td>');
					write('<td><img src="',db.category.getlogo(nil,cat),'"></td>');
					write('<td>ID: ',cat.id,'<br><br>',cat.name,' @',cat.lang,' s',cat.seasons_count,' Eps ',cat.listsize);
					write('</td><td><a href="?remote_server=',remote_server,'&action=get_new_episodes&remoteid=',serie.series_id,'&localid=',cat.id,'">Add New Episodes</a>'
						,'<br><br><a href="?remote_server=',remote_server,'&action=dld_new_episodes&remoteid=',serie.series_id,'&localid=',cat.id,'">Wget New Episodes</a>'
						,'</td></tr>')
				else
					write('</td> <td> </td><td> </td><td> </td></tr>')
				end
			else
				cat = db.serie.getbyname(serie.name, CAT_SERIE)
				if ( cat && !(cat.flags&(FLAG_DELETED|FLAG_DISABLED)) && (cat.type==CAT_SERIE) ) then
					write('<br><a href="?remote_server=',remote_server,'&action=copy_serie_infos&remoteid=',serie.series_id,'&localid=',cat.id,'">Copy Infos</a> </td>');
					write('<td><img src="',db.category.getlogo(nil,cat),'"></td>');
					write('<td>ID: ',cat.id,'<br><br>',cat.name,' @',cat.lang,' s',cat.seasons_count,' Eps ',cat.listsize);
					write('</td><td><a href="?remote_server=',remote_server,'&action=get_new_episodes&remoteid=',serie.series_id,'&localid=',cat.id,'">Add New Episodes</a>'
						,'<br><br><a href="?remote_server=',remote_server,'&action=dld_new_episodes&remoteid=',serie.series_id,'&localid=',cat.id,'">Wget New Episodes</a>'
						,'</td></tr>')
				else
					write('</td> <td> </td><td> </td><td> </td></tr>')
				end
			end
		end
	end
	write('<tr><td> </td><td>',length(r),'</td><td> </td><td colspan=3><a href="?remote_server=',remote_server,'&action=get_all_series_episodes&catid=',remote_id,'">get_all_series_episodes</a></td></tr>')
	write('</tbody></table>');


	write('\n<script> var remote_id = ',remote_id,'; let series_cat = [');
	x = db.category.getfirst()
	while (x) do
		if ( !(x.flags&(FLAG_DELETED|FLAG_DISABLED)) && (x.type==CAT_SERIE_LIST) ) then
			path = '';
			series = db.category.getlist(x.list);
			for y in series do
				if (y.pattern) then path = os.path.dirname(y.pattern); break; end
			end
			write('{ id:',x.id,',name:"',x.name,'",path:"',path,'" },');
		end
		x = x._next
	end

	-- script
	write([[];

	function create_dir() {
		let path = document.querySelector("#serie_path").value;
		let server_id = document.querySelector("#serie_server").value;

		var xhr = new XMLHttpRequest();
		xhr.addEventListener("load", function(event_) {
	        var json = JSON.parse(this.responseText);
			if (json && json.status) {
				term_write('\n Directory "'+path+'" Created\n');
			}
		}, false);
		url = '?remote_server='+1+'&ajax=create_directory&server_id='+server_id+'&path='+encodeURIComponent(path);
		xhr.open("GET", url, true);
		xhr.send(null);
	}
	function check_dir() {
		let path = document.querySelector("#serie_path").value;
		let server_id = document.querySelector("#serie_server").value;

		var xhr = new XMLHttpRequest();
		xhr.addEventListener("load", function(event_) {
	        var json = JSON.parse(this.responseText);
			let x = document.querySelector("#serie_button");
			if (json && json.status) { x.innerHTML ='&#9989;'; x.onclick = null; }
			else { x.innerHTML ='&#10010;'; x.onclick = create_dir; }
		}, false);
		url = '?remote_server='+1+'&ajax=check_directory&server_id='+server_id+'&path='+encodeURIComponent(path);
		xhr.open("GET", url, true);
		xhr.send(null);
	}
	function check_input()
	{
		clearTimeout(check_input.t);
		check_input.t = setTimeout( function(){ check_dir(); }, 1000);
	}

	function category_changed() {
		local_id = document.querySelector("#serie_category").value;
		window.location = "]],request.path(),[[?remote_server="+remote_server+"&action=get_series&catid="+remote_id+"&local_id="+local_id;
	}

	function set_category() {
		id = document.querySelector("#serie_category").value;
		for (let x of series_cat) {
			if (x.id==id) {
				document.querySelector("#serie_path").value = x.path;
				check_dir();
				break;
			}
		}
	}

	function add_serie(e, remote_server, serie_id) {
		let row = getAncestorByTag(e, "TR");
		let category_id = document.querySelector("#serie_category").value;
		let server_id = document.querySelector("#serie_server").value;
		let path = document.querySelector("#serie_path").value;

		var xhr = new XMLHttpRequest();
		xhr.addEventListener("load", function(event_) {
	        var json = JSON.parse(this.responseText);
			if (json && json.id) {
				row.cells.item(4).innerHTML = '<img src="'+json.icon+'">';
				row.cells.item(5).innerHTML = json.id;
				row.cells.item(6).innerHTML = json.name+'<br><a href="?remote_server='+remote_server+'&action=get_new_episodes&remoteid='+serie_id+'&localid='+json.id+'">get_new_episodes</a>';
			}
		}, false);
		url = '?remote_server='+remote_server+'&ajax=add_serie&remoteid='+serie_id;
		if (category_id>0) url += '&category_id='+category_id;
		if (server_id>0 && path.length>0) url += '&server_id='+server_id+'&path='+encodeURIComponent(path);
		xhr.open("GET", url, true);
		xhr.send(null);
	}
	</script>]]);
end


function get_series_categories()
	path = HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_series_categories"
	write('<br>URL =',path)
	if (PROXY) then
		r = db.server.urlContent(PROXY,  path, HDRS ); if is_nil(r) then return end
		r = JSON.parse(r); if is_nil(r) then return; end
	else
		r = JSON.getUrl( path, HDRS ); if is_nil(r) then return end
	end

	write('<table class="listView" width="100%"><thead><tr class=header><th width="70px">ID</th><th width="40%">Category Name</th><th width="20%">get_series</th></tr></thead><tbody>')
	for cat in r do
		if (cat.category_id && cat.category_name) then
			write('<tr><td>',cat.category_id,'</td><td>',cat.category_name
				,'</td><td><a href="?remote_server=',remote_server,'&action=get_series&catid=',cat.category_id,'">get_series</a></td></tr>')
		end
	end
	write('</tbody></table>')
end


function get_vod_streams()
	catid = request.param("catid"); if is_nil(catid) then return end

	path = HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_vod_streams&category_id="..catid
	write('<br>', path)
	if (PROXY) then
		r = db.server.urlContent(PROXY,  path, HDRS ); if is_nil(r) then return end
		r = JSON.parse(r); if is_nil(r) then return; end
	else
		r = JSON.getUrl( path, HDRS ); if is_nil(r) then return end
	end

	write('<br><div style="padding:10px; display:flex; justify-content:space-between;position:sticky;top:0px;background-color:#f8f8f8;"><select style="width:20%" id="movie_category" onchange="set_category()">')
	write('</select><input style="width:55%; padding:3px;" id="movie_path" placeholder="Download Path" value="" oninput="check_input();">   <button  title="Create Diretory" id="movie_button" onclick="create_dir()" style="font-size:16px"> &#10010; </button> <select style="width:20%" id="movie_server">');
	x = db.server.getfirst()
	while (x) do
		if ( !(x.flags&(FLAG_DELETED|FLAG_DISABLED)) ) then
			write('<option value="',x.id,'">',x.name,'</option>');
		end
		x = x._next
	end
	write('</select></div>')
	write('<table class="listView" width="100%"><thead><tr class=header><th class="colCheck" onclick="toggleRows(this.parentNode)"><i class="chkBox chk-on"></i></th><th width="50px">Date</th><th width="50px">Logo</th><th>URL</th><th width="80px"><button class="button" onclick=\'exec_download_all_movies(this)\'>Download</button></th></tr></thead><tbody>')
	TABLE.sortby(r,"added");
	for vod in r do
		if (length(vod.direct_source)) then url = vod.direct_source
		else url = HOST.."/movie/"..USER.."/"..PASS.."/"..vod.stream_id..'.'..vod.container_extension end
		if (RELOCATION) then url = URL.getLocation(url) end
		if (length(url)) then
			if (vod.container_extension) then ext = vod.container_extension else ext = URL.getExtension(url) end
			if (ext) then name = vod.name..'.'..ext else name = vod.name end
			write('<tr data-name="',name,'" data-url="',url,'" data-icon="',vod.stream_icon,'">'
				,'<td class="colCheck" onclick=\'this.parentNode.classList.toggle("checked")\'><i class="chkBox chk-on"></i></td><td>',os.date("%d-%m-%Y",intval(vod.added))
				,'</td><td><img src="',vod.stream_icon,'"</td><td>',name,'<br>',url,'</td><td>'
				,'<button class="button" onclick=\'exec_download_movie(this)\'>Download</button>'
				,'<br><button class="button" onclick=\'exec_add_movie(this)\'>Add Link</button></td></tr>')
		else
			write('<br>## Movie not found ', vod.title)
		end
	end
	write('</tbody></table>');
	-- script
	write('<script> movies_cat = [');
	x = db.category.getfirst()
	while (x) do
		if ( !(x.flags&(FLAG_DELETED|FLAG_DISABLED)) && (x.type==CAT_MOVIE_LIST) ) then
			serverid = 0; path = "";
			for v in x.list do
				vod = db.vod.getbyid(v);
				if (vod) then
					serverid = vod.serverid; path = os.path.dirname(vod.path); break;
				end
			end
			write('{ id:',x.id,', server_id:',serverid,', name:"',x.name,'", path:"',path,'" },');
		end
		x = x._next
	end
	write([[];

	item = document.querySelector("#movie_category");
	if (item) {
		html = "<option value=0>Select Category</option>";
		for (let x of movies_cat) html += '<option value='+x.id+'>'+x.name+'</option>';
		item.innerHTML = html;
	}

	function create_dir() {
		let path = document.querySelector("#movie_path").value;
		let server_id = document.querySelector("#movie_server").value;

		var xhr = new XMLHttpRequest();
		xhr.addEventListener("load", function(event_) {
	        var json = JSON.parse(this.responseText);
			if (json && json.status) {
				term_write('\n Directory "'+path+'" Created\n');
			}
		}, false);
		url = '?remote_server='+1+'&ajax=create_directory&server_id='+server_id+'&path='+encodeURIComponent(path);
		xhr.open("GET", url, true);
		xhr.send(null);
	}
	function check_dir() {
		let path = document.querySelector("#movie_path").value;
		let server_id = document.querySelector("#movie_server").value;

		var xhr = new XMLHttpRequest();
		xhr.addEventListener("load", function(event_) {
	        var json = JSON.parse(this.responseText);
			let x = document.querySelector("#movie_button");
			if (json && json.status) { x.innerHTML ='&#9989;'; x.onclick = null; }
			else { x.innerHTML ='&#10010;'; x.onclick = create_dir; }
		}, false);
		url = '?remote_server='+1+'&ajax=check_directory&server_id='+server_id+'&path='+encodeURIComponent(path);
		xhr.open("GET", url, true);
		xhr.send(null);
	}
	function check_input()
	{
		clearTimeout(check_input.t);
		check_input.t = setTimeout( function(){ check_dir(); }, 1000);
	}

	function set_category() {
		id = document.querySelector("#movie_category").value;
		for (let x of movies_cat) {
			if (x.id==id) {
				document.querySelector("#movie_path").value = x.path;
				document.querySelector("#movie_server").value = x.server_id;
				check_dir();
				break;
			}
		}
	}

	function exec_download_movie(e, next) {
		let row = getAncestorByTag(e, "TR");
		row.classList.add("active");
		let url = row.dataset.url;
		let name = row.dataset.name;
		let icon = row.dataset.icon;
		let category_id = document.querySelector("#movie_category").value;
		let server_id = document.querySelector("#movie_server").value;
		let path = document.querySelector("#movie_path").value +'/'+ name;
		term_text = '';
		term_line = '';
		link = 'ws://]],db.gethostname(),':',db.getport(),request.path()
			,[[?action=download_movie&category_id='+category_id+'&server_id='+server_id+'&path='+encodeURIComponent(path)+'&url='+encodeURIComponent(url)+'&icon='+encodeURIComponent(icon);
		var socket = new WebSocket(link);
		socket.onopen = function (event) { term_write('Starting...\n') }
		socket.onmessage = function (event) { term_write(event.data); }
		socket.onclose = function (event) {
			term_write('\n-- Download Finished.\n');
			row.classList.remove("active");
			row.classList.add("success");
			if (next) {
				row.classList.remove("checked");
				while (row) {
					row = row.nextSibling;
					if (row && row.classList.contains("checked")) break;
				}
				if (row) setTimeout( function() { exec_download_movie(row, true); }, 1000);
			}
		}
	}

	function exec_download_all_movies(e) {
		let tab = getAncestorByTag(e, "TABLE");
		row = tab.querySelector("tr.header");
		if (row) row.classList.remove("checked");
		row = tab.querySelector("tbody tr.checked");
		if (row) exec_download_movie(row, true);
	}

	function exec_add_movie(e, next) {
		let row = getAncestorByTag(e, "TR");
		row.classList.add("active");
		let url = row.dataset.url;
		let name = row.dataset.name;
		let icon = row.dataset.icon;
		let category_id = document.querySelector("#movie_category").value;
		let server_id = document.querySelector("#movie_server").value;
		let path = document.querySelector("#movie_path").value +'/'+ name;
		term_text = '';
		term_line = '';
		link = 'ws://]],db.gethostname(),':',db.getport(),request.path()
			,[[?action=add_movie&category_id='+category_id+'&server_id='+server_id+'&name='+encodeURIComponent(name)+'&url='+encodeURIComponent(url)+'&icon='+encodeURIComponent(icon);
		var socket = new WebSocket(link);
		socket.onopen = function (event) { term_write('Starting...\n') }
		socket.onmessage = function (event) { term_write(event.data); }
		socket.onclose = function (event) {
			term_write('\n-- Finished.\n');
			row.classList.remove("active");
			row.classList.add("success");
			if (next) {
				row.classList.remove("checked");
				while (row) {
					row = row.nextSibling;
					if (row && row.classList.contains("checked")) break;
				}
				if (row) setTimeout( function() { exec_add_movie(row, true); }, 1000);
			}
		}
	}

	function exec_add_all_movies(e) {
		let tab = getAncestorByTag(e, "TABLE");
		row = tab.querySelector("tr.header");
		if (row) row.classList.remove("checked");
		row = tab.querySelector("tbody tr.checked");
		if (row) exec_add_movie(row, true);
	}

</script>]]);
end

function wget_vod_streams()
	catid = request.param("catid"); if is_nil(catid) then return end

	path = HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_vod_streams&category_id="..catid
	write('<br>', path)
	if (PROXY) then
		r = db.server.urlContent(PROXY,  path, HDRS ); if is_nil(r) then return end
		r = JSON.parse(r); if is_nil(r) then return; end
	else
		r = JSON.getUrl( path, HDRS ); if is_nil(r) then return end
	end

	TABLE.sortby(r,"added");
	for vod in r do
		if (length(vod.direct_source)) then url = vod.direct_source
		else url = HOST.."/movie/"..USER.."/"..PASS.."/"..vod.stream_id..'.'..vod.container_extension end
		if (RELOCATION) then url = URL.getLocation(url) end
		if (length(url)) then
			if (vod.container_extension) then ext = vod.container_extension else ext = URL.getExtension(url) end
			if (ext) then name = vod.name..'.'..ext else name = vod.name end
			write('<br>wget -t 10 -c -O "',name,'" "',url,'" --user-agent="',USER_AGENT,'"')
		end
	end
end

function download_movie()
	category_id = request.param("category_id"); if is_nil(category_id) then return end
	server_id = request.param("server_id"); if is_nil(server_id) then return end
	path = request.param("path"); if is_nil(path) then return end
	url = request.param("url"); if is_nil(url) then return end
	icon = request.param("icon");

	if (websocket.handshake()>=12) then
		server = db.server.getbyid(server_id); if is_nil(server) then return end
		cmd = 'wget --user-agent="'..USER_AGENT..'" --no-check-certificate --no-dns-cache --continue "'..url..'" -O "'..path..'"';
		write("<br>cmd = ",cmd)
		data = db.server.system(server, cmd);
		if (data!=0) then
			write("\nFailed")
		else
			write("\nSuccess");
			-- add
			stat = db.server.stat(server,path)
			if is_table(stat) then
				if (stat.size<10000000) then db.server.remove(server,path); write("Failed.");
				else
					cat = db.category.getbyid(category_id);
					if (cat) then
						write("<br>",path," (",stat.size,")")
						vod = db.vod.getbypath(path)
						if is_nil(vod) then
							info = os.path.getinfo(path);
							vod = db.vod.insert({ name=info.name, path=path, serverid=server.id, icon=icon })
							write(" +Vod")
						end
						if (vod) then
							if (db.category.update({ id=category_id, list_top={vod.id} })) then
								write(' +Category');
								return 1;
							end
						end
					end
				end
			end
		end
	end
end


function add_movie()
	category_id = request.param("category_id"); if is_nil(category_id) then return end
	server_id = request.param("server_id"); if is_nil(server_id) then return end
	name = request.param("name"); if is_nil(name) then return end
	url = request.param("url"); if is_nil(url) then return end
	icon = request.param("icon");

	if (websocket.handshake()>=12) then
		cat = db.category.getbyid(category_id);
		if (cat) then
			write("<br>",url)
			vod = db.vod.getbypath(url)
			if is_nil(vod) then
				info = os.path.getinfo(name);
				vod = db.vod.insert({ name=info.name, path=url, serverid=server_id, icon=icon })
				write(" +Vod")
			end
			if (vod) then
				if (db.category.update({ id=category_id, list_top={vod.id} })) then
					write(' +Category');
					return 1;
				end
			end
		end
	end
end

function get_vod_categories()
	path = HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_vod_categories"
	write('<br>', path)
	if (PROXY) then
		r = db.server.urlContent(PROXY,  path, HDRS ); if is_nil(r) then return end
		r = JSON.parse(r); if is_nil(r) then return; end
	else
		r = JSON.getUrl( path, HDRS ); if is_nil(r) then return end
	end

	write('<table class="listView" width="100%"><thead><tr class=header><th width="70px">ID</th><th width="40%">Category Name</th><th width="20%">Action</th></tr></thead><tbody>')
	for cat in r do
		if (cat.category_id && cat.category_name) then
			write('<tr><td>',cat.category_id,'</td><td>',cat.category_name
				,'</td><td><a href="?remote_server=',remote_server,'&action=get_vod_streams&catid=',cat.category_id,'">List Movies</a>'
				,'<br><br><a href="?remote_server=',remote_server,'&action=wget_vod_streams&catid=',cat.category_id,'">Wget Movies</a>'
				,'</td></tr>')
		end
	end
	write('</tbody></table>')
end


function get_live_streams()
	catid = request.param("catid"); if is_nil(catid) then return end

	path = HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_live_streams&category_id="..catid
	write('<br>URL =',path)
	if (PROXY) then
		r = db.server.urlContent(PROXY,  path, HDRS ); if is_nil(r) then return end
		r = JSON.parse(r); if is_nil(r) then return; end
	else
		r = JSON.getUrl( path, HDRS ); if is_nil(r) then return end
	end

	write('<table class="listView" width="100%"><thead><tr class=header><th width="70px">ID</th><th width="40%">Stream Name</th><th>Stream URL</th></tr></thead><tbody>')
	for stream in r do
		write('<tr><td>',stream.stream_id,'</td><td>',stream.name
			,'</td><td>',HOST,"/live/",USER,"/",PASS,"/",stream.stream_id
			,'</td></tr>')
	end
	write('</table>')
end

function get_live_categories()
	path = HOST.."/player_api.php?username="..USER.."&password="..PASS.."&action=get_live_categories"
	write('<br>URL =',path)
	if (PROXY) then
		r = db.server.urlContent(PROXY,  path, HDRS ); if is_nil(r) then return end
		r = JSON.parse(r); if is_nil(r) then return; end
	else
		r = JSON.getUrl( path, HDRS ); if is_nil(r) then return end
	end

	write('<table class="listView" width="100%"><thead><tr class=header><th width="70px">ID</th><th width="40%">Category Name</th><th width="20%"> </th></tr></thead><tbody>')
	for cat in r do
		if (cat.category_id && cat.category_name) then
			write('<tr><td>',cat.category_id,'</td><td>',cat.category_name
				,'</td><td><a href="?remote_server=',remote_server,'&action=get_live_streams&catid=',cat.category_id,'">get_live_streams</a>'
				,'</td></tr>')
		end
	end
	write('</tbody></table>')
end

function get_infos()
	path = HOST.."/player_api.php?username="..USER.."&password="..PASS
	write('<br>', path)
	if (PROXY) then
		r = db.server.urlContent(PROXY,  path, HDRS ); if is_nil(r) then return end
		r = JSON.parse(r); if is_nil(r) then return; end
	else
		r = JSON.getUrl( path, HDRS ); if is_nil(r) then return end
	end

	if is_table(r) then
		write('<br><br> Authorisation = ', r.user_info.auth);
		write('<br> Status = ', r.user_info.status);
		write('<br> is Trial = ', r.user_info.is_trial);
		write('<br> Expire = ', os.date("%Y-%m-%d %H:%M:%S", intval(r.user_info.exp_date)));
		write('<br> Max Connections = ', r.user_info.max_connections);
		write('<br> Active Connections = ', r.user_info.active_cons);
	end
end

function check_directory()
	server_id = request.param("server_id"); if is_nil(server_id) then return end
	path = request.param("path"); if is_nil(path) then return end
	server = db.server.getbyid(server_id);
	if (server) then
		stat = db.server.stat(server, path);
		if is_table(stat) then
			if stat.mode&0x4000 then
				write('{"status":1}');
				return true;
			end
		end
	end
end

ajax = request.param("ajax")
if (ajax) then
	if (ajax=='add_serie') then add_serie();
	elseif (ajax=='create_directory') then
		if ( !create_directory() ) then write('{"status":0}'); end
	elseif (ajax=='check_directory') then
		if ( !check_directory() ) then write('{"status":0}'); end
	end
	exit;
end


write( [[
<!Doctype html>
<html><head><meta charset="UTF-8">
<style>
*{
	padding: 0;
	margin: 0;
	font-family: "Helvetica Neue",Helvetica,Arial,Verdana,sans-serif;
	font-size: 12px;
	-moz-box-sizing: border-box;
	-webkit-box-sizing: border-box;
	box-sizing: border-box;
}
.btn-group { padding: 3px; }
.btn-group a {
	font-size: 1.3em; line-height: 28px; height: 30px;
	background-color: #4CAF50; border: 1px solid green;
	color: white; text-decoration: none; text-align: center;
	padding:0 25px; cursor: pointer; float: left;
	margin-left: 3px;
}
.btn-group select {
	font-size: 1.3em; line-height: 30px; height: 30px;
	background-color: #e8e8e8; border: 1px solid #777;
	color: #333; text-decoration: none; text-align: center;
	padding:0 25px; cursor: pointer; float: right;
}
.btn-group:after {
  content: "";
  clear: both;
  display: table;
}
.btn-group a:hover { background-color: #3e8e41; }

.listView { width:100%; border-collapse:collapse; }
.listView .header {
	background:#3f4344;
	background:-moz-linear-gradient(top,  #3f4344 0%, #61696b 50%, #454a4b 100%);
	background:-webkit-linear-gradient(top,  #3f4344 0%,#61696b 50%,#454a4b 100%);
	background:linear-gradient(to bottom,  #3f4344 0%,#61696b 50%,#454a4b 100%);
	filter:progid:DXImageTransform.Microsoft.gradient( startColorstr='#3f4344', endColorstr='#454a4b',GradientType=0 );
	-webkit-box-shadow:inset 0px 1px 1px 0px rgba(0,0,0,0.1);
	-moz-box-shadow:inset 0px 1px 1px 0px rgba(0,0,0,0.1);
	box-shadow:inset 0px 1px 1px 0px rgba(0,0,0,0.1);
	text-align:left;
	padding:0px 5px;
	font-size:12px;
	color:#e0d0c0;
}
.listView input { font-size:12px; }
.listView th { padding:0px 5px; height:28px; }
.listView tr { border:1px solid #e8e8e8; }
.listView tr.active { background-color:#fff2cb; }
.listView tr.failed { background-color:#ff7f7f; }
.listView tr.success { background-color:#e5faff; }
.listView > tbody > tr:hover {
	-webkit-box-shadow:inset 0px 0px 4px 0px black;
	-moz-box-shadow:inset 0px 0px 4px 0px black;
	box-shadow:inset 0px 0px 4px 0px black;
}
.listView td { max-width:15vw; font-size:12px; vertical-align: middle; text-overflow:ellipsis; overflow-x:hidden; white-space: nowrap; margin:0px; padding: 3px; height:36px; }
.listView td:first-child { padding: 0px 5px; }
.listView td a { cursor:pointer }
.listView img { text-align:center; padding:1px; max-width:50px; max-height:50px; 
	border:0px;
	margin:0px;
	padding:1px;
	vertical-align:middle;
	margin-left:auto;
	margin-right:auto;
	-webkit-border-radius:3px; -moz-border-radius:3px; border-radius:3px;
}
.listView .colCheck { width:30px; text-align:center; }
.listView .chkBox { display:block; cursor:pointer; font-size:18px; line-height:20px; height:20px; width:20px; color:#aaa;
	-webkit-border-radius:50%; -moz-border-radius:50%; border-radius:50%; text-align: center; font-weight:bold;
	font-style: normal; font-variant: normal; text-rendering: auto;
}
.listView .chkBox:hover { color:#777; }
.listView .checked:hover .chkBox,
.listView .checked .chkBox { color:#d900a3; }

.chk-on:before { content: "\229E" }
.button { margin: 3px; min-width: 70px; }

</style>
</head><body style="height:100%; width:100%; padding:5px; overflow:hidden;">]])

write('<div class="btn-group" style="width:100%">')
write('<a href="?remote_server=',remote_server,'&action=get_infos">Get Infos</a>')
write('<a href="?remote_server=',remote_server,'&action=get_live_categories">Get Live Categories</a>')
write('<a href="?remote_server=',remote_server,'&action=get_vod_categories">Get Movie Categories</a>')
write('<a href="?remote_server=',remote_server,'&action=get_series_categories">Get Series Categories</a>')
write('<select style="float:right" name=severid onchange=\'document.location.href="?remote_server="+this.value\'>')
for i,j in remote_servers do
	write('<option value=',i)
	if (i==remote_server) then write(' selected') end
	write('> ',j.host,' ',j.user,'</option>')
end
write('</select></div><div id=contents style="display:flex; justify-content: space-between;width:100%;"> <div style="width:60%; overflow-y:scroll; border:1px solid #777;">')

action = request.param("action")
if (action) then
	if (action=='get_infos') then get_infos()
	elseif (action=='get_live_categories') then get_live_categories()
	elseif (action=='get_live_streams') then get_live_streams()
	elseif (action=='get_vod_categories') then get_vod_categories()
	elseif (action=='get_vod_streams') then get_vod_streams()
	elseif (action=='wget_vod_streams') then wget_vod_streams()
	elseif (action=='get_series_categories') then get_series_categories()
	elseif (action=='get_series') then get_series()
	elseif (action=='get_all_series_episodes') then get_all_series_episodes()
	elseif (action=='download_episode') then download_episode(); exit;
	elseif (action=='download_movie') then download_movie(); exit;
	elseif (action=='add_movie') then add_movie(); exit;
	elseif (action=='get_new_episodes') then
		remoteid = request.param("remoteid");
		localid = request.param("localid");
		if (remoteid && localid) then get_new_episodes(remoteid,localid) end

	elseif (action=='dld_new_episodes') then
		remoteid = request.param("remoteid");
		localid = request.param("localid");
		if (remoteid && localid) then dld_new_episodes(remoteid, localid) end

	elseif (action=='copy_serie_infos') then
		remoteid = request.param("remoteid");
		localid = request.param("localid");
		if (remoteid && localid) then copy_serie_infos(remoteid,localid) end
	elseif (action=='get_serie_episodes') then
		remoteid = request.param("remoteid");
		if (remoteid) then get_serie_episodes(remoteid) end
	end
end

write([[</div> <div id=result style="width:40%; height:100%;">
	<pre id="term_container" style="color:white; background-color:black; padding:3px; margin:0; width:100%; height:100%; overflow-y:scroll;word-break: break-all; white-space: break-spaces;"></pre>
	</div>
	<br>
<script>
	var remote_server =]],remote_server,[[;
	let contents = document.querySelector('#contents'); contents.style.height = (window.innerHeight-contents.getBoundingClientRect().top-15)+"px";
	let result = document.querySelector('#result'); result.style.height = (window.innerHeight-result.getBoundingClientRect().top-15)+"px";

	let term;
	let term_text = '';
	let term_line = '';
	let term_caret = 0;
	function term_write(str) {
		for (i=0; i<str.length; i++) {
			c = str.charAt(i);
			if (c=='\r') term_caret = 0;
			else if (c=='\n') { term_text += term_line+'\n'; term_line = ''; term_caret = 0; }
			else {
				newline = '';
				if (term_caret > 0) newline = term_line.substr(0, term_caret);
				newline += c;
				if (term_caret<term_line.length) newline += term_line.substr(term_caret+1);
				term_line = newline;
				term_caret++;
			}
		}
		term.innerHTML = term_text + term_line;
		term.scrollTop = term.scrollHeight - term.clientHeight;
	}
	term = document.getElementById("term_container");


	function getAncestorByTag(el, tag) { while (el && (el.tagName!=tag)) el = el.parentNode; return el; }

	function toggleRows(row)
	{
		let tab = getAncestorByTag(row,'TABLE');
		if (tab) {
			let list = tab.querySelectorAll('tbody > tr');
			if (list) {
				if (row.classList.contains("checked")) {
					row.classList.remove("checked");
					for (let item of list) item.classList.remove("checked");
				}
				else {
					row.classList.add("checked");
					for (let item of list) item.classList.add("checked");
				}
			}
		}
	}

</script>
</div></div></html>]]);
