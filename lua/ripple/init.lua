local M = {}

-- Debug mode - set to true to enable debug printing
local DEBUG = true

local function debug_print(...)
	if DEBUG then
		vim.print("[ripple.nvim]", ...)
	end
end

M.setup = function(opts)
	local default = {
		vertical_step_size = 1,
		horizontal_step_size = 1,
		keys = {
			expand_right = { "<C-right>", mode = { "n", "v" }, desc = "expand right" },
			expand_left = { "<C-left>", mode = { "n", "v" }, desc = "expand left" },
			expand_up = { "<C-up>", mode = { "n", "v" }, desc = "expand up" },
			expand_down = { "<C-down>", mode = { "n", "v" }, desc = "expand down" },
		},
	}
	M.vertical_step_size = opts.vertical_step_size or default.vertical_step_size
	M.horizontal_step_size = opts.horizontal_step_size or default.horizontal_step_size
	if opts and opts.disable_keymaps then
		return
	end
	local keys = vim.tbl_deep_extend("force", default.keys, (opts and opts.keys) or {})
	for func_name, args in pairs(keys) do
		if keys[func_name] then
			if type(args) == "string" then
				args = vim.tbl_deep_extend("force", default.keys[func_name], { args })
			elseif type(args) == "table" then
				args = vim.tbl_deep_extend("force", default.keys[func_name], args)
			end
			vim.keymap.set(args.mode, args[1], M[func_name], { desc = args.desc })
		end
	end
end
-- Window resizing
--
-- :resize will first attempt to resize the current window by moving the bottom (or right) border. If that is
-- not possible, it will resize the window by moving the top (or left) border. This variable behavior is
-- pretty annoying, so the following implements a more consistent behavior by expanding the window in the
-- direction of the specified arrow key.
-- expand_up expands the window upwards by M.vertical_step_size.
function M.expand_up()
	local above_win_number = vim.fn.winnr("k")
	if above_win_number == vim.fn.winnr() then
		return false
	end
	local result = vim.fn.win_move_statusline(above_win_number, -M.vertical_step_size)
	return result ~= 0
end
-- expand_down expands the window downwards by M.vertical_step_size.
function M.expand_down()
	local current_win_number = vim.fn.winnr()
	-- Check if there's a window below
	local below_win_number = vim.fn.winnr("j")
	if below_win_number == current_win_number then
		return false
	end
	local result = vim.fn.win_move_statusline(current_win_number, M.vertical_step_size)
	return result ~= 0
end
-- expand_left expands the window to the left by M.horizontal_step_size.
function M.expand_left()
	local left_win_number = vim.fn.winnr("h")
	if left_win_number == vim.fn.winnr() then
		return false
	end
	local result = vim.fn.win_move_separator(left_win_number, -M.horizontal_step_size)
	return result ~= 0
end
-- expand_right expands the window to the right by M.horizontal_step_size.
function M.expand_right()
	local current_win_number = vim.fn.winnr()
	-- Check if there's a window to the right
	local right_win_number = vim.fn.winnr("l")
	if right_win_number == current_win_number then
		return false
	end
	local result = vim.fn.win_move_separator(current_win_number, M.horizontal_step_size)
	return result ~= 0
end

-- Set focus_disable for all buffers in the current tabpage
local function set_focus_disable_in_tabpage(disabled)
	local current_tabpage = vim.api.nvim_get_current_tabpage()
	local windows = vim.api.nvim_tabpage_list_wins(current_tabpage)
	local processed_buffers = {}

	for _, win in ipairs(windows) do
		local ok, buf = pcall(vim.api.nvim_win_get_buf, win)
		if ok and vim.api.nvim_buf_is_valid(buf) and not processed_buffers[buf] then
			processed_buffers[buf] = true
			pcall(vim.api.nvim_buf_set_var, buf, "focus_disable", disabled)
		end
	end
end

-- Intelligent window resize that handles edgy windows and falls back to standard resize
function M.smart_resize(direction, amount)
	debug_print("smart_resize called with direction:", direction, "amount:", amount)

	local edgy_ok, edgy = pcall(require, "edgy")
	debug_print("edgy.nvim available:", edgy_ok)

	if edgy_ok then
		local edgy_win = edgy.get_win()
		debug_print("edgy window found:", edgy_win ~= nil)
		if edgy_win then
			local dimension = (direction == "h" or direction == "l") and "width" or "height"
			debug_print("resizing edgy window, dimension:", dimension, "amount:", amount)
			edgy_win:resize(dimension, amount)
			debug_print("disabling focus for edgy resize")
			set_focus_disable_in_tabpage(true)
			return
		end
	end

	local expand_fn = ({
		h = M.expand_left,
		l = M.expand_right,
		j = M.expand_down,
		k = M.expand_up,
	})[direction]

	debug_print("attempting ripple expansion with function:", expand_fn and "found" or "not found")

	if expand_fn then
		local success = expand_fn()
		debug_print("ripple expansion result:", success)
		if success then
			debug_print("disabling focus after successful ripple expansion")
			set_focus_disable_in_tabpage(true)
			return
		end
	end

	debug_print("falling back to native wincmd")
	
	-- When expand function fails, we need to do the opposite operation as fallback
	-- The failure means there's no window in that direction to take space from,
	-- so we shrink the current window to give space to the opposite direction
	local wincmd = nil
	
	if direction == "h" then
		-- expand_left failed (no left window) -> shrink current to give space to right
		debug_print("expand_left failed - shrinking current window")
		wincmd = "<"
	elseif direction == "l" then
		-- expand_right failed (no right window) -> shrink current to give space to left  
		debug_print("expand_right failed - shrinking current window")
		wincmd = "<"
	elseif direction == "j" then
		-- expand_down failed (no below window) -> shrink current to give space above
		debug_print("expand_down failed - shrinking current window")
		wincmd = "-"
	elseif direction == "k" then
		-- expand_up failed (no above window) -> shrink current to give space below
		debug_print("expand_up failed - shrinking current window")
		wincmd = "-"
	end
	
	if wincmd then
		debug_print("executing wincmd", wincmd, "x", math.abs(amount), "times")
		for i = 1, math.abs(amount) do
			debug_print("wincmd iteration", i .. "/" .. math.abs(amount))
			vim.cmd("wincmd " .. wincmd)
		end
	else
		debug_print("ERROR: invalid direction for wincmd:", direction)
	end

	debug_print("disabling focus after fallback resize")
	set_focus_disable_in_tabpage(true)
end

return M
