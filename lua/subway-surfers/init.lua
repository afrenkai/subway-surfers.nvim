local M = {}
local H = {}

---@type { buf: integer, win: integer, job: integer } | nil
local buffer_data = nil

function M.setup()
	local subcommands = {
		["open"] = function()
			M.open()
		end,
		["close"] = function()
			M.close()
		end,
	}

	vim.api.nvim_create_user_command("SubwaySurfers", function(opts)
		local arg = opts.fargs[1] or "open"

		local subcommand = subcommands[arg]
		if subcommand ~= nil then
			subcommand()
		end
	end, {
		nargs = "?",
		complete = function()
			return vim.tbl_keys(subcommands)
		end,
	})
end

function M.open()
	if vim.fn.executable("mpv") == 0 then
		vim.notify("mpv is not installed", vim.log.levels.ERROR, { title = "Subway Surfers" })
		return
	end

	local old_win = vim.api.nvim_get_current_win()

	local buf = buffer_data and buffer_data.buf or nil
	local win = buffer_data and buffer_data.win or nil
	local job = buffer_data and buffer_data.job or nil

	if buf == nil or not vim.api.nvim_buf_is_valid(buf) then
		buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].modifiable = false

		-- If we had to create a new buffer, invalidate the previous window and job
		win = nil
		job = nil
	end

	if win == nil or not vim.api.nvim_win_is_valid(win) then
		win = vim.api.nvim_open_win(buf, true, {
			win = -1,
			width = math.floor(vim.o.columns * 0.25),
			vertical = true,
			split = "right",
			style = "minimal",
		})

		if win == 0 then
			vim.notify("Failed to open window", vim.log.levels.ERROR, { title = "Subway Surfers" })
			H.restore_window(old_win, nil)
			return
		end
	end

	vim.api.nvim_set_current_win(win)
	if not vim.wo[win].winfixbuf then
		vim.api.nvim_set_current_buf(buf)
		vim.wo[win].winfixbuf = true
	end

	if job ~= nil then
		H.restore_window(old_win, win)
		return
	end

	local mpv_cmd = {
		"mpv",
		"--really-quiet",
		"--vo=tct",
		"--vf-add=fps:10:round=near",
		"~/Downloads/subway-surfers.mp4",
	}

	local shell = vim.fn.has("win32") == 0 and "sh" or "powershell"
	local cmd = { shell, "-c", vim.iter(mpv_cmd):join(" ") }

	job = vim.fn.termopen(cmd, {
		stderr_buffered = true,
		on_stderr = function(_, data, _)
			local stderr = vim.iter(data):join("\n")

			vim.notify(stderr, vim.log.levels.ERROR, { title = "Subway Surfers" })
		end,
	})

	if job <= 0 then
		vim.notify("Failed to spawn mpv", vim.log.levels.ERROR, { title = "Subway Surfers" })
		return
	end

	H.setup_buffer(buf)

	buffer_data = { buf = buf, win = win, job = job }

	H.restore_window(old_win, win)
end

function M.close()
	if buffer_data == nil then
		return
	end

	local buf = buffer_data.buf
	local win = buffer_data.win
	local job = buffer_data.job

	buffer_data = nil

	vim.fn.jobstop(job)

	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	vim.api.nvim_buf_delete(buf, { force = true })

	if not vim.api.nvim_win_is_valid(win) then
		return
	end

	local old_win = vim.api.nvim_get_current_win()

	vim.api.nvim_set_current_win(win)
	vim.cmd.quit()

	H.restore_window(old_win, win)
end

---@param old_win integer
---@param win integer?
function H.restore_window(old_win, win)
	if old_win == win then
		return
	end

	vim.api.nvim_set_current_win(old_win)
end

---@param buf integer
function H.setup_buffer(buf)
	vim.api.nvim_buf_set_name(buf, "Subway Surfers")

	local augroup = vim.api.nvim_create_augroup("SubwaySurfers", { clear = true })

	vim.api.nvim_create_autocmd("BufWinLeave", {
		group = augroup,
		buffer = buf,
		callback = function()
			M.close()
		end,
		desc = "Close Subway Surfers window",
	})

	vim.keymap.set({ "n", "t" }, "q", function()
		M.close()
	end, { buffer = buf, desc = "Close Subway Surfers window" })
end

return M
