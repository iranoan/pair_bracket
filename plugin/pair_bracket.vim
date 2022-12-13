vim9script
# Author:  Iranoan <iranoan+vim@gmail.com>
# License: GPL Ver.3.

scriptencoding utf-8

if exists('g:pair_bracket')
	finish
endif
g:pair_bracket = 1

augroup pair_bracket
	autocmd!
	autocmd InsertEnter,CmdlineEnter * call pair_bracket#Init()
		| autocmd! pair_bracket
		| augroup! pair_bracket
augroup END
