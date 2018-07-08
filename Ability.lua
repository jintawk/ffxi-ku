--[[Class object of an ffxi Ability (spell/ability) - MMcGinty 2015]]

Ability = {};
Ability.__index = Ability;

--[[
    Create a new Ability 
]]
function Ability.new(params)
	local act = setmetatable({}, Ability)
	act.valid = false

	if params[1] == nil or params[2] == nil or params[3] == nil then
		return act
	end

	act.type = params[1]
	act.name = string.gsub(params[2], "_", " ")
	act.id = tonumber(params[3])
	act.valid = true

	return act
end

function Ability:init_self_magic(params)
	if params[4] == nil or params[5] == nil then
		return false
	end

	self.buff_id = tonumber(params[4])
	self.when = string.lower(params[5])
	self.cmd = 'input /ma "' .. self.name .. '" <me>'

	if self.when ~= 'all' and self.when ~= 'in' and self.when ~= 'out' then
		return false
	end

	if self.buff_id <= 0 then
		self.buff_id = nil
	end

	return true
end

function Ability:init_self_ja(params)
	if params[4] == nil or params[5] == nil or params[6] == nil then
		return false
	end

	self.buff_id = tonumber(params[4])
	self.recast_id = tonumber(params[5])
	self.when = string.lower(params[6])
	self.cmd = 'input /ja "' .. self.name .. '" <me>'

	if self.when ~= 'all' and self.when ~= 'in' and self.when ~= 'out' then
		return false
	end

	if self.buff_id <= 0 then
		self.buff_id = nil
	end

	return true
end

function Ability:init_target_magic()
	self.cmd = 'input /ma "' .. self.name .. '" <t>'
end

function Ability:init_target_ja(params)
	if params[4] == nil then
		return false
	end

	self.recast_id = tonumber(params[4])
	self.cmd = 'input /ja "' .. self.name .. '" <t>'

	return true
end

function Ability:init_cure_dance(params)
	if params[4] == nil or params[5] == nil or params[6] == nil then
		return false
	end

	self.recast_id = tonumber(params[4])
	self.when = string.lower(params[5])
	self.hpPerc = tonumber(params[6])
	self.cmd = 'input /ja "' .. self.name .. '" <me>'

	if self.when ~= 'all' and self.when ~= 'in' and self.when ~= 'out' then
		return false
	end

	return true
end

function Ability:init_cure_magic(params)
	if params[4] == nil or params[5] == nil then
		return false
	end

	self.when = string.lower(params[4])
	self.hpPerc = tonumber(params[5])
	self.cmd = 'input /ma "' .. self.name .. '" <me>'

	if self.when ~= 'all' and self.when ~= 'in' and self.when ~= 'out' then
		return false
	end

	return true
end