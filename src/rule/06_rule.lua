local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Мигание светодиода LED1 - уровень сигнала",
	},
	sim_id = {
		note = [[ Идентификатор активной Сим-карты: 0/1. ]],
        -- source = {
		-- 	type = "ubus",
        --     object = "tsmodem.driver",
        --     method = "sim",
        --     params = {},
        -- },
		-- modifier = {
		-- 	-- ["1_bash"] = [[ jsonfilter -e $.value ]]
		-- 	["1_lua-func"] = function (vars)
		-- 		local lua_table = luci.jsonc.parse(vars.subtotal) or {}
		-- 		return lua_table.value or ""
		-- 	end,
		-- }

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "sim",
				params = {},
			}
		},
	 	{
			["func"] = function (vars)
				local lua_table = luci.jsonc.parse(vars.sim_id) or {}
				return lua_table.value or ""
			end,
		}
    },

    network_registration = {
		note = [[ Статус регистрации Сим-карты в сети 0..7. ]],
		-- source = {
		-- 	type = "ubus",
		-- 	object = "tsmodem.driver",
		-- 	method = "reg",
		-- 	params = {},
		-- },
		-- modifier = {
		-- 	-- ["1_bash"] = [[ jsonfilter -e $.value ]],
		-- 	["1_lua-func"] = function (vars)
		-- 		local lua_table = luci.jsonc.parse(vars.subtotal) or {}
		-- 		return lua_table.value or ""
		-- 	end,
		-- }

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "reg",
				params = {},
			}
		},
		{
			["func"] = function (vars)
				local lua_table = luci.jsonc.parse(vars.network_registration) or {}
				return lua_table.value or ""
			end,
		}
	},

	switching = {
		note = [[ Статус переключения Sim: true / false. ]],
		-- source = {
		-- 	type = "ubus",
		-- 	object = "tsmodem.driver",
		-- 	method = "switching",
		-- 	params = {},
		-- 	cached = "no" -- Turn OFF caching of the var, as next rule may use non-actual value
		-- },
		-- modifier = {
		-- 	-- ["1_bash"] = [[ jsonfilter -e $.value ]],
		-- 	["1_lua-func"] = function (vars)
		-- 		local lua_table = luci.jsonc.parse(vars.subtotal) or {}
		-- 		return lua_table.value or ""
		-- 	end,
		-- 	["2_frozen"] = [[ if ($switching == "true") then return 10 else return 0 end ]],
		-- }

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "switching",
				params = {},
				cached = "no" -- Turn OFF caching of the var, as next rule may use non-actual value
			}
		},
		{
			["func"] = function (vars)
				local lua_table = luci.jsonc.parse(vars.switching) or {}
				return lua_table.value or ""
			end
		},
		{
			["frozen"] = function (vars)
				if (vars.switching == "true") then return 10 else return 0 end
			end
		}
	},

	signal = {
		note = [[ Уровень сигнала сотового оператора, %. ]],
		-- source = {
		-- 	type = "ubus",
		-- 	object = "tsmodem.driver",
		-- 	method = "signal",
		-- 	params = {},
		-- },
		-- modifier = {
		-- 	-- ["1_bash"] = [[ jsonfilter -e $.value ]],
		-- 	["1_lua-func"] = function (vars)
		-- 		local lua_table = luci.jsonc.parse(vars.subtotal) or {}
		-- 		return lua_table.value or ""
		-- 	end,
		-- 	["2_lua-func"] = function (vars)
		-- 		if (tonumber(vars.signal)) then return vars.signal else return "-" end 
		-- 	end,
		-- },

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "signal",
				params = {},
			}
		},
		{
			["func"] = function (vars)
				local lua_table = luci.jsonc.parse(vars.signal) or {}
				return lua_table.value or ""
			end
		},
		{
			["func"] = function (vars)
				if (tonumber(vars.signal)) then return vars.signal else return "-" end
			end
		},
	},

    LED1_mode = {
        note = [[ Режим мигания светодиода LED1 ]],
        -- modifier = {
        --     ["1_lua-func"] = function (vars)
        --         local no_blinking = "v0"
        --         local mode_1 = { scale = 25, blinking = "f200,800" }
        --         local mode_2 = { scale = 50, blinking = "f200,200,200,800" }
        --         local mode_3 = { scale = 75, blinking = "f200,200,200,200,200,800" }
        --         local mode_4 = { scale = 100, blinking = "f200,200,200,200,200,200,200,800" }
		-- 		local signal = tonumber(vars.signal) or 0
        --         if vars.network_registration ~= "1" then return no_blinking
		-- 			elseif (signal == 0) then return no_blinking
		-- 			elseif (vars.switching == "true") then return no_blinking
		-- 			elseif (signal <= mode_1.scale) then return mode_1.blinking
	    --             elseif (signal > mode_1.scale and signal <= mode_2.scale) then return mode_2.blinking
	    --             elseif (signal > mode_2.scale and signal <= mode_3.scale) then return mode_3.blinking
	    --             elseif (signal > mode_3.scale and signal <= mode_4.scale) then return mode_4.blinking
		-- 			else return no_blinking
        --         end
        --      end,
        -- },

		{
            ["func"] = function (vars)
                local no_blinking = "v0"
                local mode_1 = { scale = 25, blinking = "f200,800" }
                local mode_2 = { scale = 50, blinking = "f200,200,200,800" }
                local mode_3 = { scale = 75, blinking = "f200,200,200,200,200,800" }
                local mode_4 = { scale = 100, blinking = "f200,200,200,200,200,200,200,800" }
				local signal = tonumber(vars.signal) or 0
                if vars.network_registration ~= "1" then return no_blinking
					elseif (signal == 0) then return no_blinking
					elseif (vars.switching == "true") then return no_blinking
					elseif (signal <= mode_1.scale) then return mode_1.blinking
	                elseif (signal > mode_1.scale and signal <= mode_2.scale) then return mode_2.blinking
	                elseif (signal > mode_2.scale and signal <= mode_3.scale) then return mode_3.blinking
	                elseif (signal > mode_3.scale and signal <= mode_4.scale) then return mode_4.blinking
					else return no_blinking
                end
            end
        },
    },


	send_stm_at = {
		note = [[ Отправка настроек светодиода LED1 ]],
		-- source = {
		-- 	type = "ubus",
		-- 	object = "tsmodem.stm",
		-- 	method = "send",
		-- 	params = {
        --         command = "~0:LED.1=$LED1_mode",
        --     },
		-- },
		-- modifier = {
        --     ["1_skip-func"] = function (vars)
        --         return (vars.LED1_mode == vars.previous)
        --     end
        -- }

		{
			["load-ubus"] = {
				object = "tsmodem.stm",
				method = "send",
				params = {
					command = "~0:LED.1=$LED1_mode",
				},
			}
		},
		{
            ["skip"] = function (vars)
                return (vars.LED1_mode == vars.previous)
            end
        }
    },

	previous = {
		note = [[ Режим мигания светодиода LED1 (на предыдущей итерации). ]],
		-- modifier = {
		-- 	["1_lua-func"] = function (vars)
		-- 		return vars.LED1_mode
		-- 	end,
		-- },
		{
			["func"] = function (vars)
				return vars.LED1_mode
			end,
		},
	},
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
-- Alternatively, you may run debug via shell like this "applogic 05_rule title sim_id" (use 5 variable names maximum)
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
		--if rule.debug_mode.enabled then print("------ 06_rule SKIPPED as r01_wait_timer > 0 -----") end
		return
	end

	self:follow("title"):debug()
	self:follow("sim_id"):debug()
    self:follow("network_registration"):debug()
	self:follow("switching"):debug()
    self:follow("signal"):debug()
	self:follow("LED1_mode"):debug()
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
