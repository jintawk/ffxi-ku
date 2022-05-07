--[[VERSION HISTORY
1.3 - Added support for sets
1.2 - Added zone exclusions & fixed curema
1.12 - Added cureda and curema
1.11 - Added selfda and targda
1.10 - Overhaul/refactor
1.00 - Inital with selfja/selfma/targma/targja]]

_addon.name = 'ku'
_addon.version = '1.3'
_addon.author = 'Jintawk/Jinvoco (Carbuncle)'
_addon.command = 'ku'

res = require('resources')
require('sets')
require('tables')
require "Ability"
require "List"
require "const"
require "gui"
require "util"

ability_list = List.new()
pause = false
debug = false
engaged = false
zone_restriction_id = nil
zone_restriction_name = nil

--[[
	Event: Addon command received from player
]]
windower.register_event('addon command', function()
    return function(command, ...)
    	command = string.lower(command)
    	local params = {...}


		if command == COMMANDS.ADD then
			action = Ability.new(params)

			if not action.valid then
				log_invalid_params()
				return
			end

			for i = 1, ability_list.count do
				if action.name == ability_list.items[i].name then
					log('Action already added')
					return
				end
			end

			if action.type == TYPE.SELF_MAGIC then
				if not action:init_self_magic(params) then
					log_invalid_params()
					return
				end

				log('Adding [' .. action.name .. ']')
				log_d('id[' .. action.id .. '] buff_id[' .. action.buff_id .. '] when[' .. action.when	.. '] cmd[' .. action.cmd ..']')

				ability_list:push_back(action)
			elseif action.type == TYPE.SELF_JA or action.type == TYPE.SELF_DANCE then
				if not action:init_self_ja(params) then
					log_invalid_params()
					return
				end

				log('Adding [' .. action.name .. ']')
				log_d('id[' .. action.id .. '] buff_id[' .. action.buff_id .. '] recast_id[' .. action.recast_id .. '] when[' .. action.when .. '] cmd[' .. action.cmd ..']')

				ability_list:push_back(action)
			elseif action.type == TYPE.TARGET_MAGIC then
				-- TODO ! add invalid aparams protection
				action:init_target_magic()

				log('Adding [' .. action.name .. ']')
				log_d('id[' .. action.id .. '] cmd[' .. action.cmd ..']')

				ability_list:push_back(action)
			elseif action.type == TYPE.TARGET_JA or action.type == TYPE.TARGET_DANCE then
				if not action:init_target_ja(params) then
					log_invalid_params()
					return
				end

				log('Adding [' .. action.name .. ']')
				log_d('id[' .. action.id .. '] recast_id[' .. action.recast_id .. '] cmd[' .. action.cmd ..']')

				ability_list:push_back(action)
			elseif action.type == TYPE.CURE_DANCE then
				if not action:init_cure_dance(params) then
					log_invalid_params()
					return
				end


				log('Adding [' .. action.name .. ']')
				log_d('id[' .. action.id .. '] recast_id[' .. action.recast_id .. '] when[' .. action.when .. '] hpPerc[' .. action.hpPerc .. '] cmd[' .. action.cmd ..']')

				ability_list:push_back(action)
			elseif action.type == TYPE.CURE_MAGIC then
				if not action:init_cure_magic(params) then
					log_invalid_params()
					return
				end

				log('Adding [' .. action.name .. ']')
				log_d('name[' .. action.name .. '] when[' .. action.when .. '] hpPerc[' .. action.hpPerc .. '] cmd[' .. action.cmd ..']')

				ability_list:push_back(action)
			else
	    		log_invalid_params()
			end

			update_gui(ability_list, zone_restriction_name)
		elseif command == COMMANDS.REMOVE then
			local id = tonumber(params[1])
			
			--[[if id < ability_list:first or id > ability_list:last then
				log("Can't remove " .. id .. " as it's not within the list")
				return
			end]]

			log('Removing [' .. action.name .. ']')
			ability_list:remove_at(id)
			update_gui(ability_list, zone_restriction_name)
		elseif command == COMMANDS.SET then	
			local setName = params[1]

			if settings.sets[setName] ~= nil then
				windower.add_to_chat(207, 'Found set! Clearing KU & Applying set: ' .. setName)

				ability_list:clear()

				local set = settings.sets[setName]

				for key,val in pairs(split(set, ",")) do
					local params = split(val, " ")
					local action = Ability.new(params)

					if not action.valid then
						windower.add_to_chat(207, 'An ability in the set is not valid, please review it')
						return
					end

					-- TODO! I've pasted this from the add section above, put this in a function to keep it DRY

					if action.type == TYPE.SELF_MAGIC then
						if not action:init_self_magic(params) then
							windower.add_to_chat(207, 'Failed init_self_magic')
							return
						end
		
						log('Adding [' .. action.name .. ']')
						log_d('id[' .. action.id .. '] buff_id[' .. action.buff_id .. '] when[' .. action.when	.. '] cmd[' .. action.cmd ..']')
		
						ability_list:push_back(action)
					elseif action.type == TYPE.SELF_JA or action.type == TYPE.SELF_DANCE then
						if not action:init_self_ja(params) then
							windower.add_to_chat(207, 'Failed init_self_ja')
							return
						end
		
						log('Adding [' .. action.name .. ']')
						log_d('id[' .. action.id .. '] buff_id[' .. action.buff_id .. '] recast_id[' .. action.recast_id .. '] when[' .. action.when .. '] cmd[' .. action.cmd ..']')
		
						ability_list:push_back(action)
					elseif action.type == TYPE.TARGET_MAGIC then
						-- TODO ! add invalid aparams protection
						action:init_target_magic()
		
						log('Adding [' .. action.name .. ']')
						log_d('id[' .. action.id .. '] cmd[' .. action.cmd ..']')
		
						ability_list:push_back(action)
					elseif action.type == TYPE.TARGET_JA or action.type == TYPE.TARGET_DANCE then
						if not action:init_target_ja(params) then
							windower.add_to_chat(207, 'Failed init_target_ja')
							return
						end
		
						log('Adding [' .. action.name .. ']')
						log_d('id[' .. action.id .. '] recast_id[' .. action.recast_id .. '] cmd[' .. action.cmd ..']')
		
						ability_list:push_back(action)
					elseif action.type == TYPE.CURE_DANCE then
						if not action:init_cure_dance(params) then
							windower.add_to_chat(207, 'Failed init_cure_dance')
							return
						end
		
		
						log('Adding [' .. action.name .. ']')
						log_d('id[' .. action.id .. '] recast_id[' .. action.recast_id .. '] when[' .. action.when .. '] hpPerc[' .. action.hpPerc .. '] cmd[' .. action.cmd ..']')
		
						ability_list:push_back(action)
					elseif action.type == TYPE.CURE_MAGIC then
						if not action:init_cure_magic(params) then
							windower.add_to_chat(207, 'Failed init_cure_magic')
							return
						end
		
						log('Adding [' .. action.name .. ']')
						log_d('name[' .. action.name .. '] when[' .. action.when .. '] hpPerc[' .. action.hpPerc .. '] cmd[' .. action.cmd ..']')
		
						ability_list:push_back(action)
					else
						windower.add_to_chat(207, 'Invalid action in set, please review')
					end

				end
			--				settingsBuffsToUse = settings.buffs[jobKey]

				update_gui(ability_list, zone_restriction_name)
			else
				windower.add_to_chat(207, 'No such set -> ' .. setName)
			end
    	elseif command == COMMANDS.STOP then
    		log('Paused')
    		pause = true
		elseif command == COMMANDS.START then
    		log('Resuming')
			pause = false
		elseif command == COMMANDS.ZONE then
			local new_zone = tonumber(params[1])

			for k,v in pairs(res.zones) do
				if k == new_zone then
					zone_restriction_id = k
					zone_restriction_name = v.en
				end
			end

			if zone_restriction_id ~= nil and zone_restriction_id > 0 then
				log('Zone set to [' .. zone_restriction_name .. ']')
			else
				log('Zone cleared')
			end

			update_gui(ability_list, zone_restriction_name)
		elseif command == COMMANDS.HELP then
			log(get_help_string())
		else
			log_invalid_params()
		end
    end
end())

--[[
	Event: Status has changed Engaged/Not Enaged
]]
windower.register_event('status change', function(new, old)
    if new == STATUS.ENGAGED then
    	log_d('New status: Engaged')
        engaged = true
    elseif new == STATUS.NOT_ENGAGED then
    	log_d('New status: Not Engaged')
        engaged = false
    end
end)

--[[
	Event: In game time has progress to the next minute
	Used as update loop for this addon
]]
windower.register_event('time change', function(new, old)
	if pause then
		log_d('KU is paused')
		return
	end

	if windower == nil or windower.ffxi == nil or windower.ffxi.get_player() == nil or windower.ffxi.get_info().logged_in == false then
		return
	end

	if zone_restriction_id ~= nil and zone_restriction_id > 0 then
		if windower.ffxi.get_info().zone ~= zone_restriction_id then return end
	end

	if windower.ffxi.get_player().autorun then
		log_d('Auto-running, not performing actions')
	end

	local mobHP = 0

	if engaged and windower.ffxi.get_mob_by_target('t') ~= nil then
		mobHP = windower.ffxi.get_mob_by_target('t').hpp
		log_d('Mob hpp = ' .. mobHP)
	end

	if mobHP == 100 then
		log_d('Mob hpp is 100, not starting yet')
		return
	end

	-- KU is unpaused and we are either not engaged or engaged mob has < 100% hp
	-- Look through every action in list to see if any are eligible for casting now
	for i = 1, ability_list.count do
		local action = ability_list.items[i]

		if action ~= nil then
			-- If combat status is appropriate for using this ability
			if should_recast(action, engaged) then
				-- If it has no buff or it does but the buff has worn off
				if action.buff_id == nil or is_buff_on(action) == false then
					-- If recast timer is zero
					if can_recast(action) then
						-- If have anough MP for this spell, or it's a JA
						if enough_mp(action) then
							-- Do action
							windower.send_command(action.cmd)
							return
						end
					end
				end
			end
		end
	end
end)