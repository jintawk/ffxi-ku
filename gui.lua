require "List"
require "const"
config = require('config')
-- shared mythril UI lib when present; the bundled copy makes a standalone clone work
local mythril_ok
mythril_ok, mythril = pcall(require, 'mythril')
if not mythril_ok then
	mythril = require('mythril_bundled')
end
mythril.set_assets_path(windower.addon_path .. 'assets/')

defaults = {
	pos = {
		x = 300,
		y = 475,
	},
	ui = {
		scale = 1,
		minimized = false,
	},
}

settings = config.load(defaults)

local UI_W     = 250
local ROW_H    = 18
local FOOTER_H = 16

local ui = {
	built = false,
	panel = nil,
	rows = {},        -- pooled: {idx, name, tag} labels per display slot
	footer = nil,
}

local function build_ui()
	if ui.built then
		return
	end
	ui.built = true
	mythril.set_scale(tonumber(settings.ui.scale) or 1)

	ui.panel = mythril.Panel({
		x = settings.pos.x,
		y = settings.pos.y,
		pos_source = function() return settings.pos.x, settings.pos.y end,
		w = UI_W,
		content_h = 40,
		title = 'Ku',
		minimized = settings.ui.minimized,
		on_move = function(x, y)
			settings.pos.x = x
			settings.pos.y = y
			config.save(settings)
		end,
		on_minimize = function(min)
			settings.ui.minimized = min
			config.save(settings)
			update_gui(ability_list, zone_restriction_name, pause)
		end,
	})

	ui.footer = mythril.Label({size = 9, font = mythril.font.mono, color = mythril.color.ok})
	ui.panel:add(ui.footer, 10, 0)

	-- master switch is gone in mythril; clicking the footer line toggles pause
	ui.master_hit = mythril.HitBox({w = UI_W, h = FOOTER_H, on_click = function()
		pause = not pause
		log(pause and 'Paused' or 'Resuming')
		update_gui(ability_list, zone_restriction_name, pause)
	end})
	ui.panel:add(ui.master_hit, 0, 0)

	ui.hint = mythril.Label({size = 10, color = mythril.color.text_faint, text = 'no actions - //ku help'})
	ui.panel:add(ui.hint, 10, 4)
end

local function ensure_rows(n)
	for i = #ui.rows + 1, n do
		local row = {
			idx  = mythril.Label({size = 9, font = mythril.font.mono, color = mythril.color.text_faint}),
			name = mythril.Label({size = 10, color = mythril.color.text}),
			tag  = mythril.Label({size = 9, font = mythril.font.mono, color = mythril.color.text_faint}),
		}
		local ry = 4 + (i - 1) * ROW_H
		ui.panel:add(row.idx, 10, ry + 1)
		ui.panel:add(row.name, 28, ry)
		ui.panel:add(row.tag, 150, ry + 1)
		ui.rows[i] = row
	end
end

function update_gui(list, zone, pause)
	build_ui()

	local n = list.count
	ensure_rows(n)
	-- empty list still shows the panel, with a hint line where rows would be
	local rows_h = (n > 0 and n or 1) * ROW_H
	ui.panel:content_height(4 + rows_h + 4 + FOOTER_H)

	local slot = 0
	if n > 0 then
		local first = list.first
		local last = list.first + list.count - 1
		for i = first, last do
			local item = list.items[i]
			if item ~= nil then
				slot = slot + 1
				local row = ui.rows[slot]
				local ry = 4 + (slot - 1) * ROW_H
				ui.panel:place(row.idx, 10, ry + 1)
				ui.panel:place(row.name, 28, ry)
				ui.panel:place(row.tag, 150, ry + 1)
				row.idx:text(tostring(i))
				row.name:text(item.name)
				row.name:color(pause and mythril.color.disabled or mythril.color.text)
				row.tag:text('(' .. item.type .. '-' .. (item.when or '') .. ')')
			end
		end
	end

	local state = pause and 'paused' or 'running'
	if zone ~= nil then
		state = state .. '  zone: ' .. zone
	end
	ui.footer:text(state)
	ui.footer:color(pause and mythril.color.warn or mythril.color.ok)
	ui.panel:place(ui.footer, 10, 4 + rows_h + 4)
	ui.panel:place(ui.master_hit, 0, 4 + rows_h + 4)

	ui.panel:title_dim(pause)
	if not ui.panel:visible() then
		ui.panel:show()
	end

	-- hide pooled rows beyond the current count; leave everything hidden
	-- while the panel is minimized (the panel manages its own children)
	if not ui.panel:is_minimized() then
		ui.master_hit:visible(true)
		ui.hint:visible(n == 0)
		for i = 1, #ui.rows do
			local v = i <= slot
			ui.rows[i].idx:visible(v)
			ui.rows[i].name:visible(v)
			ui.rows[i].tag:visible(v)
		end
	end
end
