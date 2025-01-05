require "List"
require "const"
config = require('config')
texts = require('texts')

defaults = {
	pos = {
		x = 300,
		y = 475,
	},
	text = {
		font = 'Arial',
		size = 8,
	},
	flags = {
		bold = true,
		draggable = true,
	},
	bg = {
		alpha = 128,
	},
}


settings = config.load(defaults)
listGUI = texts.new(settings)

function update_gui(list, zone, pause)
	if list.count == 0 then return end

	local guiStr = "KU List:"

	if zone ~= nil then
		guiStr = guiStr .. " [" .. zone .. "]"
	end

	if pause == true then
		guiStr = guiStr .. " <PAUSED>"
	else 
		guiStr = guiStr .. " <RUNNING>"
	end

	local first = list.first
	local last = list.first + list.count - 1
	
	for i = first, last do
		local item = list.items[i]
		
		if item ~= nil then
			local when = item.when or ""
			guiStr = guiStr .. "\n" .. i .. ": " .. item.name .. ' (' .. item.type .. '-' .. when .. ')'
		end
	end

	listGUI:text(guiStr)
	listGUI:visible(true)
end
