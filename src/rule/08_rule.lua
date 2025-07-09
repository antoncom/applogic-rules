local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Мигание светодиода LED3 - какая сим активна",
	},
	sim_id = {
		note = [[ Идентификатор активной Сим-карты: 0/1. ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
	            method = "sim",
            	params = {},
        	}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.sim_id) or {}
				return lua_table.value or ""
			end,
		}
    },

	switching = {
		note = [[ Статус переключения Sim: true / false. ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "switching",
				params = {},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.switching) or {}
				return lua_table.value or ""
			end
		},
		{
			["frozen"] = function (nodes)
				if (nodes.switching == "true") then return 10 else return 0 end
			end
		}
	},

	r01_sim_ready = {
		note = [[ Значение sim_ready из правила 01_rule ]],

		{
			["load-rule"] = {
				rulename = "01_rule",
				nodename = "sim_ready"
			}
		},
	},

    LED3_mode = {
        note = [[ Режим мигания светодиода LED3. ]],

		{
            ["func"] = function (nodes)
                local no_blinking = "v0"
                local mode_1 = { sim_id = "0", blinking = "f200,800" }
                local mode_2 = { sim_id = "1", blinking = "f200,200,200,800" }
                if nodes.switching == "true" then return no_blinking
				elseif  (nodes.sim_id == "0" and nodes.r01_sim_ready == "true") then return mode_1.blinking
				elseif  (nodes.sim_id == "1" and nodes.r01_sim_ready == "true") then return mode_2.blinking
                else return no_blinking end
            end
        },
    },

	send_stm_at = {
		note = [[ Отправка настроек светодиода LED3 ]],

		{
			["load-ubus"] = {
				object = "tsmodem.stm",
				method = "send",
				params = {
					command = "~0:LED.3=$LED3_mode",
				},
			}
		},
		{
			["skip"] = function (nodes)
				return (nodes.LED3_mode == nodes.previous)
			end
		}
	},

    previous = {
        note = [[ Режим мигания светодиода LED3 (на предыдущей итерации). ]],

		{
            ["func"] = function (nodes)
                return nodes.LED3_mode
            end
        },
    },
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
-- Alternatively, you may run debug via shell like this "applogic 07_rule title sim_id" (use 5 variable names maximum)
function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end

	local all_rules = rule.parent.setting.rules_list.target

	-- Пропускаем выполнения правила, если СИМ-карты нет в слоте
	local r01_wait_timer = tonumber(all_rules["01_rule"].setting.wait_timer.output)
	if (r01_wait_timer and r01_wait_timer > 0) then
		--if rule.debug_mode.enabled then print("------ 08_rule SKIPPED as r01_wait_timer > 0 -----") end
		return
	end


	self:follow("title"):debug()
	self:follow("sim_id"):debug()
	self:follow("switching"):debug()
	self:follow("r01_sim_ready"):debug()
	self:follow("LED3_mode"):debug()
	self:follow("send_stm_at"):debug()
    self:follow("previous"):debug()
end


local metatable = {
    __call = function(table, parent)
        local rule_init_table = rule_init(table, rule_setting, parent)
        rule_init_table:make()
        return rule_init_table
    end
}
setmetatable(rule, metatable)
return rule
