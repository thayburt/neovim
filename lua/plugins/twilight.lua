local bg_color = vim.api.nvim_get_hl_by_name("Normal", true)

return {
    {
	    "folke/twilight.nvim",
		opts = {
		    dimming = {
			    alpha = 0.20,
			    term_bg = string.format("#%06X", bg_color.background or 0)
			}
		}
	}
}
