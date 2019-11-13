
--Tab and Tablist widgets.
--Written by Cosmin Apreutesei. Public Domain.

local ui = require'ui'
local glue = require'glue'
local box2d = require'box2d'

local indexof = glue.indexof
local clamp = glue.clamp
local round = glue.round

--tab ------------------------------------------------------------------------

local tab = ui.layer:subclass'tab'
ui.tab = tab
tab.iswidget = true

--tablist property: removing the selected tab selects the previous tab.
--adding a tab selects the tab based on its stored selected state.

tab.tablist = false
tab:stored_property'tablist'
function tab:before_set_tablist()
	if self.tablist then
		self.tablist:_remove_tab(self)
	end
end
function tab:after_set_tablist()
	if self.tablist then
		self.parent = self.tablist
		self.tablist:_add_tab(self, self._index)
		self.selected = self._selected
	end
end
tab:nochange_barrier'tablist'

--index property: get/set a tab's positional index.

tab._index = 1/0 --add to the tablist tail

function tab:get_index()
	return self.tablist and self.tablist:tab_index(self) or self._index
end

function tab:set_index(index)
	if self.tablist then
		self.tablist:_move_tab(self, index)
	else
		self._index = index
	end
end

--visible state: hiding the selected tab selects the previous tab.

tab._visible = tab.visible

function tab:get_visible(visible)
	return self._visible
end

function tab:set_visible(visible)
	if self.tablist then
		if not visible then
			local prev_tab = self.tablist:prev_tab(self)
			if prev_tab then
				prev_tab:select()
			else
				self:unselect()
			end
		end
		self._visible = visible
		self.tablist:sync_tabs()
	end
end
tab:nochange_barrier'visible'

--close() method for decoupling visibility from closing.

function tab:close()
	if not self.closeable then return end
	if self:fire'closing' ~= false then
		self.visible = false
		self:fire'closed'
	end
end

--selected property: selecting a tab unselects the previously selected tab.

tab._selected = false

function tab:get_selected()
	if self.tablist then
		return self.tablist.selected_tab == self
	else
		return self._selected
	end
end

function tab:set_selected(selected)
	if selected then
		self:select()
	else
		self:unselect()
	end
end

function tab:select()
	if not self.tablist then
		self._selected = true
		return
	elseif not self.visible or not self.enabled then
		return
	end
	local stab = self.tablist.selected_tab
	if stab == self then return end
	if stab then
		stab:unselect()
	end
	self:settag(':selected', true)
	self:to_front()
	self:fire'tab_selected'
	self.parent:fire('tab_selected', self)
	self.tablist._selected_tab = self
end

function tab:unselect()
	if not self.tablist then
		self._selected = false
		return
	end
	local stab = self.tablist.selected_tab
	if stab ~= self then return end
	stab:settag(':selected', false)
	stab:fire'tab_unselected'
	self.tablist:fire('tab_unselected', stab)
	self.tablist._selected_tab = false
end

--init

tab:init_ignore{tablist=1, visible=1, selected=1}

function tab:after_init(t)
	if t.tablist then
		self.tablist = t.tablist
	end
	self.visible = t.visible
	self.selected = t.selected
end

function tab:before_free()
	self.tablist = false
end

--mouse interaction: drag & drop

tab.mousedown_activate = true
tab.draggable = true

function tab:activated()
	self:select()
end

function tab:start_drag(button, mx, my, area)
	if area ~= 'header' then return end
	self.origin_tablist = self.tablist
	self.origin_tab_x = self.tab_x
	self.origin_tab_h = self.tab_h
	self.origin_index = self.index
	return self
end

function tab:drag(dx, dy)
	if self.tablist then
		local x = self.origin_tab_x + dx
		local vi = self.tablist:tab_visual_index_by_pos(x)
		self.index = self.tablist:tab_index_by_visual_index(vi)
		self:transition('tab_x', self.tablist:clamp_tab_pos(x), 0)
		self:transition('tab_w', self.tablist.live_tab_w)
		local x, w = self:snapxw(0, self.tablist.w)
		local y = self.tablist.tabs_side == 'top' and self.tab_h or 0
		local y, h = self:snapyh(y, self.tablist.ch - self.tablist.tab_h)
		self:transition('x', x, 0)
		self:transition('y', y, 0)
		self:transition('w', w, 0)
		self:transition('h', h, 0)
	else
		local x = self:snapx(self.x + dx)
		local y = self:snapy(self.y + dy)
		self:transition('tab_x', self.origin_tab_x, 0)
		self:transition('tab_h', self.origin_tab_h, 0)
		self:transition('x', x, 0)
		self:transition('y', y, 0)
	end
end

tab.draggable_outside = true --can be dragged out of the original tablist

function tab:accept_drop_widget(widget)
	return self.draggable_outside or widget == self.origin_tablist
end

function tab:enter_drop_target(tablist)
	if not tab.draggable_outside and tablist ~= self.origin_tablist then
		return
	end
	self.tablist = tablist
	self:select()
end

function tab:leave_drop_target(tablist)
	if not tab.draggable_outside and tablist == self.origin_tablist then
		return
	end
	self.tablist = false
	self.parent = tablist.window
	self:to_front()
end

function tab:ended_dragging()
	if self.origin_tablist then
		self.x, self.y = self:to_other(self.origin_tablist, 0, 0)
		self.tablist = self.origin_tablist
		self.index = self.origin_index
		self:select()
	end
	self.origin_tablist = false
	self.origin_tab_x = false
	self.origin_index = false
	self.tablist:sync_tabs()
end

--mouse interaction: close-on-doubleclick

tab.max_click_chain = 2

function tab:doubleclick()
	self:close()
end

--keyboard interaction

tab.focusable = true

function tab:keypress(key)
	if key == 'enter' or key == 'space' then
		self:select()
		return true
	elseif key == 'left' or key == 'right' then
		local next_tab = self.tablist:next_tab(self,
			key == 'right' and 'next_index' or 'prev_index')
		if next_tab then
			next_tab:focus()
		end
		return true
	end
end

--drawing & hit-testing

tab.clip_content = 'background' --TODO: find a way to set this to true
tab.border_width = 1
tab.border_color = '#222'
tab.background_color = '#111'
tab.padding = 5
tab.corner_radius = 5

ui:style('tab', {
	transition_tab_x = true,
	transition_tab_w = true,
	transition_duration_tab_x = .2,
	transition_duration_tab_w = .2,
	transition_x = true,
	transition_y = true,
	transition_w = true,
	transition_h = true,
	transition_duration_x = .5,
	transition_duration_y = .5,
	transition_duration_w = .5,
	transition_duration_h = .5,
})

ui:style('tab :hot', {
	background_color = '#181818',
	transition_background_color = true,
	transition_duration = .2,
})

ui:style('tab :selected', {
	background_color = '#222',
	border_color = '#333',
	transition_duration = 0,
})

ui:style('tab :focused', {
	border_color = '#666',
})

ui:style('tab :dragging', {
	opacity = .5,
})

ui:style('tab :dropping', {
	opacity = 1,
})

function tab:slant_widths()
	local h = self.tab_h
	local tablist = self.tablist or self.origin_tablist
	local s = tablist.tab_slant
	local sl = math.rad(tablist.tab_slant_left or s)
	local sr = math.rad(tablist.tab_slant_right or s)
	local wl = h / math.tan(sl)
	local wr = h / math.tan(sr)
	return wl, wr, sl, sr
end

local sides = {'top', 'right', 'bottom', 'left'}
function tab:border_line_to(cr, x0, y0, q)
	local tablist = self.tablist or self.origin_tablist
	local side = q and sides[q] or tablist.tabs_side
	if side ~= tablist.tabs_side then return end
	local w, h = self.tab_w, self.tab_h
	local wl, wr, sl, sr = self:slant_widths()
	local r = tablist.tab_corner_radius
	local x  = self.tab_x
	local x1 = x + wl
	local x2 = x + w - wr
	local x3 = x + w
	local x4 = x + 0
	local y = y0
	local y1 = y - h
	local y2 = y - h
	local y3 = y + 0
	local y4 = y + 0
	cr:save()
	if side == 'top' then
		--nothing
	elseif side == 'bottom' then
		cr:rotate_around(x + w / 2, y, math.pi)
	elseif side == 'left' then
		--TODO:
	elseif side == 'right' then
		--TODO:
	else
		self:warn('invalid tabs_side: %s', side)
	end
	if r > 0 then
		local q = math.pi/2
		local sl = q - sl
		local sr = q - sr
		local xl = math.tan(sl / 2) * r
		local xr = math.tan(sr / 2) * r
		cr:arc_negative(x4-r+xl, y4-r, r, q*1   , q*0+sl)
		cr:arc         (x1+r-xl, y1+r, r, q*2+sl, q*3   )
		cr:arc         (x2-r+xr, y2+r, r, q*3   , q*4-sr)
		cr:arc_negative(x3+r-xr, y3-r, r, q*2-sr, q*1   )
	else
		cr:line_to(x4, y4)
		cr:line_to(x1, y1)
		cr:line_to(x2, y2)
		cr:line_to(x3, y3)
	end
	cr:restore()
end

function tab:override_hit_test(inherited, x, y, ...)
	local widget, area = inherited(self, x, y, ...)
	if widget == self and area == 'background' and self.tablist then
		if box2d.hit(x, y, self.tablist:header_rect()) then
			return self, 'header'
		end
	end
	return widget, area
end

function tab:get_occluded()
	return not (
		not self.tablist --dragging
		or self.selected --selected
		or self.tablist.foreground_fixed_tab == self --underneath dragging
	)
end

--skip drawing the hidden part of the tab (notably it's background which can
--be large) if we know for sure that the tab contents are entirely occluded.
function tab:override_border_path(inherited, cr, ...)
	if not self.occluded then
		return inherited(self, cr, ...)
	end
	local x1, y1, w, h = self:border_rect(...)
	local x2, y2 = x1 + w, y1 + h
	local side = (self.tablist or self.origin_tablist).tabs_side
	if side == 'bottom' then
		y1 = y2
	elseif side == 'right' then
		--TODO:
	elseif side == 'left' then
		--TODO:
	end
	self:border_line_to(cr, x1, y1)
	cr:close_path()
end

--skip drawing the tab's contents if we know that they are entirely occluded.
function tab:draw_children(cr)
	local occluded = self.occluded
	for i = 1, #self do
		local layer = self[i]
		if not occluded or layer == self.title or layer == self.close_button then
			layer:draw(cr)
		end
	end
end

--title

local title = ui.layer:subclass'tab_title'
tab.title_class = title

title.text_align_x = 'left'
title.padding_left = 2
title.padding_right = 2
title.text_color = '#ccc'
title.nowrap = true
title.activable = false
title.clip_content = true

ui:style('tab_title :focused', {
	font_weight = 'bold',
})

function tab:create_title(title)
	return self.title_class(self.ui, {
		parent = self,
		iswidget = false,
		tab = self,
	}, self.title, title)
end

function tab:after_init()
	self.title = self:create_title()
end

function tab:before_sync_layout_children()
	local tablist = self.tablist or self.origin_tablist
	local t = self.title
	local wl, wr = self:slant_widths()
	local p = self.padding
	t.x = self.tab_x - (self.padding_left or p) + wl + tablist.title_margin
	if tablist.tabs_side == 'top' then
		t.y = self:snapy(-self.tab_h - (self.padding_top or p))
	elseif tablist.tabs_side == 'bottom' then
		t.y = self:snapy(self.h - (self.padding_bottom or p))
	end
	t.w = self.close_button.x - t.x
	t.h = self.tab_h
end

--close button

tab.closeable = true --show close button and receive 'closing' event

local xbutton = ui.button:subclass'tab_close_button'
tab.close_button_class = xbutton

xbutton.font = 'Ionicons,13'
xbutton.text = '\u{f2c0}'
xbutton.layout = false
xbutton.w = 14
xbutton.h = 14
xbutton.padding_left = 0
xbutton.padding_right = 0
xbutton.padding_top = 0
xbutton.padding_bottom = 0
xbutton.corner_radius = 100
xbutton.corner_radius_kappa = 1
xbutton.focusable = false
xbutton.border_width = 0
xbutton.background_color = false
xbutton.text_color = '#999'

ui:style([[
	tab_close_button,
	tab_close_button :hot,
	tab_close_button !:enabled
]], {
	background_color = false,
	transition_background_color = false,
})

ui:style('tab_close_button :hot', {
	text_color = '#ddd',
	background_color = '#a00',
})

ui:style('tab_close_button :over', {
	text_color = '#fff',
})

function xbutton:pressed()
	self.tab:close()
end

function tab:create_close_button(button)
	return self.close_button_class(self.ui, {
		parent = self,
		iswidget = false,
		tab = self,
	}, self.close_button, button)
end

function tab:after_init()
	self.close_button = self:create_close_button()
end

function tab:before_sync_layout_children()
	local xb = self.close_button
	local wl, wr = self:slant_widths()
	local p = self.padding
	xb.x = self.tab_x + self.tab_w - xb.w - wr
		- (self.padding_left or p)
		- (self.tablist or self.origin_tablist).close_button_margin
	local side = (self.tablist or self.origin_tablist).tabs_side
	if side == 'top' then
		xb.cy = -math.ceil(self.tab_h / 2) - (self.padding_top or p)
	elseif side == 'bottom' then
		xb.cy = self.h + math.ceil(self.tab_h / 2) - (self.padding_bottom or p)
	end
	xb.visible = self.closeable
end

--tablist --------------------------------------------------------------------

local tablist = ui.layer:subclass'tablist'
ui.tablist = tablist

--tabs list

function tablist:tab_index(tab)
	return indexof(tab, self.tabs)
end

function tablist:clamped_tab_index(index, add)
	return clamp(index, 1, math.max(1, #self.tabs + (add and 1 or 0)))
end

function tablist:_add_tab(tab, index)
	index = self:clamped_tab_index(index, true)
	table.insert(self.tabs, index, tab)
	self:sync_tabs()
end

function tablist:_remove_tab(tab)
	local select_tab = tab.visible and tab.selected and self:prev_tab(tab)
	tab:unselect()
	table.remove(self.tabs, self:tab_index(tab))
	self:sync_tabs()
	if select_tab then
		select_tab.selected = true
	end
end

function ui.layer:_move_tab(tab, index)
	local old_index = self:tab_index(tab)
	local new_index = self:clamped_tab_index(index)
	if old_index ~= new_index then
		table.remove(self.tabs, old_index)
		table.insert(self.tabs, new_index, tab)
		self:sync_tabs()
	end
end

tablist.tab_class = tab

function tablist:tab(tab)
	if not tab.istab then
		local class = tab.class or self.tab_class
		assert(class.istab)
		tab = class(self.ui, self[class], tab, {tablist = self})
	end
	return tab
end

tablist:init_ignore{tabs = 1}

function tablist:after_init(t)
	self.tabs = {} --{tab1,...}
	if t.tabs then
		for _,tab in ipairs(t.tabs) do
			self:tab(tab)
		end
	end
	if not self.selected_tab then
		if self.selected_tab_index then
			self.selected_tab = self.tabs[self.selected_tab_index]
		else
			self.selected_tab = self:next_tab(nil, 'next_index')
		end
	end
end

--selected tab state

tablist._selected_tab = false

function tablist:get_selected_tab()
	return self._selected_tab
end

function tablist:set_selected_tab(tab)
	if tab then
		assert(tab.tablist == self)
		tab:select()
	elseif self.selected_tab then
		self.selected_tab:unselect()
	end
end

--foreground tab that is either the selected tab or the tab underneath
--the selected tab, if the selected tab is not yet in place (moving).
function tablist:get_foreground_fixed_tab()
	local stab = self.selected_tab
	local moving_tab = stab
		and (stab:end_value'x' ~= stab.x
		  or stab:end_value'y' ~= stab.y)
		and stab
	if stab and not moving_tab then
		return stab
	end
	for i = #self, 1, -1 do
		local tab = self[i]
		if tab.istab and tab.visible and tab ~= moving_tab then
			return tab
		end
	end
end

--visible tabs list

function tablist:visible_tab_count()
	local n = 0
	for _,tab in ipairs(self.tabs) do
		if tab.visible then n = n + 1 end
	end
	return n
end

tablist.last_selected_order = false

--modes: next_index, prev_index, next_layer_index, prev_layer_index.
function tablist:next_tab(from_tab, mode, rotate, include_dragging)
	if mode == nil then
		mode = true
	end
	if type(mode) == 'boolean' then
		if self.last_selected_order then
			mode = not mode
		end
		mode = (mode and 'next' or 'prev')
			.. (self.last_selected_order and '_layer' or '') .. '_index'
	end

	local forward = mode:find'next'
	local tabs = mode:find'layer' and self or self.tabs

	local i0, i1, step = 1, #tabs, 1
	if not forward then
		i0, i1, step = i1, i0, -step
	end
	if from_tab then
		local index_field = tabs == self and 'layer_index' or 'index'
		i0 = from_tab[index_field] + (forward and 1 or -1)
	end
	for i = i0, i1, step do
		local tab = tabs[i]
		if tab.istab and tab.visible and tab.enabled
			and (include_dragging or not tab.dragging)
		then
			return tab
		end
	end
	if rotate then
		return self:next_tab(nil, mode)
	end
end

function tablist:prev_tab(tab)
	local stab = self.selected_tab
	local prev_tab
	if stab == tab then
		local is_first = (stab == self:next_tab(nil, 'next_index', nil, true))
		local mode = self.last_selected_order and 'prev_layer_index'
			or (is_first and 'next_index' or 'prev_index')
		prev_tab = self:next_tab(tab, mode, nil, true)
	end
	return prev_tab
end

--keyboard interaction

tablist.main_tablist = true --responds to tab/ctrl+tab globally

function tablist:after_init()
	self.window:on({'keypress', self}, function(win, key)
		if self.main_tablist then
			if key == 'tab' and self.ui:key'ctrl' then
				local shift = self.ui:key'shift'
				local tab = self:next_tab(self.selected_tab, not shift, true)
				if tab then
					tab.selected = true
				end
				return true
			elseif self.selected_tab and key == 'W' and self.ui:key'ctrl' then
				self.selected_tab:close()
				return true
			end
		end
	end)
end

--drag & drop

tablist.tablist_group = false

function tablist:accept_drag_widget(widget, mx, my, area)
	if widget.istab then
		local group = widget.origin_tablist.tablist_group
		if not group or group == self.tablist_group then
			return not mx or area == 'header'
		end
	end
end

function tablist:drop(widget, mx, my, area)
	widget.origin_tablist = false
end

--drawing & hit-testing

tablist.w = 400
tablist.h = 400
tablist.tab_h = 26
tablist.tab_w = 150
tablist.min_tab_w = 10
tablist.tab_spacing = -10
tablist.tab_slant = 70 --degrees
tablist.tab_slant_left = false
tablist.tab_slant_right = false
tablist.tab_corner_radius = 0
tablist.tabs_padding = 10
tablist.tabs_padding_left = false
tablist.tabs_padding_right = false
tablist.tabs_side = 'top' --top, bottom, left, right

tablist.title_margin = 4
tablist.close_button_margin = 4

function tablist:clamp_tab_pos(x)
	local p = self.tabs_padding
	return clamp(x,
		self.tabs_padding_left or p,
		self.w - self.live_tab_w - (self.tabs_padding_right or p))
end

function tablist:sync_live_tab_w()
	local n = self:visible_tab_count()
	local w = self.w
		- (self.tabs_padding_left or self.tabs_padding)
		- (self.tabs_padding_right or self.tabs_padding)
		+ self.tab_spacing * n
	local tw = math.min(self.tab_w + self.tab_spacing, math.floor(w / n))
	local s = self.tab_slant
	local sl = self.tab_slant_left or s
	local sr = self.tab_slant_right or s
	local wl = self.tab_h / math.tan(math.rad(sl))
	local wr = self.tab_h / math.tan(math.rad(sr))
	local min_tw = wl + wr + self.min_tab_w
	self.live_tab_w = math.max(tw, min_tw)
end

function tablist:tab_pos_by_visual_index(index)
	return (self.tabs_padding_left or self.tabs_padding) +
		(index - 1) * (self.live_tab_w + self.tab_spacing)
end

function tablist:tab_visual_index_by_pos(x)
	local x = x - (self.tabs_padding_left or self.tabs_padding)
	return round(x / (self.live_tab_w + self.tab_spacing)) + 1
end

function tablist:tab_index_by_visual_index(vi)
	vi = math.max(1, vi)
	local vi1 = 1
	for i,tab in ipairs(self.tabs) do
		if tab.visible then
			if vi1 == vi then
				return i
			end
			vi1 = vi1 + 1
		end
	end
	return #self.tabs
end

function tablist:sync_tabs(...)
	self:sync_live_tab_w()
	local tab_w = self.live_tab_w
	local vi = 1
	local side = self.tabs_side
	for i,tab in ipairs(self.tabs) do
		if tab.visible then
			local x, w = self:snapxw(0, self.w)
			local y, h = self:snapyh(
				side == 'top' and self.tab_h or 0,
				self.h - self.tab_h)
			if not tab.dragging then
				tab:transition('tab_x', self:tab_pos_by_visual_index(vi), ...)
				tab:transition('tab_w', tab_w, ...)
				tab:transition('x', x, ...)
				tab:transition('y', y, ...)
			end
			tab:transition('w', w, ...)
			tab:transition('h', h, ...)
			tab:transition('tab_h', self.tab_h, ...)
			vi = vi + 1
			tab:sync_transitions()
		end
	end
end

function tablist:after_sync_layout()
	self:sync_tabs(0, nil, nil, nil, nil, 'replace_value')
end

function tablist:header_rect() --in content space
	local side = self.tabs_side
	if side == 'top' then
		return 0, 0, self.cw, self.tab_h
	elseif side == 'bottom' then
		return 0, self.ch - self.tab_h, self.cw, self.ch
	end
end

function tablist:override_hit_test(inherited, x, y, ...) --in parent content space
	local widget, area = inherited(self, x, y, ...)
	if widget == self and area == 'background' then
		local x, y = self:from_parent_to_box(x, y)
		local x, y = self:to_content(x, y)
		if box2d.hit(x, y, self:header_rect()) then
			return self, 'header'
		end
	end
	return widget, area
end

--demo -----------------------------------------------------------------------

if not ... then require('ui_demo')(function(ui, win)

	local color = require'color'

	win.view.grid_flow = 'x'
	win.view.grid_gap = 10
	win.view.grid_wrap = 2
	win.view.grid_min_lines = 2

	local w = (win.view.cw - 10) / 2
	local h = win.view.ch

	local tl1 = {
		tab_slant = 80,
		tab_corner_radius = 10,
		tabs_padding = 20,
		tab_h = 36,
		w = w, h = h,
		parent = win,
		tabs = {},
	}

	local tl2 = {
		x = w + 10, w = w, h = h / 2,
		tab_slant_right = 80,
		parent = win,
		tabs = {},
		tabs_side = 'bottom',
	}

	for i = 1, 10 do
		local visible = i ~= 3 and i ~= 8
		local enabled = i ~= 4 and i ~= 7
		local selected = i == 1 or i == 2
		local layer_index = 1
		local closeable = i ~= 5

		local tl = i % 2 == 0 and tl1 or tl2

		table.insert(tl.tabs, {
			tags = 'tab'..i,
			--index = 1,
			layer_index = layer_index,
			style = {
				font_slant = 'normal',
			},
			title = {text = 'Tab '..i},
			visible = visible,
			--selected = selected,
			enabled = enabled,
			closeable = closeable,
			closed = function(self)
				self:free()
			end,
		})

	end

	tl1 = ui:tablist(tl1)
	tl2 = ui:tablist(tl2)

end) end
