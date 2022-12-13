" Author:  Iranoan <iranoan+vim@gmail.com>
" License: GPL Ver.3.

scriptencoding utf-8

if exists('g:pair_bracket')
	finish
endif
let g:pair_bracket = 1

let s:save_cpo = &cpoptions
set cpoptions&vim

augroup pair_bracket
	autocmd!
	autocmd InsertEnter,CmdlineEnter * call pair_bracket#Init() | autocmd! pair_bracket | augroup! pair_bracket
augroup END

" Reset User condition
let &cpoptions = s:save_cpo
unlet s:save_cpo
