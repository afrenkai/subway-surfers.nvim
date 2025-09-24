local M = {}
local H = {}

---@param youtube_url string
---@return string?
function H.extract_video_id(youtube_url)
	local id = youtube_url
		:gsub([[(.*)(youtu)(.*)]], "%3")
		:gsub([[(%.be/)(.*)]], "%2")
		:gsub([[(.*/v/)(.*)]], "%2")
		:gsub([[(.*v=)(.*)]], "%2")

	local regex = vim.regex([[\v^[A-Za-z0-9_\-]{11}$]])

	if not regex:match_str(id) then
		return nil
	end

	return id
end

local video_url = "https://www.youtube.com/watch?v=-uAZdIJIl8o"
local video_id = H.extract_video_id(video_url) --[[@as string]]
local data_path = string.format("%s/subway-surfers.nvim", vim.fn.stdpath("data"))

function M.setup()
	local subcommands = {
		["open"] = function()
			M.download(function()
				M.open()
			end)
		end,
		["close"] = function()
			M.close()
		end,
		["download"] = function()
			M.download()
		end,
		["clean"] = function()
			M.clean()
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

---@param callback? fun()
function M.download(callback)
	if vim.fn.executable("yt-dlp") == 0 then
		vim.notify("yt-dlp is not installed", vim.log.levels.ERROR, { title = "Subway Surfers" })
		return
	end

	if vim.fn.executable("ffmpeg") == 0 then
		vim.notify("ffmpeg is not installed", vim.log.levels.ERROR, { title = "Subway Surfers" })
		return
	end

	local output_path, exists = H.output_path(video_id)
	if exists then
		if callback then
			vim.schedule(function()
				callback()
			end)
		end
		return
	end

	local yt_dlp_cmd = {
		"yt-dlp",
		"--format-sort",
		"res,ext:mp4:m4a",
		"--recode-video",
		"mp4",
		"--output",
		output_path,
		"--newline",
		"--progress",
		"--progress-template",
		"%(progress)j",
		video_url,
	}

	---@param err string?
	---@param data string?
	local function handle_stdout(err, data)
		assert(not err, err)
		if data == nil or #data == 0 then
			return
		end

		if string.sub(data, 1, 1) ~= "{" then
			return
		end

		local success, json = pcall(vim.json.decode, data)
		if not success then
			return
		end

		local total_bytes = json.total_bytes_estimate or json.total_bytes
		local new_download_percentage = (json.downloaded_bytes / total_bytes) * 100

		print(string.format("[subway-surfers.nvim] Downloading '%s'... [%.0f%%]", video_url, new_download_percentage))
	end

	local function on_exit(output)
		if output.code ~= 0 then
			vim.notify(output.stderr, vim.log.levels.ERROR, { title = "Subway Surfers" })
			return
		end

		print(string.format("[subway-surfers.nvim] Finished downloading '%s'", video_url))
		if callback then
			vim.schedule(function()
				callback()
			end)
		end
	end

	vim.system(yt_dlp_cmd, { text = true, stdout = handle_stdout }, on_exit)
end

function M.clean()
	local files = vim.fs.find(function()
		return true
	end, { path = data_path })

	for _, file in ipairs(files) do
		vim.fn.delete(file)
	end

	print(string.format("[subway-surfers.nvim] Removed videos from '%s'", data_path))
end

---@type { buf: integer, win: integer, job: integer } | nil
local buffer_data = nil

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

	local output_path, exists = H.output_path(video_id)
	if not exists then
		vim.notify(
			string.format("Could not find video '%s'", output_path),
			vim.log.levels.ERROR,
			{ title = "Subway Surfers" }
		)
		H.restore_window(old_win, win)
		return
	end

	local mpv_cmd = {
		"mpv",
		"--really-quiet",
		"--vo=tct",
		"--vf-add=fps:10:round=near",
		"--speed=1.0",
		output_path,
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
		H.restore_window(old_win, win)
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

---@param id string
---@return string
---@return boolean
function H.output_path(id)
	local file_name = id .. ".mp4"
	local output_path = vim.fs.normalize(data_path .. "/" .. file_name)
	local exists = #vim.fs.find(file_name, { path = data_path }) == 1

	return output_path, exists
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
