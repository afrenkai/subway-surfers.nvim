local M = {}

function M.setup()
	vim.api.nvim_create_user_command("SubwaySurfers", function()
		M.open()
	end, {})
end

function M.open()
	if vim.fn.executable("mpv") == 0 then
		vim.notify("mpv is not installed", vim.log.levels.ERROR, { title = "Subway Surfers" })
		return
	end

	local old_win = vim.api.nvim_get_current_win()

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		win = -1,
		width = math.floor(vim.o.columns * 0.25),
		vertical = true,
		split = "right",
		style = "minimal",
	})

	if win == 0 then
		vim.notify("Failed to open window", vim.log.levels.ERROR, { title = "Subway Surfers" })
		return
	end

	vim.bo[buf].modifiable = false

	local mpv_cmd = {
		"mpv",
		"--really-quiet",
		"--vo=tct",
		"~/Downloads/subway-surfers.mp4",
	}

	local shell = vim.fn.has("win32") == 0 and "sh" or "powershell"
	local cmd = { shell, "-c", vim.iter(mpv_cmd):join(" ") }

	vim.api.nvim_set_current_buf(buf)
	vim.fn.termopen(cmd, {
		stderr_buffered = true,
		on_stderr = function(_, data, _)
			local stderr = vim.iter(data):join("\n")

			vim.notify(stderr, vim.log.levels.ERROR, { title = "Subway Surfers" })
		end,
	})

	vim.api.nvim_buf_set_name(buf, "Subway Surfers")

	vim.api.nvim_set_current_win(old_win)
end

return M
