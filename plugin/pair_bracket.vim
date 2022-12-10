scriptencoding utf-8

augroup pair_bracket
	autocmd!
	autocmd InsertEnter,CmdlineEnter * call pair_bracket#Init() | autocmd! pair_bracket | augroup! pair_bracket
augroup END
