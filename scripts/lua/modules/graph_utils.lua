--
-- (C) 2013-17 - ntop.org
--
require "lua_utils"
require "db_utils"
require "historical_utils"
local host_pools_utils = require "host_pools_utils"
local os_utils = require "os_utils"
local have_nedge = ntop.isnEdge()

local top_rrds = {
   {rrd="num_flows.rrd",               label=i18n("graphs.active_flows")},
   {rrd="num_hosts.rrd",               label=i18n("graphs.active_hosts")},
   {rrd="num_devices.rrd",             label=i18n("graphs.active_devices")},
   {rrd="num_http_hosts.rrd",          label=i18n("graphs.active_http_servers"), nedge_exclude=1},
   {rrd="bytes.rrd",                   label=i18n("traffic")},
   {rrd="broadcast_bytes.rrd",         label=i18n("broadcast_traffic")},
   {rrd="packets.rrd",                 label=i18n("packets")},
   {rrd="drops.rrd",                   label=i18n("graphs.packet_drops"), nedge_exclude=1},
   {rrd="blocked_flows.rrd",           label=i18n("graphs.blocked_flows")},
   {rrd="num_zmq_rcvd_flows.rrd",      label=i18n("graphs.zmq_received_flows"), nedge_exclude=1},
   {rrd="num_ms_srv_nw_ltn.rrd",       label=i18n("graphs.num_ms_srv_nw_ltn"), nedge_exclude=1},
   {separator=1, nedge_exclude=1},
   {rrd="tcp_lost.rrd",                label=i18n("graphs.tcp_packets_lost"), nedge_exclude=1},
   {rrd="tcp_ooo.rrd",                 label=i18n("graphs.tcp_packets_ooo"), nedge_exclude=1},
   {rrd="tcp_retransmissions.rrd",     label=i18n("graphs.tcp_packets_retr"), nedge_exclude=1},
   {rrd="tcp_retr_ooo_lost.rrd",       label=i18n("graphs.tcp_retr_ooo_lost"), nedge_exclude=1},
   {separator=1},
   {rrd="tcp_syn.rrd",                 label=i18n("graphs.tcp_syn_packets"), nedge_exclude=1},
   {rrd="tcp_synack.rrd",              label=i18n("graphs.tcp_synack_packets"), nedge_exclude=1},
   {rrd="tcp_finack.rrd",              label=i18n("graphs.tcp_finack_packets"), nedge_exclude=1},
   {rrd="tcp_rst.rrd",                 label=i18n("graphs.tcp_rst_packets"), nedge_exclude=1},
}

-- ########################################################

if(ntop.isPro()) then
   package.path = dirs.installdir .. "/pro/scripts/lua/modules/?.lua;" .. package.path
   require "nv_graph_utils"
end

-- ########################################################

function getProtoVolume(ifName, start_time, end_time)
   ifId = getInterfaceId(ifName)
   path = os_utils.fixPath(dirs.workingdir .. "/" .. ifId .. "/rrd/")
   rrds = ntop.readdir(path)
   
   ret = { }
   for rrdFile,v in pairs(rrds) do
      if((string.ends(rrdFile, ".rrd")) and (not isTopRRD(rrdFile))) then
	 rrdname = getRRDName(ifId, nil, rrdFile)
	 if(ntop.notEmptyFile(rrdname)) then
	    local fstart, fstep, fnames, fdata = ntop.rrd_fetch(rrdname, 'AVERAGE', start_time, end_time)

	    if(fstart ~= nil) then
	       local num_points_found = table.getn(fdata)

	       accumulated = 0
	       for i, v in ipairs(fdata) do
		  for _, w in ipairs(v) do
		     if(w ~= w) then
			-- This is a NaN
			v = 0
		     else
			--io.write(w.."\n")
			v = tonumber(w)
			if(v < 0) then
			   v = 0
			end
		     end
		  end

		  accumulated = accumulated + v
	       end

	       if(accumulated > 0) then
		  rrdFile = string.sub(rrdFile, 1, string.len(rrdFile)-4)
		  ret[rrdFile] = accumulated
	       end
	    end
	 end
      end
   end

   return(ret)
end

-- ########################################################

function navigatedir(url, label, base, path, print_html, ifid, host, start_time, end_time, filter)
   local shown = false
   local to_skip = false
   local ret = { }
   local do_debug = false
   local printed = false

   -- io.write(debug.traceback().."\n")

   local rrds = ntop.readdir(path)

   for k,v in pairsByKeys(rrds, asc) do
      if(v ~= nil) then
	 local p = os_utils.fixPath(path .. "/" .. v)

	 if not ntop.isdir(p) then
	    local last_update,_ = ntop.rrd_lastupdate(getRRDName(ifid, host, k))

	    if last_update ~= nil and last_update >= start_time then

	       -- only show if there has been an update within the specified time frame

	       if not isTopRRD(v) and (not filter or filter[k:gsub('.rrd','')]) then

		  if(label == "*") then
		     to_skip = true
		  else
		     if(not(shown) and not(to_skip)) then
			if(print_html) then
			   if(not(printed)) then print('<li class="divider"></li>\n') printed = true end
			   print('<li class="dropdown-submenu"><a tabindex="-1" href="#">'..label..'</a>\n<ul class="dropdown-menu">\n')
			end
			shown = true
		     end
		  end

		  what = string.sub(path.."/"..v, string.len(base)+2)

		  label = string.sub(v,  1, string.len(v)-4)
		  label = l4Label(string.gsub(label, "_", " "))

		  ret[label] = what
		  if(do_debug) then print(what.."<br>\n") end

		  if(print_html) then
		     if(not(printed)) then print('<li class="divider"></li>\n') printed = true end
		     print("<li> <A HREF=\""..url..what.."\">"..label.."</A>  </li>\n")
		  end
	       end
	    end
	 end
      end
   end

   if(shown) then
      if(print_html) then print('</ul></li>\n') end
   end

   return(ret)
end

-- ########################################################

function breakdownBar(sent, sentLabel, rcvd, rcvdLabel, thresholdLow, thresholdHigh)
   if((sent+rcvd) > 0) then
    sent2rcvd = round((sent * 100) / (sent+rcvd), 0)
    -- io.write("****>> "..sent.."/"..rcvd.."/"..sent2rcvd.."\n")
    if((thresholdLow == nil) or (thresholdLow < 0)) then thresholdLow = 0 end
    if((thresholdHigh == nil) or (thresholdHigh > 100)) then thresholdHigh = 100 end

    if(sent2rcvd < thresholdLow) then sentLabel = '<i class="fa fa-warning fa-lg"></i> '..sentLabel
    elseif(sent2rcvd > thresholdHigh) then rcvdLabel = '<i class="fa fa-warning fa-lg""></i> '..rcvdLabel end

      print('<div class="progress"><div class="progress-bar progress-bar-warning" aria-valuenow="'.. sent2rcvd..'" aria-valuemin="0" aria-valuemax="100" style="width: ' .. sent2rcvd.. '%;">'..sentLabel)
      print('</div><div class="progress-bar progress-bar-info" aria-valuenow="'.. (100-sent2rcvd)..'" aria-valuemin="0" aria-valuemax="100" style="width: ' .. (100-sent2rcvd) .. '%;">' .. rcvdLabel .. '</div></div>')

   else
      print('&nbsp;')
   end
end

-- ########################################################

function percentageBar(total, value, valueLabel)
   -- io.write("****>> "..total.."/"..value.."\n")
   if((total ~= nil) and (total > 0)) then
      pctg = round((value * 100) / total, 0)
      print('<div class="progress"><div class="progress-bar progress-bar-warning" aria-valuenow="'.. pctg..'" aria-valuemin="0" aria-valuemax="100" style="width: ' .. pctg.. '%;">'..valueLabel)
      print('</div></div>')
   else
      print('&nbsp;')
   end
end

-- ########################################################
-- host_or_network: host or network name.
-- If network, must be prefixed with 'net:'
-- If profile, must be prefixed with 'profile:'
-- If host pool, must be prefixed with 'pool:'
-- If vlan, must be prefixed with 'vlan:'
-- If asn, must be prefixed with 'asn:'
function getRRDName(ifid, host_or_network, rrdFile)
   if host_or_network ~= nil and string.starts(host_or_network, 'net:') then
      host_or_network = string.gsub(host_or_network, 'net:', '')
      rrdname = os_utils.fixPath(dirs.workingdir .. "/" .. ifid .. "/subnetstats/")
   elseif host_or_network ~= nil and string.starts(host_or_network, 'profile:') then
      host_or_network = string.gsub(host_or_network, 'profile:', '')
      rrdname = os_utils.fixPath(dirs.workingdir .. "/" .. ifid .. "/profilestats/")
   elseif host_or_network ~= nil and string.starts(host_or_network, 'vlan:') then
      host_or_network = string.gsub(host_or_network, 'vlan:', '')
      rrdname = os_utils.fixPath(dirs.workingdir .. "/" .. ifid .. "/vlanstats/")
   elseif host_or_network ~= nil and string.starts(host_or_network, 'pool:') then
      host_or_network = string.gsub(host_or_network, 'pool:', '')
      rrdname = host_pools_utils.getRRDBase(ifid, "")
   elseif host_or_network ~= nil and string.starts(host_or_network, 'snmp:') then
      host_or_network = string.gsub(host_or_network, 'snmp:', '')
      -- snmpstats are ntopng-wide so ifid is ignored
      rrdname = os_utils.fixPath(dirs.workingdir .. "/snmpstats/")
   elseif host_or_network ~= nil and string.starts(host_or_network, 'flow_device:') then
      host_or_network = string.gsub(host_or_network, 'flow_device:', '')
      rrdname = os_utils.fixPath(dirs.workingdir .. "/" .. ifid .. "/flow_devices/")
   elseif host_or_network ~= nil and string.starts(host_or_network, 'sflow:') then
      host_or_network = string.gsub(host_or_network, 'sflow:', '')
      rrdname = os_utils.fixPath(dirs.workingdir .. "/" .. ifid .. "/sflow/")
   elseif host_or_network ~= nil and string.starts(host_or_network, 'vlan:') then
      host_or_network = string.gsub(host_or_network, 'vlan:', '')
      rrdname = os_utils.fixPath(dirs.workingdir .. "/" .. ifid .. "/vlanstats/")
   elseif host_or_network ~= nil and string.starts(host_or_network, 'asn:') then
      host_or_network = string.gsub(host_or_network, 'asn:', '')
      rrdname = os_utils.fixPath(dirs.workingdir .. "/" .. ifid .. "/asnstats/")
   else
      rrdname = os_utils.fixPath(dirs.workingdir .. "/" .. ifid .. "/rrd/")
   end

   if(host_or_network ~= nil) then
      rrdname = rrdname .. getPathFromKey(host_or_network) .. "/"
   end

   return os_utils.fixPath(rrdname..(rrdFile or ''))
end

-- ########################################################

-- label, relative_difference, seconds, graph_tick_step
zoom_vals = {
   { "1m",  "now-60s",  60,            (60)/12 },
   { "5m",  "now-300s", 60*5,          (60*5)/10 },
   { "10m", "now-600s", 60*10,         (60*10)/10 },
   { "1h",  "now-1h",   60*60*1,       (60*60*1)/12 },
   { "3h",  "now-3h",   60*60*3,       (60*60*3)/12 },
   { "6h",  "now-6h",   60*60*6,       (60*60*6)/12 },
   { "12h", "now-12h",  60*60*12,      (60*60*12)/12 },
   { "1d",  "now-1d",   60*60*24,      (60*60*24)/12 },
   { "1w",  "now-1w",   60*60*24*7,    (60*60*24*7)/7 },
   { "2w",  "now-2w",   60*60*24*14,   (60*60*24*14)/14 },
   { "1M",  "now-1mon", 60*60*24*31,   (60*60*24*31)/15 },
   { "6M",  "now-6mon", 60*60*24*31*6, (60*60*24*31*6)/18 },
   { "1Y",  "now-1y",   60*60*24*366,  (60*60*24*366)/12 }
}

function getZoomAtPos(cur_zoom, pos_offset)
  local pos = 1
  local new_zoom_level = cur_zoom
  for k,v in pairs(zoom_vals) do
    if(zoom_vals[k][1] == cur_zoom) then
      if (pos+pos_offset >= 1 and pos+pos_offset < 13) then
	new_zoom_level = zoom_vals[pos+pos_offset][1]
	break
      end
    end
    pos = pos + 1
  end
  return new_zoom_level
end

-- ########################################################

function getZoomDuration(cur_zoom)
   for k,v in pairs(zoom_vals) do
      if(zoom_vals[k][1] == cur_zoom) then
	 return(zoom_vals[k][3])
      end
   end

   return(180)
end

-- ########################################################

function zoomLevel2sec(zoomLevel)
   if(zoomLevel == nil) then zoomLevel = "1h" end

   for k,v in ipairs(zoom_vals) do
      if(zoom_vals[k][1] == zoomLevel) then
	 return(zoom_vals[k][3])
      end
   end

   return(3600) -- NOT REACHED
end

-- ########################################################

function getZoomTicksInterval(cur_zoom)
   for k,v in pairs(zoom_vals) do
      if(zoom_vals[k][1] == cur_zoom) then
	 return(zoom_vals[k][4])
      end
   end

   return(12)
end

-- ########################################################

function getZoomTicksJsArray(start_time, end_time, zoom)
   local parts = {}
   local step = getZoomTicksInterval(zoom)

   for t=start_time,end_time,step do
      parts[#parts+1] = t
   end

   return "[" .. table.concat(parts, ', ') .. "]"
end

-- ########################################################

function drawPeity(ifid, host, rrdFile, zoomLevel, selectedEpoch)
   rrdname = getRRDName(ifid, host, rrdFile)

   if(zoomLevel == nil) then
      zoomLevel = "1h"
   end

   nextZoomLevel = zoomLevel;
   epoch = tonumber(selectedEpoch);

   for k,v in ipairs(zoom_vals) do
      if(zoom_vals[k][1] == zoomLevel) then
	 if(k > 1) then
	    nextZoomLevel = zoom_vals[k-1][1]
	 end
	 if(epoch) then
	    start_time = epoch - zoom_vals[k][3]/2
	    end_time = epoch + zoom_vals[k][3]/2
	 else
	    end_time = os.time()
	    start_time = end_time - zoom_vals[k][3]/2
	 end
      end
   end

   --print("=> Found "..rrdname.."<p>\n")
   if(ntop.notEmptyFile(rrdname)) then
      --io.write("=> Found ".. start_time .. "|" .. end_time .. "<p>\n")
      local fstart, fstep, fnames, fdata = ntop.rrd_fetch(rrdname, 'AVERAGE', start_time, end_time)

      if(fstart ~= nil) then
	 local max_num_points = 512 -- This is to avoid having too many points and thus a fat graph
	 local num_points_found = table.getn(fdata)
	 local sample_rate = round(num_points_found / max_num_points)
	 local num_points = 0
	 local step = 1
	 local series = {}

	 if(sample_rate < 1) then
	    sample_rate = 1
	 end

	 -- print("=> "..num_points_found.."[".. sample_rate .."]["..fstart.."]<p>")

	 id = 0
	 num = 0
	 total = 0
	 sample_rate = sample_rate-1
	 points = {}
	 for i, v in ipairs(fdata) do
	    timestamp = fstart + (i-1)*fstep
	    num_points = num_points + 1

	    local elemId = 1
	    for _, w in ipairs(v) do
	       if(w ~= w) then
		  -- This is a NaN
		  v = 0
	       else
		  v = tonumber(w)
		  if(v < 0) then
		     v = 0
		  end
	       end

	       value = v*8 -- bps

	       total = total + value
	       if(id == sample_rate) then
		  points[num] = round(value)..""
		  num = num+1
		  id = 0
	       else
		  id = id + 1
	       end
	       elemId = elemId + 1
	    end
	 end
      end
   end

   print("<td class=\"text-right\">"..round(total).."</td><td> <span class=\"peity-line\">")
   for i=0,10 do
      if(i > 0) then print(",") end
      print(points[i])
   end
   print("</span>\n")
end

-- ########################################################

function isTopRRD(filename)
   for _,top in ipairs(top_rrds) do
      if top.rrd == filename then
         if not have_nedge or not top.nedge_exclude then
            return true
         else
            return false
         end
      end
   end

   return false
end

function isLayer4RRD(filename)
   for _, l4 in pairs(l4_keys) do
      if filename:starts(l4[2]) or filename:starts(l4[1]) then
	 return true
      end
   end

   return false
end

-- ########################################################

function printTopRRDs(ifid, host, start_time, baseurl, zoomLevel, selectedEpoch)
   local needs_separator = false

   for _,top in ipairs(top_rrds) do
      if have_nedge and top.nedge_exclude then
         goto continue
      end

      if top.separator then
         needs_separator = true
     else
         local k = top.rrd
         local v = top.label

         -- only show if there has been an update within the specified time frame
         local last_update,_ = ntop.rrd_lastupdate(getRRDName(ifid, host, k))

         if last_update ~= nil and last_update >= start_time then
            if needs_separator then
               -- Only add the separator if there are actually some entries in the group
               print('<li class="divider"></li>\n')
               needs_separator = false
            end

            print('<li><a  href="'..baseurl .. '&rrd_file=' .. k .. '&zoom=' .. (zoomLevel or '') .. '&epoch=' .. (selectedEpoch or '') .. '">'.. v ..'</a></li>\n')
         end
      end

      ::continue::
   end
end

-- ########################################################

function drawRRD(ifid, host, rrdFile, zoomLevel, baseurl, show_timeseries,
		 selectedEpoch, selected_epoch_sanitized)
   local debug_rrd = false

   if(zoomLevel == nil) then zoomLevel = "1h" end

   if((selectedEpoch == nil) or (selectedEpoch == "")) then
      -- Refresh the page every minute unless:
      -- ** a specific epoch has been selected or
      -- ** the user is browsing historical top talkers and protocols
      print[[
       <script>
       setInterval(function() {
	 var talkers_loaded, protocols_loaded, flows_loaded;
	 if($('a[href="#historical-top-talkers"]').length){
	   talkers_loaded   = $('a[href="#historical-top-talkers"]').attr("loaded");
	 }
	 if($('a[href="#historical-top-apps"]').length){
	   protocols_loaded = $('a[href="#historical-top-apps"]').attr("loaded");
	 }
	 if($('a[href="#historical-flows"]').length){
	   flows_loaded = $('a[href="#historical-flows"]').attr("loaded");
	 }
	 if(typeof talkers_loaded == 'undefined'
             && typeof protocols_loaded == 'undefined'
             && typeof flows_loaded == 'undefined'){
	   window.location.reload(); /* do not reload, it's annoying */
	 }
       }, 60*1000);
       </script>]]
   end

   if ntop.isPro() then
      _ifstats = interface.getStats()
      drawProGraph(ifid, host, rrdFile, zoomLevel, baseurl, show_timeseries, selectedEpoch, selected_epoch_sanitized)
      return
   end

   dirs = ntop.getDirs()
   rrdname = getRRDName(ifid, host, rrdFile)
   names =  {}
   series = {}

   nextZoomLevel = zoomLevel;
   epoch = tonumber(selectedEpoch);

   for k,v in ipairs(zoom_vals) do
      if(zoom_vals[k][1] == zoomLevel) then
	 if(k > 1) then
	    nextZoomLevel = zoom_vals[k-1][1]
	 end
	 if(epoch ~= nil) then
	    start_time = epoch - zoom_vals[k][3]/2
	    end_time = epoch + zoom_vals[k][3]/2
	 else
	    end_time = os.time()
	    start_time = end_time - zoom_vals[k][3]
	 end
      end
   end

   prefixLabel = l4Label(string.gsub(rrdFile, ".rrd", ""))

   -- io.write(prefixLabel.."\n")
   if(prefixLabel == "Bytes") then
      prefixLabel = "Traffic"
   end

   if(ntop.notEmptyFile(rrdname)) then

      print [[

<style>
#chart_container {
display: inline-block;
font-family: Arial, Helvetica, sans-serif;
}
#chart {
   float: left;
}
#legend {
   float: left;
   margin-left: 15px;
   color: black;
   background: white;
}
#y_axis {
   float: left;
   width: 40px;
}

</style>

<div>

<div class="container-fluid">
  <ul class="nav nav-tabs" role="tablist" id="historical-tabs-container">
    <li class="active"> <a href="#historical-tab-chart" role="tab" data-toggle="tab"> Chart </a> </li>
]]

if ntop.getPrefs().is_dump_flows_to_mysql_enabled
   -- hide historical tabs for networks and pools
   and not string.starts(host, 'net:')
   and not string.starts(host, 'pool:')
   and not string.starts(host, 'vlan:')
   and not string.starts(host, 'asn:')
then
   print('<li><a href="#historical-flows" role="tab" data-toggle="tab" id="tab-flows-summary"> Flows </a> </li>\n')
end

print[[
</ul>


  <div class="tab-content">
    <div class="tab-pane fade active in" id="historical-tab-chart">

<br>
<table border=0>
<tr><td valign="top">
]]


if(show_timeseries == 1) then
   print [[
<div class="btn-group">
  <button class="btn btn-default btn-sm dropdown-toggle" data-toggle="dropdown">Timeseries <span class="caret"></span></button>
  <ul class="dropdown-menu">
]]

   printTopRRDs(ifid, host, start_time, baseurl, zoomLevel, selectedEpoch)

   local dirs = ntop.getDirs()
   local p = dirs.workingdir .. "/" .. purifyInterfaceName(ifid) .. "/rrd/"

   if(host ~= nil) then
      p = p .. getPathFromKey(host)
   end

   local d = os_utils.fixPath(p)

   -- nDPI protocols
   navigatedir(baseurl .. '&zoom=' .. zoomLevel .. '&epoch=' .. (selectedEpoch or '')..'&rrd_file=',
	       "*", d, d, true, ifid, host, start_time, end_time, interface.getnDPIProtocols())

   -- nDPI categories
   navigatedir(baseurl .. '&zoom=' .. zoomLevel .. '&epoch=' .. (selectedEpoch or '')..'&rrd_file=',
	       "*", d, d, true, ifid, host, start_time, end_time, interface.getnDPICategories())

   print [[
  </ul>
</div><!-- /btn-group -->
]]
end -- show_timeseries == 1

print('&nbsp;Timeframe:  <div class="btn-group" data-toggle="buttons" id="graph_zoom">\n')

for k,v in ipairs(zoom_vals) do
   -- display 1 minute button only for networks and interface stats
   -- but exclude applications. Application statistics are gathered
   -- every 5 minutes
   local net_or_profile = false

   if host and (string.starts(host, 'net:')
      or string.starts(host, 'profile:')
      or string.starts(host, 'pool:')
      or string.starts(host, 'vlan:')
      or string.starts(host, 'asn:')) then
       net_or_profile = true
   end
   if zoom_vals[k][1] == '1m' and (net_or_profile or (not net_or_profile and not isTopRRD(rrdFile))) then
       goto continue
   end
   print('<label class="btn btn-link ')

   if(zoom_vals[k][1] == zoomLevel) then
      print("active")
   end
   print('">')
   print('<input type="radio" name="options" id="zoom_level_'..k..'" value="'..baseurl .. '&rrd_file=' .. rrdFile .. '&zoom=' .. zoom_vals[k][1] .. '">'.. zoom_vals[k][1] ..'</input></label>\n')
   ::continue::
end

print [[
</div>
</div>

<script>
   $('input:radio[id^=zoom_level_]').change( function() {
   window.open(this.value,'_self',false);
});
</script>

<br />
<p>


<div id="legend"></div>
<div id="chart_legend"></div>
<div id="chart" style="margin-right: 50px; margin-left: 10px; display: table-cell"></div>
<p><font color=lightgray><small>NOTE: Click on the graph to zoom.</small></font>

</td>


<td rowspan=2>
<div id="y_axis"></div>

<div style="margin-left: 10px; display: table">
<div id="chart_container" style="display: table-row">


]]

if(string.contains(rrdFile, "num_")) then
   formatter_fctn = "fint"
else
   formatter_fctn = "fpackets"
end

rrd = rrd2json(ifid, host, rrdFile, start_time, end_time, true, false) -- the latest false means: expand_interface_views

print [[
   <table class="table table-bordered table-striped" style="border: 0; margin-right: 10px; display: table-cell">
   ]]

print('   <tr><th>&nbsp;</th><th>Time</th><th>Value</th></tr>\n')

if(string.contains(rrdFile, "num_") or string.contains(rrdFile, "tcp_") or string.contains(rrdFile, "packets")  or string.contains(rrdFile, "drops") or string.contains(rrdFile, "flows")) then
   print('   <tr><th>Min</th><td>' .. os.date("%x %X", rrd.minval_time) .. '</td><td>' .. formatValue(rrd.minval) .. '</td></tr>\n')
   print('   <tr><th>Max</th><td>' .. os.date("%x %X", rrd.maxval_time) .. '</td><td>' .. formatValue(rrd.maxval) .. '</td></tr>\n')
   print('   <tr><th>Last</th><td>' .. os.date("%x %X", rrd.lastval_time) .. '</td><td>' .. formatValue(round(rrd.lastval), 1) .. '</td></tr>\n')
   print('   <tr><th>Average</th><td colspan=2>' .. formatValue(round(rrd.average, 2)) .. '</td></tr>\n')
   print('   <tr><th>95th <A HREF=https://en.wikipedia.org/wiki/Percentile>Percentile</A></th><td colspan=2>' .. formatValue(round(rrd.percentile, 2)) .. '</td></tr>\n')
   print('   <tr><th>Total Number</th><td colspan=2>' ..  formatValue(round(rrd.totalval)) .. '</td></tr>\n')
else
   formatter_fctn = "fbits"
   print('   <tr><th>Min</th><td>' .. os.date("%x %X", rrd.minval_time) .. '</td><td>' .. bitsToSize(rrd.minval) .. '</td></tr>\n')
   print('   <tr><th>Max</th><td>' .. os.date("%x %X", rrd.maxval_time) .. '</td><td>' .. bitsToSize(rrd.maxval) .. '</td></tr>\n')
   print('   <tr><th>Last</th><td>' .. os.date("%x %X", rrd.lastval_time) .. '</td><td>' .. bitsToSize(rrd.lastval)  .. '</td></tr>\n')
   print('   <tr><th>Average</th><td colspan=2>' .. bitsToSize(rrd.average*8) .. '</td></tr>\n')
   print('   <tr><th>95th <A HREF=https://en.wikipedia.org/wiki/Percentile>Percentile</A></th><td colspan=2>' .. bitsToSize(rrd.percentile) .. '</td></tr>\n')
   print('   <tr><th>Total Traffic</th><td colspan=2>' .. bytesToSize(rrd.totalval) .. '</td></tr>\n')
end

print('   <tr><th>Selection Time</th><td colspan=2><div id=when></div></td></tr>\n')
print('   <tr><th>Minute<br>Interface<br>Top Talkers</th><td colspan=2><div id=talkers></div></td></tr>\n')


print [[
   </table>
]]

print[[</div></td></tr></table>

    </div> <!-- closes div id "historical-tab-chart "-->
]]

if ntop.getPrefs().is_dump_flows_to_mysql_enabled
   -- hide historical tabs for networks and profiles and pools
   and not string.starts(host, 'net:')
   and not string.starts(host, 'pool:')
   and not string.starts(host, 'vlan:')
   and not string.starts(host, 'asn:')
then
   local k2info = hostkey2hostinfo(host)

   print('<div class="tab-pane fade" id="historical-flows">')
   if tonumber(start_time) ~= nil and tonumber(end_time) ~= nil then
      -- if both start_time and end_time are vaid epoch we can print finer-grained top flows
      historicalFlowsTab(ifid, k2info["host"] or '', start_time, end_time, rrdFile, '', '', '', k2info["vlan"])
   else
      printGraphTopFlows(ifid, k2info["host"] or '', _GET["epoch"], zoomLevel, rrdFile, k2info["vlan"])
   end
   print('</div>')
end

print[[
  </div> <!-- closes div class "tab-content" -->
</div> <!-- closes div class "container-fluid" -->

<script>

var palette = new Rickshaw.Color.Palette();

var graph = new Rickshaw.Graph( {
				   element: document.getElementById("chart"),
				   width: 600,
				   height: 300,
				   renderer: 'area',
				   series:
				]]

print(rrd.json)

print [[
				} );

graph.render();

var chart_legend = document.querySelector('#chart_legend');


function fdate(when) {
      var epoch = when*1000;
      var d = new Date(epoch);

      return(d);
}

function capitaliseFirstLetter(string)
{
   return string.charAt(0).toUpperCase() + string.slice(1);
}

/**
 * Convert number of bytes into human readable format
 *
 * @param integer bytes     Number of bytes to convert
 * @param integer precision Number of digits after the decimal separator
 * @return string
 */
   function formatBytes(bytes, precision)
      {
	 var kilobyte = 1024;
	 var megabyte = kilobyte * 1024;
	 var gigabyte = megabyte * 1024;
	 var terabyte = gigabyte * 1024;

	 if((bytes >= 0) && (bytes < kilobyte)) {
	    return bytes + ' B';
	 } else if((bytes >= kilobyte) && (bytes < megabyte)) {
	    return (bytes / kilobyte).toFixed(precision) + ' KB';
	 } else if((bytes >= megabyte) && (bytes < gigabyte)) {
	    return (bytes / megabyte).toFixed(precision) + ' MB';
	 } else if((bytes >= gigabyte) && (bytes < terabyte)) {
	    return (bytes / gigabyte).toFixed(precision) + ' GB';
	 } else if(bytes >= terabyte) {
	    return (bytes / terabyte).toFixed(precision) + ' TB';
	 } else {
	    return bytes + ' B';
	 }
      }

var Hover = Rickshaw.Class.create(Rickshaw.Graph.HoverDetail, {
    graph: graph,
    xFormatter: function(x) { return new Date( x * 1000 ); },
    yFormatter: function(bits) { return(]] print(formatter_fctn) print [[(bits)); },
    render: function(args) {
		var graph = this.graph;
		var points = args.points;
		var point = points.filter( function(p) { return p.active } ).shift();

		if(point.value.y === null) return;

		var formattedXValue = fdate(point.value.x); // point.formattedXValue;
		var formattedYValue = ]]
	  print(formatter_fctn)
	  print [[(point.value.y); // point.formattedYValue;
		var infoHTML = "";
]]

print[[

infoHTML += "<ul>";
$.ajax({
	  type: 'GET',
	  url: ']]
	  print(ntop.getHttpPrefix().."/lua/get_top_talkers.lua?epoch='+point.value.x+'&addvlan=true")
	    print [[',
		  data: { epoch: point.value.x },
		  async: false,
		  success: function(content) {
		   var info = jQuery.parseJSON(content);
		   $.each(info, function(i, n) {
		     if (n.length > 0)
		       infoHTML += "<li>"+capitaliseFirstLetter(i)+" [Avg Traffic/sec]<ol>";
		     var items = 0;
		     var other_traffic = 0;
		     $.each(n, function(j, m) {
		       if(items < 3) {
			 infoHTML += "<li><a href='host_details.lua?host="+m.address+"'>"+abbreviateString(m.label ? m.label : m.address,24);
		       infoHTML += "</a>";
		       if (m.vlan != "0") infoHTML += " ("+m.vlanm+")";
		       infoHTML += " ("+fbits((m.value*8)/60)+")</li>";
			 items++;
		       } else
			 other_traffic += m.value;
		     });
		     if (other_traffic > 0)
			 infoHTML += "<li>Other ("+fbits((other_traffic*8)/60)+")</li>";
		     if (n.length > 0)
		       infoHTML += "</ol></li>";
		   });
		   infoHTML += "</ul></li></li>";
	   }
   });
infoHTML += "</ul>";]]

print [[
		this.element.innerHTML = '';
		this.element.style.left = graph.x(point.value.x) + 'px';

		/*var xLabel = document.createElement('div');
		xLabel.setAttribute("style", "opacity: 0.5; background-color: #EEEEEE; filter: alpha(opacity=0.5)");
		xLabel.className = 'x_label';
		xLabel.innerHTML = formattedXValue + infoHTML;
		this.element.appendChild(xLabel);
		*/
		$('#when').html(formattedXValue);
		$('#talkers').html(infoHTML);


		var item = document.createElement('div');

		item.className = 'item';
		item.innerHTML = this.formatter(point.series, point.value.x, point.value.y, formattedXValue, formattedYValue, point);
		item.style.top = this.graph.y(point.value.y0 + point.value.y) + 'px';
		this.element.appendChild(item);

		var dot = document.createElement('div');
		dot.className = 'dot';
		dot.style.top = item.style.top;
		dot.style.borderColor = point.series.color;
		this.element.appendChild(dot);

		if(point.active) {
			item.className = 'item active';
			dot.className = 'dot active';
		}

		this.show();

		if(typeof this.onRender == 'function') {
			this.onRender(args);
		}

		// Put the selected graph epoch into the legend
		//chart_legend.innerHTML = point.value.x; // Epoch

		this.selected_epoch = point.value.x;

		//event
	}
} );

var hover = new Hover( { graph: graph } );

var legend = new Rickshaw.Graph.Legend( {
					   graph: graph,
					   element: document.getElementById('legend')
					} );

//var axes = new Rickshaw.Graph.Axis.Time( { graph: graph } ); axes.render();

var yAxis = new Rickshaw.Graph.Axis.Y({
    graph: graph,
    tickFormat: ]] print(formatter_fctn) print [[
});

yAxis.render();

$("#chart").click(function() {
  if(hover.selected_epoch)
    window.location.href = ']]
print(baseurl .. '&rrd_file=' .. rrdFile .. '&zoom=' .. nextZoomLevel .. '&epoch=')
print[['+hover.selected_epoch;
});

</script>

]]
else
   print("<div class=\"alert alert-danger\"><img src=".. ntop.getHttpPrefix() .. "/img/warning.png> File "..rrdname.." cannot be found</div>")
end
end

function createRRDcounter(path, step, verbose)
   if(not(ntop.exists(path))) then
      if(verbose) then print('Creating RRD ', path, '\n') end
      local prefs = ntop.getPrefs()
      local hb = step * 5 -- keep it aligned with rrd_utils.makeRRD
      ntop.rrd_create(
	 path,
	 step, -- step
	 'DS:sent:DERIVE:'..hb..':U:U',
	 'DS:rcvd:DERIVE:'..hb..':U:U',
	 'RRA:AVERAGE:0.5:1:'..tostring(prefs.other_rrd_raw_days*24*(3600/step)),  -- raw: 1 day = 1 * 24 = 24 * 12 = 288
	 'RRA:AVERAGE:0.5:'..(3600/step)..':'..tostring(prefs.other_rrd_1h_days*24), -- 1h resolution (12 points)   2400 hours = 100 days
	 'RRA:AVERAGE:0.5:'..(86400/step)..':'..tostring(prefs.other_rrd_1d_days) -- 1d resolution (288 points)  365 days
	 --'RRA:HWPREDICT:1440:0.1:0.0035:20'
      )
   end
end

-- ########################################################

function createSingleRRDcounter(path, step, verbose)
   if(not(ntop.exists(path))) then
      if(verbose) then print('Creating RRD ', path, '\n') end
      local prefs = ntop.getPrefs()
      local hb = step * 5 -- keep it aligned with rrd_utils.makeRRD
      ntop.rrd_create(
	 path,
	 step, -- step
	 'DS:num:DERIVE:'..hb..':U:U',
	 'RRA:AVERAGE:0.5:1:'..tostring(prefs.other_rrd_raw_days*24*(3600/step)),  -- raw: 1 day = 1 * 24 = 24 * 12 = 288
	 'RRA:AVERAGE:0.5:'..(3600/step)..':'..tostring(prefs.other_rrd_1h_days*24), -- 1h resolution (12 points)   2400 hours = 100 days
	 'RRA:AVERAGE:0.5:'..(86400/step)..':'..tostring(prefs.other_rrd_1d_days) -- 1d resolution (288 points)  365 days
	 -- 'RRA:HWPREDICT:1440:0.1:0.0035:20'
	 )
   end
end

-- ########################################################
-- this method will be very likely used when saving subnet rrd traffic statistics
function createTripleRRDcounter(path, step, verbose)
   if(not(ntop.exists(path))) then
      if(verbose) then io.write('Creating RRD '..path..'\n') end
      local prefs = ntop.getPrefs()
      local hb = step * 5 -- keep it aligned with rrd_utils.makeRRD
      ntop.rrd_create(
	 path,
	 step, -- step
	 'DS:ingress:DERIVE:'..hb..':U:U',
	 'DS:egress:DERIVE:'..hb..':U:U',
	 'DS:inner:DERIVE:'..hb..':U:U',
	 'RRA:AVERAGE:0.5:1:'..tostring(prefs.other_rrd_raw_days*24*(3600/step)),  -- raw: 1 day = 1 * 24 = 24 * 12 = 288
	 'RRA:AVERAGE:0.5:12:'..tostring(prefs.other_rrd_1h_days*24), -- 1h resolution (12 points)   2400 hours = 100 days
	 'RRA:AVERAGE:0.5:288:'..tostring(prefs.other_rrd_1d_days) -- 1d resolution (288 points)  365 days
	 --'RRA:HWPREDICT:1440:0.1:0.0035:20'
      )
   end
end

function printGraphTopFlows(ifId, host, epoch, zoomLevel, l7proto, vlan)
   -- Check if the DB is enabled
   rsp = interface.execSQLQuery("show tables")
   if(rsp == nil) then return end

   if((epoch == nil) or (epoch == "")) then epoch = os.time() end

   local d = getZoomDuration(zoomLevel)

   epoch_end = epoch
   epoch_begin = epoch-d

   historicalFlowsTab(ifId, host, epoch_begin, epoch_end, l7proto, '', '', '', vlan)
end

-- ########################################################

-- Make sure we do not fetch data from RRDs that have been update too much long ago
-- as this creates issues with the consolidation functions when we want to compare
-- results coming from different RRDs.
-- This is also needed to make sure that multiple data series on graphs have the
-- same number of points, otherwise d3js will generate errors.
function touchRRD(rrdname)
   local now  = os.time()
   local last, ds_count = ntop.rrd_lastupdate(rrdname)

   if((last ~= nil) and ((now-last) > 3600)) then
      local tdiff = now - 1800 -- This avoids to set the update continuously

      if(ds_count == 1) then
	 ntop.rrd_update(rrdname, tdiff.."", "0")
      elseif(ds_count == 2) then
	 ntop.rrd_update(rrdname, tdiff.."", "0", "0")
      elseif(ds_count == 3) then
	 ntop.rrd_update(rrdname, tdiff.."", "0", "0", "0")
      end

   end
end

-- ########################################################

-- Find the percentile of a list of values
-- N - A list of values.  N must be sorted.
-- P - A float value from 0.0 to 1.0
local function percentile(N, P)
   local n = math.floor(math.floor(P * #N + 0.5))
   return(N[n-1])
end

local function ninetififthPercentile(N)
   table.sort(N) -- <<== Sort first
   return(percentile(N, 0.95))
end

-- ########################################################

-- reads one or more RRDs and returns a json suitable to feed rickshaw

function singlerrd2json(ifid, host, rrdFile, start_time, end_time, rickshaw_json, append_ifname_to_labels, transform_columns_function)
   local rrdname = getRRDName(ifid, host, rrdFile)
   local names =  {}
   local names_cache = {}
   local series = {}
   local prefixLabel = l4Label(string.gsub(rrdFile, ".rrd", ""))
   -- with a scaling factor we can stretch or shrink rrd values
   -- by default we set this to a value of 8, in order to convert bytes
   -- rrds into bits.
   local scaling_factor = 8

   touchRRD(rrdname)
   --io.write(prefixLabel.."\n")

   if(prefixLabel == "Bytes") then
      prefixLabel = "Traffic"
   end

   if(string.contains(rrdFile, "num_") or string.contains(rrdFile, "tcp_") or string.contains(rrdFile, "packets") or string.contains(rrdFile, "drops") or string.contains(rrdFile, "flows")) then
      -- do not scale number, packets, and drops
      scaling_factor = 1
   end

   if(not ntop.notEmptyFile(rrdname)) then return '{}' end

   local fstart, fstep, fnames, fdata = ntop.rrd_fetch(rrdname, 'AVERAGE', start_time, end_time)
   if(fstart == nil) then return '{}' end

   if transform_columns_function ~= nil then
      --~ tprint(rrdname)
      fstart, fstep, fnames, fdata, prefixLabel = transform_columns_function(fstart, fstep, fnames, fdata)
      prefixLabel = prefixLabel or ""
   end

   --[[
   io.write('start time: '..start_time..'  end_time: '..end_time..'\n')
   io.write('fstart: '..fstart..'  fstep: '..fstep..' rrdname: '..rrdname..'\n')
   io.write('len(fdata): '..table.getn(fdata)..'\n')
   --]]
   local max_num_points = 600 -- This is to avoid having too many points and thus a fat graph

   if tonumber(global_max_num_points) ~= nil then
      max_num_points = global_max_num_points
   end

   local num_points_found = table.getn(fdata)
   local sample_rate = round(num_points_found / max_num_points)
   local port_mode = false

   if(sample_rate < 1) then sample_rate = 1 end
   
   -- Pretty printing for flowdevs/a.b.c.d/e.rrd
   local elems = split(prefixLabel, "/")
   if((elems[#elems] ~= nil) and (#elems > 1)) then
      prefixLabel = capitalize(elems[#elems] or "")
      port_mode = true
   end
   
   -- prepare rrd labels
   local protocol_categories = interface.getnDPICategories()
   for i, n in ipairs(fnames) do
      -- handle duplicates
      if (names_cache[n] == nil) then
	 local extra_info = ''
	 names_cache[n] = true
	 if append_ifname_to_labels then
	     extra_info = getInterfaceName(ifid)
	 end

	 if host ~= nil and not string.starts(host, 'profile:')
	    and protocol_categories[prefixLabel] == nil then
	     extra_info = extra_info..firstToUpper(n)
	 end

	 if string.starts(host, 'asn:') then
	    extra_info = extra_info.." by AS"
	 end

	 if extra_info ~= "" and extra_info ~= prefixLabel then
	    if(port_mode) then
	       if(#names == 0) then
		  names[#names+1] = prefixLabel.." Egress ("..extra_info..") "
	       else
		  names[#names+1] = prefixLabel.." Ingress ("..extra_info..") "
	       end
	    elseif prefixLabel ~= "" then
	       names[#names+1] = prefixLabel.." ("..extra_info..") "
	    else
	       names[#names+1] = extra_info
	    end
	 else
	     names[#names+1] = prefixLabel
	 end
      end
    end

   local minval, maxval, lastval = 0, 0, 0
   local maxval_time, minval_time, lastval_time = nil, nil, nil
   local first_time, last_time = nil, nil
   local sampling = 1
   local s = {}
   local totalval, avgval = {}, {}
   local now = os.time()

   for i, v in ipairs(fdata) do
      local instant = fstart + i * fstep  -- this is the instant in time corresponding to the datapoint
      if instant > now then break end

      s[0] = instant  -- s holds the instant and all the values
      totalval[instant] = 0  -- totalval holds the sum of all values of this instant
      avgval[instant] = 0

      local elemId = 1
      for _, w in ipairs(v) do

	 if(w ~= w) then
	    -- This is a NaN
	    w = 0
	 else
	    -- io.write(w.."\n")
	    w = tonumber(w)
	    if(w < 0) then
	       w = 0
	    end
	 end

	 -- update the total value counter, which is the non-scaled integral over time
	 totalval[instant] = totalval[instant] + w * fstep
	 -- also update the average val (do not multiply by fstep, this is not the integral)
	 avgval[instant] = avgval[instant] + w
	 -- and the scaled current value (remember that these are derivatives)
	 w = w * scaling_factor
	 -- the scaled current value w goes into its own element elemId
	 if (s[elemId] == nil) then s[elemId] = 0 end
	 s[elemId] = s[elemId] + w
	 --if(s[elemId] > 0) then io.write("[".. elemId .. "]=" .. s[elemId] .."\n") end
	 elemId = elemId + 1
      end

      last_time = instant
      if(first_time == nil) then first_time = instant end
	 
      -- stops every sample_rate samples, or when there are no more points
      if(sampling == sample_rate or num_points_found == i) then
	 local sample_sum = 0
	 for elemId=1,#s do
	    -- calculate the average in the sampling period
	    s[elemId] = s[elemId] / sampling
	    sample_sum = sample_sum + s[elemId]
	 end
	 -- update last instant
	 if lastval_time == nil or instant > lastval_time then
	    lastval = sample_sum
	    lastval_time = instant
	 end
	 -- possibly update maximum value (grab the most recent in case of a tie)
	 if maxval_time == nil or (sample_sum >= maxval and instant > maxval_time) then
	    maxval = sample_sum
	    maxval_time = instant
	 end
	 -- possibly update the minimum value (grab the most recent in case of a tie)
	 if minval_time == nil or (sample_sum <= minval and instant > minval_time) then
	    minval = sample_sum
	    minval_time = instant
	 end
	 series[#series+1] = s
	 sampling = 1
	 s = {}
     else
	 sampling = sampling + 1
      end
   end

   local tot = 0
   for k, v in pairs(totalval) do
      tot = tot + v
   end

   local vals = {}
   for k, v in pairs(series) do
      if(v[2] ~= nil) then
	 -- io.write(v[1]+v[2].."\n")
	 table.insert(vals, v[1]+v[2])
      else
	 -- io.write(v[1].."\n")
	 table.insert(vals, v[1])
      end
   end
   
   totalval = tot
   tot = 0
   for k, v in pairs(avgval) do tot = tot + v end
   local average = tot / num_points_found
   local percentile = ninetififthPercentile(vals)

   -- io.write("percentile="..percentile.."\n")
   local colors = {
      '#1f77b4',
      '#ff7f0e',
      '#2ca02c',
      '#d62728',
      '#9467bd',
      '#8c564b',
      '#e377c2',
      '#7f7f7f',
      '#bcbd22',
      '#17becf',
      -- https://github.com/mbostock/d3/wiki/Ordinal-Scales
      '#ff7f0e',
      '#ffbb78',
      '#1f77b4',
      '#aec7e8',
      '#2ca02c',
      '#98df8a',
      '#d62728',
      '#ff9896',
      '#9467bd',
      '#c5b0d5',
      '#8c564b',
      '#c49c94',
      '#e377c2',
      '#f7b6d2',
      '#7f7f7f',
      '#c7c7c7',
      '#bcbd22',
      '#dbdb8d',
      '#17becf',
      '#9edae5'
   }

   if(names ~= nil) then
      json_ret = ''

      if(rickshaw_json) then
	 for elemId=1,#names do
	    if(elemId > 1) then
	       json_ret = json_ret.."\n,\n"
	    end
	    local name = names[elemId]
	    json_ret = json_ret..'{"name": "'.. name .. '",\n'
	    json_ret = json_ret..'color: \''.. colors[elemId] ..'\',\n'
	    json_ret = json_ret..'"data": [\n'
	    n = 0
	    for key, value in pairs(series) do
	       if(n > 0) then
		  json_ret = json_ret..',\n'
	       end
	       json_ret = json_ret..'\t{ "x": '..  value[0] .. ', "y": '.. value[elemId] .. '}'
	       n = n + 1
	    end

	    json_ret = json_ret.."\n]}\n"
	 end
      else
	 -- NV3
	 local num_entries = 0;

	 for elemId=1,#names do
	    num_entries = num_entries + 1
	    if(elemId > 1) then
	       json_ret = json_ret.."\n,\n"
	    end
	    name = names[elemId]

	    json_ret = json_ret..'{"key": "'.. name .. '",\n'
--	    json_ret = json_ret..'"color": "'.. colors[num_entries] ..'",\n'
	    json_ret = json_ret..'"area": true,\n'
	    json_ret = json_ret..'"values": [\n'
	    n = 0
	    for key, value in pairs(series) do
	       if(n > 0) then
		  json_ret = json_ret..',\n'
	       end
	       json_ret = json_ret..'\t[ '..value[0] .. ', '.. value[elemId] .. ' ]'
	       --json_ret = json_ret..'\t{ "x": '..  value[0] .. ', "y": '.. value[elemId] .. '}'
	       n = n + 1
	    end

	    json_ret = json_ret.."\n] }\n"
	 end

	 if(false) then
	    json_ret = json_ret..",\n"

	    num_entries = num_entries + 1
	    json_ret = json_ret..'\n{"key": "Average",\n'
	    json_ret = json_ret..'"color": "'.. colors[num_entries] ..'",\n'
	    json_ret = json_ret..'"type": "line",\n'

	    json_ret = json_ret..'"values": [\n'
	    n = 0
	    for key, value in pairs(series) do
	       if(n > 0) then
		  json_ret = json_ret..',\n'
	       end
	       --json_ret = json_ret..'\t[ '..value[0] .. ', '.. value[elemId] .. ' ]'
	       json_ret = json_ret..'\t{ "x": '..  value[0] .. ', "y": '.. average .. '}'
	       n = n + 1
	    end
	    json_ret = json_ret..'\n] },\n'


	    num_entries = num_entries + 1
	    json_ret = json_ret..'\n{"key": "95th Percentile",\n'
	    json_ret = json_ret..'"color": "'.. colors[num_entries] ..'",\n'
	    json_ret = json_ret..'"type": "line",\n'
	    json_ret = json_ret..'"yAxis": 1,\n'
	    json_ret = json_ret..'"values": [\n'
	    n = 0
	    for key, value in pairs(series) do
	       if(n > 0) then
		  json_ret = json_ret..',\n'
	       end
	       --json_ret = json_ret..'\t[ '..value[0] .. ', '.. value[elemId] .. ' ]'
	       json_ret = json_ret..'\t{ "x": '..  value[0] .. ', "y": '.. percentile .. '}'
	       n = n + 1
	    end

	    json_ret = json_ret..'\n] }\n'
	 end
      end
   end

   local ret = {}
   ret.maxval_time = maxval_time
   ret.maxval = round(maxval, 0)

   ret.minval_time = minval_time
   ret.minval = round(minval, 0)

   ret.lastval_time = lastval_time
   ret.lastval = round(lastval, 0)

   ret.totalval = round(totalval, 0)
   ret.percentile = round(percentile, 0)
   ret.average = round(average, 0)
   ret.json = json_ret

   if(last_time ~= nil) then
     ret.duration = last_time - first_time
   else
     ret.duration = 1
   end

  return(ret)
end

-- #################################################

function rrd2json_merge(ret, num)
   -- if we are expanding an interface view, we want to concatenate
   -- jsons for single interfaces, and not for the view. Since view statistics
   -- are in ret[1], it suffices to aggregate jsons from index i >= 2
   local json = "["
   local first = true  -- used to decide where to append commas

   -- sort by "totalval" to get the top "num" results
   local by_totalval = {}
   local totalval = 0
   local minval = 0
   for i = 1, #ret do
      by_totalval[i] = ret[i].totalval
      -- update total
      totalval = totalval + ret[i].totalval
   end

   local ctr = 0

   for i,_ in pairsByValues(by_totalval, rev) do
      if ctr >= num then break end
      if(debug_metric) then io.write("->"..i.."\n") end
      if not first then json = json.."," end
      json = json..ret[i].json
      first = false
      ctr = ctr + 1
   end
   json = json.."]"
   -- the (possibly aggregated) json always goes into ret[1]
   -- ret[1] possibly contains aggregated view statistics such as
   -- maxval and maxval_time or minval and minval_time
   ret[1].json = json

   if #ret > 1 then
      -- update the total with the sum of the totals of each timeseries
      ret[1].totalval = totalval
      -- remove metrics that are no longer valid for merged rrds
      for _, k in pairs({'average',
			 'minval', 'minval_time',
			 'maxval', 'maxval_time',
			 'lastval', 'lastval_time', 'percentile'}) do
	 ret[1][k] = nil
      end
   end

   -- io.write(json.."\n")
   return(ret[1])
end

function rrd2json(ifid, host, rrdFile, start_time, end_time, rickshaw_json, expand_interface_views)
   local ret = {}
   local num = 0
   local debug_metric = false

   interface.select(getInterfaceName(ifid))
   local ifstats = interface.getStats()
   local rrd_if_ids = {}  -- read rrds for interfaces listed here
   rrd_if_ids[1] = ifid -- the default submitted interface
   -- interface.select(getInterfaceName(ifid))

   if(debug_metric) then
       io.write('ifid: '..ifid..' ifname:'..getInterfaceName(ifid)..'\n')
       io.write('expand_interface_views: '..tostring(expand_interface_views)..'\n')
   end

   if(debug_metric) then io.write("RRD File: "..rrdFile.."\n") end

   -- the following code is used to compute stacked charts of top protocols and applications
   if(rrdFile == "all" or rrdFile == "all_ndpi_categories") then -- all means all l-7 applications
       -- disable expand interface views for rrdFile == all
       local expand_interface_views = false
       local dirs = ntop.getDirs()
       local d = getRRDName(ifid, host)

       if(debug_metric) then io.write("Navigating: "..p.."\n") end

       local ndpi_protocols = interface.getnDPIProtocols()
       local ndpi_categories = interface.getnDPICategories()
       local filter = ndpi_protocols
       if rrdFile == "all_ndpi_categories" then filter = ndpi_categories end

       local rrds = navigatedir("", "*", d, d, false, ifid, host, start_time, end_time, filter)

       local traffic_array = {}

       for key, value in pairs(rrds) do
	  local rsp = singlerrd2json(ifid, host, value, start_time, end_time, rickshaw_json, expand_interface_views)
	  if(rsp.totalval ~= nil) then total = rsp.totalval else total = 0 end

	  if(total > 0) then
	     traffic_array[total] = rsp
	     if(debug_metric) then io.write("Analyzing: "..value.." [total "..total.."]\n") end
	  end

	  ::continue::
       end

       for key, value in pairsByKeys(traffic_array, rev) do
	   ret[#ret+1] = value
	   if(ret[#ret].json ~= nil) then
	       if(debug_metric) then io.write(key.."\n") end
	       num = num + 1
	       if(num >= 10) then break end
	   end
       end
   else
       num = 0
       for _,iface in pairs(rrd_if_ids) do
	   if(debug_metric) then io.write('iface: '..iface..'\n') end
	    for i,rrd in pairs(split(rrdFile, ",")) do
		if(debug_metric) then io.write("["..i.."] "..rrd..' iface: '..iface.."\n") end
		ret[#ret + 1] = singlerrd2json(iface, host, rrd, start_time, end_time, rickshaw_json, expand_interface_views)
		if(ret[#ret].json ~= nil) then num = num + 1 end
	    end
       end

   end

   if(debug_metric) then io.write("#rrds="..num.."\n") end
   if(num == 0) then
      ret = {}
      ret.json = "[]"
      return(ret)
   end

   return rrd2json_merge(ret, num)
end

-- #################################################

function showHostActivityStats(hostbase, selectedEpoch, zoomLevel)
   local activbase = hostbase .. "/activity"
   local nextZoomLevel = zoomLevel;
   local start_time, end_time
   
   if ntop.isdir(activbase) then
      local epoch = tonumber(selectedEpoch)

      -- TODO separate function and join drawPeity
      for k,v in ipairs(zoom_vals) do
         if(zoom_vals[k][1] == zoomLevel) then
            if(k > 1) then
               nextZoomLevel = zoom_vals[k-1][1]
            end
            if(epoch) then
               start_time = epoch - zoom_vals[k][3]/2
               end_time = epoch + zoom_vals[k][3]/2
            else
               end_time = os.time()
               start_time = end_time - zoom_vals[k][3]/2
            end
         end
      end
   
      for key,value in pairs(ntop.readdir(activbase)) do
         local activrrd = activbase .. "/" .. key;

         if(ntop.notEmptyFile(activrrd)) then
            local fstart, fstep, fnames, fdata = ntop.rrd_fetch(activrrd, 'AVERAGE', start_time, end_time)
            local num_points = table.getn(fdata)

            print(value.."["..num_points.." points] start="..formatEpoch(start)..", step="..fstep.."s<br><b>")

            for i, v in ipairs(fdata) do
               for _, w in ipairs(v) do
                  if(w ~= w) then
                     -- This is a NaN
                     v = 0
                  else
                     --io.write(w.."\n")
                     v = tonumber(w)
                     if(v < 0) then
                        v = 0
                     end
                  end
               end
               print(round(v, 2).." ")
            end
            
            print("</b><br>")
         end
      end
   end
end

-- #################################################

--
-- proto table should contain the following information:
--    string   traffic_quota
--    string   time_quota
--    string   protoName
--
-- ndpi_stats or category_stats can be nil if they are not relevant for the proto
--
-- quotas_to_show can contain:
--    bool  traffic
--    bool  time
--
function printProtocolQuota(proto, ndpi_stats, category_stats, quotas_to_show, show_td, hide_limit)
    local total_bytes = 0
    local total_duration = 0
    local output = {}

    if ndpi_stats ~= nil then
      -- This is a single protocol
      local proto_stats = ndpi_stats[proto.protoName]
      if proto_stats ~= nil then
        total_bytes = proto_stats["bytes.sent"] + proto_stats["bytes.rcvd"]
        total_duration = proto_stats["duration"]
      end
    else
      -- This is a category
      local cat_stats = category_stats[proto.protoName]
      if cat_stats ~= nil then
        total_bytes = cat_stats["bytes"]
        total_duration = cat_stats["duration"]
      end
    end

    if quotas_to_show.traffic then
      local bytes_exceeded = ((proto.traffic_quota ~= "0") and (total_bytes >= tonumber(proto.traffic_quota)))
      local lb_bytes = bytesToSize(total_bytes)
      local lb_bytes_quota = ternary(proto.traffic_quota ~= "0", bytesToSize(tonumber(proto.traffic_quota)), i18n("unlimited"))
      local traffic_taken = ternary(proto.traffic_quota ~= "0", math.min(total_bytes, proto.traffic_quota), 0)
      local traffic_remaining = math.max(proto.traffic_quota - traffic_taken, 0)
      local traffic_quota_ratio = round(traffic_taken * 100 / (traffic_taken+traffic_remaining), 0)

      if show_td then
        output[#output + 1] = [[<td class='text-right']]..ternary(bytes_exceeded, ' style=\'color:red;\'', '').."><span>"..lb_bytes..ternary(hide_limit, "", " / "..lb_bytes_quota).."</span>"
      end
      output[#output + 1] = [[
          <div class='progress' style=']]..(quotas_to_show.traffic_style or "")..[['>
            <div class='progress-bar progress-bar-warning' aria-valuenow=']]..traffic_quota_ratio..'\' aria-valuemin=\'0\' aria-valuemax=\'100\' style=\'width: '..traffic_quota_ratio..'%;\'>'..
              ternary(traffic_quota_ratio == traffic_quota_ratio --[[nan check]], traffic_quota_ratio, 0)..[[%
            </div>
          </div>]]
      if show_td then output[#output + 1] = ("</td>") end
    end

    if quotas_to_show.time then
      local time_exceeded = ((proto.time_quota ~= "0") and (total_duration >= tonumber(proto.time_quota)))
      local lb_duration = secondsToTime(total_duration)
      local lb_duration_quota = ternary(proto.time_quota ~= "0", secondsToTime(tonumber(proto.time_quota)), i18n("unlimited"))
      local duration_taken = ternary(proto.time_quota ~= "0", math.min(total_duration, proto.time_quota), 0)
      local duration_remaining = math.max(proto.time_quota - duration_taken, 0)
      local duration_quota_ratio = round(duration_taken * 100 / (duration_taken+duration_remaining), 0)

      if show_td then
        output[#output + 1] = [[<td class='text-right']]..ternary(time_exceeded, ' style=\'color:red;\'', '').."><span>"..lb_duration..ternary(hide_limit, "", " / "..lb_duration_quota).."</span>"
      end

      output[#output + 1] = ([[
          <div class='progress' style=']]..(quotas_to_show.time_style or "")..[['>
            <div class='progress-bar progress-bar-warning' aria-valuenow=']]..duration_quota_ratio..'\' aria-valuemin=\'0\' aria-valuemax=\'100\' style=\'width: '..duration_quota_ratio..'%;\'>'..
              ternary(duration_quota_ratio == duration_quota_ratio --[[nan check]], duration_quota_ratio, 0)..[[%
            </div>
          </div>]])
      if show_td then output[#output + 1] = ("</td>") end
    end

    return table.concat(output, '')
end

-- #################################################

function poolDropdown(ifId, pool_id, exclude)
   local output = {}
   --exclude = exclude or {[host_pools_utils.DEFAULT_POOL_ID]=true}
   exclude = exclude or {}

   for _,pool in ipairs(host_pools_utils.getPoolsList(ifId)) do
      if (not exclude[pool.id]) or (pool.id == pool_id) then
         output[#output + 1] = '<option value="' .. pool.id .. '"'

         if pool.id == pool_id then
            output[#output + 1] = ' selected'
         end

         local limit_reached = false

         if not ntop.isEnterprise() then
            local n_members = table.len(host_pools_utils.getPoolMembers(ifId, pool.id) or {})

            if n_members >= host_pools_utils.LIMITED_NUMBER_POOL_MEMBERS then
               limit_reached = true
            end
         end

         if exclude[pool.id] or limit_reached then
            output[#output + 1] = ' disabled'
         end

         output[#output + 1] = '>' .. pool.name .. ternary(limit_reached, " ("..i18n("host_pools.members_limit_reached")..")", "") .. '</option>'
      end
   end

   return table.concat(output, '')
end

function printPoolChangeDropdown(ifId, pool_id, have_nedge)
   local output = {}

   output[#output + 1] = [[<tr>
      <th>]] .. i18n(ternary(have_nedge, "nedge.user", "host_config.host_pool")) .. [[</th>
      <td>
            <select name="pool" class="form-control" style="width:20em; display:inline;">]]

   output[#output + 1] = poolDropdown(ifId, pool_id)

   local edit_pools_link = ternary(have_nedge, "/lua/pro/nedge/admin/nf_list_users.lua", "/lua/if_stats.lua?page=pools#create")

   output[#output + 1] = [[
            </select>&nbsp;
        <A HREF="]] .. ntop.getHttpPrefix() .. edit_pools_link .. [["><i class="fa fa-sm fa-cog" aria-hidden="true" title="]]
      ..i18n(ternary(have_nedge, "nedge.edit_users", "host_pools.edit_host_pools"))
      .. [["></i> ]]
      .. i18n(ternary(have_nedge, "nedge.edit_users", "host_pools.edit_host_pools"))
      .. [[</A>
   </tr>]]

   print(table.concat(output, ''))
end
