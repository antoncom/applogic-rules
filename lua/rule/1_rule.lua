local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"


local rule = {}
local rule_setting = {

	title = {
		input = "Переключение CPE Agent на резервный хост.",
	},

	cpe_status = {
		note = [[ Статус CPE Agent. Если включен - возвращает "OK". ]],
		source = {
			type = "ubus",
			object = "cpeagent",
			method = "status"
		},
		modifier = {
			--["1_func"] = [[ if string.len('$cpe_status') > 0 then return "OK" else return "" ]],
			["1_func"] = [[ if string.len('$cpe_status') > 0 then return "OK" else return "" end ]],
			["2_frozen"] = "5"
		}
	},

	cpe_host = {
		note = [[ Адрес активного хоста брокера CPE ]],
		source = {
			type = "ubus",
			object = "cpeagent",
			method = "status"
		},
		modifier = {
			["1_skip"] = [[
				local CPE_ACTIVE = ('$cpe_status' ~= '')
				return (not CPE_ACTIVE)
			]],
			["2_bash"] = [[ jsonfilter -e '$.broker.host' ]],
			["3_frozen"] = "10"
		}
	},

	cpe_pinged = {
		note = [[ Пингутет текущий хост CPE с интервалом 10 сек. и возвращает 1 или 0. ]],
		modifier = {
			["1_skip"] = [[
				local CPE_ACTIVE = ('$cpe_status' ~= '')
				return (not CPE_ACTIVE)
			]],
			["2_bash"] = "/usr/lib/lua/applogic/sh/pingcheck.sh --host $cpe_host",
			["3_func"] = [[ return string.sub("$cpe_pinged",1,1) ]],
			["4_frozen"] = "10"
		}
	},

	all_hosts = {
		note = [[ Хранит список всех хостов CPE Agent. Разделитель - ';' ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "wimark",
				type = "broker"
			}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e '$.values.*.host' | awk -v RS=  '{$1=$1}1' | tr " " ";" ]],
			["2_frozen"] = "5"
		}
	},

	alived_hosts = {
		note = [[ Пингутет все хосты, возвращает только действующие. Разделитель ";". ]],
		modifier = {
			["1_bash"] = "/usr/lib/lua/applogic/sh/pingcheck.sh --host-list '$all_hosts' | awk /^1/ | sed s/1[[:space:]]// | awk -v RS=  '{$1=$1}1' | tr ' ' ';'",
			["2_frozen"] = "15"
		}
	},

	timer = {
		note = [[ Отсчитывает 60-секундный интервал, если хост не отвечает и есть куда переключиться ]],
		input = "0",
		modifier = {
			["1_skip"] = [[
				local CPE_ACTIVE = ('$cpe_status' ~= '')
				local CPE_HOST_NOT_ALIVE = ("$cpe_pinged" == "0")
				local OK_RESERVED = ("$alived_hosts" ~= "")
				local COUNT = CPE_ACTIVE and CPE_HOST_NOT_ALIVE and OK_RESERVED
				return (not COUNT)
			]],
			["1_func"] = [[ if tonumber("$timer") >= 60 then return "0" else return "$timer" end ]],
			["2_func"] = [[ return tostring(tonumber("$timer") + 1) ]],
		}
	},

	swith_cpe = {
		note = [[ Переключает CPE Agent на резервный хост если за 50 сек. текущий хост FAIL и резервный список не пуст. ]],
		source = {
			type = "ubus",
			object = "cpeagent",
			method = "reset"
		},
		modifier = {
			["1_skip"] = [[
				local CPE_ACTIVE = ('$cpe_status' ~= '')
				local CPE_HOST_NOT_ALIVE = ("$cpe_pinged" == "0")
				local OK_RESERVED = ("$alived_hosts" ~= "")
				local DO_SWITCH = CPE_ACTIVE and CPE_HOST_NOT_ALIVE and OK_RESERVED
				return (not (DO_SWITCH and tonumber("$timer") > 50))
			]],
			["2_frozen"] = "5"
		}
	}
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug mode: RULE or VAR
-- Use :debug("INFO") - to debug single variable in the rule (ERROR also is possible)
debug_mode.type = "RULE"
debug_mode.level = "INFO"

rule.debug_mode = debug_mode

function rule:make()
	local ONLY = rule.debug_mode.level

	self:load("title"):modify():debug()	-- Use debug(ONLY) to check the var only

	self:load("cpe_status"):modify():debug()
	self:load("cpe_host"):modify():debug()
	self:load("cpe_pinged"):modify():debug()

	self:load("all_hosts"):modify():debug()
	self:load("alived_hosts"):modify():debug()

	self:load("timer"):modify():debug()
	self:load("swith_cpe"):modify():debug()

	self:clear_cache()
end


---[[ Initializing. Don't edit the code below ]]---
local metatable = {
	__call = function(table, parent)
		local t = rule_init(table, rule_setting, parent)
		if not t.is_busy then
			t.is_busy = true
			t:make()
			t.is_busy = false
		end
		return t
	end
}
setmetatable(rule, metatable)
return rule

-- ubus call uci set '{"config":"wimark","type":"broker","section":"cfg0b2e8a","values":{"host":"192.168.1.22"}}'
